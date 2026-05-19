output "slug" {
  description = "Client slug."
  value       = var.slug
}

output "fqdn" {
  description = "Fully qualified domain name the VPS is reachable at."
  value       = local.fqdn
}

output "ipv4" {
  description = "Public IPv4 of the VPS."
  value       = local.vps_ipv4
}

output "ipv6" {
  description = "Public IPv6 of the VPS, if assigned."
  value       = local.vps_ipv6
}

output "ssh_host" {
  description = "Convenience SSH target string. Use `ssh deploy@$(terraform output -raw ssh_host)` once cloud-init completes."
  value       = "deploy@${local.vps_ipv4}"
}

output "image_tag" {
  description = "Image tag recorded for this deploy. Pass to inventory."
  value       = var.image_tag
}

output "hetzner_server_id" {
  description = "Hetzner server ID. Useful for support requests to Hetzner."
  value       = try(module.vps[0].server_id, null)
}

output "vultr_instance_id" {
  description = "Vultr instance ID. Useful for support requests to Vultr."
  value       = try(module.vps_vultr[0].instance_id, null)
}

output "vps_provider" {
  description = "Selected VPS provider."
  value       = var.vps_provider
}

output "dns_record_id" {
  description = "Cloudflare DNS record ID."
  value       = module.dns.record_id
}
