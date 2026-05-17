#!/usr/bin/env bash
# Wait until <url> returns HTTP 200 over HTTPS with a non-self-signed cert.
# Usage: wait-for-https.sh <url> [--timeout SECONDS]
#
# Tolerates ACME issuance latency (~30s typical, up to 5min worst case for
# rate-limited LE). Fails loudly if the certificate looks self-signed, which
# usually means Caddy fell back to its internal issuer because port 80 was
# unreachable when ACME ran.

set -euo pipefail
IFS=$'\n\t'

# shellcheck source=../bin/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin/lib" && pwd)/common.sh"

usage() { echo "Usage: $0 <url> [--timeout SECONDS]" >&2; exit 2; }

[[ $# -ge 1 ]] || usage
URL="$1"; shift
TIMEOUT="${TIMEOUT:-300}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) fatal "unknown arg: $1" ;;
  esac
done

require_cmd curl openssl

# Extract host from URL for cert inspection.
host="$(printf '%s' "$URL" | sed -E 's#^https?://([^/:]+).*#\1#')"

info "waiting for $URL (timeout ${TIMEOUT}s)"
start="$(date +%s)"
while true; do
  status="$(curl -sk --max-time 5 -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || echo "000")"
  if [[ "$status" == "200" ]]; then
    # Verify the cert chain is real, not Caddy's `internal` self-signed.
    issuer="$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null \
      | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//' || true)"
    if [[ "$issuer" == *"Let's Encrypt"* || "$issuer" == *"R3"* || "$issuer" == *"E5"* || "$issuer" == *"E6"* ]]; then
      ok "$URL returns 200 with cert issued by: $issuer"
      exit 0
    fi
    warn "200 received but issuer is not Let's Encrypt: '$issuer'. Caddy may be on internal cert."
  fi

  now="$(date +%s)"
  if (( now - start > TIMEOUT )); then
    fatal "endpoint did not become healthy within ${TIMEOUT}s (last status: $status)"
  fi
  sleep 5
done
