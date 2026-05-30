resource "cloudflare_access_rule" "lena_server_whitelist" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  notes   = "Allow lena server to bypass Bot Fight Mode"

  configuration = {
    target = "ip"
    value  = hcloud_primary_ip.lena_primary_ip.ip_address
  }

  mode = "whitelist"
}