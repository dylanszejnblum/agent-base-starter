# Rollback runbook

Status: **M3 stub.** Full procedure documented after M3 when `bin/deploy-client` pins image tags.

## Quick rollback (today, M1)

The only mutable surface in M1 is the compose stack itself. To roll back a bad config change:

```bash
ssh deploy@<ip>
cd /opt/hermes-client/compose
sudo docker compose down
# Restore previous Caddyfile / docker-compose.yml from your laptop:
exit
rsync -az compose/ deploy@<ip>:/opt/hermes-client/compose/
ssh deploy@<ip> 'cd /opt/hermes-client/compose && sudo docker compose up -d'
```

Volumes (`hermes_*`, `caddy_data`) are untouched by this flow.

## Hard rollback (rebuild)

If the VPS is in an unknown state:

1. Backup volumes: `ssh deploy@<ip> 'sudo docker run --rm -v hermes_state:/d -v $PWD:/out alpine tar czf /out/state.tgz /d'`
2. `scp deploy@<ip>:state.tgz ./backups/`
3. `./bin/destroy-client <slug> --domain <domain>`
4. `./bin/deploy-client <slug> --domain <domain>` (fresh VPS, same FQDN)
5. Restore volumes from the tarball (manual until M4).

## M3+ image-tag rollback

Once `APP_IMAGE` in `.env` is pinned to a specific Hermes build:

```bash
ssh deploy@<ip>
cd /opt/hermes-client/compose
sudo sed -i 's|APP_IMAGE=ghcr.io/.*/hermes-pyme:.*|APP_IMAGE=ghcr.io/<org>/hermes-pyme:<previous-tag>|' .env
sudo docker compose pull
sudo docker compose up -d
```

This is intended to be 60 s with no data loss. Documented end-to-end in M3.
