terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 4"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3"
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

data "http" "script" {
  url = "https://gist.githubusercontent.com/jRiest/7893cf10c550057ce1ff53f270683e1c/raw/3ac7f45302f4f6274703c564864a684e9097bce2/party_parrot_worker.js"
}

resource "cloudflare_worker_script" "worker" {
  account_id = var.cloudflare_account
  # https://blog.cloudflare.com/deploy-workers-using-terraform/
  content    = data.http.script.response_body
  name       = var.worker_name
  lifecycle {
    ignore_changes = [
      content,
      r2_bucket_binding,
    ]
  }
}

resource "cloudflare_worker_domain" "worker_domain" {
  account_id = var.cloudflare_account
  hostname   = "test.${var.bucket_name}.${var.domain}"
  service    = cloudflare_worker_script.worker.name
  zone_id    = data.cloudflare_zone.zone.id
}
