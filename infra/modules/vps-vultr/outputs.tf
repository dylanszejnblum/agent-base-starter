output "instance_id" {
  description = "Vultr instance ID."
  value       = vultr_instance.client.id
}

output "ipv4" {
  description = "Public IPv4 of the instance."
  value       = vultr_instance.client.main_ip
}

output "ipv6" {
  description = "Public IPv6 of the instance, if assigned."
  value       = vultr_instance.client.v6_main_ip
}
