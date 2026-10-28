#!/usr/bin/env bash
# 1) hand rollout control to UpdateRuns, 2) swap the model under the "chat" alias, 3) start the run.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh
H="kubectl --context $HUB_CONTEXT"

$H patch crp chat --type merge -p '{"spec":{"strategy":{"type":"External","rollingUpdate":null}}}'
$H apply -f 04-staged-rollout/strategy.yaml

# The new model: Qwen3-1.7B still fits one T4 in fp16. Clients keep calling "chat".
$H -n "$NS" patch dgd chat --type json \
  -p '[{"op":"replace","path":"/spec/components/1/podTemplate/spec/containers/0/args/1","value":"Qwen/Qwen3-1.7B"}]'

$H apply -f 04-staged-rollout/updaterun.yaml
$H patch clusterstagedupdaterun chat-qwen3-1-7b --type merge -p '{"spec":{"state":"Run"}}'
$H get clusterstagedupdaterun chat-qwen3-1-7b -w
