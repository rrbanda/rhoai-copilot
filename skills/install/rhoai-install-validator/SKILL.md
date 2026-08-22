---
name: rhoai-install-validator
description: "Pre/post install validation checklist for RHOAI — verifies operator health, CRDs, namespace readiness, and DSC prerequisites."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Platform Engineer, Installation, Validation]
---

# RHOAI Installation Validator

Validates that a Red Hat OpenShift AI installation deployed via GitOps is complete, healthy, and properly configured.

## Trigger Phrases

- "Validate my RHOAI installation"
- "Is OpenShift AI installed correctly?"
- "Pre-install readiness check"
- "Post-install validation"

## Procedure

### Phase 1: Pre-Install Readiness

1. Call `mcp_openshift_resources_list` with kind=`Namespace` to verify required namespaces:
   - `redhat-ods-operator` (RHOAI operator namespace)
   - `redhat-ods-applications` (RHOAI applications namespace)
   - `redhat-ods-monitoring` (RHOAI monitoring namespace)
   - `istio-system` or `redhat-ods-applications-auth-provider` (ServiceMesh)
2. Call `mcp_openshift_resources_list` with kind=`CatalogSource` namespace=`openshift-marketplace`:
   - Verify `redhat-operators` or disconnected mirror catalog exists and is READY
3. Call `mcp_argocd_list_applications` and check prerequisite operators:
   - cert-manager: must be Healthy before RHOAI operator install
   - servicemesh: required for KServe
   - nfd + gpu-operator: required for GPU workloads

### Phase 2: Operator Installation Validation

4. Call `mcp_argocd_get_application` for `operator-rhoai-operator`:
   - Verify sync status is `Synced`
   - Verify health status is `Healthy`
   - If `Degraded`: check for `ResolutionFailed` (missing CatalogSource) or `ConstraintsNotSatisfiable`
5. Call `mcp_openshift_resources_get` for the RHOAI Subscription:
   - Verify `currentCSV` is set and matches expected version
   - Verify `installPlanApproval` matches policy (Manual for prod, Automatic for dev)

### Phase 3: DSC Configuration Validation

6. Call `mcp_rhoai_cluster_summary` to get current DSC status
7. Call `mcp_argocd_get_application_resource_tree` for the DSC application:
   - Verify expected components are present and not `Removed`:
     - KServe (model serving)
     - Dashboard (UI)
     - Workbenches (notebooks)
     - DataSciencePipelines (pipelines)
     - Ray (distributed training)
     - ModelMeshServing (multi-model serving)
     - Kueue (job queuing)
8. For each enabled component, verify its managed resources exist

### Phase 4: Connectivity & Access Validation

9. Call `mcp_rhoai_list_data_science_projects` to verify API responsiveness
10. Call `mcp_openshift_resources_list` with kind=`Route` namespace=`redhat-ods-applications`:
    - Verify `rhods-dashboard` route exists and has a host

## Output Format

```
# RHOAI Installation Validation Report — {timestamp}

## Overall: {PASS ✓ | PARTIAL ⚠ | FAIL ✗}

## Pre-Install Readiness
| Check | Status | Detail |
|-------|--------|--------|
| Required namespaces | ✓/✗ | {list present/missing} |
| CatalogSource | ✓/✗ | {name, state} |
| Prerequisite operators | ✓/✗ | {count healthy}/{count required} |

## Operator Installation
| Check | Status | Detail |
|-------|--------|--------|
| RHOAI operator synced | ✓/✗ | {sync status} |
| RHOAI operator healthy | ✓/✗ | {health status} |
| Subscription active | ✓/✗ | CSV: {version} |
| InstallPlan approved | ✓/✗ | {approval mode} |

## DSC Configuration
| Component | Managed | Status | Resources |
|-----------|---------|--------|-----------|
| KServe | ✓/✗ | {status} | {count} |
| Dashboard | ✓/✗ | {status} | {count} |
| Workbenches | ✓/✗ | {status} | {count} |
| ... | ... | ... | ... |

## Connectivity
| Endpoint | Status | URL |
|----------|--------|-----|
| Dashboard | ✓/✗ | {route URL} |
| API | ✓/✗ | {response time} |

## Issues Found
{Numbered list of issues with severity and recommended fix}

## Next Steps
{Prioritized actions to complete or fix installation}
```

## Domain Knowledge

- RHOAI 2.x uses `DataScienceCluster` CR; RHOAI 1.x used `KfDef` — this skill targets 2.x+
- Disconnected environments need `ImageDigestMirrorSet` or `ImageContentSourcePolicy`
- If CatalogSource shows `TRANSIENT_FAILURE`, the mirror registry is likely unreachable
- ServiceMesh version compatibility: RHOAI 2.16+ requires OSSM 2.6+ or ServiceMesh 3.0
- GPU operator requires NFD to label GPU nodes before it can schedule daemonsets
