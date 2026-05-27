## REMOVED Requirements

### Requirement: Homepage integration
**Reason**: The Homepage capability is retired (see the `homepage` delta in this change).
**Migration**: The `gethomepage.dev/*` annotations on the Ingress block in [`cluster/apps/database/pgadmin/release.yaml`](../../../../../cluster/apps/database/pgadmin/release.yaml) are removed.
