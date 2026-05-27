## ADDED Requirements

### Requirement: Deployment shape

The system SHALL deploy Paperless-ngx as a Flux `HelmRelease` using the upstream `gabe565/paperless-ngx` chart in the `media` namespace.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles `cluster/apps/media/paperless-ngx/release.yaml`
- **THEN** a `HelmRelease` named `paperless-ngx` is created in `media`
- **AND** the chart resolves to `paperless-ngx` from a new `chart-gabe565` `HelmRepository` in `flux-system`
- **AND** the release `dependsOn` `postgresql` and `redis` (both in `database`) and `longhorn` (in `longhorn-system`)
- **AND** the container image is `ghcr.io/paperless-ngx/paperless-ngx` pinned to a Renovate-managed tag
- **AND** the chart's bundled `postgresql` and `redis` sub-charts are explicitly disabled (`postgresql.enabled: false`, `redis.enabled: false`) so the cluster's shared instances are used instead

#### Scenario: OCR scope (Tesseract only)

- **WHEN** the Paperless-ngx pod boots without Tika or Gotenberg side services
- **THEN** Tesseract-based OCR of PDFs and images is supported out of the box
- **AND** Office documents (`.docx`, `.xlsx`), emails (`.eml`), and HTML ingestion are out of scope for this change; a follow-up change can introduce Tika + Gotenberg as separate HelmReleases when needed

### Requirement: Database backend

The system SHALL store Paperless-ngx state in the shared cluster PostgreSQL instance, not in the chart's bundled SQLite.

#### Scenario: Postgres connection

- **WHEN** the Paperless-ngx pod starts
- **THEN** `PAPERLESS_DBHOST`, `PAPERLESS_DBPORT=5432`, `PAPERLESS_DBNAME=paperless`, `PAPERLESS_DBUSER=postgres`, `PAPERLESS_DBPASS` are set
- **AND** the host resolves to `${POSTGRES_HOST_ADDRESS}` and the password to `${SECRET_POSTGRES_ADMIN_PASS}` via Flux substitution
- **AND** the `paperless` database has been pre-created in the PostgreSQL instance (Postgres does not auto-create databases on first connect)

### Requirement: Cache and broker backend

The system SHALL use the shared cluster Redis instance for Paperless-ngx's task queue and cache.

#### Scenario: Redis connection

- **WHEN** the Paperless-ngx pod starts
- **THEN** `PAPERLESS_REDIS` is set to `redis://${REDIS_HOST_ADDRESS}:6379` (no password — the cluster Redis runs with `auth.enabled: false`)
- **AND** the chart-managed Celery worker uses the same Redis as its broker

### Requirement: Storage layout

The system SHALL split Paperless-ngx storage into a Longhorn-backed config/data volume and two PVCs dynamically provisioned on NFS for bulk content. The chart depends on `bjw-s/common@1.5.1`, which does not support inline `type: nfs` mounts in its `persistence` keys; the cluster's `nfs-client` `StorageClass` (backed by `nfs-subdir-external-provisioner`) is used instead to obtain NFS-backed PVCs without per-app manifest plumbing.

#### Scenario: Longhorn data volume

- **WHEN** the chart's `persistence.data` block reconciles
- **THEN** a `PersistentVolumeClaim` is created in `media` with `storageClassName: longhorn`, `accessModes: [ReadWriteOnce]`, and at least `5Gi` requested
- **AND** the chart mounts it at `/usr/src/paperless/data` (Whoosh index, classifier model, runtime state)

#### Scenario: NFS-backed media volume

- **WHEN** the chart's `persistence.media` block reconciles with `storageClass: nfs-client`
- **THEN** a `PersistentVolumeClaim` is created in `media` that the `nfs-subdir-external-provisioner` (HelmRelease `nfs-subdir-external-provisioner` in `nfs-provisioner` namespace) backs with a dynamically-created subdirectory under `${STORAGE_NAS_IP}:/volume1/kubeNFS`
- **AND** the chart mounts it at `/usr/src/paperless/media` (bulk PDFs, originals, thumbnails)

#### Scenario: NFS-backed consume volume

- **WHEN** the chart's `persistence.consume` block reconciles with `storageClass: nfs-client`
- **THEN** a `PersistentVolumeClaim` is created in `media` similarly backed by NFS
- **AND** the chart mounts it at `/usr/src/paperless/consume`
- **AND** Paperless's consumer watches that directory and ingests any file copied into it (`kubectl cp` or via the Paperless web UI uploader)

### Requirement: HTTP access

The system SHALL expose Paperless-ngx on `docs.${SECRET_DOMAIN}` over HTTPS, internal-only.

#### Scenario: Ingress

- **WHEN** the HelmRelease's `ingress` block is reconciled
- **THEN** a Traefik Ingress on host `docs.${SECRET_DOMAIN}` routes to the Paperless web service
- **AND** TLS is served by Traefik's default store using the wildcard `${SECRET_DOMAIN/./-}-production-tls` certificate
- **AND** `PAPERLESS_URL` env var is set to `https://docs.${SECRET_DOMAIN}` so Paperless emits correct absolute URLs

#### Scenario: Internal DNS only

- **WHEN** k8s-gateway scans Ingress hosts on the cluster
- **THEN** `docs.${SECRET_DOMAIN}` resolves to `${NIGNX_INGRESS_IP}` via LAN DNS at `${K8S_GATEWAY_IP}`
- **AND** the Ingress carries NO `external-dns.alpha.kubernetes.io/target` annotation, so `external-dns` does NOT publish a Cloudflare record
- **AND** the host is unreachable from the public internet

### Requirement: Application secrets

The system SHALL source Paperless-ngx's Django `SECRET_KEY` from the SOPS-encrypted cluster secret.

#### Scenario: Secret key substitution

- **WHEN** the Paperless-ngx pod starts
- **THEN** `PAPERLESS_SECRET_KEY` resolves to `${SECRET_PAPERLESS_KEY}` from `cluster-secrets`
- **AND** the value is at least 50 random characters as required by Django

### Requirement: GitOps reconciliation

The system SHALL be discovered and applied by Flux through the existing `apps` Flux Kustomization without any per-app `kustomize.toolkit.fluxcd.io/v1` `Kustomization` object.

#### Scenario: Kustomize aggregation

- **WHEN** the parent Flux Kustomization `apps` reconciles `./cluster/apps`
- **THEN** `cluster/apps/media/kustomization.yaml` includes `paperless-ngx` as a resource
- **AND** `cluster/apps/media/paperless-ngx/kustomization.yaml` aggregates `pvc.yaml` and `release.yaml`
- **AND** all `${VAR}` references in those files are substituted from `cluster-settings` (ConfigMap) and `cluster-secrets` (SOPS Secret) at reconciliation time
