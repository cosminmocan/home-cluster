# Music Specification

## Purpose

The "music" capability fronts a NAS-hosted music streaming service (`192.168.100.95:8800`) behind a Traefik Ingress on `music.${SECRET_DOMAIN}`. Same NAS-fronted pattern as [Jellyfin](../jellyfin/spec.md). The ingress additionally enables the `buffering-large-files` Traefik middleware because the upstream serves large audio files and album art bundles.
## Requirements
### Requirement: Deployment shape

The system SHALL front the NAS music service using a selector-less `Service` and a hand-written `Endpoints` object.

#### Scenario: Service and Endpoints

- **WHEN** Flux reconciles [`cluster/apps/media/music/`](../../../cluster/apps/media/music/)
- **THEN** [`service.yaml`](../../../cluster/apps/media/music/service.yaml) creates a `Service` named `music` in `media` on port `80` → `targetPort: 8800`
- **AND** [`endpoint.yaml`](../../../cluster/apps/media/music/endpoint.yaml) creates an `Endpoints` object pointing at `192.168.100.95:8800`

### Requirement: HTTP access

The system SHALL expose music on `music.${SECRET_DOMAIN}` over HTTPS, publicly via Cloudflare with direct streaming, and apply the large-file buffering middleware.

#### Scenario: Ingress with public DNS and buffering middleware

- **WHEN** [`cluster/apps/media/music/ingress.yaml`](../../../cluster/apps/media/music/ingress.yaml) is reconciled
- **THEN** a Traefik Ingress on host `music.${SECRET_DOMAIN}` routes to the `music` Service on port `80`
- **AND** `external-dns.alpha.kubernetes.io/target: "${CLOUDFLARE_DDNS_RECORD}"` publishes a Cloudflare record
- **AND** `external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"` keeps Cloudflare DNS-only
- **AND** `traefik.ingress.kubernetes.io/router.middlewares: "networking-buffering-large-files@kubernetescrd"` invokes the shared Middleware defined in [`cluster/core/networking/traefik/middlewares/middlewares.yaml`](../../../cluster/core/networking/traefik/middlewares/middlewares.yaml)
