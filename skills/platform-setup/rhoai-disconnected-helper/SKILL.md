---
name: rhoai-disconnected-helper
description: "Diagnose disconnected/air-gapped RHOAI environments — mirror config, image source auditing, and CatalogSource health."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Platform Engineer, Disconnected, Air-gapped, Mirror]
---

# RHOAI Disconnected Environment Helper

Diagnoses and validates RHOAI deployments in disconnected (air-gapped) environments by checking mirror configuration, image sources, and CatalogSource health.

## Trigger Phrases

- "Check disconnected setup"
- "Why are images failing to pull?"
- "Validate mirror configuration"
- "CatalogSource is not healthy"
- "ImagePullBackOff in air-gapped cluster"

## Procedure

### Phase 1: Mirror Configuration Audit

1. Call `mcp_openshift_resources_list` with kind=`ImageDigestMirrorSet`:
   - List all IDMS resources and their mirror mappings
   - Verify RHOAI required registries are mapped:
     - `registry.redhat.io` → local mirror
     - `quay.io/modh` → local mirror (for notebook images)
     - `registry.connect.redhat.com` → local mirror (for ISVs)
2. If no IDMS found, check for legacy `ImageContentSourcePolicy`:
   - Call `mcp_openshift_resources_list` with kind=`ImageContentSourcePolicy`
3. Call `mcp_argocd_get_application` for `instance-registry-mirror` if it exists:
   - Verify the GitOps-managed IDMS is synced

### Phase 2: CatalogSource Health

4. Call `mcp_openshift_resources_list` with kind=`CatalogSource` namespace=`openshift-marketplace`:
   - For each CatalogSource, check:
     - `status.connectionState.lastObservedState` should be `READY`
     - If `TRANSIENT_FAILURE`: the mirror registry is unreachable
5. For RHOAI-specific catalog:
   - Look for a custom CatalogSource pointing to the disconnected index image
   - Verify the index image reference uses a mirrored path
6. Call `mcp_argocd_list_applications` and check if any operators show `ResolutionFailed`:
   - This often means the operator index can't resolve dependencies in the mirrored catalog

### Phase 3: Image Pull Validation

7. Call `mcp_openshift_pods_list_in_namespace` for `redhat-ods-applications`:
   - Look for pods in `ImagePullBackOff` or `ErrImagePull` state
8. For each failing pod:
   - Call `mcp_openshift_pods_get` to see the image reference
   - Check if the image uses a digest (required for mirroring) vs tag
   - Verify the image is in the IDMS mapping
9. Call `mcp_openshift_events_list` with namespace=`redhat-ods-applications` filtering for image pull events

### Phase 4: Operator Source Patching

10. Call `mcp_argocd_get_application` for each operator that has `patch-source.yaml`:
    - Verify the Subscription `source` field points to the disconnected CatalogSource
    - Verify the `sourceNamespace` matches

## Output Format

```
# Disconnected Environment Diagnostic — {timestamp}

## Overall: {HEALTHY | DEGRADED | BROKEN}

## Mirror Configuration
| Source Registry | Mirror | IDMS/ICSP | Status |
|-----------------|--------|-----------|--------|
| registry.redhat.io | {mirror} | {resource name} | ✓/✗ |
| quay.io/modh | {mirror} | {resource name} | ✓/✗ |
| ... | ... | ... | ... |

**Missing Mappings**: {list of registries that should be mirrored but aren't}

## CatalogSource Health
| CatalogSource | State | Index Image | Mirror? |
|---------------|-------|-------------|---------|
| {name} | READY/TRANSIENT_FAILURE | {image ref} | ✓/✗ |

## Image Pull Issues
| Namespace | Pod | Image | Error | Fix |
|-----------|-----|-------|-------|-----|
| {ns} | {pod} | {image} | ImagePullBackOff | Add to IDMS |

## Operator Source Configuration
| Operator | Source | Correct? | Issue |
|----------|--------|----------|-------|
| rhoai-operator | {catalog name} | ✓/✗ | {detail} |
| gpu-operator | {catalog name} | ✓/✗ | {detail} |

## Recommendations
1. {Prioritized fix actions}
```

## Domain Knowledge

- RHOAI in disconnected mode requires ALL images to be mirrored, including:
  - Operator bundle images from `registry.redhat.io/rhoai`
  - Notebook images from `quay.io/modh`
  - Runtime images for KServe (vLLM, TGI, etc.)
  - Model mesh sidecar images
- The `imageset-config-template.yaml` in this repo defines what to mirror
- `patch-source.yaml` files in each operator's directory override the CatalogSource
- If an operator shows `Degraded` with `constraints not satisfiable`, the mirrored catalog may be missing dependency operators
- Common fix: re-run `oc mirror` with updated `ImageSetConfiguration` then update IDMS
