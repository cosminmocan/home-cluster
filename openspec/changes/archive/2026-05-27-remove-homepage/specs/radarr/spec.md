## REMOVED Requirements

### Requirement: Homepage integration
**Reason**: The Homepage capability is retired (see the `homepage` delta in this change).
**Migration**: The Service-level annotations `gethomepage.dev/enabled`, `gethomepage.dev/name`, `gethomepage.dev/icon` and the corresponding widget entry in [`cluster/apps/default/homepage/config.yaml`](../../../../../cluster/apps/default/homepage/config.yaml) are removed alongside the Homepage capability. The widget's `${RADARR_SECRET_KEY}` remains in `cluster-secrets` for Radarr's own use.
