# shellcheck shell=bash
# Source this before every script and kubectl command in the demo.
# Override anything by exporting it first, e.g. `LOC_A=westus3 source env.sh`.
export RG="${RG:-dynamo-fleet-demo}"
export FLEET="${FLEET:-dynamo-fleet}"
export HUB_LOCATION="${HUB_LOCATION:-eastus2}"

# Two GPU member clusters. The canary cluster rolls out first in 04.
export MEMBER_A="${MEMBER_A:-gpu-canary}"; export LOC_A="${LOC_A:-southcentralus}"; export GPU_NODES_A="${GPU_NODES_A:-1}"
export MEMBER_B="${MEMBER_B:-gpu-prod}";   export LOC_B="${LOC_B:-eastus2}";        export GPU_NODES_B="${GPU_NODES_B:-2}"

export SYSTEM_SIZE="${SYSTEM_SIZE:-Standard_D2as_v5}"
export GPU_SIZE="${GPU_SIZE:-Standard_NC4as_T4_v3}"   # 1x T4 16 GB, Spot

export DYNAMO_VERSION="${DYNAMO_VERSION:-1.6.1}"
export NS=llm
export HUB_CONTEXT=hub
