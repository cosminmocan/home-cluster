## REMOVED Requirements

### Requirement: Homepage integration
**Reason**: The Homepage capability is retired (see the `homepage` delta in this change). The Prowlarr widget that consumed `${PROWLARR_SECRET_KEY}` is removed with the Homepage ConfigMap.
**Migration**: The Service-level annotations on [`cluster/apps/media/prowlarr/release.yaml`](../../../../../cluster/apps/media/prowlarr/release.yaml) are stripped. `${PROWLARR_SECRET_KEY}` stays in `cluster-secrets` since Prowlarr itself still consumes it as `PROWLARR__API_KEY`.
