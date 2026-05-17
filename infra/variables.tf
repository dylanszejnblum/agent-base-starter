# --- identity ---
variable "slug" {
  description = "Client slug. Used as VPS name, DNS subdomain, and resource tag. Lowercase alphanumerics and hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.slug))
    error_message = "Slug must be 3-32 chars, lowercase alphanumerics and hyphens, no leading/trailing hyphen."
  }
}

variable "domain" {
  description = "Parent domain managed in Cloudflare. The VPS will be reachable at <slug>.<domain>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain))
    error_message = "Domain must be a valid lowercase DNS name."
  }
}

# --- hetzner ---
variable "hcloud_location" {
  description = "Hetzner Cloud location. nbg1 = Nuremberg DE, fsn1 = Falkenstein DE, hel1 = Helsinki FI, ash = Ashburn US (closer to LATAM), hil = Hillsboro US."
  type        = string
  default     = "nbg1"

  validation {
    condition     = contains(["nbg1", "fsn1", "hel1", "ash", "hil"], var.hcloud_location)
    error_message = "Location must be one of: nbg1, fsn1, hel1, ash, hil."
  }
}

variable "hcloud_server_type" {
  description = "Hetzner server type. cx22 = 2 vCPU / 4 GB / 40 GB (~€4/mo). cpx21 = AMD 3 vCPU / 4 GB / 80 GB."
  type        = string
  default     = "cx22"
}

variable "hcloud_image" {
  description = "Hetzner base image. Pin to a Ubuntu LTS."
  type        = string
  default     = "ubuntu-24.04"
}

# --- access ---
variable "ssh_public_keys" {
  description = "Operator SSH public keys to attach to the VPS at provision time. Always include at least one; password login is disabled by cloud-init."
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "At least one SSH public key is required. Locked-out VPSes are not recoverable without provider console access."
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to reach SSH (port 22). Default 0.0.0.0/0 + ::/0 is open; lock down once support access pattern is decided."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

# --- cloudflare ---
variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for the parent domain. Find it in the Cloudflare dashboard sidebar."
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.cloudflare_zone_id))
    error_message = "Cloudflare zone ID is a 32-char lowercase hex string."
  }
}

variable "cloudflare_proxied" {
  description = "Whether DNS records are proxied through Cloudflare. Must be false for HTTP-01 ACME challenges to reach Caddy directly."
  type        = bool
  default     = false
}

variable "dns_ttl" {
  description = "TTL for DNS records, seconds. Low during deploy, raise after stable."
  type        = number
  default     = 300
}

# --- compose/runtime hooks (passed through to outputs for downstream scripts) ---
variable "image_tag" {
  description = "Image tag pin used downstream (e.g. for inventory). Not consumed by Terraform itself."
  type        = string
  default     = "m1-whoami"
}

variable "tags" {
  description = "Extra Hetzner labels to apply to all resources. Provider-supported chars only."
  type        = map(string)
  default     = {}
}
