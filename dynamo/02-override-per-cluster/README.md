# 02 — Different shape per cluster, one source of truth

GPU estates are never uniform: quota, SKU and traffic differ by region. A ResourceOverride
patches the placed object per cluster while the hub keeps a single DGD.

```bash
source ../env.sh
kubectl --context $HUB_CONTEXT apply -f ro-replicas.yaml
kubectl --context $MEMBER_B -n $NS get pods -l nvidia.com/dynamo-component=worker   # 2 workers
kubectl --context $MEMBER_A -n $NS get pods -l nvidia.com/dynamo-component=worker   # still 1
```

Builds on 01. The same pattern changes `nvidia.com/gpu` limits, `--tensor-parallel-size` or the
image per SKU; only the JSON patch path differs.
