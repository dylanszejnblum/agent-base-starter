variable "slug" {
  description = "Client slug. Used in firewall name."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to reach port 22. Use [\"0.0.0.0/0\", \"::/0\"] for open SSH."
  type        = list(string)
}

variable "labels" {
  description = "Hetzner labels."
  type        = map(string)
  default     = {}
}
