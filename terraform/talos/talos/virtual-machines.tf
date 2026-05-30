# terraform/talos/talos/virtual-machines.tf
resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.nodes

  node_name = each.value.host_node

  name        = each.key
  description = each.value.machine_type == "controlplane" ? "Talos Control Plane" : "Talos Worker"
  tags        = each.value.machine_type == "controlplane" ? ["k8s", "control-plane"] : ["k8s", "worker"]
  on_boot     = true
  vm_id       = each.value.vm_id

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu
    type  = "host"
  }

  memory {
    dedicated = each.value.ram_dedicated
  }

  network_device {
    bridge = "vmbr0"
  }

  vga {
    type = "serial0"

  }

  serial_device {}
  disk {
    datastore_id = each.value.datastore_id
    interface    = "scsi0"
    iothread     = false
    discard      = "on"
    ssd          = true
    file_format  = "raw"
    # Matches the live VM disk (40 GiB). Do not lower this — the proxmox provider
    # cannot shrink a disk, and a smaller value makes plans try to (and risk data loss).
    size    = 40
    file_id = proxmox_virtual_environment_download_file.this["${each.value.host_node}_${each.value.update == true ? local.update_image_id : local.image_id}"].id
  }

  disk {
    datastore_id = each.value.datastore_id
    interface    = "scsi1"
    iothread     = false
    discard      = "on"
    ssd          = true
    file_format  = "raw"
    size         = 100
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
  }

  initialization {
    datastore_id = each.value.datastore_id
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.cluster.gateway
      }
    }
  }

  lifecycle {
    # file_id is the source image used only at creation time.
    # Talos upgrades happen via the Talos API, not by swapping the disk image.
    ignore_changes = [disk[0].file_id]
  }
}
