variable "slug" {
  description = "Client slug. Used as the server name."
  type        = string
}

variable "location" {
  description = "Hetzner location, e.g. nbg1."
  type        = string
}

variable "server_type" {
  description = "Hetzner server type, e.g. cx22."
  type        = string
}

variable "image" {
  description = "Hetzner base image."
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH public-key strings to register and attach to the server."
  type        = list(string)
}

variable "user_data" {
  description = "Rendered cloud-init user-data."
  type        = string
}

variable "firewall_id" {
  description = "Firewall ID to attach to the server."
  type        = number
}

variable "labels" {
  description = "Hetzner labels."
  type        = map(string)
  default     = {}
}
