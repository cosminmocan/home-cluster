# Jellyfin Specification

## Purpose

Jellyfin is the media streaming server. The actual Jellyfin process runs on the Synology NAS (`192.168.100.130:8096`), not in the cluster. The cluster fronts it with a Traefik Ingress and a public Cloudflare DNS record so household members can stream from anywhere. This follows the NAS-fronted-service pattern documented in [`ADDING_A_NEW_APP.md`](../../../ADDING_A_NEW_APP.md): bare `Service` (no selector) + hand-written `Endpoints` + `Ingress`.
## Requirements
### Requirement: Deployment shape

The system SHALL front an external (NAS-hosted) Jellyfin process using a selector-less `Service` and a hand-written `Endpoints` object — no HelmRelease, no PVC, no pod.

#### Scenario: Service and Endpoints

- **WHEN** Flux reconciles [`cluster/apps/media/jellyfin/`](../../../cluster/apps/media/jellyfin/)
- **THEN** [`service.yaml`](../../../cluster/apps/media/jellyfin/service.yaml) creates a `Service` named `jellyfin` in `media` on port `80` → `targetPort: 8096`
- **AND** [`endpoint.yaml`](../../../cluster/apps/media/jellyfin/endpoint.yaml) creates an `Endpoints` object with the same name pointing at `192.168.100.130:8096`
- **AND** because the Service has no `selector`, Kubernetes does not auto-generate Endpoints — the hand-written object is authoritative

### Requirement: HTTP access

The system SHALL expose Jellyfin on `jellyfin.${SECRET_DOMAIN}` over HTTPS, publicly via Cloudflare with direct streaming (Cloudflare-proxied disabled).

#### Scenario: Ingress with direct streaming

- **WHEN** [`cluster/apps/media/jellyfin/ingress.yaml`](../../../cluster/apps/media/jellyfin/ingress.yaml) is reconciled
- **THEN** a Traefik Ingress on host `jellyfin.${SECRET_DOMAIN}` routes to the `jellyfin` Service on port `80`
- **AND** the annotation `external-dns.alpha.kubernetes.io/target: "${CLOUDFLARE_DDNS_RECORD}"` publishes a public Cloudflare record
- **AND** the annotation `external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"` keeps Cloudflare DNS-only (no HTTP proxy), so streaming bypasses Cloudflare's request size limits
