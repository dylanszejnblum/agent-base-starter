# Secrets handling

## Principle

No secret value is ever in the repo, in Terraform state, or in a container image.

Three trust boundaries:

1. **Operator machine** — holds API tokens (Hetzner, Cloudflare, 1Password). Sourced from env or 1Password CLI per session.
2. **VPS host** — holds `/opt/hermes-client/compose/.env` (chmod 600, owned by `deploy`). This file is the only thing Docker reads.
3. **Container** — receives secrets as env vars at start time. No file mount of secrets.

## What lives where

| Secret | Where it lives | Who can read it |
|---|---|---|
| `HCLOUD_TOKEN` | Operator env, 1Password vault | Operator only |
| `CLOUDFLARE_API_TOKEN` | Operator env, 1Password vault | Operator only |
| LLM API keys (`OPENAI_API_KEY`, etc) | `/opt/hermes-client/compose/.env` on the VPS | `deploy` user; running containers via Compose `env_file` |
| Client API keys, OAuth tokens | Same as above | Same |
| Backup encryption key (M4) | `/opt/hermes-client/secrets/age.key` (chmod 600) | `deploy` user; backup container |
| Caddy LE account key | `caddy_data` named volume | Caddy container only |

## How secrets get to the VPS

**M1 (current):** manual. Operator copies the rendered `.env` over SSH and chmods it. `bin/deploy-client` already does this — see the "render templates" and "rsync compose stack" sections of the script.

**M3 (target):** `bin/deploy-client` resolves placeholders from 1Password via `op inject`:

```bash
op inject -i templates/client.env.tmpl -o /tmp/<slug>.env
scp /tmp/<slug>.env deploy@<ip>:/opt/hermes-client/compose/.env
ssh deploy@<ip> 'chmod 600 /opt/hermes-client/compose/.env'
shred -u /tmp/<slug>.env
```

`templates/client.env.tmpl` contains lines like:

```
OPENAI_API_KEY=op://hermes-clients/<slug>/openai/api-key
```

The operator must be `op signin`'d before running deploy-client.

## Rotation

1. Update the value in 1Password (or wherever the source of truth lives).
2. Re-run `bin/deploy-client <slug> --domain <domain>` — it re-renders `.env` and re-runs `docker compose up -d`, which restarts containers with new env.

Container restart is fast (~5s for caddy/whoami; M2 Hermes restart time TBD). No data loss because state lives in named volumes.

## What never gets logged

- `.env` content
- Token values in script output
- Cloud-init runcmd outputs that touch tokens

`bin/deploy-client` does not echo secrets. If you add new env vars, do not `set -x` near them.

## Terraform state secrets

Terraform state can contain sensitive values (Cloudflare API tokens never end up in state because they're env-supplied to the provider, but check before each migration).

- **Local state:** `infra/terraform.tfstate` is in `.gitignore`. Keep on encrypted disk.
- **Remote state (recommended for M3+):** Backblaze B2 with S3-compatible API. Bucket scoped per-environment. See `infra/backend.tf.example`.
- Never share state files via Slack/email. Use `terraform output -json` to share specific values.

## CI

`gitleaks` runs on every PR (see `.github/workflows/gitleaks.yml`). Allowlist is in `.gitleaks.toml`. If gitleaks flags a real secret accidentally committed: rotate the secret first, then rewrite history second.
