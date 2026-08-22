# Quick Start

Deploy RHOAI Copilot on your OpenShift cluster in 5 minutes.

> For the complete step-by-step guide with all MCP servers, troubleshooting, and verification,
> see the [Full Deployment Guide](deployment-guide.md).

## Prerequisites

- OpenShift 4.18+ with cluster-admin access
- ArgoCD (OpenShift GitOps) installed
- Red Hat OpenShift AI operator installed
- `oc` CLI authenticated to your cluster
- A Gemini API key ([get one here](https://aistudio.google.com/))
- Podman or Docker (for building the image)

## Steps

### 1. Clone the repository

```bash
git clone https://github.com/rrbanda/rhoai-copilot.git
cd rhoai-copilot
```

### 2. Build the agent image

```bash
# IMPORTANT: Always specify linux/amd64 for OpenShift
podman build --platform linux/amd64 \
  -t quay.io/YOUR_ORG/rhoai-copilot:latest \
  -f runtimes/hermes/Containerfile .

podman push quay.io/YOUR_ORG/rhoai-copilot:latest
```

### 3. Create namespace and secrets

```bash
oc new-project rhoai-copilot

oc create secret generic rhoai-copilot-secrets \
  --from-literal=gemini-api-key=YOUR_GEMINI_KEY \
  --from-literal=argocd-api-token=YOUR_ARGOCD_TOKEN \
  --from-literal=dashboard-password=YOUR_DASHBOARD_PASSWORD \
  -n rhoai-copilot
```

See [Obtaining Credentials](../guides/obtaining-credentials.md) for how to get each value.

### 4. Deploy

```bash
# Deploy agent + RHOAI MCP + all skills in one command
oc apply -k .
```

### 5. Access the dashboard

```bash
oc get route rhoai-copilot -n rhoai-copilot -o jsonpath='{.spec.host}'
```

Open the URL in your browser and log in with `admin` / your dashboard password.

### 6. Try your first command

In the chat interface, type:

> "Give me the platform health status"

The agent will query ArgoCD and RHOAI MCP servers and return a comprehensive health report.

---

## What's Next

| Guide | Description |
|-------|-------------|
| [Full Deployment Guide](deployment-guide.md) | Complete end-to-end deployment with all 5 MCP servers |
| [MCP Server Setup](../guides/mcp-server-setup.md) | Detailed MCP server deployment (ArgoCD, RHOAI, OpenShift, MLflow, GitHub) |
| [Obtaining Credentials](../guides/obtaining-credentials.md) | How to get each API token and key |
| [Troubleshooting](../guides/troubleshooting.md) | Common errors and their fixes |
| [Environment Variables](../reference/environment-variables.md) | Complete env var reference |
| [Disconnected Setup](disconnected-setup.md) | Air-gapped deployment adjustments |
| [Architecture](../concepts/architecture.md) | How the system works |
| [Custom Skills](../guides/custom-skills.md) | Extend the agent's capabilities |
