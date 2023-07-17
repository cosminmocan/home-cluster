## 📖 Overview

This is a repository for my homelab infrastructure and Kubernetes cluster. In this repo, you will find an attempt at self hosted GitOps oriented infrastructured, using tools such as [Ansible](https://www.ansible.com/), [Terraform](https://www.terraform.io/), [Kubernetes](https://kubernetes.io/), [Flux](https://github.com/fluxcd/flux2) and [Renovate](https://github.com/renovatebot/renovate).

## ⎈ Kubernetes

Inspired by an earlier revision of this amazing template [onedr0p/flux-cluster-template](https://github.com/onedr0p/flux-cluster-template), I continued by migrating my existing infrastructure from its earlier [docker-compose](https://docs.docker.com/compose/) form, to the now modern-at-the-time-of-writing-this GitOps iteration.


###   🏁 Installation

At the base, my cluster is composed of a Lenovo P330 tiny and a Synology DS923+, I use [Proxmox](https://www.proxmox.com/en/) as a hypervisor, [Debian](https://www.debian.org/) as the VM OS of choice and some LXC containers.

Running on the hypervisor are 3 VMs(kube nodes) which compose my home kubernetes cluster.
The VMs are created using Terraform and a custom [cloud-init](https://cloudinit.readthedocs.io/en/latest/) ready template, after the deployment, the entire cluster is deployed using [Ansible Playbooks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html), and the kubernetes part is deployed using the [k3s](https://k3s.io/)  galaxy role [ansible-role-k3s](https://github.com/PyratLabs/ansible-role-k3s).

###   ⚙️  Core Components

- [calico](https://github.com/projectcalico/calico): Kubernetes CNI.
- [metallb](https://metallb.universe.tf/): Load balancer of choice.
- [cert-manager](https://cert-manager.io/docs/): SSL certificates for services.
- [external-dns](https://github.com/kubernetes-sigs/external-dns): Automatically pushed DNS records from the cluster on Cloudflare.
- [ingress-nginx](https://github.com/kubernetes/ingress-nginx/): Ingress controller to expose HTTP traffic to pods over DNS.
- [Longhorn](https://longhorn.io/): Distributed block storage for peristent storage, also backup solution for volumes.
- [sops](https://toolkit.fluxcd.io/guides/mozilla-sops/): Managed secrets for Kubernetes, Ansible and Terraform which are commited to Git.

###  ♾️ GitOps

[Flux](https://github.com/fluxcd/flux2) watches my [cluster](./cluster/) folder (see Directories below) and makes the changes to my cluster based on the YAML manifests.

The way Flux works for me here is it will recursively search the [cluster/apps](./cluster/apps) folder until it finds the most top level `kustomization.yaml` per directory and then apply all the resources listed in it. That aforementioned `kustomization.yaml` will generally only have a namespace resource and one or many Flux kustomizations. Those Flux kustomizations will generally have a `HelmRelease` or other resources related to the application underneath it which will be applied.

[Renovate](https://github.com/renovatebot/renovate) watches my **entire** repository looking for dependency updates, when they are found a PR is automatically created. When some PRs are merged [Flux](https://github.com/fluxcd/flux2) applies the changes to my cluster.

