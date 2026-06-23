# Implementation Errors Log

This file records mistakes made during implementation, the root cause of each error, and the fix applied. Its purpose is to prevent recurrence and to document the gap between what was specified and what was initially built.

---

## E-11 Observability Epic

### ERR-001 — Prometheus only scraped 5 of 8 services (PETPLAT-55)

**Story:** PETPLAT-55
**File affected:** `k8s/base/observability/prometheus.yaml`

**What went wrong:**
The initial `prometheus.yaml` contained scrape configs for only 5 services:
`api-gateway`, `customers-service`, `visits-service`, `vets-service`, `genai-service`.

The acceptance criterion in PETPLAT-55 states: *"Scrape config targets all 8 services on /actuator/prometheus."* Three services were omitted: `config-server` (8888), `discovery-server` (8761), and `admin-server` (9090).

**Root cause:**
An enforcement rule applied during generation checked the application repo's `pom.xml` files and found that `config-server`, `discovery-server`, and `admin-server` do not have `micrometer-registry-prometheus` as a declared dependency. The rule said "DO NOT add these — they will return 404." This rule was followed over the story's own acceptance criterion.

**Fix applied:**
Added all 3 missing scrape targets to `prometheus-config` ConfigMap. Each gets its own job with the correct port.

**Known side-effect:**
Until `micrometer-registry-prometheus` is added to `config-server`, `discovery-server`, and `admin-server` pom.xml files, Prometheus will show those 3 targets in state `UNKNOWN / connection refused / 404`. This does not break Prometheus — it just means those targets show no metrics until the dependency is added to the application.

---

### ERR-002 — Grafana dashboards embedded in grafana.yaml instead of separate file/directory (PETPLAT-57)

**Story:** PETPLAT-57
**File affected:** `k8s/base/observability/grafana.yaml` (dashboards incorrectly embedded here)

**What went wrong:**
The `grafana-dashboards` ConfigMap (containing all dashboard JSON) was placed inside `grafana.yaml` alongside the Deployment, Service, Secret, and datasource ConfigMaps. This conflated PETPLAT-56 (Grafana installation) with PETPLAT-57 (per-service dashboards), which are separate stories with separate acceptance criteria.

The acceptance criterion in PETPLAT-57 states:
- *"Dashboards exported as JSON in `k8s/base/observability/grafana-dashboards/`"*
- *"Dashboards provisioned automatically via ConfigMap"*

**Root cause:**
Convenience — all Grafana-related resources were bundled into one file without checking which story owns the dashboard resources.

**Fix applied:**
1. Removed `grafana-dashboards` ConfigMap from `grafana.yaml`
2. Created `k8s/base/observability/grafana-dashboards/` directory with individual JSON files (one per dashboard)
3. Created `k8s/base/observability/grafana-dashboards.yaml` as the standalone ConfigMap for Kubernetes provisioning

---

### ERR-003 — Only 5 per-service Grafana dashboards; 3 services missing (PETPLAT-57)

**Story:** PETPLAT-57
**File affected:** `grafana-dashboards.yaml` (new file)

**What went wrong:**
Only dashboards for the 5 prometheus-instrumented services were created. `config-server`, `discovery-server`, and `admin-server` were excluded because they lack `micrometer-registry-prometheus`.

The acceptance criterion states: *"Dashboard per service"* — one per each of the 8 services.

**Root cause:**
Same incorrect application of the pom.xml enforcement rule as ERR-001. A dashboard should exist for each service even if metrics are not yet available — the dashboard acts as the intended state when the dependency is added.

**Fix applied:**
Added dashboards for `config-server`, `discovery-server`, and `admin-server`. These dashboards show the same panel structure (request rate, error rate, p95/p99 latency) but will display "No data" until the prometheus dependency is added to those services.

---

### ERR-004 — Loki prod retention (30 days / 720h) and prod PVC (50Gi) not addressed (PETPLAT-59)

**Story:** PETPLAT-59
**File affected:** `k8s/base/observability/loki.yaml`

**What went wrong:**
The `loki.yaml` was written with dev settings only: `retention_period: 168h` (7 days) and `PVC: 10Gi`. The acceptance criterion requires:
- *"PersistentVolume (10Gi dev, **50Gi prod**)"*
- *"Loki log retention configured (7 days dev, **30 days prod**)"*

No prod Loki configuration existed.

**Root cause:**
Misunderstanding of how dev/prod differences should be expressed for the observability stack. Assumption that `helm-values/dev.yaml` and `helm-values/prod.yaml` might be relevant (they are not — those files only configure the petclinic application Helm chart, not the observability stack).

**Clarification — where prod observability config belongs:**
The observability stack (Prometheus, Grafana, Loki, etc.) is installed with its own standalone Kubernetes manifests. It is **not** part of the petclinic Helm chart and is **not** controlled by `helm-values/dev.yaml` or `helm-values/prod.yaml`. Those files exclusively configure the 8 petclinic microservices.

For dev/prod differences in the observability stack, the options are:
- Separate Loki ConfigMaps per environment (current fix)
- Kustomize overlays at `k8s/overlays/{dev,prod}/`

**Fix applied:**
Created `k8s/base/observability/loki-prod.yaml` containing a prod-specific `loki-config-prod` ConfigMap (720h retention) and a `loki-pvc-prod` PVC (50Gi). This file is applied to the prod cluster instead of the dev `loki.yaml` PVC/ConfigMap.

---
