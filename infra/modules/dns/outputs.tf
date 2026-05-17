output "record_id" {
  description = "Cloudflare A record ID."
  value       = cloudflare_record.a.id
}

output "aaaa_record_id" {
  description = "Cloudflare AAAA record ID, if created. Null when ipv6 is empty."
  value       = try(cloudflare_record.aaaa[0].id, null)
}
