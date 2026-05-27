# Drive Specification

## Purpose

The "drive" capability fronts a NAS-hosted file/drive service (`192.168.100.95:10002`) behind a Traefik Ingress on `drive.${SECRET_DOMAIN}`. Same NAS-fronted pattern as [Jellyfin](../jellyfin/spec.md), with the `buffering-large-files` Traefik middleware enabled because the upstream handles large file up/downloads.
## Requirements
### Requirement: Deployment shape

The system SHALL front the NAS drive service using a selector-less `Service` and a hand-written `Endpoints` object.

#### Scenario: Service and Endpoints

- **WHEN** Flux reconciles [`cluster/apps/media/drive/`](../../../cluster/apps/media/drive/)
- **THEN** [`service.yaml`](../../../cluster/apps/media/drive/service.yaml) creates a `Service` named `drive` in `media` on port `80` → `targetPort: 10002`
- **AND** [`endpoint.yaml`](../../../cluster/apps/media/drive/endpoint.yaml) creates an `Endpoints` object pointing at `192.168.100.95:10002`

### Requirement: HTTP access

The system SHALL expose drive on `drive.${SECRET_DOMAIN}` over HTTPS, publicly via Cloudflare with direct streaming, and apply the large-file buffering middleware.

#### Scenario: Ingress with public DNS and buffering middleware

- **WHEN** [`cluster/apps/media/drive/ingress.yaml`](../../../cluster/apps/media/drive/ingress.yaml) is reconciled
- **THEN** a Traefik Ingress on host `drive.${SECRET_DOMAIN}` routes to the `drive` Service on port `80`
- **AND** `external-dns.alpha.kubernetes.io/target: "${CLOUDFLARE_DDNS_RECORD}"` publishes a Cloudflare record
- **AND** `external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"` keeps Cloudflare DNS-only
- **AND** `traefik.ingress.kubernetes.io/router.middlewares: "networking-buffering-large-files@kubernetescrd"` invokes the shared Middleware
