# PostgreSQL Specification

## Purpose

PostgreSQL is the shared relational database for the cluster, running in the `database` namespace. It backs Authentik, Radarr, and Prowlarr; new apps that need a relational store should use it rather than spinning up their own. The HelmRelease is named `postgresql` (not `postgres`) to match the upstream Bitnami chart's release name; cross-app `dependsOn` references must use that name.

## Requirements

### Requirement: Deployment shape

The system SHALL deploy PostgreSQL as a Flux `HelmRelease` using the Bitnami chart in `database`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/database/postgres/release.yaml`](../../../cluster/apps/database/postgres/release.yaml)
- **THEN** a `HelmRelease` named `postgresql` is created in `database`
- **AND** the chart resolves to `postgresql` from `chart-bitnami`
- **AND** the image is pinned to `docker.io/bitnamilegacy/postgresql` with `global.security.allowInsecureImages: true` (required after Bitnami's image policy shift)
- **AND** the release `dependsOn` the `longhorn` HelmRelease in `longhorn-system`

### Requirement: Storage

The system SHALL persist Postgres data on a Longhorn-backed PVC.

#### Scenario: Longhorn PVC

- **WHEN** [`cluster/apps/database/postgres/pvc.yaml`](../../../cluster/apps/database/postgres/pvc.yaml) reconciles
- **THEN** a `PersistentVolumeClaim` named `postgresql-data` with `2Gi` `ReadWriteOnce` on `storageClassName: longhorn` is bound
- **AND** the HelmRelease references it via `primary.persistence.existingClaim: postgresql-data`

### Requirement: Authentication

The system SHALL provision a `postgres` superuser whose password is sourced from the SOPS-encrypted cluster secret.

#### Scenario: Admin user provisioning

- **WHEN** the Postgres pod initialises
- **THEN** `auth.enablePostgresUser: true` creates the `postgres` superuser
- **AND** `auth.postgresPassword` resolves from `${SECRET_POSTGRES_ADMIN_PASS}` (Flux substitution from `cluster-secrets`)
- **AND** a default database named `postgres` is created

### Requirement: Network access

The system SHALL expose Postgres only inside the cluster.

#### Scenario: ClusterIP service

- **WHEN** the HelmRelease reconciles
- **THEN** the chart creates a Service named `postgresql` in `database` on port `5432`, reachable at `postgresql.database.svc.cluster.local:5432`
- **AND** no Ingress is created
- **AND** `${POSTGRES_HOST_ADDRESS}` (consumed by Authentik, Radarr, Prowlarr) resolves to this service via Flux substitution
