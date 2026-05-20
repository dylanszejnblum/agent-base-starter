#!/usr/bin/env bash
# Wait until SSH on the target accepts our key and cloud-init has finished.
# Usage: wait-for-ssh.sh <user>@<host> [--timeout SECONDS]
#
# Exits 0 once `ssh ... cloud-init status --wait` succeeds (which itself
# blocks until cloud-init finalises). Exits non-zero on timeout.

set -euo pipefail
IFS=$'\n\t'

# shellcheck source=../bin/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin/lib" && pwd)/common.sh"

usage() { echo "Usage: $0 <user>@<host> [--timeout SECONDS]" >&2; exit 2; }

[[ $# -ge 1 ]] || usage
TARGET="$1"; shift
TIMEOUT="${TIMEOUT:-600}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) fatal "unknown arg: $1" ;;
  esac
done

require_cmd ssh

info "waiting for SSH on $TARGET (timeout ${TIMEOUT}s)"
start="$(date +%s)"
while true; do
  if ssh \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=5 \
      -o BatchMode=yes \
      -o LogLevel=ERROR \
      "$TARGET" true 2>/dev/null; then
    ok "ssh up"
    break
  fi
  now="$(date +%s)"
  if (( now - start > TIMEOUT )); then
    fatal "ssh did not come up within ${TIMEOUT}s"
  fi
  sleep 3
done

info "waiting for cloud-init to finish"
if ssh_remote "$TARGET" "sudo -n cloud-init status --wait"; then
  ok "cloud-init done"
  exit 0
fi

warn "sudo cloud-init status unavailable for $TARGET; falling back to /etc/agent-base/instance.json"
while true; do
  if ssh_remote "$TARGET" "grep -q '\"ready_at\"' /etc/agent-base/instance.json" 2>/dev/null; then
    ok "cloud-init done"
    exit 0
  fi
  now="$(date +%s)"
  if (( now - start > TIMEOUT )); then
    fatal "cloud-init did not mark ready within ${TIMEOUT}s; ssh in and check /var/log/cloud-init-output.log"
  fi
  sleep 5
done
