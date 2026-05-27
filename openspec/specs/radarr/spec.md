# Radarr Specification

## Purpose

Radarr is the movie automation manager in the `media` namespace. It indexes via Prowlarr, queues downloads to qBittorrent, and writes finished media to the NAS share mounted at `/downloads`. It uses Postgres for both its main and log databases instead of the chart's bundled SQLite. Same deployment pattern as [qBittorrent](../qbittorrent/spec.md) — `bjw-s/app-template` with a Longhorn config PVC.
## Requirements
### Requirement: Deployment shape

The system SHALL deploy Radarr as a Flux `HelmRelease` using `bjw-s/app-template` in the `media` namespace.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/media/radarr/release.yaml`](../../../cluster/apps/media/radarr/release.yaml)
- **THEN** a `HelmRelease` named `radarr` is created in `media`
- **AND** the chart resolves to `app-template@4.6.2` from `chart-bjw`
- **AND** the container image is `ghcr.io/onedr0p/radarr` pinned to a Renovate-managed tag
- **AND** the release `dependsOn` `postgresql` (namespace `database`) and `longhorn` (namespace `longhorn-system`)

### Requirement: Database backend

The system SHALL store Radarr state in the shared cluster PostgreSQL instance, not in the chart's default SQLite.

#### Scenario: Postgres connection

- **WHEN** the Radarr pod starts
- **THEN** environment variables `RADARR__POSTGRES_HOST`, `RADARR__POSTGRES_USER`, `RADARR__POSTGRES_PASSWORD`, `RADARR__POSTGRES_MAIN_DB=radarr-main`, `RADARR__POSTGRES_LOG_DB=radarr-log` are set
- **AND** values resolve from `${POSTGRES_HOST_ADDRESS}` and `${SECRET_POSTGRES_ADMIN_PASS}` via Flux substitution
- **AND** the API key `RADARR__API_KEY` resolves from `${RADARR_SECRET_KEY}`

### Requirement: Storage

The system SHALL provide a Longhorn config volume and an NFS volume for media output.

#### Scenario: Config and media mounts

- **WHEN** [`cluster/apps/media/radarr/pvc.yaml`](../../../cluster/apps/media/radarr/pvc.yaml) reconciles
- **THEN** a `2Gi` Longhorn PVC named `radarr-config` is bound and mounted at `/config`
- **AND** an NFS volume from `${STORAGE_NAS_IP}:/volume1/kubeNFS/torrents` mounts at `/downloads`

### Requirement: HTTP access

The system SHALL expose Radarr on `radarr.${SECRET_DOMAIN}` over HTTPS, internal-only.

#### Scenario: Ingress

- **WHEN** the HelmRelease's `ingress.radarr` block is rendered
- **THEN** a Traefik Ingress on host `radarr.${SECRET_DOMAIN}` routes to the `radarr` service on the HTTP port (7878)
- **AND** the Ingress carries NO `external-dns.alpha.kubernetes.io/target` annotation, keeping it internal
- **AND** `RADARR__APPLICATION_URL` is set to `https://radarr.${SECRET_DOMAIN}` so generated links are correct
