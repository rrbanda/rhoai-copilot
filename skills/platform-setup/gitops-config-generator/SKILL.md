---
name: gitops-config-generator
description: "Generate Kustomize patches for DSC and operator configuration changes — enables GitOps-driven component management."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Platform Engineer, GitOps, Kustomize, Configuration]
---

# GitOps Configuration Generator

Generates Kustomize patches and overlays for RHOAI DSC configuration changes, enabling GitOps-driven component management through ArgoCD.

## Trigger Phrases

- "Enable component X"
- "Generate config for enabling KServe"
- "Create a patch to add ModelMesh"
- "How do I enable distributed training via GitOps?"
- "Generate overlay for production DSC"

## Procedure

### Phase 1: Understand Current State

1. Call `mcp_rhoai_cluster_summary` to see current DSC configuration
2. Call `mcp_argocd_get_application` for the DSC application to identify:
   - Git repository URL
   - Target revision/branch
   - Path within repo (e.g., `components/instances/rhoai-instance/overlays/dev`)
3. Identify what the user wants to change (component to enable/disable/configure)

### Phase 2: Determine Required Changes

4. Map the requested change to the DSC spec structure:

| Component | DSC Path | Dependencies |
|-----------|----------|--------------|
| KServe | `.spec.components.kserve.managementState` | ServiceMesh, cert-manager |
| ModelMesh | `.spec.components.modelMeshServing.managementState` | — |
| Dashboard | `.spec.components.dashboard.managementState` | — |
| Workbenches | `.spec.components.workbenches.managementState` | — |
| DataSciencePipelines | `.spec.components.datasciencepipelines.managementState` | — |
| Ray | `.spec.components.ray.managementState` | — |
| Kueue | `.spec.components.kueue.managementState` | — |
| TrustyAI | `.spec.components.trustyai.managementState` | — |
| ModelRegistry | `.spec.components.modelregistry.managementState` | — |

Valid values: `Managed`, `Removed`, `Unmanaged`

5. Check prerequisites: if enabling KServe, verify ServiceMesh operator is healthy

### Phase 3: Generate Kustomize Patch

6. Generate the appropriate patch file content based on the change type:

**For enabling a component:**
```yaml
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    <component>:
      managementState: Managed
```

**For configuring serving runtime defaults:**
```yaml
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    kserve:
      managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: SelfSigned
        managementState: Managed
```

7. Generate the kustomization.yaml entry to include the patch:
```yaml
patches:
  - path: patch-enable-<component>.yaml
    target:
      kind: DataScienceCluster
      name: default-dsc
```

### Phase 4: Provide Implementation Instructions

8. Output the complete file(s) to create
9. Explain how to apply via GitOps:
   - Create patch file in the correct overlay directory
   - Update `kustomization.yaml` to reference it
   - Commit and push to trigger ArgoCD sync
10. Warn about any prerequisites or ordering requirements

## Output Format

```
# GitOps Configuration Change: {description}

## Current State
- Component: {component name}
- Current managementState: {Managed/Removed/Unmanaged}
- Dependencies satisfied: {yes/no}

## Generated Files

### File: `components/instances/rhoai-instance/overlays/{env}/patch-{description}.yaml`
```yaml
{generated patch content}
```

### Update: `components/instances/rhoai-instance/overlays/{env}/kustomization.yaml`
Add to patches:
```yaml
  - path: patch-{description}.yaml
    target:
      kind: DataScienceCluster
      name: default-dsc
```

## Apply via GitOps
1. Create the patch file at the path shown above
2. Update kustomization.yaml to include the patch
3. Commit: `git commit -m "feat(dsc): enable {component}"`
4. Push to trigger ArgoCD sync
5. Monitor: `hermes ask "Check DSC component status for {component}"`

## Prerequisites
{List any operators/components that must be healthy first}

## Rollback
To revert, change `managementState` to `Removed` and push again.
```

## Domain Knowledge

- DSC patches must target `kind: DataScienceCluster` with `name: default-dsc`
- The overlay structure in this repo: `base/` has the core DSC, `overlays/{env}/` has env-specific patches
- Common pattern: `patch-airgapped.yaml` overrides registries for disconnected environments
- KServe enabling requires: ServiceMesh operator healthy + cert-manager healthy
- Components set to `Removed` will have their operands deleted from the cluster
- `Unmanaged` means RHOAI won't reconcile the component — useful for custom configurations
- Changes to DSC are reconciled by the RHOAI operator controller — not instant, typically 2-5 minutes
