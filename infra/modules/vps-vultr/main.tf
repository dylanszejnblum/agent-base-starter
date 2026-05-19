locals {
  ssh_keys_by_id = {
    for idx, key in var.ssh_public_keys :
    "${var.slug}-${idx}" => key
  }

  instance_tags = distinct(concat(
    ["managed-by-self-contained-agent-base", "slug-${var.slug}"],
    [for key, value in var.labels : replace("${key}-${value}", "/[^A-Za-z0-9_-]/", "-")],
  ))

  ssh_v4_cidrs = {
    for cidr in var.allowed_ssh_cidrs : cidr => {
      subnet      = split("/", cidr)[0]
      subnet_size = tonumber(split("/", cidr)[1])
    } if can(regex("\\.", cidr))
  }

  ssh_v6_cidrs = {
    for cidr in var.allowed_ssh_cidrs : cidr => {
      subnet      = split("/", cidr)[0]
      subnet_size = tonumber(split("/", cidr)[1])
    } if can(regex(":", cidr))
  }
}

resource "vultr_ssh_key" "deploy" {
  for_each = local.ssh_keys_by_id

  name    = each.key
  ssh_key = trimspace(each.value)
}

resource "vultr_firewall_group" "client" {
  description = "${var.slug}-fw"
}

resource "vultr_firewall_rule" "ssh_v4" {
  for_each = local.ssh_v4_cidrs

  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = each.value.subnet
  subnet_size       = each.value.subnet_size
  port              = "22"
  notes             = "SSH"
}

resource "vultr_firewall_rule" "ssh_v6" {
  for_each = local.ssh_v6_cidrs

  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v6"
  subnet            = each.value.subnet
  subnet_size       = each.value.subnet_size
  port              = "22"
  notes             = "SSH"
}

resource "vultr_firewall_rule" "http_v4" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "80"
  notes             = "HTTP - ACME HTTP-01 and HTTPS redirect"
}

resource "vultr_firewall_rule" "http_v6" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v6"
  subnet            = "::"
  subnet_size       = 0
  port              = "80"
  notes             = "HTTP - ACME HTTP-01 and HTTPS redirect"
}

resource "vultr_firewall_rule" "https_v4" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "443"
  notes             = "HTTPS"
}

resource "vultr_firewall_rule" "https_v6" {
  firewall_group_id = vultr_firewall_group.client.id
  protocol          = "tcp"
  ip_type           = "v6"
  subnet            = "::"
  subnet_size       = 0
  port              = "443"
  notes             = "HTTPS"
}

resource "vultr_instance" "client" {
  label             = var.slug
  hostname          = var.slug
  region            = var.region
  plan              = var.plan
  os_id             = var.os_id
  enable_ipv6       = true
  backups           = var.backups
  user_data         = var.user_data
  ssh_key_ids       = [for key in vultr_ssh_key.deploy : key.id]
  firewall_group_id = vultr_firewall_group.client.id
  tags              = local.instance_tags
}
