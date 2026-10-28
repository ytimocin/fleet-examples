# Cross-Fleet Orchestration: Feature Spec & Examples

## Overview

Kargo can orchestrate promotions across multiple KubeFleet fleets. Each Kargo
Stage targets a different KubeFleet hub cluster via a credential secret. Kargo
sequences the fleets and blocks downstream promotion until each fleet is
healthy.

This extends the existing `kubefleet-update` promotion step with an optional
`hub` field. When present, the step reads a credential secret from the project
namespace and builds a Kubernetes client for that remote hub. When omitted,
behavior is identical to the single-fleet POC (local cluster).

## Credential Secret Format

Each remote hub needs a Secret in the Kargo project namespace. The Secret
**must** carry the label `kargo.akuity.io/cred-type: fleet` — the step will
reject secrets without this label.

### Option A: Full kubeconfig

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: fleet-hub-canary
  namespace: my-kargo-project
  labels:
    kargo.akuity.io/cred-type: fleet
type: Opaque
data:
  kubeconfig: <base64-encoded kubeconfig>
```

### Option B: Bearer token

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: fleet-hub-public-cloud
  namespace: my-kargo-project
  labels:
    kargo.akuity.io/cred-type: fleet
type: Opaque
data:
  server: <base64-encoded API server URL>
  bearerToken: <base64-encoded token>
  caBundle: <base64-encoded CA cert, optional>
```

For cloud-managed hubs (AKS, EKS, GKE), exec-based kubeconfigs work but
require the auth plugin binary in the Kargo controller container. The
pragmatic alternative is a dedicated service account with a static token and
scoped RBAC on the hub.

### Required RBAC on the remote hub

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kargo-fleet-integration
rules:
- apiGroups: ["placement.kubernetes-fleet.io"]
  resources: ["clusterresourceplacements"]
  verbs: ["create", "get", "list", "patch", "update", "watch"]
```

## Step Config Reference

```yaml
steps:
- uses: kubefleet-update
  config:
    hub:                          # Optional. Omit for local hub.
      secretName: <secret-name>   # Secret in the project namespace
    placements:
    - name: <crp-name>
      resourceSelectors:
      - group: <api-group>
        version: <api-version>
        kind: <kind>
        name: <name>              # Optional. Omit to select all of this GVK.
      policy:                     # Optional.
        placementType: PickAll | PickN | PickFixed
        numberOfClusters: <int>   # PickN only
        clusterNames: [...]       # PickFixed only
        affinity: { ... }         # KubeFleet affinity rules
        topologySpreadConstraints: [...]
      strategy:                   # Optional.
        rollingUpdate:
          maxUnavailable: <int-or-percent>
          maxSurge: <int-or-percent>
          unavailablePeriodSeconds: <int>
```

CRPs created by the step carry ownership labels:
- `kargo.akuity.io/project: <project>`
- `kargo.akuity.io/stage: <stage>`

## Implementation Steps

### Phase 1: Foundation (Steps 1-5)

1. Add `LabelValueCredentialTypeFleet = "fleet"` to `api/v1alpha1/labels.go`
2. Switch all CRP types from `v1beta1` to `v1` (stable, cross-hub compatible)
3. Create shared `KubeFleetHubConfig` type in `kubefleet_types.go`
4. Create `FleetClientBuilder` interface and implementation in
   `kubefleet_client.go` — builds `client.Client` from kubeconfig or bearer
   token secrets
5. Add `hub` property to `kubefleet-update-config.json` schema

### Phase 2: Core Logic (Steps 6-7)

6. Update the step runner:
   - Resolve fleet client from hub secret (or use local client)
   - Enforce `cred-type: fleet` label on secret lookup
   - API discovery check on remote hub
   - Add ownership labels to CRPs
   - Propagate hub identity through health check Input
7. Update the health checker:
   - Resolve fleet client from hub in health Input
   - Cache remote clients by `(secretName, resourceVersion)`
   - Use `(hub, crp-name)` as identity key in output maps

### Phase 3: Testing & Docs (Steps 8-11)

8. Step runner tests: remote hub, missing secret, bad label, build failure
9. Health checker tests: remote hub, caching, label enforcement
10. Update cross-fleet orchestration doc
11. Build, test, lint verification

## Examples

### Example 1: Single Fleet (no hub, current behavior)

The simplest case. Kargo and KubeFleet share the same cluster. No credential
secret needed.

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: fleet-demo
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: app-images
  namespace: fleet-demo
spec:
  subscriptions:
  - image:
      repoURL: myregistry.io/myapp
      semverConstraint: ">=1.0.0"
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: production
  namespace: fleet-demo
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: app-images
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: fleet-rollout
        config:
          placements:
          - name: myapp-production
            resourceSelectors:
            - group: ""
              version: v1
              kind: Namespace
              name: myapp
            policy:
              placementType: PickAll
```

**Flow:** Warehouse detects new image → Freight created → Stage promotes →
`kubefleet-update` creates CRP on local hub → KubeFleet rolls out to all
member clusters → Stage becomes healthy when all clusters report Available.

---

### Example 2: Cross-Cloud Pipeline (canary → public → sovereign)

Three stages, three hubs. Each fleet manages clusters in one cloud
environment. Promotion is gated on fleet-wide health at each stage.

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: global-app
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: app-images
  namespace: global-app
spec:
  subscriptions:
  - image:
      repoURL: myregistry.io/myapp
      semverConstraint: ">=1.0.0"
---
# Credential secrets for each hub
apiVersion: v1
kind: Secret
metadata:
  name: canary-hub
  namespace: global-app
  labels:
    kargo.akuity.io/cred-type: fleet
type: Opaque
data:
  kubeconfig: <base64>
---
apiVersion: v1
kind: Secret
metadata:
  name: public-cloud-hub
  namespace: global-app
  labels:
    kargo.akuity.io/cred-type: fleet
type: Opaque
data:
  kubeconfig: <base64>
---
apiVersion: v1
kind: Secret
metadata:
  name: sovereign-hub
  namespace: global-app
  labels:
    kargo.akuity.io/cred-type: fleet
type: Opaque
data:
  kubeconfig: <base64>
---
# Stage 1: Canary fleet — one cluster, fast feedback
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: canary
  namespace: global-app
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: app-images
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: canary-rollout
        config:
          hub:
            secretName: canary-hub
          placements:
          - name: myapp-canary
            resourceSelectors:
            - group: apps
              version: v1
              kind: Deployment
              name: myapp
            policy:
              placementType: PickN
              numberOfClusters: 1
              affinity:
                clusterAffinity:
                  requiredDuringSchedulingIgnoredDuringExecution:
                    clusterSelectorTerms:
                    - labelSelector:
                        matchLabels:
                          tier: canary
---
# Stage 2: Azure public cloud — all production clusters
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: azure-public
  namespace: global-app
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: app-images
    sources:
      stages:
      - canary
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: public-rollout
        config:
          hub:
            secretName: public-cloud-hub
          placements:
          - name: myapp-public
            resourceSelectors:
            - group: apps
              version: v1
              kind: Deployment
              name: myapp
            policy:
              placementType: PickAll
            strategy:
              rollingUpdate:
                maxUnavailable: "25%"
                unavailablePeriodSeconds: 60
---
# Stage 3: Sovereign clouds — after public cloud is healthy
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: sovereign
  namespace: global-app
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: app-images
    sources:
      stages:
      - azure-public
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: sovereign-rollout
        config:
          hub:
            secretName: sovereign-hub
          placements:
          - name: myapp-sovereign
            resourceSelectors:
            - group: apps
              version: v1
              kind: Deployment
              name: myapp
            policy:
              placementType: PickAll
```

**Flow:**

```
Warehouse ──► canary (Hub A, 1 cluster)
                 │ healthy?
                 ▼
              azure-public (Hub B, all prod clusters, rolling 25%)
                 │ healthy?
                 ▼
              sovereign (Hub C, all sov-cloud clusters)
```

Each transition is gated. A failure in the canary fleet blocks public cloud.
A failure in public cloud blocks sovereign. Operators see per-cluster health
at every stage.

---

### Example 3: Multi-Tenant SaaS

A SaaS provider runs one fleet per tenant. Each tenant has its own hub.
The internal tenant is the canary. Tenant rollouts happen in sequence.

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: saas-platform
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: platform-images
  namespace: saas-platform
spec:
  subscriptions:
  - image:
      repoURL: myregistry.io/platform
      semverConstraint: ">=2.0.0"
---
# Hub secrets
apiVersion: v1
kind: Secret
metadata:
  name: internal-tenant-hub
  namespace: saas-platform
  labels:
    kargo.akuity.io/cred-type: fleet
type: Opaque
data:
  server: <base64-encoded URL>
  bearerToken: <base64-encoded token>
  caBundle: <base64-encoded CA>
---
apiVersion: v1
kind: Secret
metadata:
  name: tenant-a-hub
  namespace: saas-platform
  labels:
    kargo.akuity.io/cred-type: fleet
type: Opaque
data:
  server: <base64-encoded URL>
  bearerToken: <base64-encoded token>
  caBundle: <base64-encoded CA>
---
apiVersion: v1
kind: Secret
metadata:
  name: tenant-b-hub
  namespace: saas-platform
  labels:
    kargo.akuity.io/cred-type: fleet
type: Opaque
data:
  server: <base64-encoded URL>
  bearerToken: <base64-encoded token>
---
# Stage 1: Internal tenant — canary
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: internal
  namespace: saas-platform
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: platform-images
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: internal-rollout
        config:
          hub:
            secretName: internal-tenant-hub
          placements:
          - name: platform-internal
            resourceSelectors:
            - group: ""
              version: v1
              kind: Namespace
              name: platform
            policy:
              placementType: PickAll
---
# Stage 2: Tenant A
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: tenant-a
  namespace: saas-platform
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: platform-images
    sources:
      stages:
      - internal
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: tenant-a-rollout
        config:
          hub:
            secretName: tenant-a-hub
          placements:
          - name: platform-tenant-a
            resourceSelectors:
            - group: ""
              version: v1
              kind: Namespace
              name: platform
            policy:
              placementType: PickAll
            strategy:
              rollingUpdate:
                maxUnavailable: 1
---
# Stage 3: Tenant B
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: tenant-b
  namespace: saas-platform
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: platform-images
    sources:
      stages:
      - tenant-a
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: tenant-b-rollout
        config:
          hub:
            secretName: tenant-b-hub
          placements:
          - name: platform-tenant-b
            resourceSelectors:
            - group: ""
              version: v1
              kind: Namespace
              name: platform
            policy:
              placementType: PickAll
            strategy:
              rollingUpdate:
                maxUnavailable: 1
```

**Flow:**

```
Warehouse ──► internal (Internal Hub, all internal clusters)
                 │ healthy?
                 ▼
              tenant-a (Tenant A Hub, rolling maxUnavailable=1)
                 │ healthy?
                 ▼
              tenant-b (Tenant B Hub, rolling maxUnavailable=1)
```

The internal tenant validates the update first. If healthy, tenant-a gets it.
Then tenant-b. Each tenant's fleet manages its own clusters independently.
The bearer token format is shown here as an alternative to kubeconfig.

## Health States

The health checker maps KubeFleet CRP status to Kargo health:

| CRP Condition | Kargo Health State |
|---|---|
| Scheduled=False | Unhealthy |
| Applied=False | Unhealthy |
| Available=True, Applied=True (current generation) | Healthy |
| Available=False | Progressing |
| Conditions stale (ObservedGeneration < Generation) | Progressing |
| No per-cluster statuses yet | Progressing |
| Per-cluster apply failure | Unhealthy |
| CRP not found | Unhealthy |
| Cannot reach hub | Unknown |

## Deferred Features

| Feature | Status | Notes |
|---|---|---|
| ClusterResourceOverride | Future | Per-cloud config differentiation via KubeFleet overrides |
| ResourcePlacement | Future | Namespace-scoped placements for finer-grained control |
| MemberCluster monitoring | Future | Detect silent cluster loss in PickAll |
| CRP cleanup finalizer | Future | Auto-delete CRPs when Kargo stages are removed |
| Dashboard fleet view | Future | Visual per-fleet, per-cluster rollout status |
