#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")" && source env.sh
kubectl --context "$HUB_CONTEXT" -n "$NS" delete trafficmanagerbackend,trafficmanagerprofile --all --ignore-not-found
az group delete -n "$RG" --yes --no-wait
for c in "$HUB_CONTEXT" "$MEMBER_A" "$MEMBER_B"; do kubectl config delete-context "$c" >/dev/null 2>&1 || true; done
