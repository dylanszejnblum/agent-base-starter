#!/usr/bin/env bash
# Wait until <fqdn> resolves to <expected-ip> using public resolvers.
# Usage: wait-for-dns.sh <fqdn> <expected-ipv4> [--timeout SECONDS]

set -euo pipefail
IFS=$'\n\t'

# shellcheck source=../bin/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin/lib" && pwd)/common.sh"

usage() { echo "Usage: $0 <fqdn> <expected-ipv4> [--timeout SECONDS]" >&2; exit 2; }

[[ $# -ge 2 ]] || usage
FQDN="$1"; EXPECTED="$2"; shift 2
TIMEOUT="${TIMEOUT:-300}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) fatal "unknown arg: $1" ;;
  esac
done

require_cmd dig

# Cloudflare + Google public resolvers — bypass local cache.
RESOLVERS=("1.1.1.1" "8.8.8.8")

info "waiting for $FQDN -> $EXPECTED (timeout ${TIMEOUT}s)"
start="$(date +%s)"
while true; do
  for r in "${RESOLVERS[@]}"; do
    answer="$(dig +short +time=2 +tries=1 @"$r" "$FQDN" A | tail -n1 || true)"
    if [[ "$answer" == "$EXPECTED" ]]; then
      ok "$FQDN resolves to $EXPECTED via $r"
      exit 0
    fi
  done
  now="$(date +%s)"
  if (( now - start > TIMEOUT )); then
    fatal "DNS did not converge within ${TIMEOUT}s (last answer: '${answer:-empty}')"
  fi
  sleep 5
done
