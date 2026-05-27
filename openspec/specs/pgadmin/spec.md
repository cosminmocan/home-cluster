# pgAdmin Specification

## Purpose

pgAdmin is the Postgres web UI in the `database` namespace, used for occasional inspection and ad-hoc queries against the shared PostgreSQL instance. Deployed in "desktop mode" with the login pop-up disabled because the Ingress is internal-only and not reachable from outside the LAN.
## Requirements
### Requirement: Deployment shape

The system SHALL deploy pgAdmin as a Flux `HelmRelease` using the runix chart in `database`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/database/pgadmin/release.yaml`](../../../cluster/apps/database/pgadmin/release.yaml)
- **THEN** a `HelmRelease` named `pgadmin` is created in `database`
- **AND** the chart resolves to `pgadmin4` from `chart-runix`
- **AND** the release `dependsOn` `postgresql` in `database`
- **AND** the deployment strategy is `Recreate` (the chart's PVC-or-no-PVC pattern requires it)

### Requirement: Desktop-mode authentication

The system SHALL skip pgAdmin's built-in authentication because the UI is reachable only from inside the LAN.

#### Scenario: Disabled login

- **WHEN** the pgAdmin pod starts
- **THEN** `PGADMIN_CONFIG_SERVER_MODE: "False"` runs pgAdmin in single-user desktop mode
- **AND** `PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: "False"` skips the master-password prompt
- **AND** this is acceptable only because the Ingress is internal-only — a publicly exposed pgAdmin would require these to be `True`

### Requirement: Preconfigured server entry

The system SHALL ship a server-definition entry for the in-cluster PostgreSQL so the user does not have to add it manually.

#### Scenario: Server definition

- **WHEN** the HelmRelease reconciles
- **THEN** `serverDefinitions.servers.postgres` defines a connection named `postgres` to `postgresql.database.svc.cluster.local:5432` with user `postgres`
- **AND** the password field is left blank — it must be entered interactively in the UI

### Requirement: HTTP access

The system SHALL expose pgAdmin on `pgadmin.${SECRET_DOMAIN}` over HTTPS, internal-only.

#### Scenario: Internal ingress

- **WHEN** the HelmRelease's `ingress` block renders
- **THEN** a Traefik Ingress on host `pgadmin.${SECRET_DOMAIN}` routes to the pgAdmin service
- **AND** the Ingress carries NO `external-dns.alpha.kubernetes.io/target` annotation, keeping it internal

### Requirement: Storage

The system SHALL run pgAdmin without persistent storage.

#### Scenario: PV disabled

- **WHEN** the HelmRelease reconciles
- **THEN** `persistentVolume.enabled: false` — pgAdmin state is rebuilt on each pod start
