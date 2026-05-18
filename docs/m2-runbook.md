# M2 deploy runbook

End-to-end walkthrough for deploying the real Hermes Agent stack (gateway + dashboard) on a fresh Hetzner VPS with Caddy basic_auth.

End state: `https://<slug>.<domain>/` redirects to the Hermes dashboard, gated by basic_auth, served over Let's Encrypt HTTPS. `https://<slug>.<domain>/health` returns `{"status":"ok",...}` without auth (for monitoring).

## What changed vs M1

| | M1 | M2 |
|---|---|---|
| App container | `traefik/whoami:v1.10` | `nousresearch/hermes-agent:main` × 2 services |
| Services | 2 (caddy + app) | 3 (caddy + hermes-gateway + hermes-dashboard) |
| Volumes | caddy only | caddy + `hermes_home` (`/opt/data`) |
| Caddy auth | none | basic_auth on everything except `/health` |
| Secrets | none required | `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` |
| First-boot config | n/a | Nous entrypoint copies `.env.example` → `/opt/data/.env`, creates profile dirs |
| Smoke tests | 8 (DNS, HTTPS, cert) | 14 (+ hermes binary, status, profile list, gateway running, basic_auth gate) |

## Prerequisites (delta from M1)

Everything from `docs/m1-runbook.md` **plus**:

| Requirement | How to verify |
|---|---|
| Docker on operator machine | `docker version` — needed locally to `caddy hash-password` |
| At least one LLM provider key | export `OPENAI_API_KEY=...` or `ANTHROPIC_API_KEY=...` |

The first boot of `hermes-dashboard` and `hermes-gateway` pulls a ~1.1 GB image. On a `cx22` from `nbg1` this is ~30–45 s.

## Deploy

```bash
export HCLOUD_TOKEN='...'
export CLOUDFLARE_API_TOKEN='...'
export OPENAI_API_KEY='sk-...'         # or ANTHROPIC_API_KEY

./bin/deploy-client demo --domain example.com
```

What you should see:

1. Terraform apply (~30 s on first run).
2. Cloud-init (~60–120 s).
3. DNS propagation (~10 s via Cloudflare).
4. `[info] generating dashboard password` — local `docker run --rm caddy:2-alpine caddy hash-password`.
5. `[info] rendering Caddyfile + .env`, `[info] syncing compose stack`.
6. `docker compose pull` — ~30–60 s on a fresh VPS (image is ~1.1 GB but Hetzner's bandwidth is good).
7. `docker compose up -d` — containers start; gateway initialises in ~10 s, dashboard in ~30 s.
8. Caddy issues LE cert (~15 s).
9. Smoke test summary: 14 passed, 0 failed.
10. `[ok] deploy complete` followed by the dashboard URL, username, and a one-time password.

Total: ~6–10 minutes on a clean Hetzner project.

## Capturing the password

At the end of the deploy you'll see something like:

```
[ok] deploy complete
[info] URL:      https://demo.example.com/
[info] SSH:      ssh deploy@203.0.113.42
[info] username: ops
[info] password: kJ8x_q3pP-bN2vR4fT9wYsLz
[warn] credentials also saved to: .deploy-credentials/demo.txt
```

**Move the password into 1Password immediately and delete the local file.**

The plaintext exists in three places at this point:

1. Your terminal scrollback — clear it: `clear && printf '\ec'` or close the tab.
2. `.deploy-credentials/<slug>.txt` (chmod 600, gitignored) — delete after capture: `shred -u .deploy-credentials/<slug>.txt` (Linux) or `rm -P .deploy-credentials/<slug>.txt` (macOS).
3. The bcrypt **hash** is in the VPS's `/opt/hermes-client/compose/.env` — that's fine; bcrypt is one-way.

To rotate the password later: rerun `bin/deploy-client <slug> --domain <domain>` — a new password is generated every time. Containers restart with the new hash within ~5 s.

## Verify

```bash
# Public health probe — no auth, used by monitoring
curl -sI https://demo.example.com/health
# HTTP/2 200

# Dashboard root — should challenge for basic_auth
curl -sI https://demo.example.com/
# HTTP/2 401  www-authenticate: Basic realm="restricted"

# Authenticated
curl -sI -u "ops:<password>" https://demo.example.com/
# HTTP/2 200  text/html

# Open in a browser:
open "https://ops:<password>@demo.example.com/"
```

From inside the VPS (handy for triage):

```bash
ssh deploy@<ip>
cd /opt/hermes-client/compose

# Container status
sudo docker compose ps

# Hermes self-check
sudo docker compose exec hermes-dashboard hermes status
sudo docker compose exec hermes-dashboard hermes doctor

# Logs
sudo docker compose logs -f hermes-dashboard
sudo docker compose logs -f hermes-gateway
sudo docker compose logs -f caddy
```

## Configuring the agent (first-time per-client setup)

The container's `/opt/data` volume holds Hermes's full home directory. On first boot Nous's entrypoint copies `.env.example` into `/opt/data/.env`. You then need to either:

**(a) Edit via the web dashboard.** Browse to the URL, log in, walk through the config UI. Settings are persisted to `/opt/data/config.yaml`.

**(b) Edit on the host.** `sudo $EDITOR /var/lib/docker/volumes/hermes_home/_data/config.yaml`. After saving, `sudo docker compose restart hermes-gateway hermes-dashboard`.

For the PyME pilot, configure at minimum:
- Default model + provider (matches your exported `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`).
- Profile name (we create the default profile via the slug; rename or create others via `hermes profile create`).
- Cron jobs (per the PRD: daily report at 8/9 AM, mail review every N minutes).

Skill bundle installation:

```bash
ssh deploy@<ip>
sudo docker compose exec hermes-dashboard hermes profile install <git-url-to-pyme-admin-core>
# or:
sudo docker compose exec hermes-dashboard hermes skills install <skill-name>
```

`pyme-admin-core` doesn't exist as a published distribution yet — see `skills/pyme-admin-core/README.md`.

## Common failure modes (M2-specific)

### `docker compose pull` times out

The Hermes image is large (~1.1 GB). On slow links this can take 5+ minutes. Default deploy timeout is 600s for SSH so we're fine, but the smoke test gating may run before the dashboard finishes its first-boot venv compile. If smoke tests show `dashboard reachable from caddy` failing on a fresh VPS, give it another 30 s and re-run `./scripts/smoke-test.sh <fqdn> --ssh-host deploy@<ip>`.

### `basic_auth` returns 401 even with correct creds

Check the hash got into `.env` correctly:

```bash
ssh deploy@<ip>
sudo grep HERMES_DASHBOARD /opt/hermes-client/compose/.env
# Should show:
#   HERMES_DASHBOARD_USERNAME=ops
#   HERMES_DASHBOARD_PASSWORD_HASH=$2a$14$...
# The hash should be ~60 chars and start with $2a$
```

Common cause: shell-expansion mangled the `$` chars when the rendered .env was copied. The deploy script writes via heredoc so this should not happen, but worth checking.

### Dashboard logs show "OPENAI_API_KEY not set"

You forgot to `export OPENAI_API_KEY` before running `deploy-client`. Fix by:

```bash
ssh deploy@<ip>
sudo $EDITOR /opt/hermes-client/compose/.env   # add OPENAI_API_KEY=sk-...
cd /opt/hermes-client/compose
sudo docker compose up -d        # picks up env changes, recreates containers
```

### "Permission denied" on /opt/data on first boot

The entrypoint should handle UID remap, but if you see this in logs:

```
ssh deploy@<ip>
sudo docker compose logs hermes-gateway | head -50
# Look for "Fixing ownership of /opt/data"
```

If the chown is failing, the named volume was likely created with the wrong owner. Nuclear option: `sudo docker compose down -v` (destroys data, only safe on a fresh deploy), then redeploy.

### Cert chain "internal" instead of Let's Encrypt

Same as M1: Caddy fell back to self-signed because ACME failed. Causes are unchanged from `docs/m1-runbook.md`. The only M2 wrinkle is: if you reuse a slug whose previous deploy already got a cert, the previous cert lives in `caddy_data` and will be served until renewal — destroy that volume on rebuild if you want fresh issuance.

## Teardown

Same as M1:

```bash
./bin/destroy-client demo --domain example.com
```

Volumes (including `hermes_home`) are destroyed. If you want to keep the client's data, back up the volume before running destroy — see `docs/backup-restore.md`.

## What this runbook does NOT cover

- 1Password integration (M3).
- Off-VPS backups (M4).
- Hardening pass + CI vuln scans (M5).
- `pyme-admin-core` skill bundle (own ticket — see `skills/pyme-admin-core/README.md`).
- Multi-profile management on one VPS (out of scope per PRD: one VPS per client).
