# Hermes Runtime

The default agent runtime using [NousResearch Hermes Agent](https://github.com/NousResearch/hermes-agent).

## Features

- Native MCP client support (stdio + HTTP transports)
- Built-in skill system (reads SKILL.md files)
- Dashboard with chat UI
- Memory and session persistence
- Cron scheduler for autonomous workflows
- Delegation (sub-agent spawning)

## Building

```bash
# Build for AMD64 (required for OpenShift)
podman build --platform linux/amd64 -t rhoai-copilot:latest -f runtimes/hermes/Containerfile .

# Push to registry
podman push rhoai-copilot:latest quay.io/your-org/rhoai-copilot:latest
```

## Deploying

```bash
# Deploy with Kustomize
oc apply -k runtimes/hermes/

# Create secrets (replace values)
oc create secret generic rhoai-copilot-secrets \
  --from-literal=gemini-api-key=YOUR_KEY \
  --from-literal=argocd-api-token=YOUR_TOKEN \
  --from-literal=argocd-base-url=https://your-argocd.example.com \
  --from-literal=dashboard-password=YOUR_PASSWORD \
  --from-literal=github-token=YOUR_GITHUB_PAT \
  -n rhoai-copilot
```

## Configuration

The Hermes runtime reads:
- `agent/soul.md` → mounted as `/mnt/soul/SOUL.md`
- `agent/config.yaml` → mounted as `/mnt/config/config.yaml`
- `skills/<phase>/<name>/SKILL.md` → mounted as `/mnt/skill-<name>/SKILL.md`

The `entrypoint.sh` handles runtime credential injection and skill assembly.
