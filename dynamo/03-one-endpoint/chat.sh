#!/usr/bin/env bash
# Sends one chat request through the Traffic Manager name and shows which cluster answered.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh
FQDN=$(kubectl --context "$HUB_CONTEXT" -n "$NS" get trafficmanagerprofile dynamo-fleet-chat -o jsonpath='{.status.dnsName}')
IP=$(dig +short "$FQDN" | tail -1)
# Endpoint targets may be IPs or DNS names; resolve each and match on the IP we got.
CLUSTER=unknown
while IFS=$'\t' read -r target cluster; do
  [[ "$target" =~ ^[0-9.]+$ ]] && tip=$target || tip=$(dig +short "$target" | tail -1)
  [[ "$tip" == "$IP" ]] && CLUSTER=$cluster
done < <(kubectl --context "$HUB_CONTEXT" -n "$NS" get trafficmanagerbackend chat -o json \
  | jq -r '.status.endpoints[]? | [.target, .from.cluster] | @tsv')
echo "$FQDN -> $IP ($CLUSTER)"
curl -s "http://$FQDN:8000/v1/chat/completions" -H 'content-type: application/json' \
  -d "{\"model\":\"chat\",\"messages\":[{\"role\":\"user\",\"content\":\"${1:-Say hi in five words.}\"}],\"max_tokens\":64}" \
  | jq -r '.choices[0].message.content'
