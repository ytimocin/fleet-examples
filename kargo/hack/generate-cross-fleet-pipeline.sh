#!/usr/bin/env bash
set -euo pipefail

# generate-cross-fleet-pipeline.sh — Generate a Kargo pipeline YAML that chains
# stages across N KubeFleet hubs.
#
# Usage: ./hack/generate-cross-fleet-pipeline.sh [NUM_HUBS]
# Output: docs/multi-hub-pipeline.yaml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT="${ROOT_DIR}/docs/multi-hub-pipeline.yaml"

NUM_HUBS=${1:-2}

cat > "${OUTPUT}" <<'HEADER'
# Auto-generated cross-fleet pipeline.
# Usage: kubectl --context kind-hub-1 apply -f docs/multi-hub-pipeline.yaml
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: fleet-demo
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: app-images
  namespace: fleet-demo
spec:
  subscriptions:
  - image:
      repoURL: nginx
      semverConstraint: ">=1.0.0"
HEADER

prev_stage=""

for hub_idx in $(seq 1 "${NUM_HUBS}"); do
    stage_name="hub-${hub_idx}-fleet"

    # Determine freight source
    if [[ -z "${prev_stage}" ]]; then
        sources="      direct: true"
    else
        sources="      stages:
      - ${prev_stage}"
    fi

    # Hub-1 is local (no hub field). Hub-2+ are remote.
    if [[ "${hub_idx}" -eq 1 ]]; then
        hub_config=""
        # First hub acts as canary: PickN with 1 cluster
        policy="            policy:
              placementType: PickN
              numberOfClusters: 1"
    else
        hub_config="
          hub:
            secretName: fleet-hub-${hub_idx}"
        policy="            policy:
              placementType: PickAll"
    fi

    cat >> "${OUTPUT}" <<EOF
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: ${stage_name}
  namespace: fleet-demo
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: app-images
    sources:
${sources}
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: ${stage_name}-rollout
        config:${hub_config}
          placements:
          - name: demo-${stage_name}
            resourceSelectors:
            - group: ""
              version: v1
              kind: Namespace
              name: demo
${policy}
EOF

    prev_stage="${stage_name}"
done

echo "Generated: ${OUTPUT}"
echo ""
echo "Pipeline stages:"
for hub_idx in $(seq 1 "${NUM_HUBS}"); do
    local_or_remote="remote (fleet-hub-${hub_idx})"
    if [[ "${hub_idx}" -eq 1 ]]; then
        local_or_remote="local (canary)"
    fi
    echo "  hub-${hub_idx}-fleet  [${local_or_remote}]"
done
echo ""
flow=""
for hub_idx in $(seq 1 "${NUM_HUBS}"); do
    if [[ -n "${flow}" ]]; then flow="${flow} -> "; fi
    flow="${flow}hub-${hub_idx}-fleet"
done
echo "Flow: ${flow}"
