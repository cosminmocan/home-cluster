locals {
  proxmox_target_node     = "coolio"
  template_name           = "debian11-template"
  network_gateway         = "192.168.1.1"
  network_subnet_range    = "24"
  vm_master_starting_vmid = 500
  vm_worker_starting_vmid = 550

  vm_def_master = [
    {
      ip        = "192.168.1.10"
      cores     = 2
      memory    = 3072
      disk_size = "30G"
    }
  ]

  vm_def_worker = [
    {
      ip        = "192.168.1.20"
      cores     = 2
      memory    = 4096
      disk_size = "30G"
    },
    {
      ip        = "192.168.1.21"
      cores     = 2
      memory    = 4096
      disk_size = "30G"
    }
  ]
}
