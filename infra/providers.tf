# Providers read tokens from env vars by convention:
#   HCLOUD_TOKEN              -> hcloud provider
#   VULTR_API_KEY             -> vultr provider
#   CLOUDFLARE_API_TOKEN      -> cloudflare provider
#
# Never set tokens here. The Makefile and bin/deploy-client both refuse to run
# without the env vars needed for the selected VPS provider.

provider "hcloud" {
  # In Vultr mode no hcloud resources are planned, but Terraform still
  # configures every declared provider. Use a harmless placeholder so Vultr
  # deploys do not require HCLOUD_TOKEN.
  token = var.vps_provider == "hetzner" ? null : "0000000000000000000000000000000000000000000000000000000000000000"
}

provider "vultr" {
  # Same pattern as hcloud: selected provider reads its real token from env;
  # inactive provider gets a placeholder to pass provider configuration.
  api_key = var.vps_provider == "vultr" ? null : "unused"
}

provider "cloudflare" {
  # api_token sourced from CLOUDFLARE_API_TOKEN env var
}
