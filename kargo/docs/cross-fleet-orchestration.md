# Cross-Fleet Orchestration with Kargo + KubeFleet

## The Problem

A single KubeFleet instance manages clusters that share one trust boundary and
one control plane. In practice, organizations hit limits:

- Azure Public Cloud clusters live in one Fleet. Sovereign cloud clusters live
  in another. Fleet cannot span them.
- A company runs one Fleet per cloud provider (Azure, AWS, GCP). No single
  Fleet controls all three.
- A SaaS vendor operates one Fleet per tenant or per compliance zone.

The workload is the same. The promotion flow is the same. But there is no single
Fleet that can roll it out everywhere.

Today, operators solve this by scripting promotions across fleets manually or
running completely independent pipelines per fleet with no shared gating.

## The Vision: Kargo as the Cross-Fleet Orchestrator

Kargo already models promotion as a pipeline of Stages with health gates
between them. Each Stage can run a `kubefleet-update` step targeting a
different fleet. Kargo sequences the fleets and blocks downstream promotion
until each fleet is healthy.

```
Warehouse ──► Stage: canary-fleet ──► Stage: public-cloud-fleet ──► Stage: sov-cloud-fleet
                 │                        │                             │
                 ▼                        ▼                             ▼
            KubeFleet Hub A          KubeFleet Hub B              KubeFleet Hub C
            (canary clusters)        (public cloud)               (sovereign clouds)
```

Kargo provides the orchestration across fleets. Each KubeFleet hub handles
placement and rollout within its own fleet. Neither system needs to know about
the other's internals.

## How It Works Today (POC)

The current POC assumes Kargo and the KubeFleet hub share one API server. A
single `kubefleet-update` step creates a `ClusterResourcePlacement` using
Kargo's own Kubernetes client.

This works for a single fleet. For cross-fleet orchestration, it does not,
because the second and third fleets have their own API servers that Kargo
cannot reach with its local client.

## What Needs to Change

### Multi-hub support

The `kubefleet-update` step needs the ability to target a remote KubeFleet hub
cluster. The step config would specify which hub to talk to:

```yaml
steps:
- uses: kubefleet-update
  as: public-cloud-rollout
  config:
    hub:
      name: public-cloud-hub
      credentialSecret: fleet-hub-public-cloud
    placements:
    - name: demo-placement
      resourceSelectors:
      - group: ""
        version: v1
        kind: Namespace
        name: demo
      policy:
        placementType: PickAll
```

When `hub` is omitted, the step uses the local API server (current behavior).
When `hub` is specified, the step builds a client from the referenced
credential secret.

The health checker also needs the same multi-hub awareness, so it can read CRP
status from the correct hub.

### Credential management

Each remote hub needs a kubeconfig or service account token stored as a
Kubernetes Secret. Kargo already has a credential management system
(`pkg/credentials/`) that handles secrets for Git repos and image registries.
Fleet hub credentials can follow the same pattern.

A minimal credential secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: fleet-hub-public-cloud
  namespace: fleet-demo
  labels:
    kargo.akuity.io/cred-type: kubefleet-hub
type: Opaque
data:
  kubeconfig: <base64-encoded kubeconfig>
```

### Health checker changes

The health checker currently receives a single Kubernetes client. For
cross-fleet use, it needs to resolve the correct client per placement based on
which hub the placement was created on. The health check criteria should carry
the hub reference so the checker can look up the right client at check time.

## Example: Cross-Cloud Promotion Pipeline

A platform team runs the same application across three environments, each
managed by a separate KubeFleet hub:

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
# Stage 1: canary fleet — one cluster, fast feedback
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
            name: canary-hub
            credentialSecret: fleet-hub-canary
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
---
# Stage 2: Azure public cloud fleet — all production clusters
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
        as: azure-public-rollout
        config:
          hub:
            name: azure-public-hub
            credentialSecret: fleet-hub-azure-public
          placements:
          - name: myapp-azure-public
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
---
# Stage 3: sovereign cloud fleet — after public cloud is healthy
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: azure-sovereign
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
            name: sovereign-hub
            credentialSecret: fleet-hub-sovereign
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

Freight flows: canary (1 cluster) → Azure public (all prod clusters) →
sovereign clouds. Each transition is gated on fleet-wide health.

## Example: Multi-Tenant SaaS

A SaaS provider runs one fleet per tenant. Each tenant has its own KubeFleet
hub. Kargo orchestrates the rollout across tenants:

```
Warehouse ──► Stage: internal-tenant ──► Stage: tenant-a ──► Stage: tenant-b
                                              │                    │
                                         KubeFleet Hub A     KubeFleet Hub B
```

The internal tenant acts as a canary. If it goes healthy, tenant-a gets the
update. Then tenant-b. Each fleet manages its own clusters independently.

## Implementation Plan

### Phase 1: Current POC (done)

Single fleet, co-located hub. Validates the core integration pattern:
`kubefleet-update` step, health checker, CRP lifecycle management.

### Phase 2: Multi-hub support

- Add `hub` field to `kubefleet-update` step config
- Build remote Kubernetes clients from credential secrets
- Pass hub context through health check criteria
- Health checker resolves the correct client per hub
- Test with two Kind-based hubs

### Phase 3: Operational readiness

- Dashboard support: show per-fleet, per-cluster rollout status in Stage health
- Support verification steps between fleet stages (e.g., run integration tests
  against the canary fleet before promoting to production fleet)
- Explore parallel fleet promotion (fan-out pattern) for cases where fleets
  are independent and do not need sequential gating

## What This Enables

| Without cross-fleet orchestration | With cross-fleet orchestration |
|---|---|
| Each fleet is promoted independently | One Kargo pipeline sequences all fleets |
| No gating between fleets | Fleet health gates downstream promotion |
| Manual coordination for cross-cloud rollouts | Automated flow: canary → public → sovereign |
| Per-fleet scripts and dashboards | Single promotion view across all fleets |
| Cannot span clouds with one Fleet | Kargo spans what Fleet cannot |
