# Helm Chart Guide — Petclinic Platform

**Last Updated:** 2026-06-21
**Purpose:** Explains the generic Helm chart used for all 8 Spring Petclinic services — structure, values hierarchy, how to deploy manually, how to add a new service, and how it integrates with ArgoCD.

---

## Table of Contents

1. [Bootstrap — One-time Cluster Setup](#bootstrap--one-time-cluster-setup)
2. [Chart Structure](#chart-structure)
3. [Values Hierarchy](#values-hierarchy)
4. [Deploy a Service Manually](#deploy-a-service-manually)
5. [Change Resources, Replicas, or Env Vars](#change-resources-replicas-or-env-vars)
6. [Add a New Service](#add-a-new-service)
7. [ArgoCD Integration](#argocd-integration)
8. [Validate Rendered Output](#validate-rendered-output)

---

## Bootstrap — One-time Cluster Setup

The `helm/petclinic-bootstrap/` chart handles all prerequisites that must exist before any service chart is installed. It is idempotent — safe to re-run (`helm upgrade --install`).

**What it creates:**

| Resource | Type | Notes |
|----------|------|-------|
| `petclinic-dev`, `petclinic-prod` | Namespace | PSA labels: enforce=baseline, warn/audit=restricted |
| `aws-secrets-manager` | ClusterSecretStore | Points ESO at AWS Secrets Manager in eu-central-1 |
| `rds-credentials` | ExternalSecret | Syncs RDS username + password from `petclinic/{env}/rds-credentials` |
| `openai-api-key` | ExternalSecret | Optional — disabled by default (see below) |
| `wait-for-secrets` | Job (post-install hook) | Polls until K8s Secrets are synced; self-cleans on success |

### Step 1 — Install External Secrets Operator (ESO)

ESO must be installed before the bootstrap chart, as its CRDs (`ClusterSecretStore`, `ExternalSecret`) must be registered first.

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --wait --timeout 120s

# Verify ESO is running
kubectl get pods -n external-secrets
kubectl api-resources | grep external-secrets
```

### Step 2 — Run the bootstrap chart

```bash
helm upgrade --install petclinic-bootstrap helm/petclinic-bootstrap/ \
  --set environment=dev
```

Helm applies all resources (namespaces, ClusterSecretStore, ExternalSecrets), then the `wait-for-secrets` post-install Job runs automatically. The `helm install` command blocks until the Job completes — meaning ESO has successfully synced all required K8s Secrets.

**Watch the Job logs in another terminal:**

```bash
kubectl logs -n petclinic-dev job/wait-for-secrets -f
```

Expected output:
```
Bootstrap: waiting for ESO to sync secrets into petclinic-dev...
  Waiting for secret/rds-credentials...
  secret/rds-credentials is ready.
Bootstrap complete — all required secrets synced. Safe to install service charts.
```

### Step 3 — Verify

```bash
# Namespaces exist
kubectl get namespaces petclinic-dev petclinic-prod

# ClusterSecretStore is ready
kubectl get clustersecretstore aws-secrets-manager

# rds-credentials K8s Secret exists
kubectl get secret rds-credentials -n petclinic-dev

# Helm release shows deployed
helm list -A | grep bootstrap
```

### OpenAI API key (optional)

`openai-api-key` is disabled by default. The genai-service pod starts regardless — it falls back to `OPENAI_API_KEY=demo` when the secret is absent. To enable it once you have the key:

```bash
# 1. Store in Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id petclinic/dev/openai-api-key \
  --secret-string "sk-..."

# 2. Upgrade bootstrap to create the ExternalSecret
helm upgrade petclinic-bootstrap helm/petclinic-bootstrap/ \
  --set environment=dev \
  --set externalSecrets.openaiApiKey.enabled=true

# 3. Restart genai-service to pick up the new env var
kubectl rollout restart deployment/genai-service -n petclinic-dev
```

### Re-run for prod

```bash
helm upgrade --install petclinic-bootstrap-prod helm/petclinic-bootstrap/ \
  --set environment=prod
```

---

## Chart Structure

A single generic chart at `helm/petclinic-service/` is shared by all 8 services. Per-service differences are expressed entirely through values files.

```
helm/
└── petclinic-service/
    ├── Chart.yaml              # name: petclinic-service, version: 0.1.0
    ├── values.yaml             # Defaults — all services inherit these
    └── templates/
        ├── _helpers.tpl        # Label helpers (petclinic-service.labels, .selectorLabels)
        ├── deployment.yaml     # Deployment with probes, resources, env vars, initContainers
        ├── service.yaml        # ClusterIP Service
        ├── configmap.yaml      # Non-secret config (only rendered when configData is non-empty)
        ├── serviceaccount.yaml # ServiceAccount with optional IRSA annotation
        ├── hpa.yaml            # HorizontalPodAutoscaler (only when autoscaling.enabled: true)
        └── pdb.yaml            # PodDisruptionBudget (only when podDisruptionBudget.enabled: true)

helm-values/
├── config-server.yaml          # Per-service overrides
├── discovery-server.yaml
├── api-gateway.yaml
├── customers-service.yaml
├── visits-service.yaml
├── vets-service.yaml
├── genai-service.yaml
├── admin-server.yaml
├── dev.yaml                    # Environment overrides (replicas=1, no HPA/PDB)
└── prod.yaml                   # Environment overrides
```

### Template Behaviour

| Template | Always rendered | Conditional |
|----------|----------------|-------------|
| `serviceaccount.yaml` | Yes | — |
| `configmap.yaml` | No | Only when `.Values.configData` is non-empty |
| `service.yaml` | Yes | — |
| `deployment.yaml` | Yes | initContainers block only when `.Values.initContainers` is non-empty |
| `hpa.yaml` | No | Only when `.Values.autoscaling.enabled: true` |
| `pdb.yaml` | No | Only when `.Values.podDisruptionBudget.enabled: true` |

---

## Values Hierarchy

Helm merges values in order — later files take precedence over earlier ones.

```
values.yaml (chart defaults)
    ↓ merged with
helm-values/{service}.yaml (per-service overrides)
    ↓ merged with
helm-values/{env}.yaml (per-environment overrides — wins)
    ↓ optional --set flags (highest priority)
```

**Practical result:**

| Setting | Where to put it |
|---------|----------------|
| Default port, profiles, probes | `values.yaml` |
| Service port, Spring profiles, configData, init containers, HPA/PDB settings | `helm-values/{service}.yaml` |
| Replica count (prod default), secret refs, image repo | `helm-values/{service}.yaml` |
| Force replicas=1 (dev), disable HPA/PDB (dev) | `helm-values/dev.yaml` |
| prod.yaml overrides (image pull policy, etc.) | `helm-values/prod.yaml` |

**Key design decision:** Per-service files carry the **prod replica count** (e.g., `replicaCount: 2` for api-gateway). `dev.yaml` overrides this to `replicaCount: 1` for all services since it is merged last. This ensures dev always runs single replicas without requiring per-service-per-env files.

---

## Deploy a Service Manually

Use `helm upgrade --install` with two `-f` flags: service values first, environment values second.

```bash
# Deploy customers-service to dev
helm upgrade --install customers-service helm/petclinic-service/ \
  -n petclinic-dev \
  -f helm-values/customers-service.yaml \
  -f helm-values/dev.yaml \
  --set image.tag=${SHA}

# Deploy api-gateway to prod
helm upgrade --install api-gateway helm/petclinic-service/ \
  -n petclinic-prod \
  -f helm-values/api-gateway.yaml \
  -f helm-values/prod.yaml \
  --set image.tag=${SHA}

# Deploy all 8 services to dev (loop)
for svc in config-server discovery-server api-gateway customers-service \
           visits-service vets-service genai-service admin-server; do
  helm upgrade --install "${svc}" helm/petclinic-service/ \
    -n petclinic-dev \
    -f "helm-values/${svc}.yaml" \
    -f helm-values/dev.yaml \
    --set image.tag=${SHA}
done
```

> **Note:** In normal operation, ArgoCD handles all deployments. Manual `helm install` is for initial setup or emergency use. See [ArgoCD Integration](#argocd-integration).

### Verify the release

```bash
helm list -n petclinic-dev
helm status customers-service -n petclinic-dev
kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=customers-service
```

---

## Change Resources, Replicas, or Env Vars

### Change resource requests/limits for a specific service

Edit `helm-values/{service}.yaml`:

```yaml
# helm-values/api-gateway.yaml
resources:
  requests:
    cpu: 300m      # was 200m
    memory: 256Mi  # was 128Mi
  limits:
    cpu: 1500m
    memory: 768Mi
```

Commit and push. ArgoCD detects the change and syncs automatically (dev) or queues for manual approval (prod).

### Change replica count

For a service that needs different replicas in prod, update `helm-values/{service}.yaml`:

```yaml
replicaCount: 3   # prod default; dev.yaml overrides to 1
```

To change ALL services in dev, edit `helm-values/dev.yaml`:

```yaml
replicaCount: 1   # already set; this is the dev override
```

### Add or change an environment variable

If the variable is **non-secret** (URL, flag, config value), add it to `configData` in the per-service values file:

```yaml
# helm-values/customers-service.yaml
configData:
  CONFIG_SERVER_URL: "http://config-server:8888"
  SPRING_DATASOURCE_URL: "jdbc:mysql://..."
  MY_NEW_CONFIG: "some-value"    # ← add here
```

If the variable is **secret**, add a `secretEnv` entry pointing to a Kubernetes Secret (synced from AWS Secrets Manager via ESO):

```yaml
secretEnv:
  - envVar: MY_SECRET_VAR
    secretName: my-secret-name   # K8s Secret created by ExternalSecret CR
    secretKey: my-key
    optional: false
```

### Change Spring profiles

Edit `springProfiles` in the per-service values file:

```yaml
springProfiles: "docker,mysql,production"
```

---

## Add a New Service

Follow these steps to add a 9th service to the platform:

### 1. Create a per-service values file

```bash
cp helm-values/admin-server.yaml helm-values/new-service.yaml
```

Edit `helm-values/new-service.yaml` with the service-specific values:

```yaml
image:
  repository: "231351515075.dkr.ecr.eu-central-1.amazonaws.com/petclinic-dev/new-service"
  tag: "latest"

service:
  port: 8085           # service port

component: "service"   # server | service | gateway | admin
springProfiles: "docker"

replicaCount: 2        # prod default; dev.yaml overrides to 1

configData:
  CONFIG_SERVER_URL: "http://config-server:8888"
  EUREKA_CLIENT_SERVICEURL_DEFAULTZONE: "http://discovery-server:8761/eureka/"

initContainers:
  - name: wait-for-config-server
    image: busybox:1.36
    command:
      - sh
      - -c
      - "until wget -qO- http://config-server:8888/actuator/health; do sleep 5; done"
  - name: wait-for-discovery-server
    image: busybox:1.36
    command:
      - sh
      - -c
      - "until wget -qO- http://discovery-server:8761/actuator/health; do sleep 5; done"

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 4
  targetCPUUtilizationPercentage: 70

podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

### 2. Create an ECR repository

Add the service name to the ECR module in `terraform/environments/dev/main.tf` and `prod/main.tf`:

```hcl
module "ecr" {
  source = "../../modules/ecr"
  service_names = [
    "config-server", "discovery-server", "api-gateway",
    "customers-service", "visits-service", "vets-service",
    "genai-service", "admin-server",
    "new-service"     # ← add here
  ]
}
```

Run `terraform plan` and `terraform apply`.

### 3. Validate the Helm template

```bash
helm lint helm/petclinic-service/ \
  -f helm-values/new-service.yaml \
  -f helm-values/dev.yaml \
  --namespace petclinic-dev

helm template new-service helm/petclinic-service/ \
  -f helm-values/new-service.yaml \
  -f helm-values/dev.yaml \
  --namespace petclinic-dev
```

### 4. Create ArgoCD Application CRDs

Create `k8s/argocd/applications/dev/new-service.yaml` and `k8s/argocd/applications/prod/new-service.yaml` following the pattern in those directories.

### 5. Add to CI pipeline

Add the new service directory to the `dorny/paths-filter` configuration in `.github/workflows/build-push.yml` so CI builds its Docker image on changes.

---

## ArgoCD Integration

ArgoCD is the **only** mechanism that deploys to EKS in normal operation. GitHub Actions CI pushes images and commits updated image tags; ArgoCD detects the Git change and syncs the Helm release.

### How ArgoCD uses the Helm chart

Each service has an ArgoCD `Application` CRD in `k8s/argocd/applications/{env}/`:

```yaml
# k8s/argocd/applications/dev/customers-service.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: customers-service-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/{your-username}/petclinic-platform.git
    targetRevision: main
    path: helm/petclinic-service
    helm:
      valueFiles:
        - ../../helm-values/customers-service.yaml  # per-service (first)
        - ../../helm-values/dev.yaml                # per-env (last, wins)
  destination:
    server: https://kubernetes.default.svc
    namespace: petclinic-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

For prod, the `automated` block is removed — sync requires manual approval in the ArgoCD UI or CLI.

### GitOps deployment flow

```
Developer pushes code to app repo
  → GitHub Actions (build-push.yml): builds ARM64 image, pushes to ECR
    → GitHub Actions (update-image-tags.yml): updates image.tag in helm-values/{service}.yaml, commits
      → ArgoCD detects the commit
        → Dev: auto-syncs immediately (new image running in ~2 min)
        → Prod: shows OutOfSync, waits for: argocd app sync {service}-prod
```

### Sync policy by environment

| Environment | Auto-sync | Prune | Self-heal | Manual approval |
|-------------|-----------|-------|-----------|-----------------|
| Dev | Yes | Yes | Yes | No |
| Prod | No | No | No | Yes (ArgoCD UI/CLI) |

### Manual sync commands

```bash
# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8443:443

# Sync a specific prod service
argocd app sync customers-service-prod

# Sync all prod services
argocd app sync -l app.kubernetes.io/part-of=petclinic --selector environment=prod

# Check sync status
argocd app list
argocd app get customers-service-prod
```

---

## Validate Rendered Output

Use the validation script to run `helm lint` and `helm template` across all 16 combinations (8 services × 2 environments):

```bash
# Validate all services against both environments
bash scripts/validate-helm.sh

# Validate a single service against dev only
bash scripts/validate-helm.sh customers-service dev

# Validate all services against prod only
bash scripts/validate-helm.sh all prod
```

When connected to EKS, the script also runs `kubectl apply --dry-run=client` on the rendered output:

```bash
aws eks update-kubeconfig --name petclinic-dev --region eu-central-1
bash scripts/validate-helm.sh
```

### Render and inspect a specific service manually

```bash
helm template customers-service helm/petclinic-service/ \
  -f helm-values/customers-service.yaml \
  -f helm-values/prod.yaml \
  --namespace petclinic-prod
```
