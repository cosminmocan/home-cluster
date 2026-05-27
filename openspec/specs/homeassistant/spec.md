# Home Assistant Specification

## Purpose

Home Assistant runs as a long-lived VM on the LAN (`192.168.100.64:8123`), not in the cluster. The cluster fronts it with a Traefik Ingress on the short host `ha.${SECRET_DOMAIN}` and publishes a public Cloudflare record so it can be reached remotely. Same NAS/external-host pattern as [Jellyfin](../jellyfin/spec.md), but the upstream is a separate VM rather than the Synology NAS.
## Requirements
### Requirement: Deployment shape

The system SHALL front the external Home Assistant instance using a selector-less `Service` and a hand-written `Endpoints` object.

#### Scenario: Service and Endpoints

- **WHEN** Flux reconciles [`cluster/apps/media/homeassistant/`](../../../cluster/apps/media/homeassistant/)
- **THEN** [`service.yaml`](../../../cluster/apps/media/homeassistant/service.yaml) creates a `Service` named `homeassistant` in `media` on port `80` → `targetPort: 8123`
- **AND** [`endpoint.yaml`](../../../cluster/apps/media/homeassistant/endpoint.yaml) creates an `Endpoints` object pointing at `192.168.100.64:8123`

### Requirement: HTTP access

The system SHALL expose Home Assistant on `ha.${SECRET_DOMAIN}` over HTTPS, publicly via Cloudflare with direct connection (Cloudflare-proxied disabled).

#### Scenario: Ingress with public DNS

- **WHEN** [`cluster/apps/media/homeassistant/ingress.yaml`](../../../cluster/apps/media/homeassistant/ingress.yaml) is reconciled
- **THEN** a Traefik Ingress on host `ha.${SECRET_DOMAIN}` (short subdomain) routes to the `homeassistant` Service on port `80`
- **AND** `external-dns.alpha.kubernetes.io/target: "${CLOUDFLARE_DDNS_RECORD}"` publishes a Cloudflare record
- **AND** `external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"` keeps Cloudflare DNS-only so WebSocket connections to Home Assistant work
