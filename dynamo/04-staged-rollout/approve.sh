#!/usr/bin/env bash
# Approves the after-canary gate so the run proceeds to prod.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh
H="kubectl --context $HUB_CONTEXT"
NAME=chat-qwen3-1-7b-after-canary
GEN=$($H get clusterapprovalrequest "$NAME" -o jsonpath='{.metadata.generation}')
$H patch clusterapprovalrequest "$NAME" --subresource=status --type merge -p "{\"status\":{\"conditions\":[{\"type\":\"Approved\",\"status\":\"True\",\"reason\":\"approved\",\"message\":\"approved\",\"observedGeneration\":$GEN,\"lastTransitionTime\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}}"
$H get clusterstagedupdaterun chat-qwen3-1-7b -w
