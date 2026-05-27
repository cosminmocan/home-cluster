# Redis Specification

## Purpose

Redis is the cluster's in-memory cache, used by Authentik for session storage. Deployed standalone (no replicas, no sentinel) with persistence disabled — caches are expected to be ephemeral and Authentik tolerates cold starts.

## Requirements

### Requirement: Deployment shape

The system SHALL deploy Redis as a Flux `HelmRelease` using the Bitnami chart in `database`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/database/redis/release.yaml`](../../../cluster/apps/database/redis/release.yaml)
- **THEN** a `HelmRelease` named `redis` is created in `database`
- **AND** the chart resolves to `redis` from `chart-bitnami`
- **AND** the image is `docker.io/bitnamilegacy/redis` with `global.security.allowInsecureImages: true`
- **AND** `architecture: standalone` — no replicas, no sentinel

### Requirement: Ephemeral storage

The system SHALL run Redis without any persistent storage — restarts lose state.

#### Scenario: Persistence disabled

- **WHEN** the HelmRelease reconciles
- **THEN** `master.persistence.enabled: false` and `replica.persistence.enabled: false`
- **AND** no PVC is created

### Requirement: Authentication

The system SHALL run Redis with authentication disabled — access is restricted by cluster network policy and the `${REDIS_HOST_ADDRESS}` is a private substitution value.

#### Scenario: No auth, no sentinel

- **WHEN** the Redis pod starts
- **THEN** `auth.enabled: false` and `auth.sentinel: false`
- **AND** the Service is reachable at `${REDIS_HOST_ADDRESS}` from within the cluster
