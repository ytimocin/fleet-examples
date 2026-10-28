# Kargo + KubeFleet: promote across independent fleets

Demo: **Kargo orchestrating promotions across multiple KubeFleet fleets.**

One Kargo instance sits above N KubeFleet hubs and sequences rollouts (canary on fleet A, then
fleet B, then fleet C), gating each stage on fleet-wide health. Everything runs locally in Kind.

Kargo has no KubeFleet step upstream. This demo runs a fork that adds a `kubefleet-update`
promotion step and a `kubefleet` health checker:
[ytimocin/kargo#1](https://github.com/ytimocin/kargo/pull/1), image `ghcr.io/ytimocin/kargo:cross-fleet`.

## Prerequisites

Docker, `kind`, `kubectl`, `helm`, `htpasswd` (macOS built-in; `apache2-utils` on Debian).
Six Kind clusters need roughly 4 GB of free RAM.

## Run

```bash
./hack/setup-multi-fleet.sh 2 2                 # 2 hubs x 2 members, Kargo on hub-1  (~10 min)
./hack/generate-cross-fleet-pipeline.sh 2       # writes docs/multi-hub-pipeline.yaml
kubectl --context kind-hub-1 apply -f docs/multi-hub-pipeline.yaml

kubectl --context kind-hub-1 -n kargo port-forward svc/kargo-api 31081:443 &
open https://localhost:31081                    # admin / admin
```

Promote from the UI, or with the CLI:

```bash
kargo login https://localhost:31081 --admin --insecure-skip-tls-verify
kubectl --context kind-hub-1 get freight -n fleet-demo          # pick a freight name
kargo promote --project fleet-demo --stage hub-1-fleet --freight <name>

kubectl --context kind-hub-1 get stage -n fleet-demo -w         # health per fleet
kubectl --context kind-hub-1 get crp -w                         # CRP on hub-1
kubectl --context kind-hub-2 get crp -w                         # CRP on hub-2
```

What you see:

1. The Warehouse detects an nginx image and creates Freight.
2. Promoting to `hub-1-fleet` creates a CRP on hub-1 that picks one cluster (canary).
3. Kargo waits until hub-1 reports healthy.
4. Promoting to `hub-2-fleet` creates a CRP on hub-2 through a kubeconfig Secret (`fleet-hub-2`).
5. All stages green: the rollout crossed two fleets with one pipeline.

Scale: `./hack/setup-multi-fleet.sh 3 3` plus `generate-cross-fleet-pipeline.sh 3` gives three
fleets (12 Kind clusters, ~8 GB RAM). Teardown with the same numbers:
`./hack/teardown-multi-fleet.sh 2 2`.

## Layout

| Path | What |
|---|---|
| `hack/` | setup, pipeline generator, teardown |
| `charts-kubefleet/` | upstream hub-agent and member-agent charts, vendored |
| `charts-kargo/` | Kargo chart from the fork, vendored |
| `docs/POC.md` | why Kargo plus KubeFleet, single-fleet scope |
| `docs/cross-fleet-orchestration.md` | the multi-fleet problem and architecture |
| `docs/cross-fleet-feature.md` | step config, credential Secret format, examples |

## Pinned versions

| What | Version | Override |
|---|---|---|
| KubeFleet images | v0.3.2 | `KUBEFLEET_TAG` |
| Kargo fork image | `cross-fleet` | `KARGO_IMAGE`, `KARGO_TAG` |
| cert-manager | v1.21.3 | `CERT_MANAGER_VERSION` |
| Kind node | v1.33.4 | `KIND_IMAGE` |

The vendored KubeFleet charts match the v0.3.x release charts. Bumping the image tag past that
line means re-vendoring `charts/` from the KubeFleet tag you target.
