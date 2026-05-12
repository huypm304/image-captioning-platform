# GitOps (Argo CD)

Argo CD **`Application`** manifests and **Kustomize** bases live here. Jenkins **CI** updates `deploy/helm/demo-app/values-argocd.yaml` and related files, then **git push**; Argo reconciles from Git.

## Layout

| Path | Purpose |
|------|---------|
| [`applications/demo-app-application.yaml`](applications/demo-app-application.yaml) | `Application` → Helm chart [`../helm/demo-app`](../helm/demo-app) |
| [`applications/grafana-ingress-application.yaml`](applications/grafana-ingress-application.yaml) | `Application` → Kustomize [`manifests/grafana`](manifests/grafana) |

## Order of work

1. Set **`repoURL`** / **`targetRevision`** in `applications/*.yaml` for your Git remote.
2. Jenkins credentials: `aws-creds-id`, `gitops-git-pat` (HTTPS `origin`).
3. After EKS is up: run **`infrastructure/scripts/`** `02` → `05`, then `09-install-argocd.sh`.
4. Register: `kubectl apply -f deploy/argocd/applications/`
5. Green **`app-ci-pipeline`** (`update-gitops` stage) commits real image tags / ACM → Argo sync succeeds.

## First sync

```bash
kubectl apply -f deploy/argocd/applications/
```

## Placeholders

- [`../helm/demo-app/values-argocd.yaml`](../helm/demo-app/values-argocd.yaml): `__...__` replaced by [`ci/jenkins/stages/build_sw/update-gitops.yaml`](../../ci/jenkins/stages/build_sw/update-gitops.yaml).
- [`manifests/grafana/ingress.yaml`](manifests/grafana/ingress.yaml): `__ACM_CERTIFICATE_ARN__`.

Private Git: register read-only repo creds in Argo (not in this MVP).
