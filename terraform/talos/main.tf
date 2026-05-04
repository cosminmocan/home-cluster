# terraform/talos/main.tf
module "talos" {
  source = "./talos"

  providers = {
    proxmox = proxmox
  }

  image = {
    # Upgrade path: v1.11.6 → v1.12.7 ✓ → v1.13.0 ✓
    # Boot regression in v1.13.0 (https://github.com/siderolabs/talos/issues/13231) was caused
    # by console=serial0 in extraKernelArgs — not a Talos bug. Fixed by using console=ttyS0,115200.
    version   = "v1.13.0"
    schematic = file("${path.module}/talos/image/schematic.yaml")
  }

  cilium = {
    install = file("${path.module}/talos/inline-manifests/cilium-install.yaml")
    values  = file("${path.module}/kubernetes/cilium/values.yaml")
  }

  proxmox_endpoint  = var.proxmox.endpoint
  proxmox_api_token = var.proxmox.api_token

  cluster = {
    name            = "talos"
    endpoint        = "192.168.100.10"
    gateway         = "192.168.100.1"
    proxmox_cluster = "home-cluster"

    # Upgrade path — v1.11/1.30.0 → v1.12/1.31.0 ✓ → v1.13/1.32.0 ✓ → v1.13/1.33.0 ✓ → v1.13/1.34.0 ✓ → v1.13/1.35.0 ✓ → v1.13/1.36.0 ✓
    talos_version      = "v1.13"
    kubernetes_version = "1.36.0"
  }

  nodes = {
    "ctrl-00" = {
      host_node     = "tiny"
      machine_type  = "controlplane"
      ip            = "192.168.100.10"
      vm_id         = 800
      cpu           = 4
      ram_dedicated = 12288
    }
  }
}

