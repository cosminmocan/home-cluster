# FlareSolverr Specification

## Purpose

FlareSolverr is a Cloudflare-challenge solver used internally by Prowlarr to scrape indexers protected by Cloudflare. It has no UI and no Ingress — it is reached only by other cluster pods at `flaresolverr.media.svc.cluster.local:8191`.

## Requirements

### Requirement: Deployment shape

The system SHALL deploy FlareSolverr as a Flux `HelmRelease` using `bjw-s/app-template` in `media`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/media/flaresolverr/release.yaml`](../../../cluster/apps/media/flaresolverr/release.yaml)
- **THEN** a `HelmRelease` named `flaresolverr` is created in `media`
- **AND** the chart resolves to `app-template@4.6.2` from `chart-bjw`
- **AND** the container image is `flaresolverr/flaresolverr` pinned to a Renovate-managed tag
- **AND** no `dependsOn` is declared — FlareSolverr is stateless

### Requirement: Internal-only service

The system SHALL expose FlareSolverr only inside the cluster, with no Ingress, no PVC, and no external DNS.

#### Scenario: ClusterIP service

- **WHEN** the HelmRelease reconciles
- **THEN** a single `Service` of default type `ClusterIP` named `flaresolverr` exists in `media` on port `8191`
- **AND** no `Ingress`, `PersistentVolumeClaim`, or `external-dns` annotation is created
- **AND** Prowlarr is configured to call `http://flaresolverr.media.svc.cluster.local:8191` for protected indexers
