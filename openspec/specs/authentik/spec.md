# Authentik Specification

## Purpose

Authentik is the cluster's identity provider and the source of truth for SSO. It runs in the `database` namespace because it shares Postgres and Redis with the other database-tier workloads. It backs the cluster's Traefik forward-auth middleware (see [`cluster/core/networking/traefik/middlewares/middlewares.yaml`](../../../cluster/core/networking/traefik/middlewares/middlewares.yaml)) — every app that opts into `networking-authentik-forwardauth@kubernetescrd` (such as [qBittorrent](../qbittorrent/spec.md)) ultimately resolves authentication through Authentik's embedded outpost.
## Requirements
### Requirement: Deployment shape

The system SHALL deploy Authentik as a Flux `HelmRelease` using the upstream goauthentik chart in `database`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/database/authentik/release.yaml`](../../../cluster/apps/database/authentik/release.yaml)
- **THEN** a `HelmRelease` named `authentik` is created in `database`
- **AND** the chart resolves to `authentik` from `chart-goauthentik`
- **AND** the release `dependsOn` `postgresql` and `redis` (both in `database`)

### Requirement: Backing stores

The system SHALL use the shared Postgres and Redis instances for Authentik's persistent and ephemeral state.

#### Scenario: Postgres and Redis wiring

- **WHEN** the Authentik pod starts
- **THEN** `authentik.postgresql.host` resolves to `${POSTGRES_HOST_ADDRESS}` with database name `authentik`, user `postgres`, password `${SECRET_POSTGRES_ADMIN_PASS}`
- **AND** `authentik.redis.host` resolves to `${REDIS_HOST_ADDRESS}` with an empty password (Redis has auth disabled)
- **AND** `authentik.secret_key` resolves to `${SECRET_AUTHENTIK_SECRET_KEY}` from the SOPS Secret

### Requirement: HTTP access

The system SHALL expose Authentik on `auth.${SECRET_DOMAIN}` over HTTPS, publicly via Cloudflare.

#### Scenario: Public ingress

- **WHEN** the HelmRelease's `server.ingress` block renders
- **THEN** a Traefik Ingress on host `auth.${SECRET_DOMAIN}` routes to the Authentik server service
- **AND** `external-dns.alpha.kubernetes.io/target: "${CLOUDFLARE_DDNS_RECORD}"` publishes a Cloudflare record

### Requirement: Forward-auth outpost

The system SHALL provide an in-cluster outpost that the shared Traefik middleware can reach for forward-auth requests.

#### Scenario: Outpost service

- **WHEN** Authentik finishes bootstrapping
- **THEN** an embedded outpost service named `ak-outpost-authentik-embedded-outpost` exists in `database` on port `9000`
- **AND** that service is the address called by the `networking-authentik-forwardauth` Traefik Middleware at path `/outpost.goauthentik.io/auth/traefik`
