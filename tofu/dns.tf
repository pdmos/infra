locals {
  dns_record_comment = "Managed by OpenTofu (gh:pdmos/infra)"
}

locals {
  pdmos_pt_domain = "pdmos.pt"
  pdmos_pt_subdomains = {
    id = {
      proxied     = true
      description = "Pocket ID OIDC server"
    }
    ts = {
      proxied     = false # https://headscale.net/stable/ref/integration/reverse-proxy/#cloudflare
      ttl         = 3600
      description = "Headscale server"
    }
  }
}

data "cloudflare_zone" "pdmos_pt" {
  zone_id = "cbb59031587371c5e68c8f6741def05d"
}

resource "cloudflare_dns_record" "pdmos_pt_cname" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "www"
  content = local.pdmos_pt_domain
  type    = "CNAME"
  proxied = true
  ttl     = 1
  comment = local.dns_record_comment
}

resource "cloudflare_dns_record" "pdmos_pt_a" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "@"
  content = hcloud_primary_ip.lena_primary_ip.ip_address
  type    = "A"
  proxied = true
  ttl     = 1
  comment = local.dns_record_comment
}

resource "cloudflare_dns_record" "pdmos_pt_aaaa" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "@"
  content = hcloud_primary_ip.lena_primary_ipv6.ip_address
  type    = "AAAA"
  proxied = true
  ttl     = 1
  comment = local.dns_record_comment
}

resource "cloudflare_dns_record" "pdmos_pt_subdomain_a" {
  for_each = local.pdmos_pt_subdomains

  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "${each.key}.${local.pdmos_pt_domain}"
  content = hcloud_primary_ip.lena_primary_ip.ip_address
  type    = "A"

  proxied = try(each.value.proxied, true)
  ttl     = try(each.value.ttl, 1)

  comment = join(
    " | ",
    compact([
      try(each.value.description, null),
      local.dns_record_comment,
    ])
  )
}

resource "cloudflare_dns_record" "pdmos_pt_subdomain_aaaa" {
  for_each = local.pdmos_pt_subdomains

  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "${each.key}.${local.pdmos_pt_domain}"
  content = hcloud_primary_ip.lena_primary_ipv6.ip_address
  type    = "AAAA"

  proxied = try(each.value.proxied, true)
  ttl     = try(each.value.ttl, 1)

  comment = join(
    " | ",
    compact([
      try(each.value.description, null),
      local.dns_record_comment,
    ])
  )
}