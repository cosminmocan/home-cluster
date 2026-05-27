## Why

There is no document management system in the cluster today. Receipts, manuals, scans, and other PDFs end up scattered across the Synology drive share with no search and no OCR. Paperless-ngx is the standard self-hosted answer — it OCRs incoming documents, tags them, and gives a single web UI to search the lot. Deploying it in-cluster lets it reuse the existing PostgreSQL and Redis instances and the existing NAS storage rather than standing up another VM.

The user constraint is "not accessible from outside" — so the deployment is internal-only at `docs.${SECRET_DOMAIN}`, with no Cloudflare DNS record, mirroring the [qBittorrent](../../specs/qbittorrent/spec.md) / [Prowlarr](../../specs/prowlarr/spec.md) / [Radarr](../../specs/radarr/spec.md) Ingress pattern.

## What Changes

- **New capability:** `paperless-ngx`. A `HelmRelease` deployed in the `media` namespace under [`cluster/apps/media/paperless-ngx/`](../../../cluster/apps/media/paperless-ngx/). Chart: `gabe565/paperless-ngx` (the canonical community chart that bundles the Tika + Gotenberg side services).
- **New HelmRepository:** [`cluster/charts/chart-gabe565.yaml`](../../../cluster/charts/chart-gabe565.yaml) pointing at the gabe565 chart index. The `chart-homepage` HelmRepository convention (one file per source) is preserved.
- **Wire-in:** [`cluster/apps/media/kustomization.yaml`](../../../cluster/apps/media/kustomization.yaml) gains `paperless-ngx` as a resource.
- **Storage:** one Longhorn PVC for Paperless's `data/` directory (~5Gi, index + small state) and two NFS mounts for `media/` and `consume/` (bulk PDFs, backed by the existing Synology share at `${STORAGE_NAS_IP}`). New share subpaths `/volume1/kubeNFS/paperless/{media,consume}` need to exist on the NAS.
- **Database:** a new `paperless` database in the existing PostgreSQL instance. The `postgres` superuser already has the credentials; the database itself must be pre-created via `psql` because Postgres does not auto-create on first connect.
- **Secrets:** a new `SECRET_PAPERLESS_KEY` entry in [`cluster/config/cluster-secrets.sops.yaml`](../../../cluster/config/cluster-secrets.sops.yaml) for Django's `SECRET_KEY`. Optionally a `SECRET_PAPERLESS_ADMIN_PASS` if the admin user is bootstrapped via env vars rather than the first-run web UI.
- **DNS:** internal-only via k8s-gateway. No `external-dns.alpha.kubernetes.io/target` annotation on the Ingress, so Cloudflare does not learn about it.

## Capabilities

### New Capabilities

- `paperless-ngx`: Self-hosted document management with OCR, full-text search, and tag-based organisation. Internal-only.

### Modified Capabilities

_(none)_ — no existing spec changes. The `media` category's namespace and parent `kustomization.yaml` are routine wire-in, not spec-level behaviour changes.

## Impact

- **Resources added:** 1 `HelmRelease` (`paperless-ngx`), 1 `Service`, 1 `Ingress`, 1 Longhorn `PersistentVolumeClaim`, ~3 `Deployment`s (web/scheduler, Tika, Gotenberg) depending on chart options.
- **External DNS:** none — the Ingress carries no `external-dns` annotation, so Cloudflare receives no record.
- **Cluster footprint:** approximately `cpu: 50m–100m`, `memory: 400Mi–800Mi` requests across the Paperless web + scheduler + Tika + Gotenberg pods at idle. OCR jobs spike CPU during ingestion.
- **NAS:** ~few hundred MB to many GB depending on volume of scanned documents; lives under `/volume1/kubeNFS/paperless/`.
- **PostgreSQL:** one new database `paperless`. Negligible incremental load for a single-user / small-team workload.
- **Redis:** one new logical consumer (Paperless uses Redis as its Celery broker / cache); no additional Redis deployment.
- **Renovate:** the new HelmRepository and chart version get tracked automatically once committed; Renovate's `cluster/.+\.ya?ml$` glob already covers the path.
- **Out of scope:**
  - Authentik forward-auth integration — Paperless has its own user system and the internal-only constraint already gates access. Can be layered on later if desired.
  - Public access via Cloudflare — explicitly excluded by the user.
  - Importing existing documents — operator drops them in `consume/` post-deployment; not part of the change.
  - Backup automation for the Paperless database / NAS share.
