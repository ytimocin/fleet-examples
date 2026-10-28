#!/usr/bin/env bash
# Approves the after-canary gate so the run proceeds to prod.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh
H="kubectl --context $HUB_CONTEXT"
RUN=${RUN:-chat-qwen3-1-7b}
NAME=$RUN-after-canary
# Fleet creates the request only once the canary stage has finished; wait for it.
until $H get clusterapprovalrequest "$NAME" >/dev/null 2>&1; do sleep 3; done
GEN=$($H get clusterapprovalrequest "$NAME" -o jsonpath='{.metadata.generation}')
$H patch clusterapprovalrequest "$NAME" --subresource=status --type merge -p "{\"status\":{\"conditions\":[{\"type\":\"Approved\",\"status\":\"True\",\"reason\":\"approved\",\"message\":\"approved\",\"observedGeneration\":$GEN,\"lastTransitionTime\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}}"
$H get clusterstagedupdaterun "$RUN" -w
