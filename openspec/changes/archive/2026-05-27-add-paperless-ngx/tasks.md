## 1. Out-of-cluster prerequisites

- [x] 1.1 ~~Create NFS share subdirectories on the Synology.~~ **Superseded.** The chart uses PVCs against the `nfs-client` StorageClass instead of inline NFS mounts, so `nfs-subdir-external-provisioner` will create the subdirectories under `${STORAGE_NAS_IP}:/volume1/kubeNFS/` automatically when the PVCs bind. See the Storage decision in [design.md](./design.md).

- [ ] 1.2 Pre-create the `paperless` database in PostgreSQL (Postgres does not auto-create on first connect):

  ```sh
  eval "$(direnv export zsh 2>/dev/null)" && \
    kubectl exec -n database postgresql-0 -- \
      env PGPASSWORD="$(kubectl get secret cluster-secrets -n flux-system \
                          -o jsonpath='{.data.SECRET_POSTGRES_ADMIN_PASS}' | base64 -d)" \
      psql -U postgres -d postgres \
      -c "CREATE DATABASE paperless WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE template0;"
  ```

  Verify with:

  ```sh
  eval "$(direnv export zsh 2>/dev/null)" && \
    kubectl exec -n database postgresql-0 -- \
      env PGPASSWORD="$(kubectl get secret cluster-secrets -n flux-system \
                          -o jsonpath='{.data.SECRET_POSTGRES_ADMIN_PASS}' | base64 -d)" \
      psql -U postgres -d postgres -c '\l' | grep paperless
  ```

## 2. Secrets

- [ ] 2.1 Generate a Django `SECRET_KEY` (≥ 50 random characters):

  ```sh
  openssl rand -base64 60 | head -c 60
  ```

- [ ] 2.2 Generate an admin password (≥ 16 random characters):

  ```sh
  openssl rand -base64 24 | tr -d '/+=' | head -c 24
  ```

- [ ] 2.3 Add `SECRET_PAPERLESS_KEY` and `SECRET_PAPERLESS_ADMIN_PASS` to [`cluster/config/cluster-secrets.sops.yaml`](../../../cluster/config/cluster-secrets.sops.yaml):

  ```sh
  sops cluster/config/cluster-secrets.sops.yaml
  # add under stringData:
  #   SECRET_PAPERLESS_KEY: <value from 2.1>
  #   SECRET_PAPERLESS_ADMIN_PASS: <value from 2.2>
  ```

## 3. Chart source

- [ ] 3.1 Add a new HelmRepository in [`cluster/charts/chart-gabe565.yaml`](../../../cluster/charts/chart-gabe565.yaml):

  ```yaml
  ---
  apiVersion: source.toolkit.fluxcd.io/v1
  kind: HelmRepository
  metadata:
    name: chart-gabe565
    namespace: flux-system
  spec:
    interval: 1h
    url: https://charts.gabe565.com
  ```

## 4. Workload manifests

- [ ] 4.1 Create [`cluster/apps/media/paperless-ngx/kustomization.yaml`](../../../cluster/apps/media/paperless-ngx/kustomization.yaml):

  ```yaml
  ---
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  resources:
    - release.yaml
  ```

- [ ] 4.2 **No standalone `pvc.yaml`** — the chart creates all four PVCs from `persistence.{data,media,consume,export}` directly. Skip.

- [ ] 4.3 Create [`cluster/apps/media/paperless-ngx/release.yaml`](../../../cluster/apps/media/paperless-ngx/release.yaml). Skeleton (verify the chart's value schema against `https://charts.gabe565.com` and adjust):

  ```yaml
  ---
  apiVersion: helm.toolkit.fluxcd.io/v2
  kind: HelmRelease
  metadata:
    name: paperless-ngx
    namespace: media
  spec:
    interval: 15m
    chart:
      spec:
        chart: paperless-ngx
        version: <latest from chart index>
        sourceRef:
          kind: HelmRepository
          name: chart-gabe565
          namespace: flux-system
    maxHistory: 3
    install:
      remediation:
        retries: 3
    upgrade:
      cleanupOnFail: true
      remediation:
        strategy: rollback
        retries: 3
    uninstall:
      keepHistory: false
    dependsOn:
      - name: postgresql
        namespace: database
      - name: redis
        namespace: database
      - name: longhorn
        namespace: longhorn-system
    values:
      image:
        tag: 2.14.7  # Renovate-managed; matches chart 0.24.1 appVersion
      env:
        TZ: ${TIMEZONE}
        PAPERLESS_URL: "https://docs.${SECRET_DOMAIN}"
        PAPERLESS_SECRET_KEY: "${SECRET_PAPERLESS_KEY}"
        PAPERLESS_DBHOST: "${POSTGRES_HOST_ADDRESS}"
        PAPERLESS_DBPORT: "5432"
        PAPERLESS_DBNAME: paperless
        PAPERLESS_DBUSER: postgres
        PAPERLESS_DBPASS: "${SECRET_POSTGRES_ADMIN_PASS}"
        PAPERLESS_REDIS: "redis://${REDIS_HOST_ADDRESS}:6379"
        PAPERLESS_OCR_LANGUAGE: eng
        PAPERLESS_ADMIN_USER: admin
        PAPERLESS_ADMIN_PASSWORD: "${SECRET_PAPERLESS_ADMIN_PASS}"
        PAPERLESS_ADMIN_MAIL: "admin@${SECRET_DOMAIN}"
      # Disable bundled subcharts — the cluster's shared services are used instead
      postgresql:
        enabled: false
      redis:
        enabled: false
      ingress:
        main:
          enabled: true
          ingressClassName: traefik
          hosts:
            - host: &host "docs.${SECRET_DOMAIN}"
              paths:
                - path: /
                  pathType: Prefix
          tls:
            - hosts: [*host]
      persistence:
        data:
          enabled: true
          storageClass: longhorn
          accessMode: ReadWriteOnce
          size: 5Gi
        media:
          enabled: true
          storageClass: nfs-client
          accessMode: ReadWriteOnce
          size: 50Gi
        consume:
          enabled: true
          storageClass: nfs-client
          accessMode: ReadWriteOnce
          size: 5Gi
        export:
          enabled: true
          storageClass: longhorn
          accessMode: ReadWriteOnce
          size: 1Gi
      resources:
        requests:
          cpu: 50m
          memory: 400Mi
        limits:
          memory: 1Gi
  ```

## 5. Wire into the category

- [ ] 5.1 Append `paperless-ngx` to [`cluster/apps/media/kustomization.yaml`](../../../cluster/apps/media/kustomization.yaml):

  ```yaml
  resources:
    - namespace.yaml
    - qbittorrent
    - prowlarr
    - jellyseerr
    - radarr
    - jellyfin
    - flaresolverr
    - homeassistant
    - drive
    - photos
    - music
    - paperless-ngx
  ```

## 6. Lint and commit

- [ ] 6.1 Run pre-commit on the staged files:

  ```sh
  pre-commit run --files $(git diff --cached --name-only | tr '\n' ' ')
  ```

- [ ] 6.2 Confirm no plaintext secrets — `kingfisher` and `forbid-secrets` hooks must pass.
- [ ] 6.3 Stage and commit:

  ```sh
  git add -A cluster/ openspec/changes/add-paperless-ngx
  git commit -m "Add Paperless-ngx at docs.\${SECRET_DOMAIN}"
  ```

- [ ] 6.4 Push to `main`:

  ```sh
  git push origin main
  ```

## 7. In-cluster verification

- [ ] 7.1 Force a Flux reconcile to pick up the new chart source and HelmRelease:

  ```sh
  eval "$(direnv export zsh 2>/dev/null)" && \
    flux reconcile source helm chart-gabe565 -n flux-system && \
    flux reconcile kustomization apps -n flux-system --with-source
  ```

- [ ] 7.2 Watch the HelmRelease come up:

  ```sh
  eval "$(direnv export zsh 2>/dev/null)" && \
    kubectl -n media get helmrelease paperless-ngx -w
  ```

  Expect: `Ready: True`, `Status: Helm install succeeded`.

- [ ] 7.3 Verify the pods are running (web + scheduler/consumer + Tika + Gotenberg):

  ```sh
  eval "$(direnv export zsh 2>/dev/null)" && \
    kubectl -n media get pods -l 'app.kubernetes.io/name in (paperless-ngx,tika,gotenberg)'
  ```

- [ ] 7.4 Verify Paperless connected to Postgres (look for "Migrations applied"):

  ```sh
  eval "$(direnv export zsh 2>/dev/null)" && \
    kubectl -n media logs deploy/paperless-ngx --tail=200 | grep -iE 'migration|database'
  ```

- [ ] 7.5 Verify LAN DNS resolves to the ingress IP:

  ```sh
  eval "$(direnv export zsh 2>/dev/null)" && \
    dig "docs.$(kubectl get secret cluster-secrets -n flux-system \
                  -o jsonpath='{.data.SECRET_DOMAIN}' | base64 -d)" \
        @192.168.100.31 +short
  ```

  Expect: `192.168.100.30` (the `${NIGNX_INGRESS_IP}`).

- [ ] 7.6 Verify the public Cloudflare resolver does NOT have a record:

  ```sh
  dig "docs.$(kubectl get secret cluster-secrets -n flux-system \
                -o jsonpath='{.data.SECRET_DOMAIN}' | base64 -d)" @1.1.1.1 +short
  ```

  Expect: empty.

- [ ] 7.7 Open `https://docs.${SECRET_DOMAIN}` in a LAN browser. Log in as `admin` with the password from 2.2. Confirm the dashboard loads.

- [ ] 7.8 Drop a small test PDF into `/volume1/kubeNFS/paperless/consume` from the Synology web UI. Confirm Paperless picks it up within ~1 minute and the document appears in the UI with extracted text.

## 8. Archive the change

- [ ] 8.1 Once verified, archive:

  ```sh
  openspec archive add-paperless-ngx
  ```

  This moves `openspec/changes/add-paperless-ngx/` to `openspec/changes/archive/YYYY-MM-DD-add-paperless-ngx/` and seeds `openspec/specs/paperless-ngx/spec.md` from the delta.
