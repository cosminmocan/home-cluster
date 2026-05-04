# terraform/talos/talos/config.tf
resource "talos_machine_secrets" "this" {
  talos_version = var.cluster.talos_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.nodes : v.ip]
  endpoints            = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
}

data "talos_machine_configuration" "this" {
  for_each           = var.nodes
  cluster_name       = var.cluster.name
  cluster_endpoint   = "https://${var.cluster.endpoint}:6443"
  talos_version      = var.cluster.talos_version
  kubernetes_version = var.cluster.kubernetes_version
  machine_type       = each.value.machine_type
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  config_patches = each.value.machine_type == "controlplane" ? [
    templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
      hostname       = each.key
      node_name      = each.value.host_node
      cluster_name   = var.cluster.proxmox_cluster
      cilium_values  = var.cilium.values
      cilium_install = var.cilium.install
    })
  ] : [
    templatefile("${path.module}/machine-config/worker.yaml.tftpl", {
      hostname     = each.key
      node_name    = each.value.host_node
      cluster_name = var.cluster.proxmox_cluster
    })
  ]
}

resource "talos_machine_configuration_apply" "this" {
  depends_on                  = [proxmox_virtual_environment_vm.this]
  for_each                    = var.nodes
  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.this[each.key]]
    # Talos v1.13 rejects re-applying any config that contains machine.network.hostname
    # on a node that already has hostname configured (even with the same value).
    # ignore_changes = all: apply runs only once on fresh node (replace_triggered_by
    # handles VM recreation). Config drift is managed via talosctl patch machineconfig.
    ignore_changes = all
  }
}

resource "talos_machine_bootstrap" "this" {
  node                 = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
  endpoint             = var.cluster.endpoint
  client_configuration = talos_machine_secrets.this.client_configuration
}

# Triggers talosctl upgrade when the installer image changes (version or schematic).
# Upgrade path: v1.11.6 → v1.12.7 ✓ → v1.13.0
# For each step: update image.version in main.tf, then run terraform apply.
# After OS upgrade: bump talos_version + kubernetes_version, apply again.
# --force skips pod eviction (required for single-node clusters).
# If upgrade doesn't complete within 10 minutes, falls back to a Proxmox API hard reboot
# (only if node is STILL ONLINE — avoids interfering with an in-progress installer).
resource "null_resource" "talos_upgrade" {
  for_each = var.nodes

  triggers = {
    installer_image = "factory.talos.dev/installer/${local.schematic_id}:${local.version}"
  }

  provisioner "local-exec" {
    # talosctl upgrade --wait exits with non-zero when the connection drops as the
    # node reboots mid-upgrade. The fallback only triggers a Proxmox reboot if the
    # node is STILL ONLINE after the upgrade attempt (truly stuck), never while it's
    # already rebooting (which would interrupt the installer).
    command = <<-EOT
      # Longhorn's instance-manager PDB blocks kubelet pod shutdown during reboot,
      # causing the node to hang. Delete it before upgrading — Longhorn recreates it
      # automatically on startup. The node-drain-policy is set to always-allow in the
      # Longhorn HelmRelease, but existing PDBs persist until manually cleared.
      echo "Clearing Longhorn instance-manager PDBs to unblock reboot..."
      kubectl delete pdb -n longhorn-system \
        -l longhorn.io/managed-by=longhorn-manager \
        --ignore-not-found 2>/dev/null || true

      talosctl upgrade \
        --nodes ${each.value.ip} \
        --image ${self.triggers.installer_image} \
        --force --wait --timeout 10m0s \
      || {
        echo "talosctl upgrade exited — sleeping 90s to let a natural reboot complete before checking..."
        sleep 90
        if ping -c 3 -W 3 ${each.value.ip} > /dev/null 2>&1; then
          echo "Node still online after 90s — truly stuck. Triggering Proxmox hard reboot of VM ${each.value.vm_id}..."
          curl -k -s -X POST \
            "$PROXMOX_ENDPOINT/api2/json/nodes/${each.value.host_node}/qemu/${each.value.vm_id}/status/reboot" \
            -H "Authorization: PVEAPIToken=$PROXMOX_TOKEN"
          echo "Reboot triggered."
        else
          echo "Node is offline (rebooted naturally for upgrade)."
        fi
        echo "Waiting for node to become healthy (up to 10m)..."
        talosctl --nodes ${each.value.ip} health --wait-timeout 10m
      }
    EOT
    environment = {
      TALOSCONFIG      = "${abspath(path.root)}/output/talos-config.yaml"
      PROXMOX_ENDPOINT = var.proxmox_endpoint
      PROXMOX_TOKEN    = var.proxmox_api_token
      KUBECONFIG       = "${abspath(path.root)}/output/kube-config.yaml"
    }
  }

  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this,
  ]
}

data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this,
    null_resource.talos_upgrade,
  ]
  client_configuration = data.talos_client_configuration.this.client_configuration
  control_plane_nodes  = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
  worker_nodes         = [for k, v in var.nodes : v.ip if v.machine_type == "worker"]
  endpoints            = data.talos_client_configuration.this.endpoints
  timeouts = {
    read = "10m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
    data.talos_cluster_health.this,
  ]
  node                 = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
  endpoint             = var.cluster.endpoint
  client_configuration = talos_machine_secrets.this.client_configuration
  timeouts = {
    read = "1m"
  }
}
