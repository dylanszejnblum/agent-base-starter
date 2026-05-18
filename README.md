```text
╭───────────────────────────────────────────────────────────────────────────────────╮
│                                                                                   │
│    █████╗  ██████╗ ███████╗███╗   ██╗████████╗   ██████╗  █████╗ ███████╗███████╗ │
│   ██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝   ██╔══██╗██╔══██╗██╔════╝██╔════╝ │
│   ███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║      ██████╔╝███████║███████╗█████╗   │
│   ██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║      ██╔══██╗██╔══██║╚════██║██╔══╝   │
│   ██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║      ██████╔╝██║  ██║███████║███████╗ │
│   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝ │
│                                                                                   │
│                a hermes agent in a box  ·  one command  ·  any VPS                │
│                                                                                   │
╰───────────────────────────────────────────────────────────────────────────────────╯
```

Single-command, production-grade installer for a containerized [Hermes Agent](https://github.com/NousResearch/hermes-agent) client instance on a fresh VPS. One operator command provisions infrastructure (Hetzner + Cloudflare + firewall), prepares the host (Docker + hardening), brings up Caddy + Hermes with automatic Let's Encrypt HTTPS, and runs a 14-point smoke test.

> [deploy runbook](docs/m3-runbook.md) · [secrets](secrets/README.md) · [security baseline](docs/secrets.md) · [support access](docs/support-access.md)

---

## Status — M3 (age secrets + pinned image)

| Milestone | State | Lands |
|---|---|---|
| M1 — Skeleton | ✓ done | Terraform (Hetzner + Cloudflare), cloud-init, compose with Caddy, smoke tests |
| M2 — Hermes services | ✓ done | Official `nousresearch/hermes-agent` image, gateway + dashboard, Caddy basic_auth |
| M3 — age secrets + image pin | ✓ done | `secrets/<slug>.env.age` (encrypted in repo), pinned Hermes SHA, stable dashboard password |
| M4 — Backups + runbooks | — | `scripts/backup-client.sh`, off-VPS sync, restore tested |
| M5 — Production-ready | — | fail2ban tuning, gitleaks/trivy in CI, first paying-client deploy |

Strategy & spec live in the sibling `agent-consultancy` repo:

- [PRD — Dockerized Hermes Client Instance Installer](../agent-consultancy/PRD%20—%20Dockerized%20Hermes%20Client%20Instance%20Installer.md)
- [AGCON-013 — Dockerized Hermes Client Installer](../agent-consultancy/Tickets/AGCON-013%20—%20Dockerized%20Hermes%20Client%20Installer.md)

## What it does — one screen

```text
        operator laptop                                   client VPS (Hetzner)
        ──────────────────                                ──────────────────────
        $ ./bin/deploy-client acme                        ┌──────────────────┐
                │                                         │   caddy:2-alpine │
                ├─ terraform apply ─────────────────────► │   ↓ basic_auth   │
                │   (hetzner + cloudflare + firewall)     ├──────────────────┤
                ├─ wait for SSH + cloud-init              │  hermes-gateway  │
                │   (Docker, ufw, fail2ban, deploy user)  │  hermes-dashboard│
                ├─ wait for DNS                           │   :9119 (proxied)│
                ├─ decrypt secrets/acme.env.age           ├──────────────────┤
                │   (age + ~/.config/age/operator.key)    │   /opt/data      │
                ├─ bcrypt-hash dashboard password         │   hermes_home    │
                ├─ rsync compose/ + .env (chmod 600)      │   volume         │
                ├─ docker compose pull + up -d            └──────────────────┘
                ├─ wait for HTTPS (LE issuance)
                ├─ 14-point smoke test
                └─ append client-inventory.md
```

## Quickstart

Full walkthrough: [`docs/m3-runbook.md`](docs/m3-runbook.md). Older milestone runbooks for reference: [M2](docs/m2-runbook.md), [M1](docs/m1-runbook.md).

```bash
# 1. One-time per operator: generate age key, add public key to recipients
brew install age   # or: apt install age
age-keygen -o ~/.config/age/operator.key && chmod 600 ~/.config/age/operator.key
age-keygen -y ~/.config/age/operator.key >> secrets/.recipients
git add secrets/.recipients && git commit -m "ops: add my age key"

# 2. Configure infra
cp infra/terraform.tfvars.example infra/terraform.tfvars
$EDITOR infra/terraform.tfvars   # slug, domain, ssh_public_keys, zone_id

# 3. Export tokens for this session
export HCLOUD_TOKEN=...
export CLOUDFLARE_API_TOKEN=...
export OPENAI_API_KEY=...        # seed for first-time init

# 4. Provision (first run prompts interactively if env keys missing)
./bin/deploy-client acme --domain example.com

# 5. Commit the encrypted secrets file
git add secrets/acme.env.age && git commit -m "ops: init acme secrets"

# 6. Verify
curl -sI https://acme.example.com/health   # 200, public
curl -sI https://acme.example.com/         # 401, requires basic_auth

# 7. Read the dashboard password (lives only in the encrypted file)
age -d -i ~/.config/age/operator.key secrets/acme.env.age \
  | grep HERMES_DASHBOARD_PASSWORD
```

End state: dashboard reachable at `https://<slug>.<domain>` behind basic_auth over Let's Encrypt HTTPS. Plaintext credentials never touch disk on the operator machine for longer than a single deploy command.

## Prerequisites

| | Why |
|---|---|
| Terraform `>= 1.6` (or OpenTofu) | Provisions VPS + DNS + firewall |
| `age` | Per-client secret encryption — `brew install age` / `apt install age` |
| `docker` (local) | Bcrypt-hashes dashboard passwords via a disposable `caddy:2-alpine` |
| `rsync`, `ssh`, `curl`, `dig`, `jq`, `openssl` | Standard, all preinstalled on macOS/Linux |
| Hetzner Cloud project + API token | The VPS |
| Cloudflare zone + API token (Zone:Read, DNS:Edit) | The subdomain + DNS |
| At least one of: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | Hermes's runtime provider |

See [`secrets/README.md`](secrets/README.md) for the one-time age key setup.

## Repo layout

```text
.
├── bin/                    # operator entrypoints
│   ├── deploy-client       # the single command
│   ├── destroy-client      # terraform destroy + DNS cleanup
│   └── lib/common.sh       # shared shell helpers (age, ssh, password)
├── infra/                  # Terraform: Hetzner + Cloudflare + firewall
│   ├── main.tf · variables.tf · outputs.tf · providers.tf · versions.tf
│   ├── backend.tf.example  # remote state (B2 / S3-compatible)
│   └── modules/{vps,dns,firewall}
├── cloud-init/
│   └── user-data.yaml.tmpl # Docker + deploy user + ufw + fail2ban
├── compose/
│   ├── docker-compose.yml       # caddy + hermes-gateway + hermes-dashboard
│   ├── docker-compose.local.yml # local dev override (self-signed)
│   ├── Caddyfile.tmpl
│   └── .env.example
├── secrets/                # age-encrypted per-client envs (tracked, encrypted)
│   ├── README.md
│   ├── .recipients         # operator age public keys
│   ├── .env.example        # plaintext schema reference
│   └── <slug>.env.age      # per-client, created on first deploy
├── scripts/                # building blocks
│   ├── wait-for-{ssh,dns,https}.sh
│   ├── smoke-test.sh       # 14 checks: DNS, HTTPS, cert, container health, hermes
│   ├── append-inventory.sh
│   ├── backup-client.sh    # M4 stub
│   └── restore-client.sh   # M4 stub
├── docs/
│   ├── m3-runbook.md       # current
│   ├── m2-runbook.md       # historical
│   ├── m1-runbook.md       # historical
│   ├── secrets.md
│   ├── support-access.md
│   ├── client-inventory.md # auto-maintained
│   ├── rollback.md
│   ├── backup-restore.md   # M4
│   └── incident-runbook.md # M5
├── images/hermes/          # M2.5+: custom image only if baking a skill bundle
├── skills/                 # M2.5+: vendored skill bundles per agent
├── .github/workflows/      # gitleaks · terraform-validate · shellcheck
├── .gitleaks.toml
└── Makefile
```

## Security baseline

| | |
|---|---|
| Secrets at rest | `age`-encrypted in `secrets/<slug>.env.age`, committed to repo |
| Secrets in transit | over SSH, file chmod 600 on both ends |
| Plaintext on operator disk | only during single deploy command, then `shred`/`rm -P` |
| Dashboard credentials | bcrypt-hashed via `caddy:2-alpine` before they reach the VPS |
| Terraform state | never committed; remote backend documented in `infra/backend.tf.example` |
| Host hardening | SSH key-only, no root, `ufw` 22/80/443, `fail2ban` on sshd, unattended security upgrades |
| Container hardening | `cap_drop ALL`, `no-new-privileges`, non-root user, named volumes |
| CI gates | `gitleaks` blocks committed secrets; `.env.age` allowlisted, plaintext `secrets/*.env` flagged |

See [`docs/secrets.md`](docs/secrets.md) and [`docs/support-access.md`](docs/support-access.md).

## Workflow

```
feat/<slug>  ──PR──▶  develop  ──release PR──▶  main
```

- New work branches from `develop` (the default branch)
- Feature branches: `feat/<short-slug>`
- PRs target `develop` automatically
- Releases happen via a `develop → main` PR, tagged `v0.x.0`

## License

Internal — not for public distribution. Future: open-source.

---

<sub>built by [polh.io](https://polh.io) · runs [Hermes Agent](https://github.com/NousResearch/hermes-agent) by [Nous Research](https://nousresearch.com)</sub>
