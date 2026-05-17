# Providers read tokens from env vars by convention:
#   HCLOUD_TOKEN              -> hcloud provider
#   CLOUDFLARE_API_TOKEN      -> cloudflare provider
#
# Never set tokens here. The Makefile and bin/deploy-client both refuse to run
# without the env vars present.

provider "hcloud" {
  # token sourced from HCLOUD_TOKEN env var
}

provider "cloudflare" {
  # api_token sourced from CLOUDFLARE_API_TOKEN env var
}
