---
name: rhoai-model-lifecycle
description: "Track AI model deployments through the RHOAI serving pipeline — from InferenceService to GPU allocation and readiness."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, Models, KServe, InferenceService, GPU, Serving]
---

# RHOAI Model Lifecycle Tracker

Track model deployments managed by the GitOps model ApplicationSet through the full lifecycle.

## Model Deployment Architecture in this Repo

Models are deployed via:
1. `usecases/models/<model-name>/profiles/tier1-minimal/config.json` — toggle enabled/disabled
2. A `cluster-models` ApplicationSet auto-discovers enabled models
3. Each model creates an InferenceService CR → KServe reconciles it
4. KServe creates: Deployment + Service + Route + (optionally) model cache PV
5. Kueue admits the workload based on ClusterQueue quotas and GPU availability

## Procedure

1. Call `mcp_argocd_list_applications` — identify model applications (not operator-* or instance-*)
2. For each model application:
   - Call `mcp_argocd_get_application` to check health and sync
   - Call `mcp_argocd_get_application_resource_tree` to find InferenceService resources
3. For each InferenceService found:
   - Note its `health.status` from the resource tree
   - Check if there's a corresponding Deployment and its readiness
   - Check for PersistentVolumeClaims (model cache)
4. Cross-reference with Kueue:
   - Check `instance-kueue-config` resource tree for ClusterQueue admission status
   - Note available GPU quota vs. used
5. Produce the model lifecycle report

## Output Format

```
# Model Deployment Report — {timestamp}

## Summary
- Total models deployed: {n}
- Serving (Ready): {n}
- Progressing: {n}
- Failed: {n}
- Queued (Kueue): {n}

## Model Details
| Model | Namespace | Health | GPU Allocated | Endpoint |
|-------|-----------|--------|---------------|----------|
| gpt-oss-120b | model-ns | Healthy | 4x A100 | Ready |
| ... | ... | ... | ... | ... |

## GPU Capacity (from Kueue)
- ClusterQueue: {name}
- Total GPU quota: {n}
- Used: {n}
- Available: {n}

## Issues
{Any models stuck in Pending, ImagePullBackOff, or InsufficientGPU}

## Recommendations
{Scaling suggestions, cache optimization, queue priority adjustments}
```

## RHOAI-Specific Knowledge

- Models in this repo: gpt-oss-120b, orchestrator-8b, qwen-math-7b (check usecases/models/)
- Services: guardrails-gateway, toolorchestra-app (check usecases/services/)
- HardwareProfiles define GPU types and quantities for model serving
- ResourceFlavor `default-gpu` matches nodes with label `nvidia.com/gpu.present: true`
- Model cache uses `kserve-localmodelnode-pv` PersistentVolumes for fast loading
- If a model is stuck in Pending, check: (1) Kueue quota, (2) GPU node availability, (3) model cache PV
