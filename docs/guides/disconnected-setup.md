# Disconnected Environment Setup

How to deploy and configure RHOAI Copilot in an air-gapped (disconnected) OpenShift cluster.

## Prerequisites

- Bastion host with access to both the internet and the internal network
- Internal container registry (e.g., `registry.internal.example.com:5000`)
- `oc-mirror` CLI plugin installed on the bastion
- OpenShift 4.14+ cluster with no external network access

## Step 1: Mirror Required Images

On your bastion host, mirror the following images:

```bash
# Agent image
podman pull quay.io/your-org/rhoai-copilot:latest
podman tag quay.io/your-org/rhoai-copilot:latest registry.internal.example.com:5000/rhoai-copilot:latest
podman push registry.internal.example.com:5000/rhoai-copilot:latest

# MLflow MCP image (if using MLflow)
podman pull quay.io/rbrhssa/mlflow-mcp:3.15.0-v2
podman tag quay.io/rbrhssa/mlflow-mcp:3.15.0-v2 registry.internal.example.com:5000/mlflow-mcp:3.15.0-v2
podman push registry.internal.example.com:5000/mlflow-mcp:3.15.0-v2
```

## Step 2: Update Image References

In your deployment overlay, patch image references to use the internal registry:

```yaml
# runtimes/hermes/overlays/disconnected/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../
patches:
  - target:
      kind: Deployment
      name: rhoai-copilot
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: registry.internal.example.com:5000/rhoai-copilot:latest
```

## Step 3: Configure MCP Server URLs

All MCP servers must be reachable via internal cluster networking:

```env
# agent/profiles/disconnected.env
RHOAI_MCP_URL=http://rhoai-mcp.rhoai-copilot.svc:8000/mcp
OPENSHIFT_MCP_URL=http://openshift-mcp-server.ocp-mcp-server.svc.cluster.local:8080/mcp
MLFLOW_MCP_URL=http://mlflow-mcp.redhat-ods-applications.svc.cluster.local:8080/mcp
```

## Step 4: Disable External MCPs

GitHub MCP requires internet access. In disconnected environments, either:
- Replace with a Gitea/GitLab MCP pointing to your internal Git server
- Remove from `agent/config.yaml`

## Step 5: Deploy

```bash
oc apply -k runtimes/hermes/overlays/disconnected/
```

## Using the Disconnected Deploy Skill

Once deployed, ask the agent:

> "Help me deploy RHOAI 2.19 on this disconnected cluster using registry.internal.example.com:5000"

The agent will use the `rhoai-disconnected-deploy` skill to guide you through the full process.
