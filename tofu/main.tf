terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.60"
    }
  }

  encryption {
    key_provider "pbkdf2" "encryption_key" {
      passphrase = var.passphrase
    }

    method "aes_gcm" "default_encryption_method" {
      keys = key_provider.pbkdf2.encryption_key
    }

    state {
      method   = method.aes_gcm.default_encryption_method
      enforced = true
    }

    plan {
      method   = method.aes_gcm.default_encryption_method
      enforced = true
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}
