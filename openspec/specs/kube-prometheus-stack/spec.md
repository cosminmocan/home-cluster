# kube-prometheus-stack Specification

## Purpose

The kube-prometheus-stack release bundles Prometheus, Grafana, and the Prometheus Operator into the `monitoring` namespace. It powers metrics collection (Prometheus), visualisation (Grafana), and the recommendation engine for [VPA](../vpa/spec.md) / [Goldilocks](../goldilocks/spec.md). Alertmanager is intentionally disabled — alert delivery for the cluster is handled by Flux's Discord/GitHub notification providers instead of by Prometheus alerts.

## Requirements

### Requirement: Deployment shape

The system SHALL deploy kube-prometheus-stack as a Flux `HelmRelease` in `monitoring`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/monitoring/kube-prometheus-stack/release.yaml`](../../../cluster/apps/monitoring/kube-prometheus-stack/release.yaml)
- **THEN** a `HelmRelease` named `kube-prometheus-stack` is created in `monitoring`
- **AND** the chart resolves to `kube-prometheus-stack` from `chart-prometheus-community`
- **AND** the release `dependsOn` `longhorn` in `longhorn-system`
- **AND** CRDs are managed out-of-band (`install.crds: Skip`, `upgrade.crds: Skip`, `crds.enabled: false`) — the chart's CRDs are applied separately under [`cluster/crds/prometheus/`](../../../cluster/crds/prometheus/) by the `crds` Flux Kustomization

### Requirement: Prometheus storage and retention

The system SHALL retain at most 14 days or 8GB of metrics on a Longhorn-backed volume.

#### Scenario: Storage spec

- **WHEN** the Prometheus StatefulSet is created
- **THEN** a volumeClaimTemplate produces a `10Gi` Longhorn PVC with `accessModes: [ReadWriteOnce]`
- **AND** `prometheusSpec.retention: 14d` and `retentionSize: 8GB` cap data growth

### Requirement: Grafana

The system SHALL deploy Grafana with persistent storage and an internal Ingress.

#### Scenario: Grafana persistence

- **WHEN** Grafana is reconciled
- **THEN** a `2Gi` Longhorn PVC is bound for Grafana's data directory
- **AND** `defaultDashboardsTimezone: ${TIMEZONE}` aligns dashboard times with the cluster

#### Scenario: Grafana ingress (internal-only)

- **WHEN** the Grafana subchart renders its Ingress
- **THEN** a Traefik Ingress on host `grafana.${SECRET_DOMAIN}` routes to the Grafana service
- **AND** the Ingress carries NO `external-dns.alpha.kubernetes.io/target` annotation, keeping it LAN-only

### Requirement: Disabled Alertmanager

The system SHALL run without Alertmanager — alerting flows through Flux notifications instead.

#### Scenario: Alertmanager disabled

- **WHEN** the chart reconciles
- **THEN** `alertmanager.enabled: false`
- **AND** no Alertmanager StatefulSet, Service, or PVC is created

### Requirement: Exporters

The system SHALL run kube-state-metrics and prometheus-node-exporter for cluster-wide visibility.

#### Scenario: Exporters enabled

- **WHEN** the chart reconciles
- **THEN** `nodeExporter.enabled: true` and the node-exporter DaemonSet runs on every node
- **AND** kube-state-metrics is deployed with `cpu: 15m`, `memory: 64Mi` requests
