# Fleet examples

Demos of [KubeFleet](https://kubefleet.dev) and
[Azure Kubernetes Fleet Manager](https://learn.microsoft.com/azure/kubernetes-fleet/) doing
multi-cluster work for other systems. Each folder is self-contained with its own README,
scripts and manifests.

| Example | Pairs Fleet with | Runs on | Shows |
|---|---|---|---|
| [`dynamo/`](dynamo/) | NVIDIA Dynamo (LLM inference) | AKS, two GPU regions | place a model everywhere, per-cluster shape, one DNS endpoint, staged model rollout, drain a region |
| [`kargo/`](kargo/) | Kargo (promotion pipelines) | Kind, local | one Kargo instance promoting across independent KubeFleet hubs with health gates |
| [kubeflow-fleet-gitops](https://github.com/ytimocin/kubeflow-fleet-gitops) | Kubeflow (GPU training) | AKS, two regions | regional training, pipelines, shared storage, onboarding GPU members. Separate repo because Flux syncs from it. |

Azure examples create real resources: read each folder's prerequisites and cleanup section first.
