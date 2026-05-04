# main-cluster

This repository manages my homelab infrastructure and Kubernetes cluster using a GitOps approach with [Terraform](https://www.terraform.io/) and [Flux](https://github.com/fluxcd/flux2).

## Hardware

| Device | Role |
| --- | --- |
| Lenovo P330 Tiny | Proxmox hypervisor host |
| Synology DS923+ | NAS / NFS storage backend |

## Cluster

A single-node Kubernetes cluster running on [Talos Linux](https://www.talos.dev/), provisioned as a VM on Proxmox.

| Component | Details |
| --- | --- |
| Hypervisor | [Proxmox VE](https://www.proxmox.com/) |
| OS | Talos Linux v1.13 |
| Kubernetes | v1.36 |
| VM | 1 control-plane node (`ctrl-00`, `192.168.100.10`) |

## Core Components

| Component | Purpose |
| --- | --- |
| [Cilium](https://cilium.io/) | CNI, kube-proxy replacement, L2 LoadBalancer IP announcements (ARP) |
| [cert-manager](https://cert-manager.io/) | Automatic TLS certificates |
| [Traefik](https://traefik.io/) | Ingress controller (`192.168.100.30`), HTTP→HTTPS redirect, ForwardAuth middleware for Authentik |
| [k8s-gateway](https://github.com/ori-edge/k8s_gateway) | Internal DNS for `*.REDACTED-DOMAIN` (`192.168.100.31`) |
| [external-dns](https://github.com/kubernetes-sigs/external-dns) | Syncs DNS records to Cloudflare |
| [cloudflare-ddns](https://github.com/favonia/cloudflare-ddns) | Keeps the public IP record up to date |
| [Longhorn](https://longhorn.io/) | Persistent block storage |
| [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) | NFS storage class backed by Synology |
| [metrics-server](https://github.com/kubernetes-sigs/metrics-server) | `kubectl top` / HPA metrics |
| [reflector](https://github.com/emberstack/kubernetes-reflector) | Secret/ConfigMap replication across namespaces |
| [reloader](https://github.com/stakater/Reloader) | Automatic pod restarts on config/secret changes |

## GitOps

[Flux](https://github.com/fluxcd/flux2) watches the [cluster/](./cluster/) directory and reconciles all resources automatically. The layout is:

```text
cluster/
├── core/       # infrastructure components (CNI, ingress, storage, etc.)
└── apps/       # workloads
    ├── database/   # Authentik, PostgreSQL, Redis, pgAdmin
    ├── default/    # Homepage dashboard
    ├── media/      # Jellyfin, Jellyseerr, Radarr, Prowlarr, qBittorrent, Flaresolverr, Guacamole, Home Assistant, Nextology
    └── monitoring/ # Goldilocks, VPA
```

[Renovate](https://github.com/renovatebot/renovate) watches the repository for dependency updates and opens PRs automatically. Flux applies them once merged.

## Infrastructure as Code

Terraform manages cluster provisioning and supporting cloud resources:

```text
terraform/
├── talos/       # Talos VM on Proxmox, machine config, Kubernetes bootstrap, Cilium CRDs
└── cloudflare/  # DNS zones and records
```

Common operations via [Task](https://taskfile.dev/):

```sh
task terraform:talos:plan
task terraform:talos:apply
task terraform:cloudflare:plan
task terraform:cloudflare:apply
```

## Secrets

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) and committed to the repository. Flux decrypts them at apply time.
