output "server_id" {
  description = "Hetzner server numeric ID."
  value       = hcloud_server.client.id
}

output "ipv4" {
  description = "Public IPv4 of the server."
  value       = hcloud_server.client.ipv4_address
}

output "ipv6" {
  description = "Public IPv6 of the server (network /64; first address is appended for connectivity)."
  value       = hcloud_server.client.ipv6_address
}
