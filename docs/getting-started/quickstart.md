# Quick Start

Deploy RHOAI Copilot on your OpenShift cluster in 5 minutes.

## Prerequisites

- OpenShift 4.14+ with cluster-admin access
- ArgoCD (OpenShift GitOps) installed
- Red Hat OpenShift AI operator installed
- `oc` CLI authenticated to your cluster

## Steps

### 1. Clone the repository

```bash
git clone https://github.com/rrbanda/rhoai-copilot.git
cd rhoai-copilot
```

### 2. Create secrets

```bash
oc new-project rhoai-copilot

oc create secret generic rhoai-copilot-secrets \
  --from-literal=gemini-api-key=YOUR_GEMINI_KEY \
  --from-literal=argocd-api-token=YOUR_ARGOCD_TOKEN \
  --from-literal=argocd-base-url=https://YOUR_ARGOCD_URL \
  --from-literal=dashboard-password=YOUR_DASHBOARD_PASSWORD \
  -n rhoai-copilot
```

### 3. Build and deploy

```bash
# Build the container image
make build

# Deploy using Kustomize
oc apply -k runtimes/hermes/
```

### 4. Access the dashboard

```bash
oc get route rhoai-copilot -n rhoai-copilot -o jsonpath='{.spec.host}'
```

Open the URL in your browser and log in with `admin` / your dashboard password.

### 5. Try your first command

In the chat interface, type:

> "Give me the platform health status"

The agent will query ArgoCD and RHOAI MCP servers and return a comprehensive health report.

## Next Steps

- [Architecture Overview](../concepts/architecture.md)
- [Configuring for Disconnected Environments](../guides/disconnected-setup.md)
- [Adding Custom Skills](../guides/custom-skills.md)
