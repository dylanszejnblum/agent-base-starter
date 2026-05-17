#!/usr/bin/env bash
# Append a row to docs/client-inventory.md describing a deploy.
# Usage: append-inventory.sh <slug> <fqdn> <ipv4> <image_tag>
#
# The inventory file is a markdown table with a known header. This script
# inserts the new row immediately after the header, so newest deploys are
# at the top. Idempotent: if a row with the same slug already exists, it
# is replaced instead of duplicated.

set -euo pipefail
IFS=$'\n\t'

# shellcheck source=../bin/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin/lib" && pwd)/common.sh"

usage() { echo "Usage: $0 <slug> <fqdn> <ipv4> <image_tag>" >&2; exit 2; }

[[ $# -eq 4 ]] || usage
SLUG="$1"; FQDN="$2"; IPV4="$3"; TAG="$4"

INV_FILE="$(repo_root)/docs/client-inventory.md"
[[ -f "$INV_FILE" ]] || fatal "inventory file not found: $INV_FILE"

DEPLOY_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NEW_ROW="| $SLUG | $FQDN | $IPV4 | $TAG | $DEPLOY_DATE | active |"

# Remove any existing row for this slug (idempotent).
tmp="$(mktemp)"
awk -v slug="$SLUG" '
  /^\| *'"$SLUG"' *\|/ { next }
  { print }
' "$INV_FILE" > "$tmp"

# Insert new row after the table-separator line (the second |---| row).
awk -v row="$NEW_ROW" '
  BEGIN { inserted = 0 }
  /^\|[- :|]+\|$/ && !inserted {
    print
    print row
    inserted = 1
    next
  }
  { print }
' "$tmp" > "$INV_FILE"

rm -f "$tmp"
ok "inventory updated: $SLUG -> $FQDN @ $IPV4"
