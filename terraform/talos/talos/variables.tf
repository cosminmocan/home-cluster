# terraform/talos/talos/variables.tf
variable "image" {
  description = "Talos image configuration"
  type = object({
    factory_url = optional(string, "https://factory.talos.dev")
    schematic = string
    version   = string
    update_schematic = optional(string)
    update_version = optional(string)
    arch = optional(string, "amd64")
    platform = optional(string, "nocloud")
    proxmox_datastore = optional(string, "local")
  })
}

variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name               = string
    endpoint           = string
    gateway            = string
    talos_version      = string
    kubernetes_version = string
    proxmox_cluster    = string
  })
}

variable "nodes" {
  description = "Configuration for cluster nodes"
  type = map(object({
    host_node     = string
    machine_type  = string
    datastore_id = optional(string, "local-lvm")
    ip            = string
    vm_id         = number
    cpu           = number
    ram_dedicated = number
    update = optional(bool, false)
    igpu = optional(bool, false)
  }))
}

variable "cilium" {
  description = "Cilium configuration"
  type = object({
    values  = string
    install = string
  })
}

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (for emergency VM reboot fallback)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (for emergency VM reboot fallback)"
  type        = string
  sensitive   = true
}
