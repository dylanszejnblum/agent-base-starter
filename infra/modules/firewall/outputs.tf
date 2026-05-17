output "firewall_id" {
  description = "Hetzner firewall ID. Attach to servers via firewall_ids."
  value       = hcloud_firewall.client.id
}
