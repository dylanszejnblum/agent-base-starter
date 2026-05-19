# Vultr Provider Runbook

Vultr is the second supported VPS provider. Hetzner remains the default; Vultr
is selected explicitly at deploy/destroy time or in `infra/terraform.tfvars`.

## Defaults

| Setting | Default | Why |
|---|---|---|
| `vps_provider` | `hetzner` | Existing production path remains unchanged. |
| `vultr_region` | `ord` | Matches the validated manual smoke test in Chicago. |
| `vultr_plan` | `vc2-2c-4gb` | 2 vCPU / 4 GB / 80 GB, enough headroom for Hermes. |
| `vultr_os_id` | `2284` | Ubuntu 24.04 LTS. |
| `vultr_backups` | `disabled` | Paid add-on; repo-managed backups are tracked separately. |

## Deploy

```bash
export VULTR_API_KEY='...'
export CLOUDFLARE_API_TOKEN='...'
export OPENAI_API_KEY='sk-...'

./bin/deploy-client acme --domain example.com --provider vultr
```

Optional overrides:

```bash
./bin/deploy-client acme --domain example.com \
  --provider vultr \
  --vultr-region mex \
  --vultr-plan vc2-2c-4gb \
  --vultr-os-id 2284
```

Use `mex` only after confirming the selected Cloud Compute plan is available in
that region.

## Destroy

Destroy must use the same provider as deploy unless `vps_provider` is pinned in
`infra/terraform.tfvars`.

```bash
export VULTR_API_KEY='...'
export CLOUDFLARE_API_TOKEN='...'

./bin/destroy-client acme --domain example.com --provider vultr --yes
```

## DNS

DNS is unchanged. Cloudflare remains the only DNS provider, and
`cloudflare_proxied=false` is still required for Caddy HTTP-01 issuance.

## Smoke Mode

For IP-only/no-domain validation, use the smoke override:

```bash
cd compose
docker compose -f docker-compose.yml -f docker-compose.smoke.yml --env-file .env up -d
```

This runs Caddy with `tls internal` and self-signed certificates for the
configured `FQDN` or IP. It is for throwaway smoke tests, not paying-client
deploys.
