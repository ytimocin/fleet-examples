# 04 — Roll a new model, one region at a time

Bumping a model across every cluster at once is how inference outages happen. A
ClusterStagedUpdateRun rolls the canary cluster, waits for a human, then rolls prod. Clients keep
calling the alias `chat`; only the weights behind it change.

```bash
source ../env.sh
# Terminal 1: keep traffic flowing
while true; do ../03-one-endpoint/chat.sh "Which model are you?"; sleep 2; done
# Terminal 2
./run.sh                 # canary rolls to Qwen3-1.7B, then the run waits
kubectl --context $HUB_CONTEXT get clusterapprovalrequest
./approve.sh             # prod rolls
```

Watch a member while it rolls: `kubectl --context $MEMBER_A -n $NS get pods -w`. The Dynamo
operator starts a worker Deployment for the new spec, retires the old one, and the Frontend keeps
answering. If the canary looks wrong, `kubectl patch ... -p '{"spec":{"state":"Stop"}}'` instead of
approving, and revert the DGD on the hub.

Builds on 01 and 03. After this step the CRP strategy is `External`, so every later change to the
`llm` namespace needs an UpdateRun. That is the point.

## Two things the scripts handle for you

- **The run takes the snapshot.** Under `External` the placement controller stops creating resource
  snapshots; the UpdateRun creates one when it initializes, from the hub agent's informer cache.
  That cache can trail the API server by minutes for CRD objects. `run.sh` records the snapshot
  index before the change and retries the run until it initializes on a newer one. Without that
  check a run can "succeed" while re-applying the old model everywhere.
- **GPU budget for the swap.** Dynamo replaces workers by surging a new Deployment next to the old
  one (default `maxSurge` 25%, rounded up to 1). On a pool where every GPU is in use the new worker
  never schedules and the rollout hangs. The DGD in 01 sets
  `nvidia.com/deployment-rolling-update-max-surge: "0"` and `...-max-unavailable: "1"` on the
  worker pod template, so one old worker is retired first. A single-worker canary blips for the
  duration of a model load; prod with two workers keeps one serving. Give each pool one spare GPU
  and drop the annotations if you want zero-blip canaries too.
