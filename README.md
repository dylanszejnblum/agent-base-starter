# self-contained-agent-base

Single-command, production-grade installer for a containerized Hermes Agent client instance on a fresh VPS.

One operator command provisions infrastructure (Hetzner VPS + Cloudflare DNS + firewall), prepares the host (Docker, hardening), brings up a Dockerized Hermes + Caddy stack with automatic Let's Encrypt HTTPS, and runs smoke tests against `https://<slug>.<domain>`.

## Status — M1 skeleton

| Milestone | State | What works |
|---|---|---|
| M1 — Skeleton | **in progress** | Terraform (Hetzner + Cloudflare), cloud-init, compose with Caddy + `whoami` placeholder, smoke tests |
| M2 — Hermes image | not started | Custom `images/hermes/` Dockerfile, swap whoami → hermes |
| M3 — Single command | not started | `bin/deploy-client` fully wired end-to-end |
| M4 — Backups + runbooks | not started | `scripts/backup-client.sh`, off-VPS sync, restore tested |
| M5 — Production-ready | not started | fail2ban tuning, gitleaks/trivy in CI, first paying-client deploy |

PRD: `../agent-consultancy/PRD — Dockerized Hermes Client Instance Installer.md`
Ticket: `../agent-consultancy/Tickets/AGCON-013 — Dockerized Hermes Client Installer.md`

## Repo layout

```text
.
├── bin/                    # operator entrypoints
│   ├── deploy-client       # single-command deploy (M1 wires terraform + compose)
│   ├── destroy-client      # terraform destroy + DNS cleanup
│   └── lib/                # shared shell helpers
├── infra/                  # Terraform / OpenTofu
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── versions.tf
│   ├── backend.tf.example  # remote state config (B2/S3-compatible)
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vps/            # Hetzner cloud server + SSH key
│       ├── dns/            # Cloudflare A record
│       └── firewall/       # Hetzner cloud firewall
├── cloud-init/
│   └── user-data.yaml.tmpl # bootstraps Docker + deploy user + ufw + fail2ban
├── compose/
│   ├── docker-compose.yml      # Caddy + app (whoami in M1, hermes in M2)
│   ├── docker-compose.local.yml # local dev override (self-signed)
│   ├── Caddyfile.tmpl
│   └── .env.example
├── images/
│   └── hermes/             # M2: custom Hermes image
├── scripts/                # reusable building blocks
│   ├── wait-for-ssh.sh
│   ├── wait-for-dns.sh
│   ├── wait-for-https.sh
│   ├── smoke-test.sh
│   ├── append-inventory.sh
│   ├── backup-client.sh    # M4 stub
│   └── restore-client.sh   # M4 stub
├── skills/
│   └── pyme-admin-core/    # M2: vendored/submoduled skill bundle
├── templates/
│   └── client.env.tmpl     # 1Password placeholders
├── docs/
│   ├── m1-runbook.md       # manual + script-assisted M1 deploy walkthrough
│   ├── secrets.md
│   ├── support-access.md
│   ├── client-inventory.md
│   ├── rollback.md         # M3+
│   ├── backup-restore.md   # M4
│   └── incident-runbook.md # M5
├── .github/workflows/
│   ├── gitleaks.yml        # secret scanner
│   └── terraform-validate.yml
├── .gitignore
├── .gitleaks.toml
├── .editorconfig
└── Makefile
```

## Prerequisites

On the operator machine:

- Terraform `>= 1.6` or OpenTofu `>= 1.6`
- Docker (only needed for local dev with `docker-compose.local.yml`)
- `rsync`, `ssh`, `curl`, `dig`, `jq` (all standard)
- A Hetzner Cloud project + API token
- A domain delegated to Cloudflare (or willingness to set this up before M1 completes)
- A Cloudflare API token scoped to the zone (Zone:Read, DNS:Edit)
- 1Password CLI `op` for secret injection (required in M3; optional in M1)

## M1 quickstart

See [`docs/m1-runbook.md`](docs/m1-runbook.md) for the full walkthrough. Short version:

```bash
# 1. Configure
cp infra/terraform.tfvars.example infra/terraform.tfvars
$EDITOR infra/terraform.tfvars   # set slug, domain, region, ssh_public_key

# 2. Export tokens (never commit these)
export HCLOUD_TOKEN=...
export CLOUDFLARE_API_TOKEN=...

# 3. Provision
./bin/deploy-client <slug> --domain <your-domain>

# 4. Verify
curl -sI https://<slug>.<your-domain>/health
```

End state: `https://<slug>.<domain>` returns the `whoami` placeholder over a valid Let's Encrypt cert.

## Security baseline

- No secrets in repo (`.gitignore` + `gitleaks` CI gate).
- Terraform state never committed; remote backend documented in `infra/backend.tf.example`.
- SSH key-only on the VPS, `ufw` open for 22/80/443 only, `fail2ban` on sshd.
- Docker daemon never exposed on TCP; only Caddy publishes ports.
- `.env` on host is chmod 600, owned by the `deploy` user.

See [`docs/secrets.md`](docs/secrets.md) and [`docs/support-access.md`](docs/support-access.md).

## License

Internal — not for public distribution.
