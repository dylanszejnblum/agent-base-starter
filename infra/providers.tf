# Providers read tokens from env vars by convention:
#   HCLOUD_TOKEN              -> hcloud provider
#   VULTR_API_KEY             -> vultr provider
#   CLOUDFLARE_API_TOKEN      -> cloudflare provider
#
# Never set tokens here. The Makefile and bin/deploy-client both refuse to run
# without the env vars needed for the selected VPS provider.

provider "hcloud" {
  # token sourced from HCLOUD_TOKEN env var
}

provider "vultr" {
  # api_key sourced from VULTR_API_KEY env var
}

provider "cloudflare" {
  # api_token sourced from CLOUDFLARE_API_TOKEN env var
}
