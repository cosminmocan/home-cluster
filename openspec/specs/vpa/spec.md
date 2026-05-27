# VPA Specification

## Purpose

The Vertical Pod Autoscaler (VPA) runs in **recommender-only mode** in the `monitoring` namespace. It reads historical resource usage from Prometheus and writes resource recommendations to the cluster, but does not enforce them — the admission controller and updater are both disabled. [Goldilocks](../goldilocks/spec.md) consumes those recommendations and renders them as a dashboard.

## Requirements

### Requirement: Deployment shape

The system SHALL deploy VPA as a Flux `HelmRelease` using the Fairwinds chart in `monitoring`.

#### Scenario: HelmRelease declaration

- **WHEN** Flux reconciles [`cluster/apps/monitoring/vpa/release.yaml`](../../../cluster/apps/monitoring/vpa/release.yaml)
- **THEN** a `HelmRelease` named `vpa` is created in `monitoring`
- **AND** the chart resolves to `vpa` from `chart-fairwinds`
- **AND** the release `dependsOn` `kube-prometheus-stack` in `monitoring`

### Requirement: Recommender-only mode

The system SHALL run only the VPA recommender component, with admission controller and updater disabled.

#### Scenario: Component toggles

- **WHEN** the HelmRelease reconciles
- **THEN** `recommender.enabled: true` runs the recommender pod
- **AND** `updater.enabled: false` and `admissionController.enabled: false` — VPA NEVER modifies pod resource requests automatically
- **AND** the recommender image is pinned to `registry.k8s.io/autoscaling/vpa-recommender:1.6.0`

### Requirement: Prometheus storage backend

The system SHALL pull historical metrics from the in-cluster Prometheus instance rather than VPA's default checkpoint store.

#### Scenario: Prometheus address

- **WHEN** the recommender starts
- **THEN** `extraArgs.prometheus-address: "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"` and `extraArgs.storage: prometheus` are set
- **AND** recommendations are based on rolling Prometheus history, not VPA-owned checkpoints
