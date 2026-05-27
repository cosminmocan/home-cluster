## Context

The Homepage dashboard has been the front door to `home.${SECRET_DOMAIN}` since the cluster's first day, but the value-to-overhead ratio has eroded:

- The `homepage` ConfigMap is hand-maintained and duplicates information already encoded in per-app `gethomepage.dev/*` annotations. The two sources drift.
- The pod has a non-trivial memory floor (`248Mi` request, `2Gi` limit) for what is functionally a static index page.
- Every new app needs three annotations on its Ingress *plus* a separate entry in `homepage/config.yaml` for widgets. That coupling crosses the boundary between an app's own spec and a dashboard's spec.

The user has decided to retire it without replacement. This design focuses on getting the removal clean — the moving parts are not many, but a few of them touch DNS and shared cluster artefacts (the `default` namespace, the `chart-homepage` HelmRepository).

## Goals / Non-Goals

**Goals**

- Delete Homepage and every artefact unique to it from the repo and the cluster.
- Bring spec / manifest annotations back into sync after removal — no orphan `gethomepage.dev/*` tags floating in Ingresses.
- Free the host `home.${SECRET_DOMAIN}` for future reuse.
- Keep the change cleanly revertable from git — restoring the deleted files plus the spec deltas would bring Homepage back exactly as it was.

**Non-Goals**

- Provisioning a replacement dashboard (none requested).
- Setting up a redirect from `home.${SECRET_DOMAIN}` to another host.
- Removing `${PROWLARR_SECRET_KEY}` or `${RADARR_SECRET_KEY}` from `cluster-secrets` — these are still consumed by the apps themselves.
- Tearing down the shared Traefik / k8s-gateway / external-dns / Authentik plumbing.
- Removing the `chart-homepage` `HelmRepository` from `cluster/charts/` (kept so a future reintroduction is one commit away).

## Decisions

### Delete the whole `cluster/apps/default/` directory rather than the `homepage/` subdir alone

The `default` category contains nothing but Homepage today. Leaving an empty `default/` directory with just `namespace.yaml` adds a directory Flux must keep traversing for no payoff, and leaves the `goldilocks.fairwinds.com/enabled` opt-in unset on a namespace nobody uses. Deleting the whole category is one filesystem operation and is cleanly reverted via `git revert` if needed.

The built-in Kubernetes `default` namespace is unaffected — Kubernetes refuses to delete it. The `kustomize.toolkit.fluxcd.io/prune: disabled` label currently applied to the namespace by [`cluster/apps/default/namespace.yaml:5-7`](../../../cluster/apps/default/namespace.yaml#L5-L7) is silently removed when the manifest is deleted; that does not put the namespace at risk because no other Flux Kustomization manages it.

Alternative considered: keep `default/namespace.yaml` for the `prune: disabled` and `goldilocks.fairwinds.com/enabled` labels in case future apps land in `default`. Rejected — speculative; the labels can be re-added when (if) a new app lands.

### Trust Flux's pruning for the in-cluster cleanup

The `apps` Flux Kustomization at [`cluster/flux/apps.yaml:9`](../../../cluster/flux/apps.yaml#L9) has `prune: true`. Once the manifests disappear from the path under `./cluster/apps`, the next 10-minute reconcile drops:

- `HelmRelease` `homepage` (which then triggers helm-controller to uninstall the chart and remove its `Deployment`, `Service`, `ServiceAccount`, `Role`, and `RoleBinding`)
- `ConfigMap` `homepage`
- `Ingress` `homepage`
- `Namespace` `default` is attempted but Kubernetes refuses; Flux logs a benign error and moves on

external-dns observes the deleted Ingress within its `interval: 2m` (per [`cluster/core/networking/external-dns/release.yaml:32`](../../../cluster/core/networking/external-dns/release.yaml#L32)) and drops the public Cloudflare record because its policy is `sync`. k8s-gateway watches Ingresses too and stops resolving `home.${SECRET_DOMAIN}` the moment the Ingress is gone.

Alternative considered: explicitly `kubectl delete` the Homepage resources before the merge. Rejected — Flux's own teardown is what we want to validate, and racing the controllers is more error-prone than just waiting one reconcile cycle.

### Strip the orphan annotations in the same change

The `gethomepage.dev/*` annotations are cosmetic once Homepage is gone — Kubernetes doesn't care, nothing reads them. They could be left. But leaving them lets the manifests drift from the specs (which no longer require Homepage integration) and quietly invites the next person to assume Homepage is still running.

Touching twelve files is mechanical and reversible. Doing it in the same change keeps the post-archive cluster consistent with the post-archive specs.

### Order of operations: in-cluster cleanup follows merge, not the other way around

Because all the cleanup is Flux-driven, there's nothing to do in the cluster ahead of the merge. The single observable step is "merge, watch Discord for `homepage` HelmRelease finalised + DNS record dropped".

## Risks / Trade-offs

- **Risk: open browser sessions on `home.${SECRET_DOMAIN}` get 404 / NXDOMAIN with no warning.** → Mitigation: the host is essentially the user's own bookmark; one-line heads-up in the commit message is enough.
- **Risk: Renovate has an open PR for the `homepage` chart at merge time.** → Mitigation: Renovate gracefully drops PRs whose target files no longer exist; the PR can be closed manually if it doesn't auto-close.
- **Risk: leaving the `chart-homepage` `HelmRepository` creates an unused Flux source.** → Trade-off accepted: it's a few KB of memory in source-controller, and keeping it makes a "bring Homepage back" change a 5-minute revert instead of a re-init.
- **Risk: another change has a half-merged Homepage tile addition.** → Mitigation: checking `git log` is part of the apply step (see `tasks.md`).
- **Trade-off: stripping annotations from twelve files is noisy in the diff.** → Accepted: keeping spec and manifest in lockstep is worth a 24-line diff.

## Migration Plan

There is no schema migration, no data migration, and no user-visible flow change other than the host disappearing. The migration step is purely "stop visiting `home.${SECRET_DOMAIN}`; use the per-app subdomain bookmarks instead." A note can be added to the README or omitted — `home.` is not documented anywhere except in the (also-being-modified) `homepage/spec.md`.

**Rollback** — if removing Homepage turns out to be the wrong call, `git revert <merge-sha>` brings back every deleted file, restores the twelve sets of annotations, and Flux re-creates the HelmRelease, ConfigMap, Ingress, and Cloudflare DNS record on the next reconcile. Total recovery is bounded by Flux's `interval: 10m` for the `apps` Kustomization.

## Open Questions

- Should the change also remove the `chart-homepage` `HelmRepository` from [`cluster/charts/`](../../../cluster/charts/)? **Default**: no — it's effectively free and keeps the reversal trivial. Flip if the user wants a stricter cleanup.
- Should a Traefik `IngressRoute` be left behind to redirect `home.${SECRET_DOMAIN}` → e.g. `jellyseerr.${SECRET_DOMAIN}` for bookmark survivors? **Default**: no, per the proposal's "no replacement" stance. Trivial follow-up if desired.
