#!/usr/bin/env bash
# Members: NVIDIA GPU Operator + Dynamo Platform (operator, etcd, NATS).
# Hub: only the DynamoGraphDeployment CRD, so the hub can store the object Fleet places.
set -euo pipefail
cd "$(dirname "$0")/.." && source env.sh

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null
helm repo update >/dev/null
helm pull "https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-${DYNAMO_VERSION}.tgz"

for ctx in "$MEMBER_A" "$MEMBER_B"; do
  helm --kube-context "$ctx" upgrade --install gpu-operator nvidia/gpu-operator \
    -n gpu-operator --create-namespace -f 00-setup/gpu-operator-values.yaml --wait --timeout 15m
  helm --kube-context "$ctx" upgrade --install dynamo-platform "dynamo-platform-${DYNAMO_VERSION}.tgz" \
    -n dynamo-system --create-namespace --wait --timeout 10m
  kubectl --context "$ctx" get nodes -l agentpool=gpu -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
done

# The CRD is ~3 MB, so client-side apply would overflow the last-applied annotation.
kubectl --context "$HUB_CONTEXT" apply --server-side -f \
  "https://raw.githubusercontent.com/ai-dynamo/dynamo/v${DYNAMO_VERSION}/deploy/operator/config/crd/bases/nvidia.com_dynamographdeployments.yaml"
# The CRD declares a conversion webhook served by the operator, which does not run on the hub.
# The hub only stores v1beta1 objects, so no conversion is ever needed.
kubectl --context "$HUB_CONTEXT" patch crd dynamographdeployments.nvidia.com --type merge \
  -p '{"spec":{"conversion":{"strategy":"None"}}}'
