resource "cloudflare_record" "a" {
  zone_id = var.zone_id
  name    = var.fqdn
  type    = "A"
  content = var.ipv4
  ttl     = var.ttl
  proxied = var.proxied
  comment = "managed-by:self-contained-agent-base"
}

resource "cloudflare_record" "aaaa" {
  count = var.create_ipv6_record ? 1 : 0

  zone_id = var.zone_id
  name    = var.fqdn
  type    = "AAAA"
  content = var.ipv6
  ttl     = var.ttl
  proxied = var.proxied
  comment = "managed-by:self-contained-agent-base"
}
