locals {
  fqdn = "${var.slug}.${var.domain}"

  base_labels = {
    "managed-by" = "self-contained-agent-base"
    "slug"       = var.slug
    "env"        = "client"
  }

  labels = merge(local.base_labels, var.tags)
}

# cloud-init is rendered from a template using templatefile() — works under
# Terraform and OpenTofu without the deprecated `template` provider. Inputs
# are non-secret only; secrets are pushed over SSH by bin/deploy-client
# after cloud-init signals completion.
locals {
  user_data = templatefile("${path.module}/../cloud-init/user-data.yaml.tmpl", {
    slug            = var.slug
    fqdn            = local.fqdn
    ssh_public_keys = var.ssh_public_keys
  })
}

# --- firewall ---
module "firewall" {
  source = "./modules/firewall"

  slug              = var.slug
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  labels            = local.labels
}

# --- VPS ---
module "vps" {
  source = "./modules/vps"

  slug            = var.slug
  location        = var.hcloud_location
  server_type     = var.hcloud_server_type
  image           = var.hcloud_image
  ssh_public_keys = var.ssh_public_keys
  user_data       = local.user_data
  firewall_id     = module.firewall.firewall_id
  labels          = local.labels
}

# --- DNS ---
module "dns" {
  source = "./modules/dns"

  zone_id  = var.cloudflare_zone_id
  fqdn     = local.fqdn
  ipv4     = module.vps.ipv4
  ipv6     = module.vps.ipv6
  proxied  = var.cloudflare_proxied
  ttl      = var.dns_ttl
}
