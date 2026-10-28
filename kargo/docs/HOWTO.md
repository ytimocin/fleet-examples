# How to Run the Kargo + KubeFleet POC

## Prerequisites

Docker, `kubectl`, and `helm` installed. Other tools are auto-installed by the
Makefiles.

## 1. Set up KubeFleet

```bash
cd kubefleet
make setup-clusters        # Creates hub + 3 member Kind clusters, installs agents
make join-members          # Creates MemberCluster resources, waits for Joined=True
```

Verify the fleet is ready:

```bash
kubectl --context kind-hub get membercluster
```

All three should show `Joined` condition as `True`.

## 2. Install Kargo on the hub cluster

The Kargo Tiltfile is configured for `orbstack` by default. To run against the
KubeFleet hub cluster, temporarily update the allowed context:

```bash
cd kargo
sed -i '' "s/allow_k8s_contexts('orbstack')/allow_k8s_contexts('kind-hub')/" Tiltfile
kubectl config use-context kind-hub
make hack-tilt-up
```

Kargo UI: http://localhost:30082 (password: `admin`)

## 3. Grant KubeFleet RBAC to the Kargo controller

```bash
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kargo-controller-kubefleet
rules:
- apiGroups: ["placement.kubernetes-fleet.io"]
  resources: ["clusterresourceplacements"]
  verbs: ["create","get","list","patch","update","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kargo-controller-kubefleet
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kargo-controller-kubefleet
subjects:
- kind: ServiceAccount
  namespace: kargo
  name: kargo-controller
EOF
```

## 4. Build the Kargo CLI

```bash
cd kargo
make build-cli
```

The binary is at `bin/kargo-<os>-<arch>`. Add it to your PATH or use the full
path in the commands below.

## 5. Create a test workload and Kargo pipeline

```bash
kubectl create namespace demo
kubectl create deployment nginx --image=nginx:1.27 -n demo

kubectl apply -f - <<'EOF'
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: fleet-demo
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: nginx
  namespace: fleet-demo
spec:
  subscriptions:
  - image:
      repoURL: nginx
      semverConstraint: ">=1.0.0"
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: production-fleet
  namespace: fleet-demo
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: nginx
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - uses: kubefleet-update
        as: fleet-rollout
        config:
          placements:
          - name: demo-placement
            resourceSelectors:
            - group: ""
              version: v1
              kind: Namespace
              name: demo
            policy:
              placementType: PickAll
EOF
```

## 6. Promote and watch

```bash
# Wait for Freight to appear
kubectl get freight -n fleet-demo -w

# Promote (replace <freight-name> with the actual name)
bin/kargo-$(go env GOOS)-$(go env GOARCH) promote \
  --project fleet-demo --stage production-fleet --freight <freight-name>

# Watch the CRP
kubectl get clusterresourceplacement demo-placement -w

# Watch Stage health
kubectl get stage production-fleet -n fleet-demo -o jsonpath='{.status.health.status}'
```

Or use the Kargo UI at http://localhost:30082 to promote and watch the Stage
turn green.

## What you should see

1. Warehouse detects nginx tags, creates Freight.
2. Promotion runs the `kubefleet-update` step, creates the CRP.
3. KubeFleet schedules the `demo` namespace across all 3 member clusters.
4. Stage shows `Progressing` while clusters converge.
5. Once all clusters report `Available=True`, the Stage becomes `Healthy`.

## Teardown

```bash
cd kargo
make hack-tilt-down                    # Undeploy Kargo from the hub cluster
sed -i '' "s/allow_k8s_contexts('kind-hub')/allow_k8s_contexts('orbstack')/" Tiltfile

cd kubefleet
make clean-e2e-tests                   # Destroys all Kind clusters (hub + members)
```

---

## Multi-Hub Setup (Cross-Fleet Orchestration)

This creates multiple independent KubeFleet fleets and wires them together
with Kargo for cross-fleet promotion orchestration.

### Prerequisites

Same as single-fleet, plus `htpasswd` (from `apache2-utils` or macOS built-in).

### Quick start

```bash
# Create 2 hubs with 2 members each (6 Kind clusters total)
./hack/setup-multi-fleet.sh 2 2

# Generate a cross-fleet pipeline
./hack/generate-cross-fleet-pipeline.sh 2

# Apply the pipeline
kubectl --context kind-hub-1 apply -f docs/multi-hub-pipeline.yaml
```

### Access Kargo

```bash
# Port-forward the Kargo API
kubectl --context kind-hub-1 -n kargo port-forward svc/kargo-api 31081:443 &

# UI: https://localhost:31081 (admin / admin)

# CLI login
kargo login https://localhost:31081 --admin --insecure-skip-tls-verify
```

### Promote and watch

```bash
# Wait for Freight to appear
kubectl --context kind-hub-1 get freight -n fleet-demo -w

# Promote (replace <freight-name> with the actual name)
kargo promote --project fleet-demo --stage hub-1-fleet --freight <freight-name>

# Watch CRPs on each hub
kubectl --context kind-hub-1 get clusterresourceplacement -w
kubectl --context kind-hub-2 get clusterresourceplacement -w

# Watch Stage health
kubectl --context kind-hub-1 get stage -n fleet-demo -w
```

### What you should see

1. Warehouse detects nginx tags, creates Freight.
2. Promotion to `hub-1-fleet` creates a CRP on hub-1 (canary, 1 cluster).
3. Kargo waits until hub-1 fleet is healthy.
4. Promotion to `hub-2-fleet` creates a CRP on hub-2 via credential secret.
5. Kargo waits until hub-2 fleet is healthy.
6. All stages green — cross-fleet promotion complete.

### Scaling up

```bash
# 3 hubs, 3 members each (12 Kind clusters — needs ~8GB RAM)
./hack/setup-multi-fleet.sh 3 3
./hack/generate-cross-fleet-pipeline.sh 3
```

### Multi-hub teardown

```bash
# Must match the numbers used in setup
./hack/teardown-multi-fleet.sh 2 2
```
