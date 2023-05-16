terraform {

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.11"
    }

    sops = {
      source  = "carlpett/sops"
      version = "0.7.2"
    }

    http = {
      source  = "hashicorp/http"
      version = "3.2.1"
    }
  }
}
