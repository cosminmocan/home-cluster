## Context

Paperless-ngx is one of the few projects with a clear "self-hosted document manager" niche — it ingests scans / PDFs / emails, OCRs them via Tika + Gotenberg, indexes the text, and exposes a search/tag UI. The cluster already has every backing dependency it needs:

- **PostgreSQL** at `${POSTGRES_HOST_ADDRESS}` (the [`postgresql` HelmRelease](../../../cluster/apps/database/postgres/release.yaml) in `database`).
- **Redis** at `${REDIS_HOST_ADDRESS}` (the [`redis` HelmRelease](../../../cluster/apps/database/redis/release.yaml), auth disabled, ephemeral).
- **Longhorn** for small-state PVCs.
- **NFS share** on the Synology NAS for bulk document storage.
- **Traefik + k8s-gateway** for internal-only HTTPS.

The user's explicit constraints are *"not accessible from outside"* and *"docs.${SECRET_DOMAIN}"*. Both are routine for this repo — every internal app follows the same pattern of an Ingress with no `external-dns` annotation, using the wildcard cert and LAN DNS.

What this design has to settle is the small set of choices that aren't dictated by repo precedent: which chart, which category, how to bootstrap the Postgres database, and whether to involve Authentik.

## Goals / Non-Goals

**Goals**

- Stand up Paperless-ngx at `docs.${SECRET_DOMAIN}`, LAN-only.
- Reuse the existing Postgres and Redis instances; no new database tier components.
- Place document state on durable storage (Longhorn for index data, NFS for bulk).
- Drop-folder ingestion (`consume/` on NFS) so the operator can scan-and-drop from any LAN client.

**Non-Goals**

- Authentik forward-auth integration. Paperless ships its own user system; layering forward-auth in front double-prompts and complicates first-run setup. Can be added later as a separate change if multi-app SSO becomes the goal.
- Public access via Cloudflare. Explicitly excluded by the user.
- Automatic document import from existing storage locations. Operator drops them in `consume/` post-deploy.
- Backup automation. The Synology NAS already has its own snapshot policy for `kubeNFS/`; PostgreSQL backups are a separate concern tracked elsewhere (or, currently, nowhere — a known cluster-wide gap surfaced during exploration).
- Email ingestion via IMAP. Optional Paperless feature; not in scope.

## Decisions

### Chart: `gabe565/paperless-ngx`, not `bjw-s/app-template`

The cluster's house style is "use the upstream community chart when one exists, fall back to `bjw-s/app-template` for one-off images." Paperless-ngx has a maintained chart at `gabe565/paperless-ngx` that already wires Tika + Gotenberg, handles the env vars correctly, and is the canonical choice in homelab references.

Using `bjw-s/app-template` would mean replicating that wiring by hand for three controllers (web, Tika, Gotenberg) plus the worker scheduler — more YAML, more drift risk, no upside.

**Alternative considered:** `bjw-s/app-template`. Rejected — extra config burden for no benefit since the gabe565 chart is mature.

### New `HelmRepository`: `chart-gabe565`

The cluster doesn't pull anything from gabe565 today. A new file [`cluster/charts/chart-gabe565.yaml`](../../../cluster/charts/chart-gabe565.yaml) registers the repository (URL `https://charts.gabe565.com`). This follows the one-file-per-source convention already used in [`cluster/charts/`](../../../cluster/charts/) (see `chart-bjw.yaml`, `chart-traefik.yaml`, etc.).

**Alternative considered:** OCI source (`oci://ghcr.io/gabe565/charts/paperless-ngx`). Rejected for first pass — Flux supports it but every existing HelmRepository in this repo uses the HTTP index, and keeping the convention consistent makes the diff smaller.

### Category placement: `media/`, not a new `documents/`

Paperless deals with documents, not media, but creating a new top-level category for one app is premature — it would mean a new `namespace.yaml`, a new `kustomization.yaml`, and a new namespace to label for Goldilocks. The existing `media` category already houses workloads that aren't strictly media (Home Assistant, Drive, Music) and the broad-namespace cost of one more app is small.

If a second documents-adjacent app shows up later (e.g. Bookstack, Joplin server), splitting out `documents/` becomes worth it. Track in a follow-up change.

**Alternative considered:** new `documents/` category. Rejected as premature.

### Storage split: Longhorn for `data/`, PVCs on `nfs-client` for `media/` + `consume/`

Same _shape_ as [qBittorrent](../../specs/qbittorrent/spec.md) and [Radarr](../../specs/radarr/spec.md) — Longhorn for state, NFS for bulk — but a different _mechanism_. Those apps use the `bjw-s/app-template` chart directly with `persistence.<name>.type: nfs` mounts. The gabe565 chart depends on `bjw-s/common@1.5.1`, which **does not** support inline `type: nfs` in `persistence` keys (that arrived in common v2+).

So the bulk volumes use **PVCs against the `nfs-client` StorageClass** instead. That StorageClass (provisioned by [`nfs-subdir-external-provisioner`](../../../cluster/core/nfs-subdir-external-provisioner/) in the `nfs-provisioner` namespace, pointed at `192.168.100.95:/volume1/kubeNFS`) creates a fresh subdirectory under `kubeNFS/` for every PVC and mounts it. No pre-created paths on the NAS are needed.

- `/usr/src/paperless/data` → `storageClass: longhorn`, `accessMode: ReadWriteOnce`, `size: 5Gi`. Whoosh index, classifier model, run state.
- `/usr/src/paperless/media` → `storageClass: nfs-client`, `accessMode: ReadWriteOnce`, `size: 50Gi`. Bulk PDFs, originals, thumbnails. Lives under a dynamically-named subdir of `kubeNFS/`.
- `/usr/src/paperless/consume` → `storageClass: nfs-client`, `accessMode: ReadWriteOnce`, `size: 5Gi`. Drop folder.
- `/usr/src/paperless/export` → `storageClass: longhorn`, `size: 1Gi`. Rarely used; Longhorn is fine.

**Consume directory workflow** — because the consume dir is now a dynamically-provisioned NFS subdirectory (path like `kubeNFS/media-paperless-ngx-consume-<uid>` on the NAS) rather than a fixed-path Synology share, the canonical way to drop files is via the **Paperless web UI uploader** at `https://docs.${SECRET_DOMAIN}/` or via `kubectl cp <local-pdf> media/<pod>:/usr/src/paperless/consume/`. The NAS-share drag-and-drop workflow is gone; if it's wanted later, a follow-up change can replace the `consume` PVC with an inline NFS mount pointed at a stable path (would require switching this app to `bjw-s/app-template` directly).

**Alternative considered:** inline `type: nfs` mount via additional volumes in `common@1.5.1`. Rejected — `additionalVolumes` is supported but pointing it at the `consume` mountPath conflicts with the chart's persistence handling, and routing media through a fixed NFS path requires that subdir to exist on the NAS (the original Job-based bootstrap, which already hit a permission-denied error in practice).

**Alternative considered:** all-NFS. Rejected — Whoosh index does many small reads/writes; NFS latency would noticeably slow searches and reindexing.

**Alternative considered:** all-Longhorn. Rejected — bulk PDFs on Longhorn fill the cluster disk faster than necessary.

### Scope: ship Paperless only, defer Tika + Gotenberg to a follow-up

The `gabe565/paperless-ngx` chart's [`Chart.yaml`](https://github.com/gabe565/charts/blob/paperless-ngx-0.24.1/charts/paperless-ngx/Chart.yaml) declares dependencies on `common`, `postgresql`, `mariadb`, and `redis` only — there is no Tika or Gotenberg subchart and no values toggle for them. Standing them up would require either:

- A second HelmRelease per service using `bjw-s/app-template`, plus env wiring (`PAPERLESS_TIKA_ENABLED`, `PAPERLESS_TIKA_ENDPOINT`, `PAPERLESS_TIKA_GOTENBERG_ENDPOINT`) pointing at the new services. Doable but adds three more files and three more workloads.
- Sidecar containers in the Paperless pod via `additionalContainers`. Couples their lifecycle to Paperless's and complicates Renovate updates.

Neither is needed for the first deployment. Paperless's built-in Tesseract OCR handles **PDFs and images** without Tika/Gotenberg. Only **Office documents (.docx, .xlsx)**, **emails (.eml)**, and **HTML imports** require Tika; only **HTML rendering** requires Gotenberg. None of those are the immediate use case.

If/when those formats matter, a follow-up change can layer Tika + Gotenberg in as two separate HelmReleases under `cluster/apps/media/paperless-ngx-tika/` and `cluster/apps/media/paperless-ngx-gotenberg/`, then patch the Paperless HelmRelease's env block.

**Alternative considered:** pivot to `bjw-s/app-template` directly and define Paperless + Tika + Gotenberg as three controllers in a single HelmRelease. Rejected — bigger change, more YAML to maintain, and the user's brief ("implement Paperless-ngx") doesn't call for it.

### Database bootstrap: pre-create via `psql` exec

Postgres does not auto-create databases on first connection, and the Paperless image's entrypoint does not run `CREATE DATABASE`. The `paperless` database has to exist before the pod starts; otherwise the first run fails with `database "paperless" does not exist` and the HelmRelease falls into a retry loop.

Two ways to handle it:

1. **Manual one-time `psql` exec** (chosen). The operator runs one command in the postgres pod to create the database. Recorded as a task in [tasks.md](./tasks.md) and survives `git revert` (deleting the HelmRelease does not drop the database — and that is intentional, see Migration Plan).

2. A Kubernetes `Job` defined in the change that runs `psql -c "CREATE DATABASE paperless"`. Cleaner GitOps, but the Job would have to live somewhere logical (Paperless's own dir? Postgres's?) and would need its own `kustomize.toolkit.fluxcd.io/prune` handling so it doesn't get re-run on every reconcile. Rejected as overkill for a one-time bootstrap.

If Paperless is later removed, the `paperless` database stays in Postgres. Re-adding Paperless then is a no-op for the DB (the chart connects to the existing DB and runs Django migrations).

### Secret key: new entry in `cluster-secrets.sops.yaml`

Adding `SECRET_PAPERLESS_KEY` (and optionally `SECRET_PAPERLESS_ADMIN_PASS` for env-var admin bootstrap) to the existing SOPS-encrypted `cluster-secrets` Secret. This keeps Paperless in the same substitution-driven secret model as Authentik / Radarr / Prowlarr, with no per-app Secret object to manage and no reflector exception needed.

The Django `SECRET_KEY` should be ≥ 50 random characters. Generate with `openssl rand -base64 60 | head -c 60`.

### Authentik forward-auth: deferred

Three reasons not to wire forward-auth in this first deployment:

1. Paperless has its own authentication and user model. Forward-auth would double-prompt unless Paperless's auth is also disabled via env var — that's a stretch given the user hasn't asked for it.
2. The "not accessible from outside" constraint is satisfied by the LAN-only Ingress alone. Defence in depth via Authentik is nice-to-have, not required.
3. Bootstrapping Paperless requires logging in as `admin` to set up tags / first ingestion; the simplest path is to use Paperless's own admin user first, then revisit SSO once the basics work.

## Risks / Trade-offs

- **Risk: the `paperless` database is pre-created with mismatched encoding/collation, breaking later imports.** → Mitigation: create with `WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE template0`. Documented in tasks.md.
- **Risk: NFS mounts unavailable on pod start → CrashLoopBackoff.** → Existing NFS shares (jellyfin, qbittorrent) already prove the cluster can mount NFS from `${STORAGE_NAS_IP}`. New share paths just need to exist. If the Synology shares don't exist, the pod's NFS mount will fail clearly and visibly.
- **Risk: Whoosh index corruption from an unclean pod kill.** → Longhorn ReadWriteOnce on a single node means no concurrent writers; this is the same blast radius as Radarr's config volume.
- **Risk: Paperless updates rename env vars or migrate config in breaking ways.** → Renovate's `minimumReleaseAge: 30 days` plus the chart's release notes give a window to react; the spec's Postgres + Redis dependencies are stable.
- **Risk: chart version churn.** → Acceptable. The spec deliberately doesn't pin a specific chart version; Renovate manages that.
- **Trade-off: no Authentik integration today.** → Accepted. Can be added later as a non-breaking change.

## Migration Plan

There is no existing Paperless data to migrate, so the "migration" is just initial deployment:

1. Create the NFS share subdirectories on the Synology (under the existing `kubeNFS` share).
2. Pre-create the `paperless` database in PostgreSQL.
3. Add the new HelmRepository + HelmRelease + PVC, plus the secret key, in a single commit.
4. Watch Flux apply. First pod start runs Django migrations; second pod start serves the login page.
5. Create the first admin user via the Paperless container exec OR via the env-var bootstrap path, then log into `docs.${SECRET_DOMAIN}`.

**Rollback** — `git revert <merge-sha>` deletes the HelmRelease, the PVC, and the Ingress on the next Flux reconcile. The `paperless` PostgreSQL database stays behind (intentional — re-deploying restores state). The NFS share contents remain on the NAS. Total wall-clock rollback < 10 minutes.

## Open Questions

- **NFS share subpaths** — `/volume1/kubeNFS/paperless/{media,consume}` needs to exist on the Synology before the first reconcile. If the operator wants different paths (e.g. nested under an existing structure), update the HelmRelease values accordingly. **Default:** create the two new subdirectories as proposed.
- **Initial admin user** — bootstrap via env vars (`PAPERLESS_ADMIN_USER`, `PAPERLESS_ADMIN_PASSWORD`, `PAPERLESS_ADMIN_MAIL`) or via `manage.py createsuperuser` in a pod exec after first deploy? **Default:** env-var path, with `SECRET_PAPERLESS_ADMIN_PASS` added to `cluster-secrets`. Cleaner for re-deploys.
- **OCR languages** — default is English (`PAPERLESS_OCR_LANGUAGE: eng`). If non-English documents are expected, add e.g. `ron+eng`. **Default:** `eng` only; operator changes the env var later if needed.
- **Renovate auto-merge for Paperless** — Paperless does fairly aggressive migrations between minors. Worth leaving auto-merge OFF (matches current cluster-wide setting in [`.github/renovate/autoMerge.json`](../../../.github/renovate/autoMerge.json)) and reviewing each chart bump. **Default:** inherit existing behaviour (auto-merge disabled).
