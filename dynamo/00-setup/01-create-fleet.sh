#!/usr/bin/env bash
# Creates: resource group, Fleet Manager with hub + managed identity,
# two AKS clusters each with a Spot T4 pool, joined as members with labels.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh

az group create -n "$RG" -l "$HUB_LOCATION" -o none
az fleet create -g "$RG" -n "$FLEET" -l "$HUB_LOCATION" --enable-hub --enable-managed-identity -o none

create_member() { # name location gpu-node-count env-label
  local name=$1 loc=$2 gpus=$3 env=$4
  az aks create -g "$RG" -n "$name" -l "$loc" --node-count 2 --node-vm-size "$SYSTEM_SIZE" --generate-ssh-keys -o none
  # --gpu-driver None: the NVIDIA GPU Operator installs the driver (Dynamo's documented AKS path).
  az aks nodepool add -g "$RG" --cluster-name "$name" -n gpu --node-count "$gpus" --node-vm-size "$GPU_SIZE" \
    --priority Spot --eviction-policy Delete --spot-max-price -1 --gpu-driver None -o none
  az fleet member create -g "$RG" -f "$FLEET" -n "$name" \
    --member-cluster-id "$(az aks show -g "$RG" -n "$name" --query id -o tsv)" \
    --labels gpu=true env="$env" -o none
  az aks get-credentials -g "$RG" -n "$name" --context "$name" --overwrite-existing
}

create_member "$MEMBER_A" "$LOC_A" "$GPU_NODES_A" canary
create_member "$MEMBER_B" "$LOC_B" "$GPU_NODES_B" prod

az fleet get-credentials -g "$RG" -n "$FLEET" --context "$HUB_CONTEXT" --overwrite-existing
kubectl --context "$HUB_CONTEXT" get memberclusters
