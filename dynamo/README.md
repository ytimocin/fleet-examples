# Dynamo on a Fleet: one model, two GPU regions, one endpoint

A short demo of running [NVIDIA Dynamo](https://github.com/ai-dynamo/dynamo) inference across
several AKS clusters with [KubeFleet](https://kubefleet.dev) via
[Azure Kubernetes Fleet Manager](https://learn.microsoft.com/azure/kubernetes-fleet/).

## The scenario

A platform team runs "LLM inference as a service" for the rest of the company. GPU quota is
granted per region, so they have GPU node pools in two regions whether they planned to or not.
Product teams want one URL and a model name. The platform team wants to change models and
runtimes without anyone noticing.

Dynamo is a single-cluster serving operator: a `DynamoGraphDeployment` (DGD) becomes an
OpenAI-compatible Frontend, a KV-aware Router and vLLM workers in **one** cluster. Nothing in it
places, routes or rolls across clusters. That is where Fleet starts.

| Layer | Does | Owns |
|---|---|---|
| Dynamo (per cluster) | Frontend, router, workers, in-cluster autoscaling, request migration | the serving |
| Fleet (hub) | which clusters, per-cluster shape, one DNS name, staged rollout, traffic steering | the fleet |

## Examples

| # | Folder | Shows | Builds on |
|---|---|---|---|
| 00 | [`00-setup`](00-setup/) | Fleet hub, two Spot-T4 AKS members, Dynamo platform, DGD CRD on the hub | — |
| 01 | [`01-place-model`](01-place-model/) | One DGD on the hub placed to every `gpu=true` cluster | 00 |
| 02 | [`02-override-per-cluster`](02-override-per-cluster/) | Prod runs 2 workers, canary 1, from the same DGD | 01 |
| 03 | [`03-one-endpoint`](03-one-endpoint/) | ServiceExport + Azure Traffic Manager: one DNS name over both regions | 01 |
| 04 | [`04-staged-rollout`](04-staged-rollout/) | Swap the model under a stable alias, canary first, approve, then prod | 01, 03 |
| 05 | [`05-drain-region`](05-drain-region/) | Send 0% traffic to a region from the hub without touching a pod | 03, 04 |

Each folder has its own README with the commands and what the step proves. 01 to 03 can be
shown on their own; 04 and 05 assume the earlier ones.

## Prerequisites

- Azure subscription with Spot quota for `Standard_NC4as_T4_v3` in two regions. Defaults are
  `southcentralus` and `eastus2`; change them in [`env.sh`](env.sh).
- `az` with the `fleet` extension, `kubectl`, `helm`, `jq`, `dig`.
- Permission to create role assignments (for Traffic Manager in 03 and 05).

```bash
source env.sh
00-setup/01-create-fleet.sh          # ~15 min
00-setup/02-install-dynamo.sh        # ~10 min
00-setup/03-traffic-manager-rbac.sh  # then wait for RBAC propagation
```

Tear down with `./cleanup.sh`.

## Things to know before presenting

- **Small model on purpose.** Qwen3-0.6B on one T4 is not production, but the DGD shape is
  identical to Dynamo's Qwen3-32B tensor-parallel recipes. Only the args and GPU count change.
- **Aggregated, not disaggregated.** Prefill/decode splitting wants RDMA and Grove; both are
  out of scope here and change nothing on the Fleet side.
- **The hub only stores the DGD.** It has the CRD with conversion set to `None` and no
  operator. Members run the real operator.
- **Traffic Manager is DNS.** Failover follows TTL. Front Door would give L7 routing; the
  Fleet objects stay the same.
- **No GPU-aware placement yet.** Fleet's Azure property provider reports CPU and memory only,
  so "put it where GPUs are free" is done with labels today.
- **04 switches the CRP to `External`.** From then on every change to the namespace goes
  through an UpdateRun. That is the behaviour a platform team wants.

## References

- Dynamo: [deploy with DGD](https://github.com/ai-dynamo/dynamo/blob/main/docs/fern/pages/kubernetes/model-deployment/deploy-with-dgd.md),
  [AKS setup](https://github.com/ai-dynamo/dynamo/blob/main/docs/fern/pages/kubernetes/installation/managed-kubernetes/azure/aks-setup.mdx),
  [Spot VMs](https://github.com/ai-dynamo/dynamo/blob/main/docs/fern/pages/kubernetes/installation/managed-kubernetes/azure/spot-vms.mdx)
- KubeFleet: [ClusterResourcePlacement](https://kubefleet.dev/docs/how-tos/crp/),
  [ResourceOverride](https://kubefleet.dev/docs/how-tos/resource-override/),
  [staged updates](https://kubefleet.dev/docs/how-tos/staged-update/)
- Fleet Manager: [DNS load balancing](https://learn.microsoft.com/azure/kubernetes-fleet/howto-dns-load-balancing)
