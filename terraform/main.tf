terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 4"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

resource "cloudflare_r2_bucket" "cloudflare-bucket" {
  account_id = var.cloudflare_account
  name       = var.bucket_name
  # See https://developers.cloudflare.com/r2/reference/data-location for location
  # location   = "apac"
}

data "cloudflare_zone" "zone" {
  name = var.domain
}

resource "cloudflare_record" "r2-domain" {
  name    = cloudflare_r2_bucket.cloudflare-bucket.name
  type    = "CNAME"
  zone_id = data.cloudflare_zone.zone.id
  proxied = true
  ttl     = 1
  value   = "public.r2.dev"
}
