#!/usr/bin/env bash
# 1) hand rollout control to UpdateRuns, 2) swap the model under the "chat" alias, 3) start the run.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh
H="kubectl --context $HUB_CONTEXT"
RUN=${RUN:-chat-qwen3-1-7b}   # override to start a second run with the same strategy

$H patch crp chat --type merge -p '{"spec":{"strategy":{"type":"External","rollingUpdate":null}}}'
$H apply -f 04-staged-rollout/strategy.yaml

# Under External the placement controller stops taking resource snapshots; the UpdateRun takes one
# when it initializes. Remember the current index so we can prove the run picked up the change.
latest_index() { $H get clusterresourcesnapshot -l kubernetes-fleet.io/parent-CRP=chat,kubernetes-fleet.io/is-latest-snapshot=true \
  -o jsonpath='{.items[0].metadata.labels.kubernetes-fleet\.io/resource-index}'; }
BEFORE=$(latest_index)

# The new model: Qwen3-1.7B still fits one T4 in fp16. Clients keep calling "chat".
$H -n "$NS" patch dgd chat --type json \
  -p '[{"op":"replace","path":"/spec/components/1/podTemplate/spec/containers/0/args/1","value":"Qwen/Qwen3-1.7B"}]'
# The run snapshots what the hub agent's cache holds. That cache can lag the API server by minutes
# for CRD objects, so create the run, check that it saw the change, and retry if it did not.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  sed "s/chat-qwen3-1-7b/$RUN/" 04-staged-rollout/updaterun.yaml | $H apply -f - >/dev/null
  for _ in $(seq 60); do
    INIT=$($H get clusterstagedupdaterun "$RUN" -o jsonpath='{.status.conditions[?(@.type=="Initialized")]}')
    [[ $INIT == *'"status":"True"'* ]] && break
    [[ $INIT == *'"status":"False"'* ]] && { echo "run failed to initialize: $INIT" >&2; exit 1; }
    sleep 2
  done
  USED=$($H get clusterstagedupdaterun "$RUN" -o jsonpath='{.status.resourceSnapshotIndexUsed}')
  (( USED > BEFORE )) && break
  echo "attempt $attempt: run snapshotted index $USED, same as before the change; retrying in 60s"
  $H delete clusterstagedupdaterun "$RUN" >/dev/null; sleep 60
  (( attempt == 10 )) && { echo "hub never picked up the change" >&2; exit 1; }
done
echo "run uses resource snapshot $USED (was $BEFORE)"

$H patch clusterstagedupdaterun "$RUN" --type merge -p '{"spec":{"state":"Run"}}'
$H get clusterstagedupdaterun "$RUN" -w
