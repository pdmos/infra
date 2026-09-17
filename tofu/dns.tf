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
    matrix = {
      proxied     = true
      description = "Matrix homeserver (tuwunel)"
    }
    mail = {
      proxied     = false
      ttl         = 3600
      description = "Mail server"
    }
    srs = {
      proxied     = false
      ttl         = 3600
      description = "Sender Rewriting Scheme domain"
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

resource "cloudflare_dns_record" "pdmos_pt_mx" {
  zone_id  = data.cloudflare_zone.pdmos_pt.id
  name     = "@"
  content  = "mail.pdmos.pt"
  type     = "MX"
  ttl      = 3600
  priority = 10
  comment  = "Mail server MX record | ${local.dns_record_comment}"
}

resource "cloudflare_dns_record" "pdmos_pt_spf" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "@"
  content = "v=spf1 mx -all"
  type    = "TXT"
  ttl     = 86400
  comment = "SPF record for mail server | ${local.dns_record_comment}"
}

resource "cloudflare_dns_record" "pdmos_pt_dmarc" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "_dmarc"
  content = "v=DMARC1; p=quarantine"
  type    = "TXT"
  ttl     = 86400
  comment = "DMARC record for mail server | ${local.dns_record_comment}"
}

resource "cloudflare_dns_record" "pdmos_pt_dkim" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "mail._domainkey"
  content = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtdi4e7zTcrqCO30w6nzQjg43l2fWBQHayMcfDf5TgidTxQAYoi5nRGpd470i4oUW8vYRK1aE4FI1hOFRMgDXhmyGQsstH5hfwgJpRjvIYBDv8KqBcO6eVI+0Cf1DA1shfhTukxldRlmJ6SqI13yWLd2P1c/OtijTf/NpDFRG2zT5QvUC1xAQZgR0K21LI+gwu7RiTHYVOh8Vlcxk7r50WVVeV4aY8DWJ6eArGaoL41lEtuhf0o1HGgtgPHarCggZZSGAMj7z2IJZaSkB4VabC5OAKWfJFSED3g7Kq/wGcOl8pGEC9F5BD+4JMadX8kfLVCunDyaq/7hTDvKEWT40UQIDAQAB"
  type    = "TXT"
  ttl     = 3600
  comment = "DKIM key for pdmos.pt (selector: mail) | ${local.dns_record_comment}"
}

resource "cloudflare_dns_record" "srs_pdmos_pt_mx" {
  zone_id  = data.cloudflare_zone.pdmos_pt.id
  name     = "srs"
  content  = "mail.pdmos.pt"
  type     = "MX"
  ttl      = 10800
  priority = 10
  comment  = "SRS MX record | ${local.dns_record_comment}"
}

resource "cloudflare_dns_record" "srs_pdmos_pt_spf" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "srs"
  content = "v=spf1 mx -all"
  type    = "TXT"
  ttl     = 10800
  comment = "SPF record for SRS domain | ${local.dns_record_comment}"
}

resource "cloudflare_dns_record" "srs_pdmos_pt_dmarc" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "_dmarc.srs"
  content = "v=DMARC1; p=reject; aspf=r; adkim=s"
  type    = "TXT"
  ttl     = 86400
  comment = "DMARC record for SRS domain | ${local.dns_record_comment}"
}

resource "cloudflare_dns_record" "srs_pdmos_pt_dkim" {
  zone_id = data.cloudflare_zone.pdmos_pt.id
  name    = "mail._domainkey.srs"
  content = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiFi9AyzqgczRSXsz6CIXCixPkhZYCwPGeVxgjjGni0aeHwIbAvV1nSu8pBmUSQu7JBJOqHj4iu6YxtL0HAKt1SIpb4tWgzMw34zQpflr8YJtoG0dzkwluXm/MGqPcvYyPmVASXptWirAfTAEjDWW9I9dKIf0qqnn7Z/TgMxT5d0JWXMGHVaNhkcQiLJeiWzfKcdTGDMWBG9SQACEpyvbKgmiU/a4NNxcAkd0SZKH/lb4RykasVgbISPUDkK/0fpATf2b98OXW+hrmzDBu4oR2dBnRvlD1b5oxWbc0TrKd/glc5tpcD9/pEInYB82B3lJxg69iINoOjQ/LTcbwWgNqQIDAQAB"
  type    = "TXT"
  ttl     = 3600
  comment = "DKIM key for srs.pdmos.pt (selector: mail) | ${local.dns_record_comment}"
}
