#!/usr/bin/env bash
set -euo pipefail

# setup-multi-fleet.sh — Create N KubeFleet hubs with M members each,
# install Kargo on hub-1, and wire up credential secrets for cross-fleet
# orchestration.
#
# Usage: ./hack/setup-multi-fleet.sh [NUM_HUBS] [MEMBERS_PER_HUB]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

NUM_HUBS=${1:-2}
MEMBERS_PER_HUB=${2:-2}

# Image configuration — upstream KubeFleet published images
REGISTRY="${REGISTRY:-ghcr.io}"
KUBEFLEET_NS="${KUBEFLEET_NS:-kubefleet-dev/kubefleet}"
KUBEFLEET_TAG="${KUBEFLEET_TAG:-v0.2.2}"
HUB_AGENT_IMAGE="${HUB_AGENT_IMAGE:-${KUBEFLEET_NS}/hub-agent}"
MEMBER_AGENT_IMAGE="${MEMBER_AGENT_IMAGE:-${KUBEFLEET_NS}/member-agent}"
REFRESH_TOKEN_IMAGE="${REFRESH_TOKEN_IMAGE:-${KUBEFLEET_NS}/refresh-token}"
TAG="${TAG:-${KUBEFLEET_TAG}}"
KIND_IMAGE="${KIND_IMAGE:-kindest/node:v1.33.4}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.2}"

# Kargo configuration
KARGO_PROJECT="fleet-demo"
KARGO_ADMIN_PASS="${KARGO_ADMIN_PASS:-admin}"
KARGO_IMAGE="${KARGO_IMAGE:-ghcr.io/ytimocin/kargo}"
KARGO_TAG="${KARGO_TAG:-cross-fleet}"

info()  { echo "==> $*"; }
warn()  { echo "WARNING: $*" >&2; }
error() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Image builds
# ---------------------------------------------------------------------------
pull_kubefleet_images() {
    info "Pulling KubeFleet images (tag: ${TAG})..."
    for img in "${HUB_AGENT_IMAGE}" "${MEMBER_AGENT_IMAGE}" "${REFRESH_TOKEN_IMAGE}"; do
        docker pull "${REGISTRY}/${img}:${TAG}" 2>&1 | tail -1
    done
}

pull_kargo_image() {
    info "Pulling Kargo image ${KARGO_IMAGE}:${KARGO_TAG}..."
    docker pull "${KARGO_IMAGE}:${KARGO_TAG}" 2>&1 | tail -3
}

# ---------------------------------------------------------------------------
# Kind cluster management
# ---------------------------------------------------------------------------
create_kind_cluster() {
    local name=$1
    info "Creating Kind cluster: ${name}"
    kind create cluster --name "${name}" --image "${KIND_IMAGE}" --wait 60s 2>&1
}

load_images_to_cluster() {
    local cluster_name=$1
    shift
    for img in "$@"; do
        kind load docker-image "${img}" --name "${cluster_name}" 2>/dev/null || true
    done
}

get_hub_url() {
    local hub_name=$1
    local ip
    ip=$(docker inspect "${hub_name}-control-plane" \
        --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
    echo "https://${ip}:6443"
}

# ---------------------------------------------------------------------------
# cert-manager
# ---------------------------------------------------------------------------
install_cert_manager() {
    local context=$1
    info "Installing cert-manager on ${context}..."
    helm repo add jetstack https://charts.jetstack.io --force-update 2>/dev/null
    helm repo update jetstack 2>/dev/null
    helm install cert-manager jetstack/cert-manager \
        --kube-context "${context}" \
        --namespace cert-manager --create-namespace \
        --version "${CERT_MANAGER_VERSION}" \
        --set crds.enabled=true \
        --wait --timeout=300s 2>&1 | tail -3
}

# ---------------------------------------------------------------------------
# KubeFleet hub agent
# ---------------------------------------------------------------------------
install_hub_agent() {
    local context=$1
    info "Installing hub-agent on ${context}..."
    helm install hub-agent "${ROOT_DIR}/charts-kubefleet/hub-agent/" \
        --kube-context "${context}" \
        --set image.repository="${REGISTRY}/${HUB_AGENT_IMAGE}" \
        --set image.tag="${TAG}" \
        --set namespace=fleet-system \
        --set logVerbosity=5 \
        --set replicaCount=1 \
        --set useCertManager=true \
        --set webhookCertSecretName=fleet-webhook-server-cert \
        --set enableWebhook=true \
        --set enableWorkload=true \
        --set webhookClientConnectionType=service \
        --set forceDeleteWaitTime="1m0s" \
        --set clusterUnhealthyThreshold="3m0s" \
        --set MaxConcurrentClusterPlacement=200 \
        --wait --timeout=300s 2>&1 | tail -3
}

# ---------------------------------------------------------------------------
# KubeFleet member agent
# ---------------------------------------------------------------------------
setup_member_on_hub() {
    local hub_context=$1
    local member_name=$2

    # Create ServiceAccount on hub
    kubectl --context "${hub_context}" create sa \
        "fleet-member-agent-${member_name}" -n fleet-system 2>/dev/null || true

    # Create token Secret on hub
    kubectl --context "${hub_context}" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: fleet-member-agent-${member_name}-sa
  namespace: fleet-system
  annotations:
    kubernetes.io/service-account.name: fleet-member-agent-${member_name}
type: kubernetes.io/service-account-token
EOF

    # Wait for token to be populated
    for _ in $(seq 1 30); do
        local token
        token=$(kubectl --context "${hub_context}" get secret \
            "fleet-member-agent-${member_name}-sa" -n fleet-system \
            -o jsonpath='{.data.token}' 2>/dev/null || echo "")
        if [[ -n "${token}" ]]; then
            echo "${token}" | base64 -d
            return 0
        fi
        sleep 1
    done
    error "Timed out waiting for SA token for ${member_name}"
}

create_hub_kubeconfig_secret_on_member() {
    local member_context=$1
    local token=$2

    kubectl --context "${member_context}" create secret generic hub-kubeconfig-secret \
        --from-literal=token="${token}" 2>/dev/null || \
    kubectl --context "${member_context}" delete secret hub-kubeconfig-secret 2>/dev/null && \
    kubectl --context "${member_context}" create secret generic hub-kubeconfig-secret \
        --from-literal=token="${token}"
}

install_member_agent() {
    local member_context=$1
    local hub_url=$2
    local member_cluster_name=$3

    info "Installing member-agent on ${member_context}..."
    helm install member-agent "${ROOT_DIR}/charts-kubefleet/member-agent/" \
        --kube-context "${member_context}" \
        --set config.hubURL="${hub_url}" \
        --set config.memberClusterName="${member_cluster_name}" \
        --set image.repository="${REGISTRY}/${MEMBER_AGENT_IMAGE}" \
        --set image.tag="${TAG}" \
        --set refreshtoken.repository="${REGISTRY}/${REFRESH_TOKEN_IMAGE}" \
        --set refreshtoken.tag="${TAG}" \
        --set namespace=fleet-system \
        --set logVerbosity=5 \
        --set workApplierRequeueRateLimiterMaxSlowBackoffDelaySeconds=30 \
        --set workApplierRequeueRateLimiterMaxFastBackoffDelaySeconds=10 \
        --wait --timeout=300s 2>&1 | tail -3
}

# ---------------------------------------------------------------------------
# Member cluster joining
# ---------------------------------------------------------------------------
join_members() {
    local hub_context=$1
    local hub_idx=$2

    info "Creating MemberCluster resources on ${hub_context}..."
    for m in $(seq 1 "${MEMBERS_PER_HUB}"); do
        local mc_name="kind-hub-${hub_idx}-member-${m}"
        kubectl --context "${hub_context}" apply -f - <<EOF
apiVersion: cluster.kubernetes-fleet.io/v1beta1
kind: MemberCluster
metadata:
  name: ${mc_name}
spec:
  identity:
    name: fleet-member-agent-hub-${hub_idx}-member-${m}
    kind: ServiceAccount
    namespace: fleet-system
  heartbeatPeriodSeconds: 15
EOF
    done

    # Wait for all members to join
    for m in $(seq 1 "${MEMBERS_PER_HUB}"); do
        local mc_name="kind-hub-${hub_idx}-member-${m}"
        echo -n "  Waiting for ${mc_name} to join..."
        for attempt in $(seq 1 60); do
            local joined
            joined=$(kubectl --context "${hub_context}" get membercluster "${mc_name}" \
                -o jsonpath='{.status.conditions[?(@.type=="Joined")].status}' 2>/dev/null || echo "")
            if [[ "${joined}" == "True" ]]; then
                echo " OK"
                break
            fi
            if [[ "${attempt}" -eq 60 ]]; then
                echo " TIMEOUT"
                warn "Member ${mc_name} did not join within 5 minutes"
            fi
            sleep 5
        done
    done
}

# ---------------------------------------------------------------------------
# Kargo
# ---------------------------------------------------------------------------
install_kargo() {
    local context=$1
    info "Installing Kargo on ${context}..."

    # Pre-load published image into the Kind node so the pod starts fast
    # and works offline after the first pull.
    kind load docker-image "${KARGO_IMAGE}:${KARGO_TAG}" --name hub-1 2>/dev/null || true

    # Generate bcrypt hash for admin password
    local pass_hash signing_key
    pass_hash=$(htpasswd -bnBC 10 "" "${KARGO_ADMIN_PASS}" | tr -d ':\n')
    signing_key=$(openssl rand -base64 48 | tr -d "=+/" | head -c 32)

    helm install kargo "${ROOT_DIR}/charts-kargo/" \
        --kube-context "${context}" \
        --namespace kargo --create-namespace \
        --set image.repository="${KARGO_IMAGE}" \
        --set image.tag="${KARGO_TAG}" \
        --set controller.kubefleet.integrationEnabled=true \
        --set api.adminAccount.enabled=true \
        --set "api.adminAccount.passwordHash=${pass_hash}" \
        --set "api.adminAccount.tokenSigningKey=${signing_key}" \
        --wait --timeout=300s 2>&1 | tail -5
}

create_kargo_project() {
    local context=$1
    info "Creating Kargo project: ${KARGO_PROJECT}"
    kubectl --context "${context}" apply -f - <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: ${KARGO_PROJECT}
EOF

    # Wait for project namespace to be created
    echo -n "  Waiting for project namespace..."
    for _ in $(seq 1 30); do
        if kubectl --context "${context}" get namespace "${KARGO_PROJECT}" &>/dev/null; then
            echo " OK"
            return 0
        fi
        sleep 2
    done
    echo " TIMEOUT"
    warn "Project namespace ${KARGO_PROJECT} was not created in time"
}

create_credential_secrets() {
    local kargo_context=$1

    for hub_idx in $(seq 2 "${NUM_HUBS}"); do
        local secret_name="fleet-hub-${hub_idx}"
        info "Creating credential secret: ${secret_name}"

        # Use --internal to get Docker-network-routable addresses
        kind get kubeconfig --name "hub-${hub_idx}" --internal > "/tmp/hub-${hub_idx}.kubeconfig"

        kubectl --context "${kargo_context}" create secret generic "${secret_name}" \
            --namespace="${KARGO_PROJECT}" \
            --from-file=kubeconfig="/tmp/hub-${hub_idx}.kubeconfig" 2>/dev/null || true

        kubectl --context "${kargo_context}" label secret "${secret_name}" \
            --namespace="${KARGO_PROJECT}" \
            kargo.akuity.io/cred-type=fleet --overwrite

        rm -f "/tmp/hub-${hub_idx}.kubeconfig"
    done
}

apply_remote_hub_rbac() {
    # Hub-1 RBAC is handled by Kargo Helm chart (kubefleet.integrationEnabled).
    # Remote hubs need RBAC for the kubeconfig credential (which authenticates
    # as system:masters via Kind's admin kubeconfig).
    for hub_idx in $(seq 2 "${NUM_HUBS}"); do
        local context="kind-hub-${hub_idx}"
        info "Applying CRP RBAC on ${context}..."
        kubectl --context "${context}" apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kargo-fleet-integration
rules:
- apiGroups: ["placement.kubernetes-fleet.io"]
  resources: ["clusterresourceplacements"]
  verbs: ["create","get","list","patch","update","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kargo-fleet-integration
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kargo-fleet-integration
subjects:
- kind: Group
  name: system:masters
  apiGroup: rbac.authorization.k8s.io
EOF
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local total_clusters=$(( NUM_HUBS + NUM_HUBS * MEMBERS_PER_HUB ))
    info "Setting up ${NUM_HUBS} hub(s) with ${MEMBERS_PER_HUB} member(s) each (${total_clusters} Kind clusters total)"
    echo ""

    # Build images
    pull_kubefleet_images
    pull_kargo_image
    echo ""

    # Set up each fleet (hub + members)
    for hub_idx in $(seq 1 "${NUM_HUBS}"); do
        local hub_name="hub-${hub_idx}"
        local hub_context="kind-${hub_name}"

        info "--- Fleet ${hub_idx}/${NUM_HUBS}: ${hub_name} ---"

        # Create and configure hub
        create_kind_cluster "${hub_name}"
        load_images_to_cluster "${hub_name}" \
            "${REGISTRY}/${HUB_AGENT_IMAGE}:${TAG}" \
            "${REGISTRY}/${MEMBER_AGENT_IMAGE}:${TAG}" \
            "${REGISTRY}/${REFRESH_TOKEN_IMAGE}:${TAG}"
        install_cert_manager "${hub_context}"
        install_hub_agent "${hub_context}"

        # Ensure fleet-system namespace exists on hub
        kubectl --context "${hub_context}" create namespace fleet-system 2>/dev/null || true

        local hub_url
        hub_url=$(get_hub_url "${hub_name}")
        info "Hub ${hub_name} API: ${hub_url}"

        # Create and configure members
        for m in $(seq 1 "${MEMBERS_PER_HUB}"); do
            local member_name="hub-${hub_idx}-member-${m}"
            local member_context="kind-${member_name}"

            create_kind_cluster "${member_name}"
            load_images_to_cluster "${member_name}" \
                "${REGISTRY}/${MEMBER_AGENT_IMAGE}:${TAG}" \
                "${REGISTRY}/${REFRESH_TOKEN_IMAGE}:${TAG}"

            # Set up member identity on hub and token on member
            local token
            token=$(setup_member_on_hub "${hub_context}" "${member_name}")
            create_hub_kubeconfig_secret_on_member "${member_context}" "${token}"

            install_member_agent "${member_context}" "${hub_url}" "kind-${member_name}"
        done

        # Join all members
        join_members "${hub_context}" "${hub_idx}"
        echo ""
    done

    # Install Kargo on hub-1
    info "--- Kargo Installation on hub-1 ---"
    install_kargo "kind-hub-1"
    create_kargo_project "kind-hub-1"

    # Create credential secrets for remote hubs
    if [[ "${NUM_HUBS}" -gt 1 ]]; then
        info "--- Cross-Fleet Credential Secrets ---"
        create_credential_secrets "kind-hub-1"
        apply_remote_hub_rbac
    fi

    echo ""
    info "========================================="
    info "Multi-fleet setup complete!"
    info "========================================="
    echo ""
    echo "Fleets:"
    for hub_idx in $(seq 1 "${NUM_HUBS}"); do
        echo "  hub-${hub_idx}: $(get_hub_url "hub-${hub_idx}")"
        for m in $(seq 1 "${MEMBERS_PER_HUB}"); do
            echo "    - kind-hub-${hub_idx}-member-${m}"
        done
    done
    echo ""
    echo "Kargo installed on: kind-hub-1"
    echo "Kargo project: ${KARGO_PROJECT}"
    if [[ "${NUM_HUBS}" -gt 1 ]]; then
        echo "Credential secrets:"
        for hub_idx in $(seq 2 "${NUM_HUBS}"); do
            echo "  fleet-hub-${hub_idx} -> hub-${hub_idx}"
        done
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Generate pipeline:  ./hack/generate-cross-fleet-pipeline.sh ${NUM_HUBS}"
    echo "  2. Apply pipeline:     kubectl --context kind-hub-1 apply -f docs/multi-hub-pipeline.yaml"
    echo "  3. Port-forward UI:    kubectl --context kind-hub-1 -n kargo port-forward svc/kargo-api 31081:443 &"
    echo "  4. Open UI:            https://localhost:31081  (admin / ${KARGO_ADMIN_PASS})"
    echo "  5. Teardown:           ./hack/teardown-multi-fleet.sh ${NUM_HUBS} ${MEMBERS_PER_HUB}"
}

main
