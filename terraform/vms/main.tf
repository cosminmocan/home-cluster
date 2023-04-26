data "sops_file" "vms_secrets" {
  source_file = "secrets.sops.yaml"
}

data "http" "github_keys" {
  url = "https://github.com/cosminmocan.keys"
}

provider "proxmox" {
  pm_api_url          = data.sops_file.vms_secrets.data["proxmox_api_url"]
  pm_api_token_id     = data.sops_file.vms_secrets.data["proxmox_api_id"]
  pm_api_token_secret = data.sops_file.vms_secrets.data["proxmox_api_token"]
  pm_tls_insecure     = true
}

resource "proxmox_vm_qemu" "cluster_master" {
  for_each = { for vm in local.vm_def_master : vm.ip => vm }

  vmid        = local.vm_master_starting_vmid + index(local.vm_def_master, each.value)
  name        = try(each.value.hostname, "cluster-master-${index(local.vm_def_master, each.value)}")
  target_node = local.proxmox_target_node
  clone       = local.template_name

  onboot    = true
  os_type   = "cloud-init"
  cpu       = "host"
  agent     = try(each.value.agent, 1)
  cores     = try(each.value.cores, 1)
  sockets   = try(each.value.sockets, 1)
  memory    = try(each.value.memory, 1024)
  ipconfig0 = "ip=${each.value.ip}/${local.network_subnet_range},gw=${local.network_gateway}"

  ciuser  = data.sops_file.vms_secrets.data["vm_cloudinit_user"]
  sshkeys = chomp(data.http.github_keys.response_body)

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disk {
    storage = "local-lvm"
    size    = try(each.value.disk_size, "25G")
    type    = "scsi"
    ssd     = 1
    discard = "on"
  }
}

resource "proxmox_vm_qemu" "cluster_worker" {
  for_each = { for vm in local.vm_def_worker : vm.ip => vm }

  vmid        = local.vm_worker_starting_vmid + index(local.vm_def_worker, each.value)
  name        = try(each.value.hostname, "cluster-worker-${index(local.vm_def_worker, each.value)}")
  target_node = local.proxmox_target_node
  clone       = local.template_name

  onboot    = true
  os_type   = "cloud-init"
  cpu       = "host"
  agent     = try(each.value.agent, 1)
  cores     = try(each.value.cores, 1)
  sockets   = try(each.value.sockets, 1)
  memory    = try(each.value.memory, 512)
  ipconfig0 = "ip=${each.value.ip}/${local.network_subnet_range},gw=${local.network_gateway}"

  ciuser  = data.sops_file.vms_secrets.data["vm_cloudinit_user"]
  sshkeys = chomp(data.http.github_keys.response_body)

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disk {
    storage = "local-lvm"
    size    = try(each.value.disk_size, "25G")
    type    = "scsi"
    ssd     = 1
    discard = "on"
  }
}
