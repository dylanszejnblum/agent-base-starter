# Secrets handling

## Principle

No secret value is ever committed in plaintext, in Terraform state, or in a container image. Secrets at rest in the repo are **age-encrypted**; addressable only to operator public keys listed in `secrets/.recipients`.

Three trust boundaries:

1. **Operator machine** — holds the age private key, the operator's OpenAI/Anthropic key, the compute-provider/Cloudflare tokens. Tokens are env vars per session; the age key is a file on disk (chmod 600).
2. **VPS host** — holds `/opt/hermes-client/compose/.env` (chmod 600, owned by `deploy`). This file is the only thing Docker reads. The dashboard password lands here as a **bcrypt hash**, never plaintext.
3. **Container** — receives secrets as env vars at start time. No secret is written to disk inside containers.

## Map of what lives where

| Secret | Where it lives | Who can read it |
|---|---|---|
| `HCLOUD_TOKEN` / `VULTR_API_KEY` | Operator env, password manager | Operator |
| `CLOUDFLARE_API_TOKEN` | Operator env, password manager | Operator |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | `secrets/<slug>.env.age` (encrypted, in repo) | Operators whose public keys are in `.recipients` |
| `HERMES_DASHBOARD_PASSWORD` (plaintext) | Same encrypted file | Same |
| `HERMES_DASHBOARD_PASSWORD_HASH` (bcrypt) | `/opt/hermes-client/compose/.env` on VPS | `deploy` user on VPS; Caddy container at runtime |
| Caddy LE account key | `caddy_data` named volume on VPS | Caddy container only |
| age private key (operator's) | `~/.config/age/operator.key` on operator's machine | The operator |

## Workflow — see `secrets/README.md` for full procedures

Quick reference:

```bash
# One-time per operator
age-keygen -o ~/.config/age/operator.key
chmod 600 ~/.config/age/operator.key
age-keygen -y ~/.config/age/operator.key >> secrets/.recipients
git add secrets/.recipients && git commit -m "ops: add my age key"

# Per-client init (automatic on first deploy of a slug)
./bin/deploy-client <slug> --domain <domain>
# -> detects missing secrets/<slug>.env.age
# -> prompts for OPENAI_API_KEY (or reads from env)
# -> generates random dashboard password
# -> encrypts to secrets/<slug>.env.age
# (operator commits the file afterwards)

# Edit existing secrets
age -d -i ~/.config/age/operator.key secrets/<slug>.env.age > /tmp/<slug>.env
$EDITOR /tmp/<slug>.env
age -R secrets/.recipients -o secrets/<slug>.env.age /tmp/<slug>.env
shred -u /tmp/<slug>.env  # rm -P on macOS

# Read the dashboard password (the only common read-only operation)
age -d -i ~/.config/age/operator.key secrets/<slug>.env.age | grep HERMES_DASHBOARD_PASSWORD
```

## How secrets get to the VPS

At deploy time `bin/deploy-client`:

1. Decrypts `secrets/<slug>.env.age` → ephemeral file (chmod 600, in a tmpdir).
2. Sources that file into its own env.
3. Bcrypt-hashes the plaintext dashboard password via a disposable `caddy:2-alpine` container.
4. Writes the VPS-side `.env` containing **the hash** plus the LLM keys.
5. `scp`s the .env, then `chmod 600` on the VPS.
6. Shreds the ephemeral plaintext file on the operator's machine.

The plaintext dashboard password is **never** echoed to stdout, written to disk uncrypted on the operator machine for longer than the lifetime of a single deploy command, or transmitted over the wire.

## Rotation

### Dashboard password

```bash
age -d -i ~/.config/age/operator.key secrets/<slug>.env.age > /tmp/<slug>.env
# edit HERMES_DASHBOARD_PASSWORD line in /tmp/<slug>.env
age -R secrets/.recipients -o secrets/<slug>.env.age /tmp/<slug>.env
shred -u /tmp/<slug>.env
./bin/deploy-client <slug> --domain <domain>   # re-renders + restarts caddy
```

Caddy restarts in ~5 s. No data loss.

### LLM provider key

Same flow. Hermes restarts in ~30 s once the new env propagates.

### age operator key (own key compromised or rotating staff)

See `secrets/README.md` § "Rotating a leaked operator key". Remove the public key from `.recipients`, re-encrypt every `.env.age` so older versions become unreadable to that key, and rotate the underlying secrets (LLM keys etc) because the leaked key may have decrypted earlier versions before rotation.

## Terraform state secrets

Terraform state can contain sensitive values. We pass tokens via env so they don't end up in state, but verify before each migration.

- **Local state:** `infra/terraform.tfstate` is in `.gitignore`. Keep on encrypted disk.
- **Remote state (recommended pre-pilot):** Backblaze B2 with S3-compatible API. Bucket scoped per environment. See `infra/backend.tf.example`.
- Never share state files via Slack/email. Use `terraform output -json` to share specific values.

## CI

`gitleaks` runs on every PR (`.github/workflows/gitleaks.yml`). Allowlist is in `.gitleaks.toml`:

- `*.env.age` files are allowlisted (encrypted by design — high-entropy ciphertext is not a leak).
- `secrets/<slug>.env` (plaintext) is **explicitly flagged** as a rule violation, defence in depth on top of `.gitignore`.

If gitleaks flags a real secret accidentally committed: rotate the secret first, then rewrite history second.

## Why age and not 1Password / SOPS / Doppler

| | age (chosen) | SOPS | 1Password | Doppler |
|---|---|---|---|---|
| Cost | free | free | $4-8/mo | free tier |
| SaaS dependency | no | no | yes | yes |
| Files in git | encrypted | encrypted | no | no |
| Team-friendly UI | no | no | yes | yes |
| Solo-dev simplicity | best | good | good | good |

age is the right fit for solo-dev / small-team. Migrate to 1Password or SOPS later when team size / structured-config needs justify it.
