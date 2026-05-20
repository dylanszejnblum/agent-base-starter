variable "slug" {
  description = "Client slug. Used as the instance label and hostname."
  type        = string
}

variable "region" {
  description = "Vultr region code, e.g. ord or mex."
  type        = string
}

variable "plan" {
  description = "Vultr plan ID, e.g. vc2-2c-4gb."
  type        = string
}

variable "os_id" {
  description = "Vultr OS ID, e.g. Ubuntu 24.04 LTS."
  type        = number
}

variable "backups" {
  description = "Vultr automatic backups setting: enabled or disabled."
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH public-key strings to register and attach to the instance."
  type        = list(string)
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to reach port 22."
  type        = list(string)
}

variable "user_data" {
  description = "Rendered cloud-init user-data."
  type        = string
}

variable "labels" {
  description = "Common labels from the root module. Vultr receives these as best-effort tags on the instance."
  type        = map(string)
  default     = {}
}
