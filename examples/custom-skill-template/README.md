# Example: Creating a Custom Skill

Step-by-step walkthrough of adding a new skill to the agent.

## Scenario

You want to add a skill that checks GPU driver compatibility across nodes.

## Steps

### 1. Create the skill directory

```bash
mkdir -p skills/administer/gpu-driver-checker
```

### 2. Write the SKILL.md

See `skills/_template/SKILL.md.template` for the format.

### 3. Add a ConfigMap entry

In your Kustomization:

```yaml
configMapGenerator:
  - name: skill-gpu-driver-checker
    files:
      - SKILL.md=../../skills/administer/gpu-driver-checker/SKILL.md
```

### 4. Mount in the deployment

Add volume and volumeMount entries for the new skill.

### 5. Add an eval scenario

Create `eval/scenarios/gpu-driver-check.yaml` to test the skill.

### 6. Submit a PR

The CI will validate your skill format automatically.
