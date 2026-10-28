# 05 — Drain a region without touching a pod

Spot eviction, a bad driver update, a region incident: the fix is "stop sending traffic there".
A weight annotation on the exported Service does it from the hub.

```bash
source ../env.sh
kubectl --context $HUB_CONTEXT apply -f ro-weight.yaml
# 04 left the CRP on External, so push the override through a run:
sed 's/chat-qwen3-1-7b/drain-canary/' ../04-staged-rollout/updaterun.yaml | kubectl --context $HUB_CONTEXT apply -f -
kubectl --context $HUB_CONTEXT patch clusterstagedupdaterun drain-canary --type merge -p '{"spec":{"state":"Run"}}'
kubectl --context $HUB_CONTEXT get clusterapprovalrequest          # approve drain-canary-after-canary as in 04
kubectl --context $HUB_CONTEXT -n $NS get trafficmanagerbackend chat -o yaml   # canary endpoint weight 0
for i in 1 2 3 4 5; do ../03-one-endpoint/chat.sh; done              # always prod now
```

Undo: delete the override and run another UpdateRun. For a permanent move use a
ClusterResourcePlacementEviction after tainting the member, as in the fleet-networking demos.

Separate from 04 in spirit, but shares its UpdateRun plumbing.
