# 04 — Roll a new model, one region at a time

Bumping a model across every cluster at once is how inference outages happen. A
ClusterStagedUpdateRun rolls the canary cluster, waits for a human, then rolls prod. Dynamo's
graceful shutdown and in-flight request migration keep the alias `chat` answering throughout.

```bash
source ../env.sh
# Terminal 1: keep traffic flowing
while true; do ../03-one-endpoint/chat.sh "Which model are you?"; sleep 2; done
# Terminal 2
./run.sh                 # canary rolls to Qwen3-1.7B, then the run waits
kubectl --context $HUB_CONTEXT get clusterapprovalrequest
./approve.sh             # prod rolls
```

Check with `curl .../v1/models` on each cluster: the model id is still `chat`; the backing
weights changed. If the canary looks wrong, `kubectl patch ... -p '{"spec":{"state":"Stop"}}'`
instead of approving, and revert the DGD on the hub.

Builds on 01 and 03. After this step the CRP strategy is `External`, so every later change to the
`llm` namespace needs an UpdateRun. That is the point.
