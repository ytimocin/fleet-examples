#!/usr/bin/env bash
set -euo pipefail

# teardown-multi-fleet.sh — Delete all Kind clusters created by setup-multi-fleet.sh.
#
# Usage: ./hack/teardown-multi-fleet.sh [NUM_HUBS] [MEMBERS_PER_HUB]

NUM_HUBS=${1:-2}
MEMBERS_PER_HUB=${2:-2}

echo "Tearing down ${NUM_HUBS} hub(s) with ${MEMBERS_PER_HUB} member(s) each..."

for hub_idx in $(seq 1 "${NUM_HUBS}"); do
    # Delete member clusters first
    for m in $(seq 1 "${MEMBERS_PER_HUB}"); do
        cluster="hub-${hub_idx}-member-${m}"
        echo "  Deleting ${cluster}..."
        kind delete cluster --name "${cluster}" 2>/dev/null || true
    done
    # Delete hub cluster
    echo "  Deleting hub-${hub_idx}..."
    kind delete cluster --name "hub-${hub_idx}" 2>/dev/null || true
done

# Clean up temp files
rm -f /tmp/hub-*.kubeconfig

echo "Done."
