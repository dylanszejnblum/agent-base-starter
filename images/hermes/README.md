# `images/hermes/` — M2

Custom Hermes image built from the Nous Research install script with `pyme-admin-core` baked in.

Status: **not started.** M1 uses `traefik/whoami` as a placeholder in compose.

## M2 scope

- `Dockerfile` based on `ubuntu:24.04`
- Run Nous install script during build
- Layer `skills/pyme-admin-core` (vendored or submodule)
- Non-root runtime user (`hermes:hermes`, UID matches the cloud-init `hermes` user)
- `HEALTHCHECK` that calls `hermes profile show <slug>` via env
- Entrypoint that renders the client profile from env vars at start
- Push to `ghcr.io/<org>/hermes-pyme:<hermes-ver>-<bundle-ver>`

## Open questions to resolve before starting

- Same image as scheduler, or split? (PRD default: same.)
- How does `hermes skill install` behave inside Docker build context? Needs verification — may need to write skill files directly to `/opt/hermes/skills/<name>/` instead.
- Does the Nous install script require interactive stdin?

See PRD §M2 and the open questions list.
