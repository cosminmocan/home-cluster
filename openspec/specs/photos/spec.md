# Photos Specification

## Purpose

The "photos" capability fronts a NAS-hosted photo service (`192.168.100.95:5080`) behind a Traefik Ingress on `photos.${SECRET_DOMAIN}`. Same NAS-fronted pattern as [Jellyfin](../jellyfin/spec.md) and [music](../music/spec.md), with the `buffering-large-files` Traefik middleware enabled for uploads of large photo bundles.
## Requirements
### Requirement: Deployment shape

The system SHALL front the NAS photos service using a selector-less `Service` and a hand-written `Endpoints` object.

#### Scenario: Service and Endpoints

- **WHEN** Flux reconciles [`cluster/apps/media/photos/`](../../../cluster/apps/media/photos/)
- **THEN** [`service.yaml`](../../../cluster/apps/media/photos/service.yaml) creates a `Service` named `photos` in `media` on port `80` → `targetPort: 5080`
- **AND** [`endpoint.yaml`](../../../cluster/apps/media/photos/endpoint.yaml) creates an `Endpoints` object pointing at `192.168.100.95:5080`

### Requirement: HTTP access

The system SHALL expose photos on `photos.${SECRET_DOMAIN}` over HTTPS, publicly via Cloudflare with direct streaming, and apply the large-file buffering middleware.

#### Scenario: Ingress with public DNS and buffering middleware

- **WHEN** [`cluster/apps/media/photos/ingress.yaml`](../../../cluster/apps/media/photos/ingress.yaml) is reconciled
- **THEN** a Traefik Ingress on host `photos.${SECRET_DOMAIN}` routes to the `photos` Service on port `80`
- **AND** `external-dns.alpha.kubernetes.io/target: "${CLOUDFLARE_DDNS_RECORD}"` publishes a Cloudflare record
- **AND** `external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"` keeps Cloudflare DNS-only
- **AND** `traefik.ingress.kubernetes.io/router.middlewares: "networking-buffering-large-files@kubernetescrd"` invokes the shared Middleware
