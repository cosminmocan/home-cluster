## REMOVED Requirements

### Requirement: Homepage integration
**Reason**: The Homepage capability is retired (see the `homepage` delta in this change). With no consumer, the requirement that "a tile linking to qBittorrent appears on `home.${SECRET_DOMAIN}`" is no longer meaningful.
**Migration**: The annotations `gethomepage.dev/enabled`, `gethomepage.dev/name`, `gethomepage.dev/icon` on [`cluster/apps/media/qbittorrent/ingress.yaml`](../../../../../cluster/apps/media/qbittorrent/ingress.yaml) are removed in this change to keep manifests and specs in sync.
