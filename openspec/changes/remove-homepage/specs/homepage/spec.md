## REMOVED Requirements

### Requirement: Deployment shape
**Reason**: The Homepage capability is retired wholesale. The HelmRelease, ConfigMap, Ingress, ServiceAccount, and RBAC are all deleted alongside the entire `cluster/apps/default/homepage/` directory.
**Migration**: No replacement dashboard is provisioned. Users should bookmark per-app subdomains (`radarr.${SECRET_DOMAIN}`, `prowlarr.${SECRET_DOMAIN}`, etc.) directly.

### Requirement: ConfigMap-driven content
**Reason**: With the Homepage HelmRelease removed, the `homepage` ConfigMap is also deleted. There is no consumer left.
**Migration**: Any bookmark or service entry previously curated in [`cluster/apps/default/homepage/config.yaml`](../../../../../cluster/apps/default/homepage/config.yaml) must be relocated by the user — typically into browser bookmarks or a personal note. The Prowlarr widget definition (which referenced `${PROWLARR_SECRET_KEY}`) no longer has a host; the secret remains in `cluster-secrets` for future reuse.

### Requirement: HTTP access
**Reason**: The Ingress for `home.${SECRET_DOMAIN}` is deleted. external-dns removes the public Cloudflare record on its next reconcile; k8s-gateway stops resolving the host once the Ingress is gone.
**Migration**: `home.${SECRET_DOMAIN}` becomes a hard NXDOMAIN for both LAN and public clients. There is no redirect. If a redirect to a per-app host is desired later, a small Traefik `IngressRoute` could be added in a follow-up change.

### Requirement: Storage
**Reason**: The pod is deleted, so the `emptyDir` volume disappears with it. No PVC was ever created, so no `PersistentVolumeClaim` needs to be cleaned up.
**Migration**: None.
