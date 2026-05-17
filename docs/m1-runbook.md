# M1 deploy runbook

End-to-end walkthrough for deploying the M1 placeholder stack (Caddy + whoami) to a fresh Hetzner VPS with a Cloudflare-managed domain.

End state: `https://<slug>.<domain>/` returns the whoami page over a valid Let's Encrypt certificate. `https://<slug>.<domain>/health` returns `{"status":"ok","fqdn":"<slug>.<domain>"}`.

## Prerequisites

| Requirement | How to verify |
|---|---|
| Terraform >= 1.6 | `terraform version` |
| `ssh`, `rsync`, `dig`, `curl`, `openssl`, `jq` | `command -v <each>` |
| Hetzner Cloud project | https://console.hetzner.cloud |
| Hetzner API token | Cloud Console → Security → API tokens → "Generate" (read+write) |
| Domain on Cloudflare | Cloudflare dashboard shows the zone as active |
| Cloudflare zone ID | Cloudflare dashboard → overview sidebar |
| Cloudflare API token | My Profile → API Tokens → Create. Permissions: `Zone:Read`, `DNS:Edit`. Zone resource: limit to the specific zone. |
| SSH public key | `cat ~/.ssh/id_ed25519.pub` |

## One-time setup

```bash
cd /Users/dylanszejnblum/Documents/self-contained-agent-base

# Configure variables
cp infra/terraform.tfvars.example infra/terraform.tfvars
$EDITOR infra/terraform.tfvars
# fill in: slug, domain, ssh_public_keys, cloudflare_zone_id

# Export credentials for the session (never commit these)
export HCLOUD_TOKEN='<your-hetzner-token>'
export CLOUDFLARE_API_TOKEN='<your-cloudflare-token>'

# Validate the Terraform stack compiles
terraform -chdir=infra init
terraform -chdir=infra validate
```

## Deploy

```bash
./bin/deploy-client demo --domain example.com
```

What you should see, in order:

1. `terraform init` — provider download (~10 s first time).
2. `terraform apply` — creates SSH key, firewall, server, DNS records (~30 s).
3. `[info] waiting for SSH on deploy@<ip>` — cloud-init is running; expect ~60–120 s.
4. `[ok] ssh up` then `[ok] cloud-init done`.
5. `[info] waiting for <fqdn> -> <ip>` — DNS propagation; Cloudflare is usually <10 s.
6. `[info] rendering Caddyfile + .env`, `[info] syncing compose stack`, `[info] docker compose up -d`.
7. `[info] waiting for https://<fqdn>/health` — Caddy issues the LE cert here; ~15–60 s on first issuance.
8. `[ok] $URL returns 200 with cert issued by: Let's Encrypt`.
9. Smoke test summary: 8 passed, 0 failed (DNS, HTTPS, cert, compose health, etc).
10. `[ok] deploy complete`.

Total: ~5–8 minutes end to end on a clean Hetzner project.

## Verify

```bash
# From your laptop
curl -sI https://<slug>.<domain>/health
# Expect: HTTP/2 200, content-type: text/plain

curl https://<slug>.<domain>/
# Expect: whoami body with Hostname, IP, RemoteAddr, etc.

# Cert chain
echo | openssl s_client -servername <slug>.<domain> -connect <slug>.<domain>:443 2>/dev/null \
  | openssl x509 -noout -issuer -dates
# Expect: issuer=C = US, O = Let's Encrypt, CN = R3 (or E5/E6)
```

## Common failure modes

### `terraform apply` fails with `401 Unauthorized`

Token is wrong or scoped too narrowly.

- Hetzner: token must have read+write on the project.
- Cloudflare: token must have `DNS:Edit` on the specific zone. `Zone:Read` alone is not enough.

### `wait-for-ssh.sh` times out

Cloud-init is still running or never ran. SSH in with `ssh root@<ip>` (root works on first boot if the SSH key was attached) and check:

```bash
sudo cloud-init status --long
sudo tail -100 /var/log/cloud-init-output.log
```

Common cause: cloud-init failed to install Docker — usually a transient apt mirror failure. Re-running `sudo cloud-init clean --logs && sudo cloud-init init` may recover, but the production fix is `terraform destroy` and try again.

### `wait-for-dns.sh` times out

Two causes:

1. **Wrong zone ID.** Cloudflare silently accepted the record on a different zone; `dig` won't find it. Verify in the Cloudflare DNS tab.
2. **Domain not actually on Cloudflare.** Run `dig NS <domain>` — if it's not Cloudflare nameservers, fix delegation at the registrar first.

### `wait-for-https.sh` times out, cert is "internal"

Caddy could not complete the HTTP-01 challenge. Causes:

- Cloudflare proxy on: `cloudflare_proxied = false` is required.
- Firewall blocking 80/tcp inbound.
- DNS not propagated yet on the LE servers (rare; usually waits resolve this).

SSH in and check Caddy logs:

```bash
ssh deploy@<ip> 'sudo docker compose -f /opt/hermes-client/compose/docker-compose.yml logs caddy --tail=100'
```

### Smoke test fails on cert expiry parsing

On macOS, `date -j -f` is BSD and parses LE date strings differently than GNU date. Install `coreutils` (`brew install coreutils`) and the test will pick up `gdate` automatically — or just ignore that one specific failure for now.

## Teardown

```bash
./bin/destroy-client demo --domain example.com
# type the slug to confirm
```

This destroys VPS + DNS + firewall and marks the inventory row as `destroyed` (does not delete the historical record).

## What this runbook does NOT cover

- M2 (Hermes image), M3 (secret injection from 1Password), M4 (backups), M5 (CI hardening).
- Local dev workflow: see `compose/docker-compose.local.yml` and `make local-up`.
- Off-VPS backup destination: documented in `docs/backup-restore.md` (stub).
- Support access rotation: `docs/support-access.md`.
