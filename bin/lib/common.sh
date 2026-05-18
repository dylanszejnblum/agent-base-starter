# shellcheck shell=bash
# Shared helpers for bin/* scripts. Sourced, not executed.
#
# Conventions:
#   - All shell scripts run with: set -euo pipefail; IFS=$'\n\t'
#   - Logs go to stderr so stdout stays usable for piping.
#   - Errors abort with non-zero exit and a clear message.

if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
  COMMON_SH_LOADED=1

  # --- colors (suppressed when not a tty) ---
  if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
    _C_RED="$(tput setaf 1)"
    _C_GRN="$(tput setaf 2)"
    _C_YLW="$(tput setaf 3)"
    _C_BLU="$(tput setaf 4)"
    _C_DIM="$(tput dim)"
    _C_RST="$(tput sgr0)"
  else
    _C_RED="" _C_GRN="" _C_YLW="" _C_BLU="" _C_DIM="" _C_RST=""
  fi

  log()   { printf '%s[%s] %s%s\n' "$_C_DIM" "$(date +%H:%M:%S)" "$*" "$_C_RST" >&2; }
  info()  { printf '%s[info]%s %s\n'  "$_C_BLU" "$_C_RST" "$*" >&2; }
  ok()    { printf '%s[ok]%s %s\n'    "$_C_GRN" "$_C_RST" "$*" >&2; }
  warn()  { printf '%s[warn]%s %s\n'  "$_C_YLW" "$_C_RST" "$*" >&2; }
  err()   { printf '%s[err]%s %s\n'   "$_C_RED" "$_C_RST" "$*" >&2; }
  fatal() { err "$*"; exit 1; }

  # --- paths ---
  # Resolve repo root from any sourcing script.
  repo_root() {
    local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local dir
    dir="$(cd "$(dirname "$src")/.." && pwd)"
    # If we were sourced from bin/lib/, climb one more.
    if [[ "$(basename "$dir")" == "lib" ]]; then
      dir="$(cd "$dir/.." && pwd)"
    fi
    if [[ "$(basename "$dir")" == "bin" ]]; then
      dir="$(cd "$dir/.." && pwd)"
    fi
    printf '%s\n' "$dir"
  }

  # --- prereq checks ---
  require_cmd() {
    local missing=()
    for c in "$@"; do
      command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
      fatal "missing required commands: ${missing[*]}"
    fi
  }

  require_env() {
    local missing=()
    for v in "$@"; do
      [[ -n "${!v:-}" ]] || missing+=("$v")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
      fatal "missing required env vars: ${missing[*]}"
    fi
  }

  # --- validation ---
  validate_slug() {
    local s="$1"
    if [[ ! "$s" =~ ^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$ ]]; then
      fatal "invalid slug '$s' — must be 3-32 chars, lowercase alphanumerics and hyphens, no leading/trailing hyphen"
    fi
  }

  validate_domain() {
    local d="$1"
    if [[ ! "$d" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
      fatal "invalid domain '$d' — must be a lowercase DNS name"
    fi
  }

  # --- ssh helper ---
  # Suppresses host-key prompts on first connect by writing to a per-deploy
  # known_hosts. This is deliberate: first-boot VPS has no prior fingerprint,
  # and trusting on first use is the standard pragmatic compromise.
  ssh_remote() {
    local host="$1"; shift
    ssh \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="${SSH_KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}" \
      -o ConnectTimeout=10 \
      -o ServerAliveInterval=15 \
      -o LogLevel=ERROR \
      "$host" "$@"
  }

  scp_remote() {
    scp \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="${SSH_KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}" \
      -o ConnectTimeout=10 \
      -o LogLevel=ERROR \
      "$@"
  }

  # --- password helpers ---
  # Generate a URL-safe random password. Default length 32 chars.
  gen_password() {
    local len="${1:-32}"
    # Prefer openssl (universally available); fall back to /dev/urandom.
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -base64 48 | tr -dc 'A-Za-z0-9_-' | head -c "$len"
    else
      LC_ALL=C tr -dc 'A-Za-z0-9_-' </dev/urandom | head -c "$len"
    fi
    echo
  }

  # Bcrypt-hash a password using a one-shot caddy container. Output is the
  # raw $2a$ hash, ready to drop into Caddyfile or .env. Uses caddy:2-alpine
  # so the hash format always matches what the running caddy will accept.
  hash_password_caddy() {
    local plain="$1"
    require_cmd docker
    docker run --rm caddy:2-alpine caddy hash-password --plaintext "$plain" 2>/dev/null
  }

  # --- age secret helpers ---
  # Defaults reflect the operator-side conventions documented in secrets/README.md.
  age_key_path()        { printf '%s\n' "${AGE_KEY:-$HOME/.config/age/operator.key}"; }
  age_recipients_path() { printf '%s\n' "$(repo_root)/secrets/.recipients"; }
  age_secret_path()     { printf '%s\n' "$(repo_root)/secrets/$1.env.age"; }

  # Verify age is installed and the operator has a key. Fatal with install
  # hints if not. Run this once at the start of any command that touches
  # secrets, NOT inline per-call.
  require_age() {
    require_cmd age
    local key recipients
    key="$(age_key_path)"
    recipients="$(age_recipients_path)"

    if [[ ! -f "$key" ]]; then
      fatal "age key not found at $key — generate one with: age-keygen -o $key && chmod 600 $key (then add the public key to $recipients)"
    fi
    if [[ ! -f "$recipients" ]]; then
      fatal "recipients file missing: $recipients — see secrets/README.md"
    fi
    if ! grep -qE '^age1' "$recipients"; then
      fatal "no recipients in $recipients — append at least one age public key (age-keygen -y $key)"
    fi
  }

  # Decrypt secrets/<slug>.env.age to stdout. Caller is responsible for
  # capturing into a 0600 temp file and shredding it after use.
  age_decrypt_secret() {
    local slug="$1"
    local file
    file="$(age_secret_path "$slug")"
    [[ -f "$file" ]] || fatal "secret file not found: $file"
    age -d -i "$(age_key_path)" "$file"
  }

  # Encrypt a plaintext file to secrets/<slug>.env.age, addressed to all
  # recipients in secrets/.recipients. Overwrites any existing file.
  age_encrypt_secret() {
    local slug="$1" plaintext="$2"
    local out
    out="$(age_secret_path "$slug")"
    mkdir -p "$(dirname "$out")"
    age -R "$(age_recipients_path)" -o "$out" < "$plaintext"
    chmod 644 "$out"   # the file is encrypted; mode is for git ergonomics, not secrecy
  }

  # Has a per-slug encrypted secret been initialized?
  age_secret_exists() {
    [[ -f "$(age_secret_path "$1")" ]]
  }

  # Cross-platform "shred-and-remove" for ephemeral plaintext temp files.
  shred_file() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    if command -v shred >/dev/null 2>&1; then
      shred -u "$f" 2>/dev/null || rm -f "$f"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
      rm -P "$f" 2>/dev/null || rm -f "$f"
    else
      rm -f "$f"
    fi
  }
fi
