locals {
  proxmox_target_node     = data.sops_file.vms_secrets.data["proxmox_node"]
  template_name           = "debian11-template"
  network_gateway         = "192.168.100.1"
  network_subnet_range    = "24"
  vm_master_starting_vmid = 500
  vm_worker_starting_vmid = 550

  vm_def_master = [
    {
      ip        = "192.168.100.10"
      cores     = 2
      memory    = 4096
      disk_size = "40G"
    }
  ]

  vm_def_worker = [
    {
      ip        = "192.168.100.20"
      cores     = 2
      memory    = 4096
      disk_size = "40G"
    },
    {
      ip        = "192.168.100.21"
      cores     = 2
      memory    = 4096
      disk_size = "40G"
    }
  ]
}
