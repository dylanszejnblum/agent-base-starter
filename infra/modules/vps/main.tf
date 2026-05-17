# Register each provided SSH public key with Hetzner. Names are derived from
# the key's comment field where present, falling back to a slug+index name.
# `for_each` keeps state stable across reorderings.
locals {
  ssh_keys_by_id = {
    for idx, key in var.ssh_public_keys :
    "${var.slug}-${idx}" => key
  }
}

resource "hcloud_ssh_key" "deploy" {
  for_each = local.ssh_keys_by_id

  name       = each.key
  public_key = trimspace(each.value)
  labels     = var.labels
}

resource "hcloud_server" "client" {
  name        = var.slug
  image       = var.image
  server_type = var.server_type
  location    = var.location
  user_data   = var.user_data
  labels      = var.labels

  ssh_keys     = [for k in hcloud_ssh_key.deploy : k.id]
  firewall_ids = [var.firewall_id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # Recreate if user_data changes — cloud-init only runs on first boot.
  # Without this, a user_data edit would be silently ignored.
  lifecycle {
    create_before_destroy = false
    replace_triggered_by  = []
  }
}
