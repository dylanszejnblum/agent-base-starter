#!/usr/bin/env bash
# M4 stub — backup of named volumes to local tar + optional off-VPS sync.
#
# Status: not implemented. M1-M3 deploys produce backups manually via
# `docker run --rm -v hermes_state:/d alpine tar czf - /d | ssh ...`.
# M4 wires this into a cron container (see compose/docker-compose.yml).

set -euo pipefail
echo "backup-client.sh is an M4 stub; not implemented yet" >&2
exit 64  # EX_USAGE
