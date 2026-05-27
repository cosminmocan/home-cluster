# qBittorrent Specification

## Purpose

qBittorrent is the cluster's BitTorrent client, deployed in the `media` namespace and used to download Linux ISOs and other content for the *arr stack. It serves as the canonical reference for how an in-cluster application is wired in this repository — every pattern documented in [`ADDING_A_NEW_APP.md`](../../../ADDING_A_NEW_APP.md) appears here: HelmRelease with `bjw-s/app-template`, dual storage (Longhorn PVC for config + NFS for bulk data), Cilium-announced LoadBalancer for the BitTorrent port, and a Traefik-fronted web UI gated by Authentik forward-auth.
## Requirements
### Requirement: Deployment shape

The system SHALL deploy qBittorrent as a Flux `HelmRelease` using the `bjw-s/app-template` chart in the `media` namespace.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/media/qbittorrent/release.yaml`](../../../cluster/apps/media/qbittorrent/release.yaml)
- **THEN** a `HelmRelease` named `qbittorrent` is created in namespace `media`
- **AND** the chart resolves to `app-template@4.6.2` from the `chart-bjw` `HelmRepository` in `flux-system`
- **AND** the release `dependsOn` the `longhorn` HelmRelease in namespace `longhorn-system`
- **AND** the container image is `ghcr.io/onedr0p/qbittorrent` pinned to a Renovate-managed tag

#### Scenario: Pod identity and resource budget

- **WHEN** the qBittorrent pod is admitted to the cluster
- **THEN** the pod runs with `runAsUser: 1000`, `runAsGroup: 1000`, `fsGroup: 1000` and `fsGroupChangePolicy: OnRootMismatch`
- **AND** the container requests `cpu: 15m`, `memory: 1Gi` with `memory` limit `4Gi`
- **AND** the `TZ` environment variable resolves to `${TIMEZONE}` from the `cluster-settings` ConfigMap

### Requirement: Storage

The system SHALL provide two distinct persistence paths for qBittorrent — a Longhorn-backed PVC for application state and an NFS mount for bulk downloads.

#### Scenario: Longhorn config volume

- **WHEN** [`cluster/apps/media/qbittorrent/pvc.yaml`](../../../cluster/apps/media/qbittorrent/pvc.yaml) is reconciled
- **THEN** a `PersistentVolumeClaim` named `qbitorrent-config` (sic, preserved for compatibility) exists in `media`
- **AND** the claim requests `500Mi` with `accessModes: [ReadWriteOnce]` and `storageClassName: longhorn`
- **AND** the HelmRelease references it via `persistence.config.existingClaim: qbitorrent-config` mounted at `/config`

#### Scenario: NFS downloads volume

- **WHEN** the pod starts
- **THEN** a volume of type `nfs` mounts the share `${STORAGE_NAS_IP}:/volume1/kubeNFS/torrents` at `/downloads`
- **AND** no PVC is created for this mount — it is declared inline in `persistence.downloads`

### Requirement: BitTorrent port exposure

The system SHALL expose the BitTorrent listening port on a dedicated, externally reachable IP separate from the web UI.

#### Scenario: Cilium L2 LoadBalancer announcement

- **WHEN** the `bittorrent` service is reconciled
- **THEN** the service is of type `LoadBalancer` with `externalTrafficPolicy: Local`
- **AND** the annotation `io.cilium/lb-ipam-ips: "${QBITTORRENT_IP}"` pins the IP, with `externalIPs: ["${QBITTORRENT_IP}"]` echoing the same value
- **AND** Cilium L2 announcements advertise `${QBITTORRENT_IP}` (resolved from the `cluster-secrets` SOPS-encrypted Secret) on the LAN
- **AND** TCP port `18289` (`QBITTORRENT__BT_PORT`) is exposed for inbound peer connections

### Requirement: HTTP access

The system SHALL expose the qBittorrent web UI on `qbittorrent.${SECRET_DOMAIN}` over HTTPS, internal-only, protected by Authentik forward-auth.

#### Scenario: Ingress and TLS

- **WHEN** [`cluster/apps/media/qbittorrent/ingress.yaml`](../../../cluster/apps/media/qbittorrent/ingress.yaml) is reconciled
- **THEN** a `networking.k8s.io/v1` `Ingress` named `qbittorrent` exists in `media` with `ingressClassName: traefik`
- **AND** the host `qbittorrent.${SECRET_DOMAIN}` routes to the `qbittorrent` Service on port `8080`
- **AND** TLS is served by Traefik's default store using the wildcard `${SECRET_DOMAIN/./-}-production-tls` certificate

#### Scenario: Internal DNS only

- **WHEN** k8s-gateway scans Ingress hosts on the cluster
- **THEN** `qbittorrent.${SECRET_DOMAIN}` resolves to `${NIGNX_INGRESS_IP}` via LAN DNS at `${K8S_GATEWAY_IP}`
- **AND** the Ingress carries NO `external-dns.alpha.kubernetes.io/target` annotation, so `external-dns` does not publish a Cloudflare record

#### Scenario: Authentik forward-auth gating

- **WHEN** a request reaches Traefik for `qbittorrent.${SECRET_DOMAIN}`
- **THEN** the annotation `traefik.ingress.kubernetes.io/router.middlewares: "networking-authentik-forwardauth@kubernetescrd"` invokes the shared forward-auth Middleware
- **AND** Traefik calls the Authentik embedded outpost at `http://ak-outpost-authentik-embedded-outpost.database.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik`
- **AND** unauthenticated users are redirected to the Authentik login page; authenticated users have `X-authentik-*` identity headers forwarded to the upstream

### Requirement: GitOps reconciliation

The system SHALL be discovered and applied by Flux without any per-app `kustomize.toolkit.fluxcd.io/v1` `Kustomization` object.

#### Scenario: Kustomize aggregation

- **WHEN** the parent Flux Kustomization `apps` reconciles `./cluster/apps`
- **THEN** [`cluster/apps/media/kustomization.yaml`](../../../cluster/apps/media/kustomization.yaml) includes `qbittorrent` as a resource
- **AND** [`cluster/apps/media/qbittorrent/kustomization.yaml`](../../../cluster/apps/media/qbittorrent/kustomization.yaml) aggregates `pvc.yaml`, `release.yaml`, and `ingress.yaml`
- **AND** all `${VAR}` references in those files are substituted from `cluster-settings` (ConfigMap) and `cluster-secrets` (SOPS Secret) at reconciliation time
