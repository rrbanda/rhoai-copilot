# Creating Custom Skills

Add new capabilities to the agent by writing a SKILL.md file.

## Quick Start

1. Identify which RHOAI lifecycle phase your skill belongs to
2. Create a directory: `skills/<phase>/<your-skill-name>/`
3. Write `SKILL.md` following the format in `skills/SKILL_SPEC.md`
4. Deploy by rebuilding or updating the ConfigMap mount

## Example: Adding a "Node GPU Inventory" Skill

```bash
mkdir -p skills/plan/node-gpu-inventory
```

Create `skills/plan/node-gpu-inventory/SKILL.md`:

```markdown
# Node GPU Inventory

## Description

Reports the GPU types, counts, and availability across all cluster nodes.
Useful for capacity planning before deploying large model serving workloads.

## Trigger Conditions

- User asks about available GPUs
- User wants to know if there's capacity for a new model
- Before model deployment planning

## Required MCP Tools

- **OpenShift MCP**: `nodes_list`, `nodes_get`
- **RHOAI MCP**: `get_cluster_resources`

## Procedure

1. Call `nodes_list` to get all nodes
2. Filter for nodes with `nvidia.com/gpu` resource
3. For each GPU node, call `nodes_get` to retrieve:
   - GPU type (from node labels)
   - Total GPU count
   - Allocatable GPUs
   - Current GPU utilization
4. Compile into a summary table

## Output Format

| Node | GPU Type | Total | Available | Utilization |
|------|----------|-------|-----------|-------------|
| ... | ... | ... | ... | ... |

## Safety Constraints

- Read-only operation, no modifications
```

## Deploying Skills

### Via Kustomize (GitOps)

Add to your kustomization's `configMapGenerator`:

```yaml
configMapGenerator:
  - name: skill-node-gpu-inventory
    files:
      - SKILL.md=../../skills/plan/node-gpu-inventory/SKILL.md
```

### Via Direct Mount

For quick testing, create the ConfigMap manually:

```bash
oc create configmap skill-node-gpu-inventory \
  --from-file=SKILL.md=skills/plan/node-gpu-inventory/SKILL.md \
  -n rhoai-copilot
```

Then add the volume mount to the deployment and restart.
