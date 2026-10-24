# nothingeats-gitops

Flux configuration for every [NothingEats](https://github.com/slashncode/nothingeats) cluster. Whatever is on `main` runs in the cluster.

## Layout

```
clusters/local/            Flux entry point for the local k3d cluster (flux-system/ is written by bootstrap)
  infrastructure.yaml      infra-crds → infra-controllers → infra-configs
  apps.yaml                apps (after infra-configs)
infrastructure/
  crds/                    Gateway API CRDs v1.6.3 (standard channel), straight from kubernetes-sigs/gateway-api
  controllers/             Traefik (Gateway API), CloudNativePG operator, Mailpit
  configs/                 namespace nothingeats, Postgres cluster + per-service roles, routes for infra UIs
apps/
  base/sources/            the backend-service chart from GHCR, accepted only with a valid cosign signature
  base/<service>/          HelmRelease, Database, ImageRepository + ImagePolicy
  local/                   what runs locally, plus the ImageUpdateAutomation
```

Each stage waits for the previous one to be healthy, so CRDs exist before controllers and controllers before the resources that need them.

## Delivery

1. A service merges to `main`; its CI pushes `ghcr.io/slashncode/nothingeats-<service>:main-<sha>-<unix time>`, signed with cosign.
2. The service's `ImagePolicy` picks the newest tag by timestamp.
3. The `ImageUpdateAutomation` commits the tag into `apps/base/<service>/release.yaml` (setter marker `# {"$imagepolicy": ...}`).
4. Flux upgrades the HelmRelease: the migrate Job runs first, then the Deployment rolls.

## Secrets

Secrets are committed encrypted with [SOPS](https://github.com/getsops/sops) + age (`.sops.yaml`); only `data`/`stringData` are encrypted. Flux decrypts them with the key in `flux-system/sops-age`. CI rejects any `Secret` that is not encrypted.

```bash
sops apps/base/<service>/<name>.sops.yaml     # edit in place (needs SOPS_AGE_KEY_FILE)
```

## Adding a service

1. `infrastructure/configs/postgres.yaml`: add the role; `postgres-roles.sops.yaml`: add its credentials secret.
2. `apps/base/<service>/`: `release.yaml`, `database.yaml`, `image.yaml`, `kustomization.yaml` (copy `catalog-service`).
3. Add it to `apps/local/kustomization.yaml`.

## Local cluster

From the hub repo: `just up` (k3d cluster, SOPS key, Flux bootstrap), `just flux-status`.

| URL | What |
|---|---|
| http://nothingeats.localhost/api/catalog/... | catalog-service |
| http://mail.nothingeats.localhost | Mailpit |
| `localhost:15432` | Postgres (NodePort) |
| `localhost:11025` | Mailpit SMTP |

## Validation

`scripts/validate.sh` (also in CI): builds every kustomization, validates all objects with kubeconform against Kubernetes 1.36 and the CRD schemas, and checks that every secret is encrypted.

## License

MIT
