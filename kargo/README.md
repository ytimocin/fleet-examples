# Kargo + KubeFleet Cross-Fleet Playground

Demo: **Kargo orchestrating promotions across multiple independent KubeFleet fleets.**

One Kargo instance sits above N KubeFleet hubs and sequences rollouts (e.g. canary on fleet A, then fleet B, then fleet C), gating each stage on fleet-wide health.

## Prerequisites

- Docker
- `kubectl`, `helm`, `kind`
- `htpasswd` (from `apache2-utils` or macOS built-in)

## Quick start

```bash
# 2 hubs, 2 member clusters each (6 Kind clusters total)
./hack/setup-multi-fleet.sh 2 2

# Generate pipeline YAML that chains stages across those hubs
./hack/generate-cross-fleet-pipeline.sh 2

# Apply it
kubectl --context kind-hub-1 apply -f docs/multi-hub-pipeline.yaml

# Open Kargo UI
kubectl --context kind-hub-1 -n kargo port-forward svc/kargo-api 31081:443 &
# Browse: https://localhost:31081  (admin / admin)
```

## What you'll see

1. Warehouse detects new nginx image → creates Freight.
2. Promote to `hub-1-fleet` → CRP created on hub-1 (canary, 1 cluster).
3. Kargo waits until hub-1 is healthy.
4. Promote to `hub-2-fleet` → CRP created on hub-2 (remote fleet via credential Secret).
5. All stages green — cross-fleet rollout complete.

## Teardown

```bash
./hack/teardown-multi-fleet.sh 2 2
```

## Scaling

```bash
./hack/setup-multi-fleet.sh 3 3   # 3 hubs, 3 members each (12 Kind clusters, ~8GB RAM)
./hack/generate-cross-fleet-pipeline.sh 3
```

## Under the hood

- **Kargo image**: `ghcr.io/ytimocin/kargo:cross-fleet` (built from [this fork](https://github.com/ytimocin/kargo/tree/cross-fleet), PR #1).
- **KubeFleet images**: upstream `ghcr.io/kubefleet-dev/kubefleet/*:v0.2.2`.
- Helm charts for both are vendored in `charts-kargo/` and `charts-kubefleet/`.

See `docs/` for design notes:
- `cross-fleet-feature.md` — step config, security, examples
- `cross-fleet-orchestration.md` — vision & architecture
- `HOWTO.md` — extended walkthrough
