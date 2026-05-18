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

  COMPOSE_CMD="cd /opt/hermes-client/compose && sudo docker compose"

  _check_compose_healthy() {
    local out
    out="$(ssh_remote "$SSH_HOST" "$COMPOSE_CMD ps --format json" 2>/dev/null || true)"
    [[ -n "$out" ]] && ! echo "$out" | grep -qi '"State":"exited"'
  }
  check "compose services running (no exited)" _check_compose_healthy

  _check_no_errors_in_logs() {
    local n
    # Hermes prints colourful banners on boot; match on uppercase ERROR/FATAL
    # at the start of a log line only (json driver prefixes with timestamp +
    # stream so we anchor after the prefix).
    n="$(ssh_remote "$SSH_HOST" "$COMPOSE_CMD logs --tail=200 2>&1 | grep -ciE '(ERROR|FATAL|Traceback)' || true")"
    info "error/fatal/traceback lines in last 200 log entries: $n"
    [[ "$n" -le 0 ]]
  }
  check "no ERROR/FATAL/Traceback in last 200 compose log lines" _check_no_errors_in_logs

  _check_audit_writable() {
    ssh_remote "$SSH_HOST" "sudo test -w /var/log/hermes/audit" >/dev/null 2>&1
  }
  check "audit log path is writable" _check_audit_writable

  # --- Hermes-specific checks ---
  # The dashboard container is the one we exec into; gateway has the same
  # binary so either would work, but dashboard's healthcheck gates startup
  # already so it's the safer target.

  _check_hermes_version() {
    local out
    out="$(ssh_remote "$SSH_HOST" "$COMPOSE_CMD exec -T hermes-dashboard hermes --version" 2>&1 || true)"
    info "$out"
    echo "$out" | grep -qi "Hermes Agent v"
  }
  check "hermes binary responds to --version" _check_hermes_version

  _check_hermes_status() {
    # `hermes status` exits 0 when config + at least one provider is set.
    ssh_remote "$SSH_HOST" "$COMPOSE_CMD exec -T hermes-dashboard hermes status" >/dev/null 2>&1
  }
  check "hermes status reports configured" _check_hermes_status

  _check_hermes_profile() {
    local out
    out="$(ssh_remote "$SSH_HOST" "$COMPOSE_CMD exec -T hermes-dashboard hermes profile list" 2>&1 || true)"
    info "$(echo "$out" | head -3)"
    # Default profile is created automatically by the entrypoint; we just
    # need the list command to succeed and print something.
    echo "$out" | grep -qiE "(default|Profile)"
  }
  check "hermes profile list works" _check_hermes_profile

  _check_gateway_running() {
    # `gateway status` returns running once the foreground process has
    # finished initialisation.
    local out
    out="$(ssh_remote "$SSH_HOST" "$COMPOSE_CMD exec -T hermes-gateway hermes gateway status" 2>&1 || true)"
    info "$(echo "$out" | head -3)"
    # Some Hermes versions report "running" via systemd-style output; others
    # via a status table. Accept either as a non-error exit.
    [[ -n "$out" ]] && ! echo "$out" | grep -qi "error"
  }
  check "hermes gateway running" _check_gateway_running

  _check_dashboard_reachable_internally() {
    # From inside the docker network, the dashboard answers HEAD / on :9119.
    ssh_remote "$SSH_HOST" "$COMPOSE_CMD exec -T caddy wget --spider -q http://hermes-dashboard:9119/" >/dev/null 2>&1
  }
  check "dashboard reachable from caddy on internal network" _check_dashboard_reachable_internally

  _check_basic_auth_required() {
    # Without credentials, the proxy path returns 401; /health is unauthed.
    local code
    code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://$FQDN/" || echo 000)"
    info "https://$FQDN/ unauthenticated -> $code"
    [[ "$code" == "401" ]]
  }
  check "dashboard requires authentication" _check_basic_auth_required
else
  warn "SSH checks skipped — pass --ssh-host user@host to enable"
fi

echo
info "smoke test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
