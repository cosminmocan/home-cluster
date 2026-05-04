# Post-Mortem: Talos v1.13.0 Upgrade Incident

**Date**: 2026-05-02  
**Duration**: ~8 hours  
**Outcome**: Cluster recovered, running Talos v1.13.0 + Kubernetes v1.31.0

---

## Summary

An upgrade from Talos v1.12.7 to v1.13.0 cascaded into a multi-stage failure: a bootloop, a force-rebooted write that corrupted the BOOT partition XFS filesystem, and then a kernel crash that blocked recovery. The root cause of every single boot failure — the bootloop, the rollback failure, and the recovery crash — was a single line in `schematic.yaml`:

```yaml
extraKernelArgs:
  - console=serial0   # ← this killed everything
```

`serial0` is not a valid Linux kernel console device. The kernel only understands `ttyS0`, `tty0`, etc. Older kernel builds silently ignored the invalid parameter. The 6.18.24-talos kernel (used in all April 2026 Talos builds including v1.12.7 and v1.13.0) triple-faults at startup when it cannot initialize the specified console. GRUB's fallback mechanism then created the appearance of a "bootloop": slot B crashes → GRUB tries fallback slot A → also crashes → GRUB reloads → repeat.

---

## Timeline

### Stage 1 — The Bootloop

**What happened**: `talosctl upgrade` ran the v1.13.0 installer, which wrote the new kernel/initramfs to the inactive GRUB slot and updated `grub.cfg` to boot from it. The node rebooted. Both the new slot (v1.13.0) and the old slot (v1.12.x) immediately crashed on every boot attempt.

**What we thought**: Wrong image schematic (missing `bootloader: grub`). After adding `bootloader: grub`, still a bootloop — then assumed it was the "boot regression" in Talos v1.13.0 reported in [siderolabs/talos#13231](https://github.com/siderolabs/talos/issues/13231).

**What was actually happening**: The new 6.18.24-talos kernel (used by BOTH the new v1.13.0 slot and the freshly overwritten old slot) triple-faults when `console=serial0` is in the kernel command line. GRUB's `set fallback=` mechanism was cycling through both slots, making it look like a bootloop rather than an instant crash.

The `bootloader: grub` change was correct and necessary (without it, v1.13.0's installer writes the wrong bootloader for SeaBIOS VMs). But it didn't fix the crash because that was a separate problem.

### Stage 2 — The XFS Corruption

**What happened**: While the node was running from the old slot (user manually selected it from the GRUB menu during the brief window when the 3-second timeout was visible), a second `talosctl upgrade --force` was issued to write fresh v1.12.7 to the inactive slot. The node was force-rebooted before the write completed. The interrupted write left the XFS BOOT partition (sda3) with corrupted metadata.

On next boot, GRUB printed `error: not a correct xfs inode` and could not load anything.

**What caused the corruption**: XFS journals writes atomically but the physical write of a large file (vmlinuz, ~21 MB) across many blocks is not atomic at the block level. A hard reboot mid-write leaves the journal in a state that points to partially-written blocks. xfs_repair can reconstruct the filesystem structure but cannot recover data that was mid-write.

### Stage 3 — XFS Recovery

**Environment**: A separate Lubuntu live VM (192.168.100.108) with VM 800's disk attached, sda3 mounted at `/data`.

**Steps taken**:

1. `xfs_repair /dev/sda3` — repaired all 7 phases successfully. However, xfs_repair zeroed the permissions on the `grub/` directory (a known side effect when inodes are rebuilt from scratch).

2. `chmod 755 /data/grub` — restored directory permissions so GRUB could traverse it.

3. `grub-install --target=i386-pc --recheck --boot-directory=/data /dev/sda` — this was the critical step. After xfs_repair, the physical block locations of the GRUB directory had changed. The existing `core.img` (GRUB's second-stage loader in the BIOS partition, sda2) had a stale blocklist pointing to the old locations. `grub-install --recheck` regenerated `core.img` with the correct block addresses.

After this, GRUB could read the menu and load kernels again.

### Stage 4 — The Kernel Crash

**What happened**: GRUB loaded vmlinuz and initramfs correctly (verified by checksum — byte-for-byte identical to the installer image). The kernel decompressor ran, printed "Booting the kernel...", then the VM instantly rebooted. No panic message, no output — a triple fault.

**What we ruled out**:
- File corruption: checksums matched the installer image exactly
- CPU compatibility: VM uses `x86-64-v2-AES` which fully satisfies the kernel's requirements
- initramfs format: file is valid zstd (the `.xz` extension is a Talos naming convention, the kernel handles it)
- GRUB version mismatch: Lubuntu's grub-install correctly loaded the kernel into memory

**Root cause**: `console=serial0` in the kernel command line. The Linux kernel processes `console=` arguments during very early initialization, before most subsystems are up. In the 6.18.24-talos kernel, passing an unrecognized console device name causes an early panic or fault that the VGA display cannot show (since the kernel output is directed nowhere). The VM's watchdog timer then triggers a reset.

`serial0` is the Proxmox/QEMU device name for the first serial port. The Linux kernel name for the same device is `ttyS0`. Talos may have historically aliased this in older kernel builds, but the 6.18.24 kernel does not.

**The fix**: Updated `grub.cfg` (in the recovery environment) to replace `console=serial0` with `console=ttyS0,115200 console=tty0`. Both slots booted immediately on the next attempt.

---

## Why v1.13.0 Ended Up Running

The grub.cfg had `set default="B - Talos v1.12.7"`. After the console fix, B booted first. Talos's init read the META partition (sda4), which still recorded v1.13.0 as the committed active slot from the original upgrade attempt. Talos performed a `kexec` into the A slot (v1.13.0). Since the console fix applied to the grub.cfg for both slots, v1.13.0 booted successfully.

The cluster came up fully healthy: etcd, apid, kubelet, and all control plane components.

---

## Root Cause

**One bad kernel argument in `schematic.yaml`** caused every boot failure in this incident:

```yaml
# Before (broken):
extraKernelArgs:
  - -console
  - console=serial0

# After (fixed):
extraKernelArgs:
  - -console
  - console=ttyS0,115200
```

The `console=serial0` argument was added to suppress the default VGA console and redirect output to the Proxmox serial socket. The intent was correct — Proxmox maps `serial0` to a socket that the `qm terminal` command reads. But the Linux kernel requires the `ttyS0` name, not `serial0`. The Proxmox serial socket is still accessible via `ttyS0,115200` in the kernel.

This bug was latent in the schematic for the entire lifetime of the cluster but only surfaced when the 6.18.24 kernel was introduced. Older kernels either ignored the bad parameter or handled it non-fatally.

---

## Stage 5 — Post-Boot: All LoadBalancer IPs Unreachable

**What happened**: After the cluster came up on v1.13.0, all services backed by LoadBalancer IPs (`192.168.100.30` for nginx-ingress, `192.168.100.31` for k8s-gateway DNS) were unreachable from the LAN. DNS queries to k8s-gateway timed out. Every `*.REDACTED-DOMAIN` hostname was unresolvable.

**Root cause**: Cilium's L2 announcement policy was configured to send ARP replies on interface `eth0`. The 6.18.24-talos kernel uses predictable network interface naming — on a Q35 machine with the virtio-net device on PCIe slot 18, the interface is named `ens18` instead of `eth0`. Because no interface matched the policy, Cilium sent no ARP replies for the LoadBalancer IPs. The network had no idea which MAC address owned `.30` and `.31`, so all traffic was dropped.

The Talos dns-resolve-cache warnings (`error serving dns request ... i/o timeout`) pointed at upstream DNS (192.168.100.1) failing, which was a red herring — the real issue was the k8s-gateway LoadBalancer IP being unreachable, not the router.

**Additional bug found**: `tofu/kubernetes/cilium/l2-pol.yaml` had a stale `flux` prefix on the `apiVersion:` line, making the file invalid YAML that `kubectl apply` would reject. The policy existed in the cluster only because it had been applied correctly at some earlier point and never needed re-applying.

**Fix**:

```yaml
# l2-pol.yaml — before:
flux apiVersion: cilium.io/v2alpha1
spec:
  interfaces:
    - eth0

# l2-pol.yaml — after:
apiVersion: cilium.io/v2alpha1
spec:
  interfaces:
    - ens18
```

Applied live via `kubectl patch`, services restored immediately.

**Why this wasn't caught before**: The cluster was running on the old kernel where the interface was `eth0`, so the policy matched and ARP worked. The interface rename happened silently as a side effect of the kernel upgrade.

---

## Collateral Damage

| Item | Status |
|------|--------|
| BOOT partition (sda3) XFS | Repaired via xfs_repair + grub-install |
| Terraform state | Out of sync (talos_machine_configuration_apply and null_resource.talos_upgrade need re-apply) |
| Original v1.12.x kernel in A slot | Permanently overwritten by v1.13.0 installer |
| Kubernetes version | Still v1.31.0 — k8s upgrade to 1.32.0 is a separate step |
| All LoadBalancer IPs | Restored after Cilium L2 policy interface fix |

---

## What Was Fixed Permanently

- `tofu/talos/image/schematic.yaml`: `console=serial0` → `console=ttyS0,115200`
- `tofu/main.tf`: `image.version` → `v1.13.0`, `talos_version` → `v1.13`
- `tofu/kubernetes/cilium/l2-pol.yaml`: `eth0` → `ens18`, fixed stale `flux` prefix on `apiVersion:`
- `tofu/kubernetes.tf`: added `kubernetes_manifest` resources for `l2-pol.yaml` and `ip-pool.yaml` so they are Terraform-managed going forward instead of applied manually
- GRUB reinstalled with correct XFS block list

---

## Remaining Actions

1. **Run `terraform apply`** from `tofu/` to reconcile Terraform state with the running cluster (includes importing the now-Terraform-managed Cilium CRDs).
2. **Upgrade Kubernetes**: bump `kubernetes_version = "1.32.0"` in `main.tf` and apply. This is the Phase 2 upgrade (OS is now on v1.13, k8s can follow).
3. **Remove Lubuntu ISO** from VM 800's CD drive and restore boot order to `scsi0` first.
4. **Clean up recovery VM** (192.168.100.108) if no longer needed.

---

## Lessons

1. **Test kernel args on a throwaway VM first** before upgrading the only control plane node.
2. **Never force-reboot mid-upgrade** unless the node is confirmed to be stuck and not just slow. The 90-second fallback wait in `null_resource.talos_upgrade` exists for this reason — it was bypassed manually.
3. **xfs_repair does not restore file data** — only filesystem metadata. After repair, always checksum critical files against a known-good source before trusting them.
4. **A "bootloop" in GRUB is often two crashes, not one** — GRUB's `set fallback=` silently retries the other slot, making a crash look like a loop.
5. **`grub-install --recheck` is required after xfs_repair** changes inode locations — the existing `core.img` blocklist becomes stale.
6. **Interface names change with kernel upgrades** — any network policy hardcoding `eth0` will silently break when a newer kernel assigns predictable names like `ens18`. Use interface selectors or verify names after every major kernel bump.
7. **Keep CRDs Terraform-managed** — manually applied resources (like the Cilium L2 policy) can accumulate silent bugs (the `flux apiVersion:` prefix) and drift from the repo state without any plan/apply catching it.
