# GitOps (Argo CD)

Argo CD **`Application`** manifests and **Kustomize** bases live here. Jenkins **CI** updates `deploy/helm/demo-app/values-argocd.yaml` and related files, then **git push**; Argo reconciles from Git.

## Layout

| Path | Purpose |
|------|---------|
| [`applications/demo-app-application.yaml`](applications/demo-app-application.yaml) | `Application` **image-captioning** → Helm chart [`../helm/demo-app`](../helm/demo-app) |
| [`applications/grafana-ingress-application.yaml`](applications/grafana-ingress-application.yaml) | `Application` → Kustomize [`manifests/grafana`](manifests/grafana) |
| [`applications/argocd-ingress-application.yaml`](applications/argocd-ingress-application.yaml) | `Application` → Kustomize [`manifests/argocd-ingress`](manifests/argocd-ingress) — **https://argocd.minhhuy.me** (same ALB group `image-caption`) |

## Order of work

1. Set **`repoURL`** / **`targetRevision`** in `applications/*.yaml` for your Git remote and **branch** (repo defaults to `feature/test` in this workspace — change to `main` after merge if needed).
2. Jenkins credentials: `aws-creds-id`, `gitops-git-pat` (HTTPS `origin`).
3. After EKS is up: run **`infrastructure/scripts/`** `02` → `05`, then **`09-install-argocd.sh`** (installs Argo with **`server.insecure=true`** for ALB TLS offload).
4. Register: `kubectl apply -f deploy/argocd/applications/` (includes **argocd-ingress** for **https://argocd.minhhuy.me**).
5. Green **`app-ci-pipeline`** (`update-gitops` stage) fills ACM on ingress manifests → Argo sync succeeds.

## First sync

```bash
kubectl apply -f deploy/argocd/applications/
```

## Placeholders

- [`../helm/demo-app/values-argocd.yaml`](../helm/demo-app/values-argocd.yaml): `__...__` replaced by [`ci/jenkins/stages/build_sw/update-gitops.yaml`](../../ci/jenkins/stages/build_sw/update-gitops.yaml).
- [`manifests/grafana/ingress.yaml`](manifests/grafana/ingress.yaml): `__ACM_CERTIFICATE_ARN__`.
- [`manifests/argocd-ingress/ingress.yaml`](manifests/argocd-ingress/ingress.yaml): `__ACM_CERTIFICATE_ARN__` (Argo CD UI at **argocd.minhhuy.me**).

Private Git: register read-only repo creds in Argo (not in this MVP).
