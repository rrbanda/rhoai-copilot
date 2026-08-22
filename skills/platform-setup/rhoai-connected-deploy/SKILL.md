---
name: rhoai-connected-deploy
description: End-to-end connected Red Hat OpenShift AI deployment covering CLI, Console, and GitOps installation paths
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms:
  - linux
metadata:
  hermes:
    tags:
      - RHOAI
      - OpenShift AI
      - Installation
      - Connected
      - Deployment
---

# RHOAI Connected Deployment

Deploy Red Hat OpenShift AI on a connected OpenShift cluster using CLI (`oc`), Web Console, or GitOps (ArgoCD) paths.

> **Disconnected clusters:** Use the `rhoai-disconnected-deploy` skill instead.

---

## Phase 1: Prerequisites Check

### Cluster Requirements

| Requirement | Minimum |
|---|---|
| OCP version | 4.19+ |
| Worker nodes (multi-node) | 2 × (8 CPU, 32 GiB RAM) |
| Single-node option | 1 × (32 CPU, 128 GiB RAM) |
| StorageClass | Default with dynamic provisioning |
| Open Data Hub | Must NOT be installed |

### Verification Steps

Use MCP tools to validate the cluster before proceeding:

```bash
# Verify OCP version
oc get clusterversion

# Check worker node capacity
oc get nodes -l node-role.kubernetes.io/worker --no-headers \
  -o custom-columns='NAME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.capacity.memory'

# Confirm a default StorageClass exists
oc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'

# Ensure Open Data Hub is NOT installed
oc get csv -A | grep -i opendatahub && echo "ERROR: ODH found" || echo "OK: No ODH"
```

**MCP tool calls:**

- `mcp_openshift.nodes_top` — confirm node resources meet minimums
- `mcp_openshift.resources_list` (kind: `Subscription`, all namespaces) — confirm no ODH subscriptions
- `mcp_openshift.resources_list` (kind: `StorageClass`) — confirm default SC exists

---

## Phase 2: Install Dependency Operators

> **Order matters.** Install operators in the sequence below. Wait for each CSV to reach `Succeeded` before moving to the next.

### 2.1 cert-manager Operator

<details>
<summary><strong>CLI Path</strong></summary>

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cert-manager-operator
  namespace: cert-manager-operator
spec:
  targetNamespaces:
    - cert-manager-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  channel: stable-v1
  name: openshift-cert-manager-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

```bash
oc apply -f cert-manager-subscription.yaml
oc wait csv -n cert-manager-operator -l operators.coreos.com/openshift-cert-manager-operator.cert-manager-operator --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s
```

</details>

<details>
<summary><strong>Console Path</strong></summary>

1. Navigate to **Operators → OperatorHub**
2. Search for **cert-manager Operator for Red Hat OpenShift**
3. Select channel **stable-v1**
4. Install into namespace **cert-manager-operator** (create if needed)
5. Set Install Plan Approval to **Automatic**
6. Click **Install** and wait for status *Succeeded*

</details>

<details>
<summary><strong>GitOps Path</strong></summary>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: <your-gitops-repo>
    path: operators/cert-manager
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Place the Subscription YAML from the CLI path into `operators/cert-manager/` in your GitOps repo.

</details>

---

### 2.2 ServiceMesh Operator 3

<details>
<summary><strong>CLI Path</strong></summary>

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator3
  namespace: openshift-operators
spec:
  channel: stable
  name: servicemeshoperator3
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

```bash
oc apply -f servicemesh-subscription.yaml
oc wait csv -n openshift-operators -l operators.coreos.com/servicemeshoperator3.openshift-operators --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s
```

</details>

<details>
<summary><strong>Console Path</strong></summary>

1. Navigate to **Operators → OperatorHub**
2. Search for **Red Hat OpenShift Service Mesh 3**
3. Select channel **stable**
4. Install into **All namespaces** (openshift-operators)
5. Set Install Plan Approval to **Automatic**
6. Click **Install** and wait for status *Succeeded*

</details>

<details>
<summary><strong>GitOps Path</strong></summary>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: servicemesh-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: <your-gitops-repo>
    path: operators/servicemesh
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-operators
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

</details>

---

### 2.3 Node Feature Discovery (NFD) Operator — GPU only

> Skip this step if no GPU workloads are planned.

<details>
<summary><strong>CLI Path</strong></summary>

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-nfd
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-nfd
  namespace: openshift-nfd
spec:
  targetNamespaces:
    - openshift-nfd
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: stable
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

```bash
oc apply -f nfd-subscription.yaml
oc wait csv -n openshift-nfd -l operators.coreos.com/nfd.openshift-nfd --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s
```

</details>

<details>
<summary><strong>Console Path</strong></summary>

1. Navigate to **Operators → OperatorHub**
2. Search for **Node Feature Discovery Operator**
3. Select channel **stable**
4. Install into namespace **openshift-nfd** (create if needed)
5. Click **Install** and wait for status *Succeeded*

</details>

<details>
<summary><strong>GitOps Path</strong></summary>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nfd-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: <your-gitops-repo>
    path: operators/nfd
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-nfd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

</details>

---

### 2.4 NVIDIA GPU Operator — GPU only

> Requires NFD Operator to be healthy first. Skip if no GPU workloads are planned.

<details>
<summary><strong>CLI Path</strong></summary>

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nvidia-gpu-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
    - nvidia-gpu-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: stable
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

```bash
oc apply -f gpu-operator-subscription.yaml
oc wait csv -n nvidia-gpu-operator -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
```

</details>

<details>
<summary><strong>Console Path</strong></summary>

1. Navigate to **Operators → OperatorHub**
2. Search for **NVIDIA GPU Operator**
3. Select channel **stable**
4. Install into namespace **nvidia-gpu-operator** (create if needed)
5. Source: **certified-operators**
6. Click **Install** and wait for status *Succeeded*

</details>

<details>
<summary><strong>GitOps Path</strong></summary>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gpu-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: <your-gitops-repo>
    path: operators/gpu
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: nvidia-gpu-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

</details>

---

### 2.5 Kueue Operator

<details>
<summary><strong>CLI Path</strong></summary>

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kueue-operator
  namespace: openshift-operators
spec:
  channel: stable-v1.4
  name: kueue-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

```bash
oc apply -f kueue-subscription.yaml
oc wait csv -n openshift-operators -l operators.coreos.com/kueue-operator.openshift-operators --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s
```

</details>

<details>
<summary><strong>Console Path</strong></summary>

1. Navigate to **Operators → OperatorHub**
2. Search for **Kueue**
3. Select channel **stable-v1.4**
4. Install into **All namespaces** (openshift-operators)
5. Click **Install** and wait for status *Succeeded*

</details>

<details>
<summary><strong>GitOps Path</strong></summary>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kueue-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: <your-gitops-repo>
    path: operators/kueue
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-operators
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

</details>

---

### 2.6 Optional: LWS and JobSet Operators

Required only for llm-d distributed inference or distributed training workloads.

```bash
# LeaderWorkerSet (LWS)
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: lws-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: lws-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# JobSet
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: jobset-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: jobset-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

---

## Phase 3: Install RHOAI Operator

### CLI Path

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable-2.19
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

```bash
oc apply -f rhoai-operator.yaml
oc wait csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
```

### Console Path

1. Navigate to **Operators → OperatorHub**
2. Search for **Red Hat OpenShift AI**
3. Select the latest **stable** channel
4. Install into namespace **redhat-ods-operator** (created automatically)
5. Set Install Plan Approval to **Automatic**
6. Click **Install**
7. Wait for the operator status to show *Succeeded*

### GitOps Path

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoai-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: <your-gitops-repo>
    path: operators/rhoai
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: redhat-ods-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Verify Operator Readiness

```bash
oc get csv -n redhat-ods-operator
# Expected: rhods-operator.x.y.z  Succeeded
```

**MCP tool call:** `mcp_openshift.resources_list` (kind: `ClusterServiceVersion`, namespace: `redhat-ods-operator`) — confirm phase is `Succeeded`.

---

## Phase 4: Create DataScienceCluster

> **Important:** Do NOT create the DSC until the RHOAI operator CSV shows `Succeeded`.

Apply the following DataScienceCluster CR. Set any component to `Removed` if you do not need it.

```yaml
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    dashboard:
      managementState: Managed
    workbenches:
      managementState: Managed
    datasciencepipelines:
      managementState: Managed
    kserve:
      managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: SelfSigned
        managementState: Managed
    ray:
      managementState: Managed
    kueue:
      managementState: Managed
    modelregistry:
      managementState: Managed
    trustyai:
      managementState: Managed
    trainingoperator:
      managementState: Managed
```

```bash
oc apply -f datasciencecluster.yaml

# Wait for DSC to reconcile
oc wait datasciencecluster default-dsc --for=condition=Available --timeout=600s
```

For GitOps, commit the DSC YAML to your repo under `platform/datasciencecluster/` and create an ArgoCD Application targeting it.

---

## Phase 5: Validate

Hand off to the **rhoai-install-validator** skill to run post-install health checks:

- All operator CSVs in `Succeeded` phase
- DSC conditions show `Available=True`
- Dashboard route accessible
- Component pods running in `redhat-ods-applications`

```bash
# Quick manual validation
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
oc get pods -n redhat-ods-applications --field-selector=status.phase!=Running,status.phase!=Succeeded
oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}'
```

**MCP tool calls:**

- `mcp_rhoai.cluster_summary` — full RHOAI health overview
- `mcp_argocd.list_applications` — confirm all ArgoCD apps are synced (GitOps path)

---

## Safety Constraints

1. **Never install RHOAI before dependency operators are healthy** — always confirm each prerequisite CSV is `Succeeded` before proceeding.
2. **Never modify cluster state directly for the GitOps path** — generate YAML manifests only; let ArgoCD handle reconciliation.
3. **Always verify the operator CSV is ready before creating the DSC** — a premature DSC creation will fail silently or enter a degraded state.
4. **Include rollback guidance** — see below.

---

## Rollback

If the installation must be reversed:

```bash
# 1. Delete the DataScienceCluster
oc delete datasciencecluster default-dsc

# 2. Delete the RHOAI operator subscription and CSV
oc delete subscription rhods-operator -n redhat-ods-operator
oc delete csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator

# 3. (Optional) Remove dependency operators in reverse order
# GPU Operator → NFD → Kueue → ServiceMesh → cert-manager
```

For GitOps, delete the corresponding ArgoCD Applications or set them to `pruneOnDelete: true` and remove from the repo.

---

## MCP Tools Used

| Tool | Purpose |
|---|---|
| `mcp_rhoai.cluster_summary` | Overall RHOAI health status |
| `mcp_openshift.resources_list` | Query Namespaces, CatalogSources, Subscriptions, CSVs |
| `mcp_openshift.nodes_top` | Verify node CPU/memory capacity |
| `mcp_argocd.list_applications` | Confirm GitOps sync status |

---

## Disconnected Environment Notes

For disconnected (air-gapped) clusters that cannot reach external registries or the Red Hat operator catalog directly, use the **rhoai-disconnected-deploy** skill instead. That skill covers mirror registry setup, ImageContentSourcePolicy/ImageDigestMirrorSet configuration, and catalog mirroring procedures.
