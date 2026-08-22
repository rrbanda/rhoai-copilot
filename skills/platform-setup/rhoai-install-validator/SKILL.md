---
name: rhoai-install-validator
description: "Pre/post install validation checklist for RHOAI — verifies operator health, CRDs, namespace readiness, and DSC prerequisites across both GitOps and direct deployment methods."
version: 2.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Platform Engineer, Installation, Validation, Disconnected]
---

# RHOAI Installation Validator

Validates that a Red Hat OpenShift AI installation is complete, healthy, and properly configured. Supports both ArgoCD-managed (GitOps) and direct Kubernetes deployments, including disconnected environments.

## Trigger Phrases

- "Validate my RHOAI installation"
- "Is OpenShift AI installed correctly?"
- "Pre-install readiness check"
- "Post-install validation"
- "Check RHOAI health"

## Procedure

### Phase 0: Detect Deployment Method

1. Call `mcp_argocd_list_applications`:
   - **If ArgoCD responds with applications**: set validation mode to `gitops` — use ArgoCD-based validation (Phase 2a, 3a)
   - **If ArgoCD fails, times out, or returns empty**: set validation mode to `direct` — use direct Kubernetes resource validation (Phase 2b, 3b)
2. Report detected mode to user before proceeding

### Phase 1: Pre-Install Readiness

3. Call `mcp_openshift_resources_list` with kind=`Namespace` to verify required namespaces:
   - `redhat-ods-operator` (RHOAI operator namespace)
   - `redhat-ods-applications` (RHOAI applications namespace)
   - `redhat-ods-monitoring` (RHOAI monitoring namespace)
   - `istio-system` or `redhat-ods-applications-auth-provider` (ServiceMesh)
4. Call `mcp_openshift_resources_list` with kind=`CatalogSource` namespace=`openshift-marketplace`:
   - Verify `redhat-operators` or disconnected mirror catalog exists and is READY
5. Check prerequisite operators:
   - **If gitops mode**: Call `mcp_argocd_list_applications` and verify:
     - cert-manager: must be Healthy before RHOAI operator install
     - servicemesh: required for KServe
     - nfd + gpu-operator: required for GPU workloads
   - **If direct mode**: Call `mcp_openshift_resources_list` with kind=`Subscription` namespace=`openshift-operators` and verify subscriptions exist for:
     - `openshift-cert-manager-operator`
     - `servicemeshoperator`
     - `nfd` and `gpu-operator-certified` (if GPU workloads planned)

### Phase 2a: Operator Installation Validation (GitOps Mode)

6. Call `mcp_argocd_get_application` for `operator-rhoai-operator`:
   - Verify sync status is `Synced`
   - Verify health status is `Healthy`
   - If `Degraded`: check for `ResolutionFailed` (missing CatalogSource) or `ConstraintsNotSatisfiable`
7. Call `mcp_openshift_resources_get` for the RHOAI Subscription:
   - Verify `currentCSV` is set and matches expected version
   - Verify `installPlanApproval` matches policy (Manual for prod, Automatic for dev)

### Phase 2b: Operator Installation Validation (Direct Mode)

6. Call `mcp_openshift_resources_list` with kind=`Subscription` namespace=`redhat-ods-operator`:
   - Verify RHOAI subscription exists
   - Check `status.currentCSV` is populated
   - Check `status.state` is `AtLatestKnown`
7. Call `mcp_openshift_resources_list` with kind=`ClusterServiceVersion` namespace=`redhat-ods-operator`:
   - Find the RHOAI CSV (name contains `rhods-operator`)
   - Verify `status.phase` is `Succeeded`
   - If `Failed` or `Pending`: check `status.reason` for resolution errors
8. Call `mcp_openshift_resources_list` with kind=`InstallPlan` namespace=`redhat-ods-operator`:
   - Verify install plan is approved and complete

### Phase 3a: DSC Configuration Validation (GitOps Mode)

9. Call `mcp_rhoai_cluster_summary` to get current DSC status
10. Call `mcp_argocd_get_application_resource_tree` for the DSC application:
    - Verify expected components are present and not `Removed`:
      - KServe (model serving)
      - Dashboard (UI)
      - Workbenches (notebooks)
      - DataSciencePipelines (pipelines)
      - Ray (distributed training)
      - ModelMeshServing (multi-model serving)
      - Kueue (job queuing)
      - TrainingOperator (distributed training jobs)
      - ModelRegistry (model catalog)
11. For each enabled component, verify its managed resources exist

### Phase 3b: DSC Configuration Validation (Direct Mode)

9. Call `mcp_openshift_resources_list` with kind=`DataScienceCluster`:
   - Verify a DSC resource exists (typically named `default-dsc`)
   - Check `status.phase` is `Ready`
   - Check `status.conditions` for any degraded components
10. Call `mcp_rhoai_cluster_summary` to get detailed component status
11. For each component in the DSC spec, verify:
    - If `managementState: Managed` → corresponding pods are running in `redhat-ods-applications`
    - If any component shows errors in status conditions, report them

### Phase 4: Disconnected Environment Checks

12. Call `mcp_openshift_resources_list` with kind=`ImageDigestMirrorSet`:
    - Verify IDMS resources exist that cover RHOAI registries
    - Check mappings include `registry.redhat.io`, `quay.io/modh`, `registry.connect.redhat.com`
13. Call `mcp_openshift_resources_list` with kind=`ImageTagMirrorSet`:
    - Verify ITMS resources exist (oc-mirror v2 generates both IDMS and ITMS)
14. Call `mcp_openshift_resources_list` with kind=`CatalogSource` namespace=`openshift-marketplace`:
    - Verify custom CatalogSource is `READY` (not `TRANSIENT_FAILURE`)
    - If `TRANSIENT_FAILURE`: mirror registry is unreachable or index image is invalid
15. Check pull secret configuration:
    - Call `mcp_openshift_resources_get` for Secret `pull-secret` in namespace `openshift-config`
    - Verify it contains credentials for the private registry host

> **Note:** Skip Phase 4 if the cluster has direct internet access (no IDMS/ITMS found and default `redhat-operators` CatalogSource is READY).

### Phase 5: Connectivity & Access Validation

16. Call `mcp_rhoai_list_data_science_projects` to verify API responsiveness
17. Call `mcp_openshift_resources_list` with kind=`Route` namespace=`redhat-ods-applications`:
    - Verify `rhods-dashboard` route exists and has a host

## Output Format

```
# RHOAI Installation Validation Report — {timestamp}

## Overall: {PASS ✓ | PARTIAL ⚠ | FAIL ✗}
## Deployment Mode: {GitOps (ArgoCD) | Direct (Kubernetes)}

## Pre-Install Readiness
| Check | Status | Detail |
|-------|--------|--------|
| Required namespaces | ✓/✗ | {list present/missing} |
| CatalogSource | ✓/✗ | {name, state} |
| Prerequisite operators | ✓/✗ | {count healthy}/{count required} |

## Operator Installation
| Check | Status | Detail |
|-------|--------|--------|
| RHOAI operator synced | ✓/✗ | {sync status or subscription state} |
| RHOAI operator healthy | ✓/✗ | {health status or CSV phase} |
| Subscription active | ✓/✗ | CSV: {version} |
| InstallPlan approved | ✓/✗ | {approval mode} |

## DSC Configuration
| Component | Managed | Status | Resources |
|-----------|---------|--------|-----------|
| KServe | ✓/✗ | {status} | {count} |
| Dashboard | ✓/✗ | {status} | {count} |
| Workbenches | ✓/✗ | {status} | {count} |
| DataSciencePipelines | ✓/✗ | {status} | {count} |
| Ray | ✓/✗ | {status} | {count} |
| ModelMeshServing | ✓/✗ | {status} | {count} |
| Kueue | ✓/✗ | {status} | {count} |
| TrainingOperator | ✓/✗ | {status} | {count} |
| ModelRegistry | ✓/✗ | {status} | {count} |

## Disconnected Environment (if applicable)
| Check | Status | Detail |
|-------|--------|--------|
| IDMS configured | ✓/✗/N/A | {count} IDMS resources |
| ITMS configured | ✓/✗/N/A | {count} ITMS resources |
| CatalogSource healthy | ✓/✗ | {state} |
| Pull secret valid | ✓/✗ | Covers: {registry hosts} |

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
- Disconnected environments need `ImageDigestMirrorSet` and/or `ImageTagMirrorSet` (oc-mirror v2 generates both)
- Legacy `ImageContentSourcePolicy` (ICSP) is deprecated in OCP 4.14+ in favor of IDMS/ITMS
- If CatalogSource shows `TRANSIENT_FAILURE`, the mirror registry is likely unreachable
- ServiceMesh version compatibility: RHOAI 2.16+ requires OSSM 2.6+ or ServiceMesh 3.0
- GPU operator requires NFD to label GPU nodes before it can schedule daemonsets
- Not all clusters use ArgoCD — many production deployments use direct `oc apply` or Helm
- RHOAI 3.5 introduces TrainingOperator, FeastOperator, and MLflow components
- The DSCInitialization CR must exist before the DSC can be created
