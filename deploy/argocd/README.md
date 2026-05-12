# GitOps (Argo CD)

This directory holds **Argo CD `Application`** manifests and **Kustomize** manifests that Argo syncs to the cluster. **Jenkins does not run `helm upgrade` for the app** in the default pipeline; it updates `deploy/charts/demo-app/values-argocd.yaml` and pushes to Git; Argo CD reconciles.

## Order of work (repo first, AWS last)

Do these **before** or **without** a live cluster:

1. Fork or clone: set **`repoURL`** / **`targetRevision`** in [`applications/demo-app-application.yaml`](applications/demo-app-application.yaml) and [`applications/grafana-ingress-application.yaml`](applications/grafana-ingress-application.yaml) to **your** Git remote (Argo pulls from Git, not your laptop).
2. Jenkins: create credentials **`aws-creds-id`**, **`gitops-git-pat`** (see main README). App job `STAGE=all` needs a reachable `origin` over **HTTPS** for `git push`.

**After** EKS exists and `kubectl get nodes` works:

3. Cluster add-ons from repo scripts: [`../../scripts/02-configure-kubectl.sh`](../../scripts/02-configure-kubectl.sh) → [`../../scripts/03-install-alb.sh`](../../scripts/03-install-alb.sh) → [`../../scripts/04-deploy-services.sh`](../../scripts/04-deploy-services.sh) → [`../../scripts/05-verify.sh`](../../scripts/05-verify.sh).
4. Models: [`../../scripts/08-upload-models.sh`](../../scripts/08-upload-models.sh) (needs bucket from Terraform).
5. Argo CD: [`../../scripts/09-install-argocd.sh`](../../scripts/09-install-argocd.sh) (fails fast if the API server is unreachable — e.g. right after `terraform destroy`).
6. Register apps: `kubectl apply -f deploy/gitops/applications/`
7. First **green** App pipeline **`gitops`** stage commits real image tags / ACM placeholder → then Argo sync should go green.

## Layout

| Path | Purpose |
|------|---------|
| [`applications/demo-app-application.yaml`](applications/demo-app-application.yaml) | `Application` for Helm chart [`../../deploy/charts/demo-app`](../../deploy/charts/demo-app) (`values.yaml` + `values-argocd.yaml`) |
| [`applications/grafana-ingress-application.yaml`](applications/grafana-ingress-application.yaml) | `Application` for Grafana ALB ingress (Kustomize) |
| [`manifests/grafana/`](manifests/grafana/) | Kustomize base for Grafana `Ingress` (ACM ARN placeholders replaced by CI) |

## Private Git repository

If the Git repo is **private**, register read-only credentials in Argo CD (UI, `argocd repo add`, or `SealedSecret`) — not included in this MVP.

## First sync

```bash
kubectl apply -f deploy/gitops/applications/
```

Open Argo CD UI and sync `demo-app` and `grafana-ingress`, or rely on `syncPolicy.automated` in the sample manifests.

## Placeholders

- [`../../deploy/charts/demo-app/values-argocd.yaml`](../../deploy/charts/demo-app/values-argocd.yaml) uses `__...__` placeholders; Jenkins `gitops` stage replaces them from Terraform outputs + `BUILD_NUMBER`.
- [`manifests/grafana/ingress.yaml`](manifests/grafana/ingress.yaml) uses `__ACM_CERTIFICATE_ARN__` for the same reason.

Until the first successful **gitops** Jenkins run commits real values, Argo may show sync errors for Helm — that is expected.
