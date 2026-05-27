## REMOVED Requirements

### Requirement: Homepage integration
**Reason**: The Homepage capability is retired (see the `homepage` delta in this change).
**Migration**: The `gethomepage.dev/*` annotations on the `server.ingress` block in [`cluster/apps/database/authentik/release.yaml`](../../../../../cluster/apps/database/authentik/release.yaml) are removed.
