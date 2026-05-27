## 1. Pre-flight checks

- [x] 1.1 Verify no open PR is adding Homepage tiles or widgets:
  ```bash
  gh pr list --search "homepage in:title,body" --state open
  ```
- [x] 1.2 Verify no other manifest under `cluster/` references the `homepage` HelmRelease, ConfigMap, or Service:
  ```bash
  grep -RIn 'name: homepage' cluster/ | grep -v 'cluster/apps/default/homepage'
  grep -RIn 'homepage.default.svc' cluster/
  grep -RIn 'home\.\${SECRET_DOMAIN}' cluster/
  ```
  Expect: only references inside `cluster/apps/default/homepage/` and the spec/change directories.
- [x] 1.3 Confirm the `apps` Flux Kustomization still has `prune: true`:
  ```bash
  grep -n 'prune:' cluster/flux/apps.yaml
  ```

## 2. Delete the Homepage manifests

- [x] 2.1 Delete the whole category directory:
  ```bash
  rm -rf cluster/apps/default
  ```
  This removes `homepage/release.yaml`, `homepage/config.yaml`, `homepage/kustomization.yaml`, `namespace.yaml`, and the category `kustomization.yaml`.

## 3. Strip orphan annotations from the remaining apps

Each step removes the now-meaningless `gethomepage.dev/*` (and one `hajimari.io/*`) annotations.

- [x] 3.1 [`cluster/apps/media/qbittorrent/ingress.yaml`](../../../cluster/apps/media/qbittorrent/ingress.yaml) — remove the three `gethomepage.dev/*` annotations.
- [x] 3.2 [`cluster/apps/media/radarr/release.yaml`](../../../cluster/apps/media/radarr/release.yaml) — remove the three `gethomepage.dev/*` annotations from `service.app.annotations`.
- [x] 3.3 [`cluster/apps/media/prowlarr/release.yaml`](../../../cluster/apps/media/prowlarr/release.yaml) — remove the three `gethomepage.dev/*` annotations from `service.app.annotations`.
- [x] 3.4 [`cluster/apps/media/jellyseerr/release.yaml`](../../../cluster/apps/media/jellyseerr/release.yaml) — remove the three `gethomepage.dev/*` annotations from `ingress.jellyseerr.annotations`.
- [x] 3.5 [`cluster/apps/media/jellyfin/ingress.yaml`](../../../cluster/apps/media/jellyfin/ingress.yaml) — remove the three `gethomepage.dev/*` annotations.
- [x] 3.6 [`cluster/apps/media/music/ingress.yaml`](../../../cluster/apps/media/music/ingress.yaml) — remove the three `gethomepage.dev/*` annotations.
- [x] 3.7 [`cluster/apps/media/photos/ingress.yaml`](../../../cluster/apps/media/photos/ingress.yaml) — remove the three `gethomepage.dev/*` annotations.
- [x] 3.8 [`cluster/apps/media/drive/ingress.yaml`](../../../cluster/apps/media/drive/ingress.yaml) — remove the three `gethomepage.dev/*` annotations.
- [x] 3.9 [`cluster/apps/media/homeassistant/ingress.yaml`](../../../cluster/apps/media/homeassistant/ingress.yaml) — remove `gethomepage.dev/name` and the legacy `hajimari.io/icon` annotation.
- [x] 3.10 [`cluster/apps/database/pgadmin/release.yaml`](../../../cluster/apps/database/pgadmin/release.yaml) — remove the three `gethomepage.dev/*` annotations from `ingress.annotations`.
- [x] 3.11 [`cluster/apps/database/authentik/release.yaml`](../../../cluster/apps/database/authentik/release.yaml) — remove the three `gethomepage.dev/*` annotations from `server.ingress.annotations`. Keep `external-dns.alpha.kubernetes.io/target`.
- [x] 3.12 [`cluster/apps/monitoring/goldilocks/release.yaml`](../../../cluster/apps/monitoring/goldilocks/release.yaml) — remove the three `gethomepage.dev/*` annotations from `dashboard.ingress.annotations`.

## 4. Lint and commit

- [ ] 4.1 Run pre-commit hooks locally to catch yamllint / trailing-whitespace issues:
  ```bash
  pre-commit run --all-files
  ```
- [ ] 4.2 Stage and commit:
  ```bash
  git add -A cluster/apps openspec/changes/remove-homepage
  git status
  git commit -m "Retire Homepage dashboard and strip orphan annotations"
  ```
- [ ] 4.3 Push to `main` (or open a PR if branch protection requires one):
  ```bash
  git push origin main
  ```

## 5. Verify in-cluster cleanup

- [ ] 5.1 Watch Flux apply the change (Discord alerts should announce the `apps` Kustomization reconciling):
  ```bash
  eval "$(direnv export zsh 2>/dev/null)" && \
    flux reconcile kustomization apps -n flux-system --with-source
  ```
- [ ] 5.2 Confirm the HelmRelease, ConfigMap, and Ingress are gone:
  ```bash
  eval "$(direnv export zsh 2>/dev/null)" && \
    kubectl get helmrelease,configmap,ingress -n default | grep -i homepage
  ```
  Expect: no `homepage`-named resources.
- [ ] 5.3 Confirm `home.${SECRET_DOMAIN}` no longer resolves on the LAN:
  ```bash
  eval "$(direnv export zsh 2>/dev/null)" && \
    dig "home.$(kubectl get secret cluster-secrets -n flux-system -o jsonpath='{.data.SECRET_DOMAIN}' | base64 -d)" @192.168.100.31 +short
  ```
  Expect: empty output (NXDOMAIN).
- [ ] 5.4 Confirm external-dns dropped the public Cloudflare record:
  ```bash
  eval "$(direnv export zsh 2>/dev/null)" && \
    kubectl logs -n networking deploy/external-dns --tail=200 | grep -i 'home\.'
  ```
  Expect: a recent log line indicating the `home.*` record was deleted from Cloudflare.
- [ ] 5.5 Spot-check one of the apps whose annotations were stripped — its own Ingress should still resolve and respond:
  ```bash
  curl -sIk "https://radarr.$(kubectl get secret cluster-secrets -n flux-system -o jsonpath='{.data.SECRET_DOMAIN}' | base64 -d)/" | head -1
  ```
  Expect: `HTTP/2 200` or `HTTP/2 302` (Authentik redirect for protected apps).

## 6. Archive the change

- [ ] 6.1 With everything verified, archive the change so the base specs absorb the deltas:
  ```bash
  openspec archive remove-homepage
  ```
  This moves `openspec/changes/remove-homepage/` to `openspec/changes/archive/`, deletes `openspec/specs/homepage/`, and removes the "Homepage integration" requirement from each of the twelve modified app specs.

## 7. Optional follow-ups (out of scope for this change)

- [ ] 7.1 If a redirect for `home.${SECRET_DOMAIN}` is wanted, file a new change to add a Traefik `IngressRoute` returning `301` to a chosen replacement host.
- [ ] 7.2 If a stricter cleanup is wanted, file a new change to delete the `chart-homepage` `HelmRepository` from `cluster/charts/`.
