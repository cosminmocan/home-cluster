## REMOVED Requirements

### Requirement: Homepage integration
**Reason**: The Homepage capability is retired (see the `homepage` delta in this change). The legacy `hajimari.io/icon` annotation also loses its only past consumer.
**Migration**: Both `gethomepage.dev/name` and `hajimari.io/icon` annotations are removed from [`cluster/apps/media/homeassistant/ingress.yaml`](../../../../../cluster/apps/media/homeassistant/ingress.yaml).
