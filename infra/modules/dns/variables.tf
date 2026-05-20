variable "zone_id" {
  description = "Cloudflare zone ID for the parent domain."
  type        = string
}

variable "fqdn" {
  description = "Fully qualified domain name to create (e.g. acme.example.com)."
  type        = string
}

variable "ipv4" {
  description = "IPv4 address the FQDN should resolve to."
  type        = string
}

variable "ipv6" {
  description = "IPv6 address the FQDN should resolve to. Pass empty string to skip."
  type        = string
  default     = ""
}

variable "create_ipv6_record" {
  description = "Whether to create an AAAA record. Must be known at plan time."
  type        = bool
  default     = true
}

variable "proxied" {
  description = "Cloudflare proxy/orange-cloud. Must be false for HTTP-01 ACME via Caddy."
  type        = bool
  default     = false
}

variable "ttl" {
  description = "DNS TTL seconds. Cloudflare ignores this when proxied=true."
  type        = number
  default     = 300
}
