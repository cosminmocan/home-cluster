## REMOVED Requirements

### Requirement: Homepage integration
**Reason**: The Homepage capability is retired (see the `homepage` delta in this change).
**Migration**: The `gethomepage.dev/*` annotations on the `dashboard.ingress` block in [`cluster/apps/monitoring/goldilocks/release.yaml`](../../../../../cluster/apps/monitoring/goldilocks/release.yaml) are removed.
