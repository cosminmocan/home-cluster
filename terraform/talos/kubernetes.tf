# terraform/talos/kubernetes.tf
# Cilium CRDs managed directly (not via Helm/Flux) so they can be version-controlled
# and applied atomically alongside the cluster provisioning.
# Uses null_resource + kubectl apply (idempotent) instead of kubernetes_manifest
# because the kubernetes provider's kubernetes_manifest resource fails on CREATE
# when the resource already exists in the cluster (no import/adopt support).

resource "null_resource" "cilium_ip_pool" {
  triggers = {
    manifest_hash = filesha256("${path.module}/kubernetes/cilium/ip-pool.yaml")
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/kubernetes/cilium/ip-pool.yaml"
    environment = {
      KUBECONFIG = "${abspath(path.root)}/output/kube-config.yaml"
    }
  }

  depends_on = [
    module.talos,
  ]
}

resource "null_resource" "cilium_l2_announcement_policy" {
  triggers = {
    manifest_hash = filesha256("${path.module}/kubernetes/cilium/l2-pol.yaml")
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/kubernetes/cilium/l2-pol.yaml"
    environment = {
      KUBECONFIG = "${abspath(path.root)}/output/kube-config.yaml"
    }
  }

  depends_on = [
    null_resource.cilium_ip_pool,
  ]
}
