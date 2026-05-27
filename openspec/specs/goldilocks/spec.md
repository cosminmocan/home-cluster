# Goldilocks Specification

## Purpose

Goldilocks visualises [VPA](../vpa/spec.md) recommendations on a per-workload basis. Namespaces labelled `goldilocks.fairwinds.com/enabled: "true"` get scanned; the dashboard at `goldilocks.${SECRET_DOMAIN}` shows current vs. recommended `requests`/`limits` so the operator can right-size resources. Internal-only — not exposed via Cloudflare.
## Requirements
### Requirement: Deployment shape

The system SHALL deploy Goldilocks as a Flux `HelmRelease` using the Fairwinds chart in `monitoring`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/monitoring/goldilocks/release.yaml`](../../../cluster/apps/monitoring/goldilocks/release.yaml)
- **THEN** a `HelmRelease` named `goldilocks` is created in `monitoring`
- **AND** the chart resolves to `goldilocks` from `chart-fairwinds`
- **AND** the release `dependsOn` `vpa` in `monitoring`

### Requirement: Namespace opt-in

The system SHALL only scan namespaces that explicitly opt in via label.

#### Scenario: Label selector

- **WHEN** Goldilocks scans the cluster
- **THEN** it produces recommendations only for namespaces carrying the label `goldilocks.fairwinds.com/enabled: "true"`
- **AND** the current opted-in namespaces are `media`, `database`, and `monitoring` (see each `namespace.yaml` under `cluster/apps/*/`)

### Requirement: HTTP access

The system SHALL expose the Goldilocks dashboard on `goldilocks.${SECRET_DOMAIN}` over HTTPS, internal-only.

#### Scenario: Internal ingress

- **WHEN** the HelmRelease's `dashboard.ingress` block renders
- **THEN** a Traefik Ingress on host `goldilocks.${SECRET_DOMAIN}` routes to the dashboard service
- **AND** the Ingress carries NO `external-dns.alpha.kubernetes.io/target` annotation, keeping it LAN-only
