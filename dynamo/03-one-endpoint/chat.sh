#!/usr/bin/env bash
# Sends one chat request through the Traffic Manager name and shows which cluster answered.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh
FQDN=$(kubectl --context "$HUB_CONTEXT" -n "$NS" get trafficmanagerprofile dynamo-fleet-chat -o jsonpath='{.status.dnsName}')
ip_of() { curl -s --max-time 10 -o /dev/null -w '%{remote_ip}' "http://$1:8000/v1/models" || true; }
IP=$(ip_of "$FQDN")
# Endpoint targets are DNS labels of the member LBs; find the one that resolves to the IP we hit.
CLUSTER=unknown
while IFS=$'\t' read -r target cluster; do
  [[ $(ip_of "$target") == "$IP" ]] && CLUSTER=$cluster
done < <(kubectl --context "$HUB_CONTEXT" -n "$NS" get trafficmanagerbackend chat -o json \
  | jq -r '.status.endpoints[]? | [.target, .from.cluster] | @tsv')
echo "$FQDN -> ${IP:-unresolved} ($CLUSTER)"
# enable_thinking=false: Qwen3 otherwise spends the whole token budget inside <think>.
curl -s "http://$FQDN:8000/v1/chat/completions" -H 'content-type: application/json' \
  -d "{\"model\":\"chat\",\"messages\":[{\"role\":\"user\",\"content\":\"${1:-Say hi in five words.}\"}],\"max_tokens\":64,\"chat_template_kwargs\":{\"enable_thinking\":false}}" \
  | jq -r '.choices[0].message.content'
