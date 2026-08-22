---
name: rhoai-disconnected-deploy
description: "End-to-end guide for deploying RHOAI via GitOps in disconnected environments — generates mirror configs, validates pre-flight, diagnoses post-deploy failures."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Disconnected, Air-gapped, GitOps, Mirror, oc-mirror, Deployment]
---

# RHOAI Disconnected GitOps Deployment

Complete guide for deploying Red Hat OpenShift AI in disconnected (air-gapped) environments using this GitOps repository. Operates in 3 modes: pre-deployment guidance, pre-flight validation, and post-deploy diagnosis.

## Trigger Phrases

**Mode 1 — Pre-Deployment Guide:**
- "Deploy RHOAI in disconnected environment"
- "How do I set up RHOAI in an air-gapped cluster?"
- "Generate the mirror configuration for RHOAI"
- "What do I need to mirror for OpenShift AI?"

**Mode 2 — Pre-Flight Validation:**
- "Validate disconnected setup"
- "Are we ready to deploy in disconnected mode?"
- "Check if mirroring is complete"
- "Pre-flight check for disconnected"

**Mode 3 — Post-Deploy Diagnosis:**
- "Why is my disconnected deployment failing?"
- "ImagePullBackOff in disconnected cluster"
- "Operators stuck after mirroring"
- "CatalogSource not ready"

---

## Mode 1: Pre-Deployment Guide

### When to use
User wants to deploy RHOAI from scratch in a disconnected environment and needs step-by-step guidance.

### Procedure

#### Step 1: Gather Deployment Requirements

Ask the user for:
1. **Target OCP version** (4.19, 4.20, etc.) — determines catalog index tag
2. **RHOAI version/channel** (fast, stable, eus, or specific version like 3.5.0)
3. **Private registry URL** (e.g., `myregistry.example.com:5000`)
4. **Internal Git URL** (where this repo is hosted, e.g., `https://gitea.internal/platform/rhoai-deploy-gitops.git`)
5. **Which DSC components to enable** (KServe, Workbenches, Pipelines, Ray, ModelRegistry, etc.)
6. **GPU workloads needed?** (determines if GPU operator + NFD must be mirrored)

#### Step 2: Generate ImageSetConfiguration

Based on the answers, produce a customized `ImageSetConfiguration`:

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
              # Optional version pinning:
              # minVersion: "{VERSION}"
              # maxVersion: "{VERSION}"
        - name: openshift-gitops-operator
          channels:
            - name: latest
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
    # GPU operator (certified-operators index)
    - catalog: registry.redhat.io/redhat/certified-operator-index:v{OCP_VERSION}
      packages:
        - name: gpu-operator-certified
          channels:
            - name: stable
  additionalImages:
    # Workload images from this repo
    - name: registry.redhat.io/openshift4/ose-cli:v4.18
    - name: registry.redhat.io/rhel9/postgresql-15:1
    - name: registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.3.0
    # IMPORTANT: Add platform images from
    # https://github.com/red-hat-data-services/rhoai-disconnected-install-helper
```

**Tell the user**: "You MUST also merge the additionalImages from the official RHOAI disconnected install helper for your version. Get them from: https://github.com/red-hat-data-services/rhoai-disconnected-install-helper"

#### Step 3: Produce Mirror Commands

```bash
# On connected bastion:
# 1. Mirror to disk (for fully air-gapped)
oc mirror -c imageset-config.yaml file://./mirror-rhoai --v2

# 2. Transfer files to disconnected network (sneakernet/diode)

# 3. Upload from disk to private registry
oc mirror -c imageset-config.yaml --from file://./mirror-rhoai docker://{REGISTRY} --v2

# OR for partially-disconnected (bastion has access to both):
oc mirror -c imageset-config.yaml docker://{REGISTRY} --v2
```

#### Step 4: Produce Cluster Setup Commands

```bash
# Apply generated cluster resources (IDMS + CatalogSource)
oc apply -f ./mirror-rhoai/working-dir/cluster-resources/

# Verify CatalogSource is READY
oc get catalogsource -n openshift-marketplace
# Note the CatalogSource name — you need it for configure.sh
```

#### Step 5: Produce configure.sh Command

```bash
./scripts/configure.sh \
  --repo {GIT_URL} \
  --overlay disconnected \
  --catalog-source {CATALOG_NAME} \
  --certified-catalog-source {CERTIFIED_CATALOG_NAME} \
  --registry {REGISTRY} \
  --channel {CHANNEL} \
  --dsc {DSC_PROFILE}
```

Explain what configure.sh does:
- Updates all 12 operator `patch-source.yaml` files to use the mirrored CatalogSource
- Rewrites container image references to use the private registry
- Sets the DSC to air-gapped mode (`nim.airGapped: true`)
- Generates `patch-channel.yaml` files if channels differ from defaults

#### Step 6: Deploy Command

```bash
git add -A && git commit -m "Configure for disconnected cluster" && git push

# Bootstrap ArgoCD
until oc apply -k bootstrap/overlays/disconnected; do sleep 10; done
```

---

## Mode 2: Pre-Flight Validation

### When to use
User has completed mirroring and configure.sh but wants to verify everything is correct BEFORE deploying.

### Procedure

1. Call `mcp_argocd_list_applications` to check if ArgoCD is already running:
   - If no applications exist yet → this is a fresh deployment, skip to step 4
   - If applications exist → this is an existing cluster, validate current state

2. Call `mcp_argocd_get_application` for each operator app to check:
   - Is the `source` field in the Subscription pointing to the mirrored CatalogSource?
   - Is the health `Degraded` with `CatalogSourcesUnhealthy` or `ResolutionFailed`?
   - These indicate the mirror catalog is not configured or not reachable

3. Call `mcp_rhoai_cluster_summary` to verify RHOAI API responsiveness:
   - If it responds → operator is installed and DSC exists
   - If it fails → operator may not be installed yet

4. Check the repo configuration (using knowledge of this repo's structure):
   - Verify `patch-source.yaml` files exist for all operators (12 files)
   - Verify `bootstrap/overlays/disconnected/kustomization.yaml` references the correct overlay
   - Verify `patch-gitops-source.yaml` patches the GitOps operator subscription

5. Produce a pre-flight report:

```
# Pre-Flight Validation Report

## CatalogSource
- Name: {detected or configured}
- Status: {READY / NOT FOUND / TRANSIENT_FAILURE}
- Issue: {if any}

## Operators Configured for Disconnected
| Operator | patch-source.yaml exists | Source value | Correct? |
|----------|-------------------------|-------------|----------|
| rhoai-operator | Yes/No | {value} | Yes/No |
| cert-manager | Yes/No | {value} | Yes/No |
| ... | ... | ... | ... |

## Missing Configuration
{List any issues that will block deployment}

## Ready to Deploy: {YES / NO — fix issues first}
```

---

## Mode 3: Post-Deploy Diagnosis

### When to use
User has deployed but something is failing — operators stuck, pods not starting, images not pulling.

### Procedure

1. Call `mcp_argocd_list_applications` and identify unhealthy apps:
   - `Degraded` with `CatalogSourcesUnhealthy` → CatalogSource problem
   - `Degraded` with `ResolutionFailed` → package not in mirrored catalog
   - `Missing` → application never created (bootstrap issue)
   - `ComparisonError` → Git branch/revision not accessible

2. For each degraded operator, call `mcp_argocd_get_application`:
   - Check `status.conditions` and `status.operationState`
   - Look for specific error messages

3. Call `mcp_rhoai_explore_cluster` to check platform state:
   - Are models failing? (possible runtime image not mirrored)
   - Are workbenches failing? (possible notebook image not mirrored)

4. Apply the diagnosis decision tree:

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| `CatalogSourcesUnhealthy` on operator | CatalogSource pod can't pull mirrored index | Verify: `oc get catalogsource -n openshift-marketplace`, check index image is mirrored |
| `ResolutionFailed` on operator | Package not found in mirrored catalog | Re-run oc-mirror with the missing package added to ImageSetConfiguration |
| `ComparisonError` on all apps | Git repo unreachable from cluster | ArgoCD can't reach internal Git — check network/DNS from `openshift-gitops` namespace |
| DSC `Degraded` but operators `Healthy` | DSC component images not mirrored | Merge additionalImages from rhoai-disconnected-install-helper and re-mirror |
| Specific pod `ImagePullBackOff` | Image not in IDMS mapping | Add image to `additionalImages` in ImageSetConfiguration, re-run oc-mirror |
| Subscription stuck `UpgradePending` | InstallPlan needs approval OR version mismatch | Check `installPlanApproval: Automatic` in Subscription; verify version exists in catalog |
| All operators healthy but no workbenches | Notebook images not mirrored | Mirror notebook images from rhoai-disconnected-install-helper |
| Model serving fails | vLLM/TGI runtime image not mirrored | Add runtime image to additionalImages and re-mirror |

5. For each issue found, produce the specific fix:

```
## Issue: {description}
### Root Cause: {explanation}
### Fix:
1. Add to your ImageSetConfiguration:
   ```yaml
   additionalImages:
     - name: {exact image reference}
   ```
2. Re-run: `oc mirror -c imageset-config.yaml docker://{registry} --v2`
3. After mirroring completes, the pod will auto-heal (IDMS already configured)
```

---

## Repository-Specific Knowledge

### File Locations
- ImageSetConfiguration template: `disconnected/imageset-config-template.yaml`
- Bootstrap overlay: `bootstrap/overlays/disconnected/`
- Operator patch files: `components/operators/{name}/patch-source.yaml`
- Channel patches: `components/operators/{name}/patch-channel.yaml`
- Configure script: `scripts/configure.sh`
- Mirror script: `scripts/mirror-images.sh`
- Full documentation: `docs/disconnected.md`

### Operators Managed (12 total)
| Operator | Default Channel | Catalog |
|----------|----------------|---------|
| rhods-operator (RHOAI) | fast | redhat-operator-index |
| openshift-cert-manager-operator | stable-v1 | redhat-operator-index |
| nfd | stable | redhat-operator-index |
| gpu-operator-certified | stable | certified-operator-index |
| kueue-operator | stable-v1.4 | redhat-operator-index |
| leader-worker-set (LWS) | stable-v1.0 | redhat-operator-index |
| job-set | stable-v1.0 | redhat-operator-index |
| openshift-custom-metrics-autoscaler | stable | redhat-operator-index |
| servicemeshoperator3 | stable | redhat-operator-index |
| rhcl-operator | stable | redhat-operator-index |
| openshift-external-secrets-operator | stable-v1 | redhat-operator-index |
| rhdh (optional) | fast | redhat-operator-index |

### DSC Components (RHOAI 3.5)
| Component | managementState options | Dependencies |
|-----------|------------------------|--------------|
| kserve | Managed/Removed | ServiceMesh, cert-manager |
| dashboard | Managed/Removed | None |
| workbenches | Managed/Removed | None |
| aipipelines | Managed/Removed | None |
| ray | Managed/Removed | None |
| kueue | Managed/Removed | kueue-operator |
| modelregistry | Managed/Removed | None |
| trustyai | Managed/Removed | None |
| mlflowoperator | Managed/Removed | None |
| trainingoperator | Managed/Removed | None |
| feastoperator | Managed/Removed | None |
| ogx | Managed/Removed | None |

### Common Disconnected Pitfalls
1. **Forgetting platform images**: oc-mirror only mirrors operator bundles. Notebook images, Ray images, and model serving runtimes are NOT in the catalog — they must be in `additionalImages`
2. **CatalogSource name mismatch**: oc-mirror generates a name like `cs-redhat-operator-index`. This exact name must be passed to `configure.sh --catalog-source`
3. **Certified vs Red Hat catalogs**: GPU operator is in `certified-operator-index`, all others in `redhat-operator-index`. Two separate catalog names needed.
4. **Channel drift**: Mirrored catalog may have different channel names than public catalog. Use `oc get packagemanifest` to check available channels.
5. **IDMS not applied**: If oc-mirror output IDMS is not applied to the cluster, CRI-O won't redirect pulls to the mirror.
6. **Pull secret incomplete**: Global pull secret must include credentials for the private registry.
7. **oc-mirror v1 vs v2**: RHOAI 3.5 requires v2 (`--v2` flag). v1 is deprecated and may produce incompatible output.
