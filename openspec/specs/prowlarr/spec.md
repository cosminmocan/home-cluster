# Prowlarr Specification

## Purpose

Prowlarr is the indexer manager in the `media` namespace. It aggregates torrent indexers and pushes them to Radarr (and any future *arr siblings). Same deployment shape as [qBittorrent](../qbittorrent/spec.md) — `bjw-s/app-template` with a Longhorn config PVC and Postgres-backed state. Pulls the `prowlarr-develop` branch image rather than stable.
## Requirements
### Requirement: Deployment shape

The system SHALL deploy Prowlarr as a Flux `HelmRelease` using `bjw-s/app-template` in `media`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/media/prowlarr/release.yaml`](../../../cluster/apps/media/prowlarr/release.yaml)
- **THEN** a `HelmRelease` named `prowlarr` is created in `media`
- **AND** the chart resolves to `app-template@4.6.2` from `chart-bjw`
- **AND** the container image is `ghcr.io/onedr0p/prowlarr-develop` pinned to a Renovate-managed tag with `PROWLARR__BRANCH: develop`
- **AND** the release `dependsOn` `postgresql` (namespace `database`) and `longhorn` (namespace `longhorn-system`)

### Requirement: Database backend

The system SHALL store Prowlarr state in the shared cluster PostgreSQL instance.

#### Scenario: Postgres connection

- **WHEN** the Prowlarr pod starts
- **THEN** `PROWLARR__POSTGRES_HOST`, `PROWLARR__POSTGRES_USER`, `PROWLARR__POSTGRES_PASSWORD`, `PROWLARR__POSTGRES_MAIN_DB=prowlarr-main`, `PROWLARR__POSTGRES_LOG_DB=prowlarr-log` are set
- **AND** values resolve from `${POSTGRES_HOST_ADDRESS}` and `${SECRET_POSTGRES_ADMIN_PASS}`
- **AND** the API key `PROWLARR__API_KEY` resolves from `${PROWLARR_SECRET_KEY}`

### Requirement: Storage

The system SHALL provide a Longhorn config volume — no media mount is required (Prowlarr does not handle downloads).

#### Scenario: Config volume

- **WHEN** [`cluster/apps/media/prowlarr/pvc.yaml`](../../../cluster/apps/media/prowlarr/pvc.yaml) reconciles
- **THEN** a Longhorn PVC named `prowlarr-config-v2` is bound and mounted at `/config`

### Requirement: HTTP access

The system SHALL expose Prowlarr on `prowlarr.${SECRET_DOMAIN}` over HTTPS, internal-only.

#### Scenario: Ingress

- **WHEN** the HelmRelease's `ingress.prowlarr` block is rendered
- **THEN** a Traefik Ingress on host `prowlarr.${SECRET_DOMAIN}` routes to the `prowlarr` service on port `9696`
- **AND** the Ingress carries NO `external-dns.alpha.kubernetes.io/target` annotation, keeping it internal
