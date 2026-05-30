variable "passphrase" {
  sensitive   = true
  description = "OpenTofu state/plan passphrase"
}

variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token"
  sensitive   = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with access to the required zones"
}

variable "ssh_pub_key" {
  type        = string
  description = "Public SSH key that will be copied on the VMs"
}
