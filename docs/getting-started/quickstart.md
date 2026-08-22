# Quick Start

Deploy RHOAI Copilot on your OpenShift cluster.

> For the complete step-by-step guide with all MCP servers, troubleshooting, and verification,
> see the [Full Deployment Guide](deployment-guide.md).

## Prerequisites

- OpenShift 4.18+ with cluster-admin access
- ArgoCD (OpenShift GitOps) installed
- Red Hat OpenShift AI operator installed
- `oc` CLI authenticated to your cluster
- A Gemini API key ([get one here](https://aistudio.google.com/))

## Deploy in 6 Steps

### 1. Clone

```bash
git clone https://github.com/rrbanda/rhoai-copilot.git
cd rhoai-copilot
```

### 2. Build the agent image

```bash
# Build for linux/amd64 (required for OpenShift)
make build push
```

Or use the pre-built image from GitHub Container Registry:
```bash
# Edit runtimes/hermes/deployment.yaml and set:
#   image: ghcr.io/rrbanda/rhoai-copilot:latest
```

### 3. Create secrets

```bash
oc new-project rhoai-copilot

oc create secret generic rhoai-copilot-secrets \
  --from-literal=gemini-api-key='YOUR_GEMINI_KEY' \
  --from-literal=argocd-api-token='YOUR_ARGOCD_TOKEN' \
  --from-literal=argocd-base-url='https://openshift-gitops-server-openshift-gitops.apps.YOUR_CLUSTER' \
  --from-literal=dashboard-password='YOUR_PASSWORD' \
  -n rhoai-copilot
```

See [Obtaining Credentials](../guides/obtaining-credentials.md) for how to get each value.

### 4. Deploy

```bash
# Deploys agent + RHOAI MCP + all 22 skills
oc apply -k .
```

### 5. Validate

```bash
# Wait for pods to start
oc get pods -n rhoai-copilot -w

# Run validation
./scripts/validate-deployment.sh
```

### 6. Access the dashboard

```bash
echo "https://$(oc get route rhoai-copilot -n rhoai-copilot -o jsonpath='{.spec.host}')"
```

Log in with `admin` / your dashboard password. Type: *"Give me the platform health status"*

---

## Optional: Deploy Additional MCP Servers

```bash
# OpenShift MCP (cluster resource queries)
oc apply -f mcp-servers/openshift/deployment.yaml

# MLflow MCP (experiment tracking — requires MLflow deployed)
oc apply -f mcp-servers/mlflow/deployment.yaml

# GitHub MCP (just add token to secret)
oc patch secret rhoai-copilot-secrets -n rhoai-copilot \
  --type merge -p '{"data":{"github-token":"'$(echo -n "ghp_YOUR_TOKEN" | base64)'"}}'
oc rollout restart deployment/rhoai-copilot -n rhoai-copilot
```

---

## What's Next

| Guide | Description |
|-------|-------------|
| [Full Deployment Guide](deployment-guide.md) | Complete end-to-end with all 5 MCP servers |
| [MCP Server Setup](../guides/mcp-server-setup.md) | Per-server deployment details |
| [Obtaining Credentials](../guides/obtaining-credentials.md) | How to get each API key/token |
| [Troubleshooting](../guides/troubleshooting.md) | Common errors and fixes |
| [Environment Variables](../reference/environment-variables.md) | Complete env var reference |
