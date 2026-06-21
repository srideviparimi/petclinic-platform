# Rollback Runbook

**Last Updated:** 2026-06-21
**Purpose:** Step-by-step procedures for rolling back a bad deployment across all three recovery paths: GitOps revert (preferred), ArgoCD UI rollback, and emergency kubectl rollout undo.

**Related:** PETPLAT-54, [ADR-0008 (ArgoCD GitOps)](./technical-spec.md#adr-index), [CI/CD Pipeline spec](./technical-spec.md#cicd-pipeline)

---

## Table of Contents

1. [When to Roll Back](#1-when-to-roll-back)
2. [Rollback Decision Tree](#2-rollback-decision-tree)
3. [Method 1 — GitOps Revert (Preferred)](#3-method-1--gitops-revert-preferred)
4. [Method 2 — ArgoCD UI/CLI Rollback](#4-method-2--argocd-uicli-rollback)
5. [Method 3 — Emergency kubectl rollout undo](#5-method-3--emergency-kubectl-rollout-undo)
6. [Verifying Recovery](#6-verifying-recovery)
7. [Post-Rollback Actions](#7-post-rollback-actions)

---

## 1. When to Roll Back

Roll back when a deployment causes any of the following:

- Pods crash-looping or stuck in `CrashLoopBackOff`
- Health probes failing (`kubectl get pods` shows `0/1 Running` for more than 3 minutes)
- 5xx error rate spike in Grafana (alert: HighErrorRate)
- Service missing from Eureka registry (`http://discovery-server:8761/eureka/apps`)
- RDS-backed service cannot connect to the database

Do **not** roll back for:
- Slow startup (Spring Boot can take 60–90 s on t4g.small — wait for startup probe to pass)
- Single pod restart (autorestart is normal; investigate if restarts exceed 3 in 15 min)

---

## 2. Rollback Decision Tree

```
Is ArgoCD accessible?
├── Yes → Is the bad commit identifiable in Git?
│         ├── Yes → Use Method 1 (GitOps Revert) — maintains Git as source of truth
│         └── No  → Use Method 2 (ArgoCD UI rollback to previous sync)
└── No  → Use Method 3 (kubectl rollout undo — emergency only)
```

---

## 3. Method 1 — GitOps Revert (Preferred)

**When:** Bad image tag was committed to `helm-values/{service}.yaml` by CI and ArgoCD auto-synced it.
**Who:** On-call engineer with write access to petclinic-platform repo.
**Time:** 3–5 minutes.

**Steps:**

1. Identify the bad commit in the platform repo:
   ```bash
   git log --oneline helm-values/{service}.yaml
   # Example output:
   # a1b2c3d ci: update image tags to a1b2c3d (customers-service)
   # e4f5g6h ci: update image tags to e4f5g6h (customers-service)
   ```

2. Revert the bad commit:
   ```bash
   git revert <bad-commit-sha> --no-edit
   git push origin main
   ```

3. ArgoCD (dev) detects the push and auto-syncs within ~30 seconds. For prod, trigger a manual sync:
   ```bash
   argocd app sync {service}-prod
   ```

**Verify:**
- `kubectl get pods -n petclinic-{env}` — pod for the service transitions to `1/1 Running`
- Check image tag reverted: `kubectl describe pod -n petclinic-{env} -l app.kubernetes.io/name={service} | grep Image:`

**Why preferred:** The revert commit preserves the audit trail in Git. ArgoCD state matches Git state — no drift.

---

## 4. Method 2 — ArgoCD UI/CLI Rollback

**When:** Bad image tag is running and GitOps revert is not immediately available, or you need to recover faster than a Git push + ArgoCD sync.
**Who:** On-call engineer with ArgoCD access.
**Time:** 1–2 minutes.

**Steps:**

1. Access ArgoCD:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8443:443
   # Open https://localhost:8443 in browser
   ```
   Or use the CLI:
   ```bash
   argocd login localhost:8443 --username admin --insecure
   ```

2. List available history for the application:
   ```bash
   argocd app history {service}-{env}
   # Example:
   # ID  DATE                           REVISION
   # 3   2026-06-21 22:30:00 +0000 UTC  main (a1b2c3d)   ← bad
   # 2   2026-06-20 18:15:00 +0000 UTC  main (e4f5g6h)   ← good
   ```

3. Roll back to the last known-good sync:
   ```bash
   argocd app rollback {service}-{env} <history-id>
   # Example: argocd app rollback customers-service-dev 2
   ```

   **Via UI:** Open the Application → History and Rollback → select the good revision → Rollback.

**Verify:**
- ArgoCD app status transitions from `OutOfSync` → `Synced`
- `kubectl rollout status deployment/{service} -n petclinic-{env}`

**Important:** After an ArgoCD rollback, Git still has the bad commit. Follow up with a GitOps revert (Method 1) so Git and cluster are back in sync — otherwise the next ArgoCD auto-sync will re-deploy the bad image.

---

## 5. Method 3 — Emergency kubectl rollout undo

**When:** ArgoCD is unavailable and the service is down. Last resort only.
**Who:** On-call engineer with `kubectl` access to the cluster.
**Time:** 1–2 minutes.

**Steps:**

1. Update kubeconfig if not already done:
   ```bash
   aws eks update-kubeconfig --name petclinic-dev --region eu-central-1
   ```

2. Check rollout history:
   ```bash
   kubectl rollout history deployment/{service} -n petclinic-{env}
   # REVISION  CHANGE-CAUSE
   # 1         <none>
   # 2         <none>   ← current (bad)
   ```

3. Roll back to the previous revision:
   ```bash
   kubectl rollout undo deployment/{service} -n petclinic-{env}
   ```

   To roll back to a specific revision:
   ```bash
   kubectl rollout undo deployment/{service} -n petclinic-{env} --to-revision=1
   ```

**Verify:**
- `kubectl rollout status deployment/{service} -n petclinic-{env}`
- `kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service}`

**Critical follow-up:** `kubectl rollout undo` creates drift between the cluster state and Git. ArgoCD will detect OutOfSync and may re-apply the bad image on the next sync. You **must** immediately:
1. Revert the bad helm-values commit (Method 1) so Git reflects the good state.
2. Or disable ArgoCD auto-sync for the affected application until Git is fixed:
   ```bash
   argocd app set {service}-dev --sync-policy none
   ```

---

## 6. Verifying Recovery

Run these checks after any rollback to confirm the service is healthy:

```bash
# 1. Pod is running and ready
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service}

# 2. Correct image tag is running (should show the good SHA)
kubectl describe pod -n petclinic-{env} -l app.kubernetes.io/name={service} | grep "Image:"

# 3. Health endpoint responds
kubectl exec -n petclinic-{env} deploy/{service} -- \
  wget -qO- http://localhost:{port}/actuator/health

# 4. Service is registered with Eureka (for domain services)
kubectl exec -n petclinic-{env} deploy/discovery-server -- \
  wget -qO- http://localhost:8761/eureka/apps/{SERVICE-NAME-UPPERCASE}
```

For the full smoke test across all 8 services, run:
```bash
bash scripts/smoke-test.sh petclinic-{env}
```

---

## 7. Post-Rollback Actions

Complete these steps after every rollback:

1. **Fix Git state** — if Method 2 or 3 was used, ensure `helm-values/{service}.yaml` reflects the good image tag and commit it to `main`.

2. **Re-enable ArgoCD sync** — if auto-sync was disabled:
   ```bash
   argocd app set {service}-{env} --sync-policy automated
   ```

3. **File an incident** — document the bad SHA, which service was affected, detection time, and recovery time.

4. **Investigate the bad image** — check ECR scan results and build logs:
   ```bash
   aws ecr describe-image-scan-findings \
     --repository-name petclinic-dev/{service} \
     --image-id imageTag={bad-sha} \
     --region eu-central-1
   ```

5. **Fix the root cause** in the application code and push a new commit to the app repo. The CI pipeline (build-push.yml) will build a new image and fire a `repository_dispatch` to update the platform repo with the fixed tag.
