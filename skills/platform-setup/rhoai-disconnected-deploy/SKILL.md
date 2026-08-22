---
name: rhoai-disconnected-deploy
description: "End-to-end guide for deploying Red Hat OpenShift AI in disconnected (air-gapped) environments via CLI, Console, or GitOps — covers image mirroring, operator installation, and DSC creation."
version: 2.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Disconnected, Air-gapped, GitOps, CLI, Console, Mirror, oc-mirror, Deployment]
---

# RHOAI Disconnected Environment Deployment

Deploy Red Hat OpenShift AI in a disconnected (air-gapped) OpenShift cluster. Supports three deployment methods — CLI (`oc`), Console (OperatorHub UI), and GitOps (ArgoCD) — and two network topologies: partially disconnected (bastion with dual access) and fully disconnected (sneakernet/data diode).

## Trigger Conditions

- "Deploy RHOAI in a disconnected environment"
- "How do I set up OpenShift AI in an air-gapped cluster?"
- "Generate the mirror configuration for RHOAI"
- "What images do I need to mirror for OpenShift AI?"
- "Install RHOAI operators offline"
- "Set up RHOAI without internet access"

---

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | cluster_summary | Check RHOAI installation status and DSC state |
| mcp_rhoai | explore_cluster | Inspect platform health, workbenches, model serving |
| mcp_openshift | resources_list | List Namespace, CatalogSource, IDMS resources |
| mcp_argocd | list_applications | Check ArgoCD app state (GitOps path) |
| mcp_argocd | get_application | Inspect individual ArgoCD app health (GitOps path) |

---

## Procedure

### Step 1: Gather Requirements

Ask the user for the following before proceeding:

1. **OCP version** — 4.19 or later (determines catalog index tag)
2. **RHOAI version / channel** — `fast`, `stable`, or `eus` (or a specific version like `3.5.0`)
3. **Private registry URL** — e.g. `myregistry.example.com:5000`
4. **Deployment method** — CLI (`oc` commands), Console (OperatorHub UI), or GitOps (ArgoCD)
5. **DSC components needed** — which DataScienceCluster components to enable (KServe, Workbenches, Pipelines, Ray, ModelRegistry, TrustyAI, etc.)
6. **GPU workloads needed?** — determines whether NFD and the GPU Operator must be mirrored and installed

Store these as variables for use throughout the remaining steps:

- `{OCP_VERSION}` — e.g. `4.19`
- `{CHANNEL}` — e.g. `fast`
- `{REGISTRY}` — e.g. `myregistry.example.com:5000`
- `{DEPLOY_METHOD}` — `cli`, `console`, or `gitops`
- `{GPU_REQUIRED}` — `true` or `false`

---

### Step 2: Generate ImageSetConfiguration

Produce a customized `ImageSetConfiguration` for oc-mirror v2:

```yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v{OCP_VERSION}
      packages:
        - name: rhods-operator
          channels:
            - name: {CHANNEL}
        - name: openshift-cert-manager-operator
          channels:
            - name: stable-v1
        - name: nfd
          channels:
            - name: stable
        - name: kueue-operator
          channels:
            - name: stable-v1.4
        - name: leader-worker-set
          channels:
            - name: stable-v1.0
        - name: job-set
          channels:
            - name: stable-v1.0
        - name: openshift-custom-metrics-autoscaler-operator
          channels:
            - name: stable
        - name: servicemeshoperator3
          channels:
            - name: stable
        - name: rhcl-operator
          channels:
            - name: stable
        - name: openshift-external-secrets-operator
          channels:
            - name: stable-v1
    - catalog: registry.redhat.io/redhat/certified-operator-index:v{OCP_VERSION}
      packages:
        - name: gpu-operator-certified
          channels:
            - name: stable
  additionalImages:
    # ── IMPORTANT ──────────────────────────────────────────────────────
    # Get the COMPLETE additional-images list from:
    #   https://github.com/red-hat-data-services/rhoai-disconnected-install-helper
    # Navigate to the file matching your RHOAI version (e.g. rhoai-3.5.md).
    # That list is auto-updated by Red Hat and includes notebook images,
    # runtime images, and model serving images that are NOT in the
    # operator catalog.
    # ───────────────────────────────────────────────────────────────────
    #
    # Example entries (these alone are NOT sufficient):
    - name: registry.redhat.io/rhaiis/vllm-cuda-rhel9:latest
    - name: registry.redhat.io/rhoai/odh-minimal-notebook-container-rhel9:latest
    - name: registry.redhat.io/rhoai/odh-pytorch-notebook-container-rhel9:latest
    - name: registry.redhat.io/rhoai/odh-codeserver-notebook-container-rhel9:latest
```

Instruct the user: "You **must** merge the full `additionalImages` list from the [rhoai-disconnected-install-helper](https://github.com/red-hat-data-services/rhoai-disconnected-install-helper) for your specific RHOAI version. The operator catalog does NOT contain notebook images, workbench images, or model serving runtime images — those are only distributed as `additionalImages`."

If `{GPU_REQUIRED}` is `false`, remove the `certified-operator-index` section and the `gpu-operator-certified` package.

---

### Step 3: Mirror Images (oc-mirror v2)

Present the appropriate mirroring workflow based on network topology.

#### Path A — Partially Disconnected (bastion has access to both networks)

```bash
oc mirror -c imageset-config.yaml docker://{REGISTRY} --v2
```

This directly pulls from Red Hat registries and pushes to the private registry in a single step.

#### Path B — Fully Disconnected (sneakernet / data diode)

**On the connected side** (internet-facing workstation):

```bash
oc mirror -c imageset-config.yaml file://./mirror-rhoai --v2
```

This downloads all images to the `./mirror-rhoai` directory on local disk.

**Transfer** the `./mirror-rhoai` directory to the disconnected network via approved media (USB, data diode, etc.).

**On the disconnected side** (with access to the private registry):

```bash
oc mirror -c imageset-config.yaml --from file://./mirror-rhoai docker://{REGISTRY} --v2
```

This uploads the previously-downloaded images into the private registry.

---

### Step 4: Apply Cluster Resources

oc-mirror v2 generates cluster resources in a results directory. These include:

| Resource | Purpose |
|----------|---------|
| **IDMS** (ImageDigestMirrorSet) | Tells CRI-O to redirect image pulls by digest to the mirror |
| **ITMS** (ImageTagMirrorSet) | Tells CRI-O to redirect image pulls by tag to the mirror |
| **CatalogSource** | Points OLM at the mirrored operator index |

> **Note:** oc-mirror v2 generates IDMS/ITMS, NOT the deprecated ICSP (ImageContentSourcePolicy). Do not apply ICSP resources.

Apply the generated resources:

```bash
oc apply -f ./oc-mirror-workspace/results-*/
```

Verify the CatalogSource is ready:

```bash
oc get catalogsource -n openshift-marketplace
```

The output should show a CatalogSource (typically named `cs-redhat-operator-index` and, if GPU is included, `cs-certified-operator-index`) with `READY` status. Record these names — they are needed in Step 7 and Step 8 for Subscription `source` fields.

---

### Step 5: Disable Default OperatorHub Sources

Disable the default catalog sources so OLM only resolves packages from the mirrored catalogs:

```bash
oc patch operatorhub cluster --type json \
  -p '[{"op":"add","path":"/spec/disableAllDefaultSources","value":true}]'
```

Verify:

```bash
oc get catalogsource -n openshift-marketplace
```

Only the mirrored CatalogSource(s) from Step 4 should remain.

---

### Step 6: Configure Pull Secret for Private Registry

The cluster's global pull secret must include credentials for the private registry. Generate and apply the updated pull secret:

```bash
# Extract the current pull secret
oc get secret/pull-secret -n openshift-config --template='{{index .data ".dockerconfigjson" | base64decode}}' > current-pull-secret.json

# Add the private registry credentials (use podman or a JSON editor)
podman login --authfile current-pull-secret.json {REGISTRY}

# Apply the updated pull secret
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=current-pull-secret.json
```

> **Warning:** Updating the global pull secret triggers a rolling reboot of all nodes managed by the Machine Config Operator. Plan for this maintenance window.

If the private registry uses a self-signed or internal CA certificate, create a ConfigMap with the CA bundle and patch the image configuration:

```bash
oc create configmap registry-ca \
  -n openshift-config \
  --from-file={REGISTRY_HOSTNAME}..{PORT}=/path/to/ca-bundle.crt

oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-ca"}}}' --type=merge
```

---

### Step 7: Install Dependency Operators

Install operators in the following order. Order matters because later operators depend on earlier ones.

#### Operator Installation Order

| # | Operator | Channel | Namespace | Required? |
|---|----------|---------|-----------|-----------|
| 1 | openshift-cert-manager-operator | stable-v1 | redhat-ods-operator | Always |
| 2 | servicemeshoperator3 | stable | openshift-operators | Always (KServe dependency) |
| 3 | nfd | stable | openshift-nfd | If GPU workloads |
| 4 | gpu-operator-certified | stable | nvidia-gpu-operator | If GPU workloads |
| 5 | kueue-operator | stable-v1.4 | openshift-operators | If Kueue component enabled |
| 6 | leader-worker-set | stable-v1.0 | openshift-operators | Optional |
| 7 | job-set | stable-v1.0 | openshift-operators | Optional |
| 8 | openshift-external-secrets-operator | stable-v1 | openshift-operators | Optional |
| 9 | openshift-custom-metrics-autoscaler-operator | stable | openshift-operators | Optional |

#### CLI Path (`oc`)

For each operator, generate a Subscription YAML. Example for cert-manager (operator #1):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: redhat-ods-operator
  namespace: redhat-ods-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-cert-manager-operator
  namespace: redhat-ods-operator
spec:
  channel: stable-v1
  installPlanApproval: Automatic
  name: openshift-cert-manager-operator
  source: cs-redhat-operator-index       # ← must match CatalogSource from Step 4
  sourceNamespace: openshift-marketplace
```

For each operator:
- Create the namespace if it doesn't already exist
- Create an OperatorGroup if the namespace doesn't have one
- Create the Subscription with `source` pointing to the mirrored CatalogSource name from Step 4
- Wait for the operator to reach `Succeeded` phase before proceeding to the next:

```bash
oc get csv -n {NAMESPACE} --watch
```

For the GPU Operator (operator #4), use `source: cs-certified-operator-index` since it comes from the certified catalog.

#### Console Path (OperatorHub UI)

For each operator in order:
1. Navigate to **Operators → OperatorHub**
2. Search for the operator name
3. Select the operator and choose the channel listed in the table above
4. Set the installation namespace as listed in the table
5. Set update approval to **Automatic**
6. Click **Install**
7. Wait for the operator to show **Succeeded** in **Operators → Installed Operators** before installing the next one

#### GitOps Path (ArgoCD)

For each operator, generate an ArgoCD Application that wraps the Subscription manifests. Example for cert-manager:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager-operator
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    repoURL: {GIT_REPO_URL}
    targetRevision: main
    path: operators/cert-manager
  destination:
    server: https://kubernetes.default.svc
    namespace: redhat-ods-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Use `argocd.argoproj.io/sync-wave` annotations to enforce installation order. The Git repository should contain the Namespace, OperatorGroup, and Subscription manifests for each operator in the `path` directory.

Default `syncPolicy` to include `dryRun: true` initially — instruct the user to remove it only after reviewing the sync plan.

---

### Step 8: Install RHOAI Operator

#### CLI Path

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: {CHANNEL}
  installPlanApproval: Automatic
  name: rhods-operator
  source: cs-redhat-operator-index       # ← must match CatalogSource from Step 4
  sourceNamespace: openshift-marketplace
```

```bash
oc apply -f rhods-operator-subscription.yaml

# Wait for the operator to install
oc get csv -n redhat-ods-operator --watch
```

#### Console Path

1. Navigate to **Operators → OperatorHub**
2. Search for **Red Hat OpenShift AI**
3. Select the operator and choose channel `{CHANNEL}`
4. Install in namespace **redhat-ods-operator**
5. Set update approval to **Automatic**
6. Click **Install**
7. Wait for status to show **Succeeded**

#### GitOps Path

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoai-operator
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "10"
spec:
  project: default
  source:
    repoURL: {GIT_REPO_URL}
    targetRevision: main
    path: operators/rhoai
  destination:
    server: https://kubernetes.default.svc
    namespace: redhat-ods-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Set the sync-wave higher than all dependency operators to ensure they install first.

---

### Step 9: Create DataScienceCluster

Generate a DSC custom resource based on the user's selected components. All RHOAI 3.5 components are listed below — set each to `Managed` or `Removed` based on the user's requirements from Step 1.

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
        name: knative-serving
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
    feastoperator:
      managementState: Removed
    ogx:
      managementState: Removed
```

Apply the DSC:

```bash
# CLI
oc apply -f datasciencecluster.yaml

# Verify
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'
```

For the GitOps path, include the DSC manifest in the Git repository and create an ArgoCD Application with a sync-wave higher than the RHOAI operator Application.

Wait for the DSC to reach `Ready` phase. This may take several minutes as the operator reconciles all components.

---

### Step 10: Validate

Hand off to the **rhoai-install-validator** skill for comprehensive post-deployment validation.

If the validator skill is not available, perform these manual checks:

```bash
# All operator CSVs should be Succeeded
oc get csv -A | grep -E 'rhods|cert-manager|servicemesh|nfd|gpu|kueue'

# DSC should be Ready
oc get datasciencecluster -o jsonpath='{.items[0].status.phase}'

# Dashboard route should exist
oc get route -n redhat-ods-applications rhods-dashboard

# No ImagePullBackOff pods
oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded | grep -v Completed

# CatalogSource is healthy
oc get catalogsource -n openshift-marketplace
```

---

## Output Format

Present results to the user as:

1. **Generated files** — each YAML block clearly labeled with its purpose and a suggested filename
2. **Command sequence** — numbered list of `oc` commands in execution order
3. **Verification checklist** — table of expected outcomes with pass/fail indicators
4. **Next steps** — what to do after successful deployment (create workbenches, deploy models, etc.)

---

## Safety Constraints

- Never suggest running `oc-mirror` with `--continue-on-error` in production — partial mirrors cause silent failures downstream
- Never skip certificate configuration steps for the private registry — unsigned registries cause `x509: certificate signed by unknown authority` errors that are difficult to diagnose
- Never assume network access is available — every command that contacts a registry must be explicitly placed on the correct side of the air gap
- Always verify mirror completeness before deploying operators — a missing image will cause indefinite `ImagePullBackOff`
- Default sync operations to `dryRun: true` for the GitOps path — let the user review before applying
- Never embed registry credentials in YAML files or Git repositories — use Kubernetes secrets and the global pull secret exclusively
- Never weaken or bypass image signature verification without explicit user acknowledgment

## Disconnected Environment Notes

This IS the disconnected deployment skill. All procedures assume no internet access from the OpenShift cluster. Every image reference, operator catalog, and container runtime dependency must be mirrored to the private registry before any installation step can succeed.

## Related Skills

- **rhoai-install-validator** — Post-deployment validation and health checking
- **rhoai-upgrade** — Upgrading RHOAI in disconnected environments (re-mirror new version images)
- **rhoai-dsc-configure** — Advanced DataScienceCluster component configuration
