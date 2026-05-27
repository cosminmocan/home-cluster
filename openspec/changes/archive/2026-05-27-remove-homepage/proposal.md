## Why

The Homepage dashboard at `home.${SECRET_DOMAIN}` is being retired. It carried real maintenance overhead — a hand-edited `services.yaml` ConfigMap that duplicated tile metadata already living on every Ingress as `gethomepage.dev/*` annotations, plus a public Cloudflare DNS record and a long-lived pod just to render a static index page. Removing it deletes that overhead and shrinks the cluster's footprint without any user impact: every app behind Homepage is already reachable directly at its own `*.${SECRET_DOMAIN}` host.

## What Changes

- **BREAKING:** `home.${SECRET_DOMAIN}` will stop resolving (internal and public). Anyone using it as a bookmark must switch to the per-app subdomain (e.g. `radarr.${SECRET_DOMAIN}`).
- Delete the entire [`cluster/apps/default/`](../../../cluster/apps/default/) category directory, which contains nothing but Homepage.
- Drop the `default` namespace `Namespace` manifest. The built-in Kubernetes `default` namespace is unaffected (Kubernetes will not let it be deleted).
- Remove the `default` namespace from any parent-level wiring (currently no top-level `cluster/apps/kustomization.yaml` exists; Flux discovers categories recursively, so deletion alone is sufficient).
- Strip the now-orphaned `gethomepage.dev/*` annotations from every Ingress / Service that carries them (qBittorrent, Radarr, Prowlarr, Jellyseerr, Jellyfin, music, photos, drive, Home Assistant, pgAdmin, Authentik, Goldilocks). Annotations are cosmetic once Homepage is gone, but leaving them creates drift between the spec and the manifests.
- Remove the `homepage` HelmRepository wiring is **not** in scope — the `chart-homepage` HelmRepository in `cluster/charts/` is retained in case Homepage (or a fork) is reintroduced later.
- Remove the corresponding requirement from each app spec.

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `homepage`: every requirement is removed; the capability is retired wholesale.
- `qbittorrent`: drop the **Homepage integration** requirement.
- `radarr`: drop the **Homepage integration** requirement.
- `prowlarr`: drop the **Homepage integration** requirement.
- `jellyseerr`: drop the **Homepage integration** requirement.
- `jellyfin`: drop the **Homepage integration** requirement.
- `music`: drop the **Homepage integration** requirement.
- `photos`: drop the **Homepage integration** requirement.
- `drive`: drop the **Homepage integration** requirement.
- `homeassistant`: drop the **Homepage integration** requirement (including the legacy `hajimari.io/icon` annotation).
- `pgadmin`: drop the **Homepage integration** requirement.
- `authentik`: drop the **Homepage integration** requirement.
- `goldilocks`: drop the **Homepage integration** requirement.

## Impact

- **Resources removed:** 1 `HelmRelease` (`homepage`), 1 `ConfigMap` (`homepage`), 1 `Ingress` (`homepage`), 1 `ServiceAccount` + RBAC, 1 `Namespace` manifest (`default`).
- **External DNS:** the public Cloudflare record for `home.${SECRET_DOMAIN}` is removed by external-dns on the next reconcile after the Ingress is deleted.
- **Internal DNS:** k8s-gateway stops resolving `home.${SECRET_DOMAIN}` once the Ingress is gone.
- **Cluster footprint:** roughly `cpu: 15m`, `memory: 248Mi` of requests and `memory: 2Gi` of limit freed (per [`homepage/release.yaml:61-66`](../../../cluster/apps/default/homepage/release.yaml#L61-L66)).
- **Spec churn:** 13 spec files in `openspec/specs/` receive delta entries via this change. After archive, the `homepage/` capability directory is removed and 12 app spec files lose their "Homepage integration" requirement section.
- **Renovate:** the `homepage` chart will stop appearing in PRs once the HelmRelease is deleted. No PRs need to be cancelled — Renovate just skips anything not in the repo.
- **Out of scope:**
  - The `chart-homepage` `HelmRepository` in [`cluster/charts/`](../../../cluster/charts/) stays, as reintroducing Homepage later would require only restoring the deleted files.
  - No replacement dashboard is provisioned.
  - The shared Traefik forward-auth middleware, k8s-gateway, external-dns, and cert-manager are untouched.
