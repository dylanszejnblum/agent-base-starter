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
fi
