# terraform/talos/talos/providers.tf
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.60.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">=0.11.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">=3.0.0"
    }
  }
}
