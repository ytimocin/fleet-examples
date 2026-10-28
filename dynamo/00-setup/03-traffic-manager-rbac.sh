#!/usr/bin/env bash
# The hub identity creates the Traffic Manager profile in $RG and reads the member
# clusters' public IPs from their node resource groups. Needed for 03 and 05 only.
# Role: "Azure Kubernetes Fleet Manager Hub Agent Role". Propagation can take up to 60 min.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh

HUB_PRINCIPAL=$(az fleet show -g "$RG" -n "$FLEET" --query identity.principalId -o tsv)
ROLE=de2b316d-7a2c-4143-b4cd-c148f6a355a1
SUB=$(az account show --query id -o tsv)

az role assignment create --assignee-object-id "$HUB_PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role "$ROLE" --scope "/subscriptions/$SUB/resourceGroups/$RG" -o none
for m in "$MEMBER_A" "$MEMBER_B"; do
  NODE_RG=$(az aks show -g "$RG" -n "$m" --query nodeResourceGroup -o tsv)
  az role assignment create --assignee-object-id "$HUB_PRINCIPAL" --assignee-principal-type ServicePrincipal \
    --role "$ROLE" --scope "/subscriptions/$SUB/resourceGroups/$NODE_RG" -o none
done
echo "done; allow up to 60 minutes for propagation"
