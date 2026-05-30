resource "hcloud_ssh_key" "default" {
  name       = "dvcorreia-yubikey"
  public_key = var.ssh_pub_key
}

# datacenters list:
# https://docs.hetzner.com/cloud/general/locations/#what-datacenters-are-there

data "hcloud_datacenter" "frankfurt_datacenter" {
  name = "fsn1-dc14"
}

# ----------- lena ----------- #

resource "hcloud_primary_ip" "lena_primary_ip" {
  name        = "lena-primary-ip"
  location    = data.hcloud_datacenter.frankfurt_datacenter.location.name
  type        = "ipv4"
  auto_delete = true
}

resource "hcloud_primary_ip" "lena_primary_ipv6" {
  name        = "lena-primary-ipv6"
  location    = data.hcloud_datacenter.frankfurt_datacenter.location.name
  type        = "ipv6"
  auto_delete = true
}

resource "hcloud_server" "lena" {
  name        = "lena"
  image       = "debian-13"
  server_type = "cx23"
  location    = data.hcloud_datacenter.frankfurt_datacenter.location.name
  ssh_keys    = [hcloud_ssh_key.default.id]
  public_net {
    ipv4 = hcloud_primary_ip.lena_primary_ip.id
    ipv6 = hcloud_primary_ip.lena_primary_ipv6.id
  }
}
