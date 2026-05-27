# Jellyseerr Specification

## Purpose

Jellyseerr is the media request manager in the `media` namespace. Users browse for movies/shows and the request is forwarded to Radarr to provision. Deployed publicly via Cloudflare so household members can request outside the LAN. Uses `bjw-s/app-template` with a Longhorn config PVC.
## Requirements
### Requirement: Deployment shape

The system SHALL deploy Jellyseerr as a Flux `HelmRelease` using `bjw-s/app-template` in `media`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/media/jellyseerr/release.yaml`](../../../cluster/apps/media/jellyseerr/release.yaml)
- **THEN** a `HelmRelease` named `jellyseerr` is created in `media`
- **AND** the chart resolves to `app-template@4.6.2` from `chart-bjw`
- **AND** the container image is `ghcr.io/seerr-team/seerr` pinned to a Renovate-managed tag (`seerr` is the renamed Jellyseerr fork)
- **AND** the release `dependsOn` `longhorn` (namespace `longhorn-system`)

### Requirement: Storage

The system SHALL provide a Longhorn config volume mounted at `/app/config`.

#### Scenario: Config volume

- **WHEN** the HelmRelease reconciles
- **THEN** an existing PVC `jellyseerr-config` (Longhorn) is mounted at `/app/config`

### Requirement: HTTP access

The system SHALL expose Jellyseerr on `jellyseerr.${SECRET_DOMAIN}` over HTTPS, reachable from the public internet via Cloudflare.

#### Scenario: Ingress with public DNS

- **WHEN** the HelmRelease's `ingress.jellyseerr` block is rendered
- **THEN** a Traefik Ingress on host `jellyseerr.${SECRET_DOMAIN}` routes to the `jellyseerr` service on port `5055`
- **AND** the annotation `external-dns.alpha.kubernetes.io/target: "${CLOUDFLARE_DDNS_RECORD}"` causes external-dns to publish a public Cloudflare record
