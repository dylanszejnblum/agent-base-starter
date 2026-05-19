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

# --- Hetzner VPS + firewall ---
module "firewall" {
  count  = var.vps_provider == "hetzner" ? 1 : 0
  source = "./modules/firewall"

  slug              = var.slug
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  labels            = local.labels
}

module "vps" {
  count  = var.vps_provider == "hetzner" ? 1 : 0
  source = "./modules/vps"

  slug            = var.slug
  location        = var.hcloud_location
  server_type     = var.hcloud_server_type
  image           = var.hcloud_image
  ssh_public_keys = var.ssh_public_keys
  user_data       = local.user_data
  firewall_id     = module.firewall[0].firewall_id
  labels          = local.labels
}

# --- Vultr VPS + firewall ---
module "vps_vultr" {
  count  = var.vps_provider == "vultr" ? 1 : 0
  source = "./modules/vps-vultr"

  slug              = var.slug
  region            = var.vultr_region
  plan              = var.vultr_plan
  os_id             = var.vultr_os_id
  backups           = var.vultr_backups
  ssh_public_keys   = var.ssh_public_keys
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  user_data         = local.user_data
  labels            = local.labels
}

locals {
  vps_ipv4 = coalesce(
    try(module.vps[0].ipv4, null),
    try(module.vps_vultr[0].ipv4, null),
  )

  vps_ipv6 = coalesce(
    try(module.vps[0].ipv6, null),
    try(module.vps_vultr[0].ipv6, null),
    "",
  )
}

# --- DNS ---
module "dns" {
  source = "./modules/dns"

  zone_id  = var.cloudflare_zone_id
  fqdn     = local.fqdn
  ipv4     = local.vps_ipv4
  ipv6     = local.vps_ipv6
  proxied  = var.cloudflare_proxied
  ttl      = var.dns_ttl
}
