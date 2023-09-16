terraform {

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.11"
    }

    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "3.2.1"
    }
  }
}
