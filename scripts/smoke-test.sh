#!/usr/bin/env bash
# Smoke tests for a deployed client instance.
# Usage: smoke-test.sh <fqdn> [--ssh-host user@host]
#
# M1 checks (DNS, HTTPS, cert, container health, log writability).
# PRD §Smoke tests defines 10 gating checks; checks 5-9 require Hermes and
# will be added in M2 once the hermes image is in place.

set -euo pipefail
IFS=$'\n\t'

# shellcheck source=../bin/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin/lib" && pwd)/common.sh"

usage() { echo "Usage: $0 <fqdn> [--ssh-host user@host]" >&2; exit 2; }

[[ $# -ge 1 ]] || usage
FQDN="$1"; shift
SSH_HOST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-host) SSH_HOST="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) fatal "unknown arg: $1" ;;
  esac
done

require_cmd curl dig openssl
validate_domain "$FQDN"

PASS=0; FAIL=0
check() {
  local name="$1"; shift
  if "$@"; then
    ok "PASS — $name"
    PASS=$((PASS+1))
  else
    err "FAIL — $name"
    FAIL=$((FAIL+1))
  fi
}

# --- 1. DNS resolves ---
_check_dns() {
  local ip
  ip="$(dig +short @1.1.1.1 "$FQDN" A | tail -n1)"
  [[ -n "$ip" ]] && info "$FQDN -> $ip"
}
check "DNS A record present" _check_dns

# --- 2. HTTP redirects to HTTPS (Caddy default) ---
_check_redirect() {
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "http://$FQDN/" || echo 000)"
  # Caddy issues a 308 by default for the HTTP->HTTPS upgrade.
  [[ "$code" == "308" || "$code" == "301" || "$code" == "200" ]]
}
check "HTTP responds (redirect to HTTPS)" _check_redirect

# --- 3. HTTPS health endpoint returns 200 ---
_check_health() {
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://$FQDN/health" || echo 000)"
  [[ "$code" == "200" ]]
}
check "HTTPS /health returns 200" _check_health

# --- 4. Certificate issued by Let's Encrypt ---
_check_cert() {
  local issuer
  issuer="$(echo | openssl s_client -servername "$FQDN" -connect "$FQDN:443" 2>/dev/null \
    | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//' || true)"
  info "issuer: $issuer"
  [[ "$issuer" == *"Let's Encrypt"* || "$issuer" == *"R3"* || "$issuer" == *"E5"* || "$issuer" == *"E6"* ]]
}
check "TLS cert issued by Let's Encrypt" _check_cert

# --- 5. Cert not expired and not near expiry ---
_check_cert_expiry() {
  local not_after_ts now_ts days_left
  not_after_ts="$(echo | openssl s_client -servername "$FQDN" -connect "$FQDN:443" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//' \
    | xargs -I{} date -j -f "%b %e %H:%M:%S %Y %Z" "{}" "+%s" 2>/dev/null \
    || echo 0)"
  now_ts="$(date +%s)"
  if [[ "$not_after_ts" -eq 0 ]]; then
    warn "could not parse cert expiry (likely BSD date — try gdate)"
    return 0
  fi
  days_left=$(( (not_after_ts - now_ts) / 86400 ))
  info "cert expires in $days_left days"
  (( days_left > 7 ))
}
check "TLS cert not near expiry" _check_cert_expiry

# --- 6+ remote checks via SSH (require --ssh-host) ---
if [[ -n "$SSH_HOST" ]]; then
  require_cmd ssh

  _check_compose_healthy() {
    local out
    out="$(ssh_remote "$SSH_HOST" "cd /opt/hermes-client/compose && docker compose ps --format json" 2>/dev/null || true)"
    [[ -n "$out" ]] && ! echo "$out" | grep -qi '"State":"exited"'
  }
  check "compose services running (no exited)" _check_compose_healthy

  _check_no_errors_in_logs() {
    local n
    n="$(ssh_remote "$SSH_HOST" "cd /opt/hermes-client/compose && docker compose logs --tail=200 2>&1 | grep -ciE '^\\S+\\s+(ERROR|FATAL)' || true")"
    info "error/fatal lines in last 200 log entries: $n"
    [[ "$n" -le 0 ]]
  }
  check "no ERROR/FATAL in last 200 compose log lines" _check_no_errors_in_logs

  _check_audit_writable() {
    ssh_remote "$SSH_HOST" "sudo -u hermes test -w /var/log/hermes/audit" >/dev/null 2>&1
  }
  check "audit log path is writable by hermes user" _check_audit_writable

  # --- M2+ stubs (skipped in M1) ---
  warn "M2+ checks (Hermes profile, skill list, demo report) skipped — placeholder app in compose"
else
  warn "SSH checks skipped — pass --ssh-host user@host to enable"
fi

echo
info "smoke test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
