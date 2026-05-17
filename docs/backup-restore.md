# Backup and restore

Status: **M4 stub.** M1-M3 deploys do not have automated backups.

## Manual backup (M1-M3 interim)

```bash
ssh deploy@<ip>
sudo docker run --rm \
  -v hermes_state:/d/state:ro \
  -v hermes_memory:/d/memory:ro \
  -v hermes_workspace:/d/workspace:ro \
  -v hermes_audit_logs:/d/audit:ro \
  -v $PWD:/out \
  alpine \
  tar czf /out/hermes-$(hostname)-$(date +%Y%m%d).tgz /d
```

Then `scp` the tarball off the VPS to your laptop, then to encrypted off-site.

## M4 target

- `compose/docker-compose.yml` already declares a `backup` service with `offen/docker-volume-backup`, gated behind `profiles: [m4]`.
- Cron runs daily 03:00 client TZ, writes encrypted tarball to a B2 bucket.
- Per-client age encryption key in `/opt/hermes-client/secrets/age.key`.
- Retention: 7 daily / 4 weekly / 0 monthly.
- Restore: documented in this file in M4.

## Restore (high level, post-M4)

1. Provision a fresh VPS via `bin/deploy-client <slug> --domain <domain>`.
2. `docker compose down` before any state is touched.
3. Fetch the latest backup tarball from B2.
4. `docker run --rm -v hermes_state:/d -v $PWD:/in alpine tar xzf /in/<backup>.tgz -C /d --strip-components=2`
5. `docker compose up -d`.
6. Run smoke tests.

To be tested end-to-end on a throwaway VPS during M4.
