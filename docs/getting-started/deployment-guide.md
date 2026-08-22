# Deployment Guide

Complete step-by-step guide to deploy RHOAI Copilot on an OpenShift cluster. This documents the exact process that was validated on OpenShift 4.18 with RHOAI 3.5.

## Prerequisites

| Requirement | Minimum Version | Purpose |
|-------------|----------------|---------|
| OpenShift cluster | 4.18+ | Target platform |
| RHOAI operator | 2.x / 3.x | AI platform being managed |
| OpenShift GitOps (ArgoCD) | Installed | GitOps layer the agent monitors |
| `oc` CLI | 4.18+ | Cluster access |
| `podman` or `docker` | Latest | Building the agent image |
| Gemini API key | — | LLM backend for the agent |
| Registry access | quay.io or internal | Hosting the agent image |

Cluster-admin access is required for initial setup (RBAC, namespace creation).

---

## Phase 1: Build the Agent Container Image

The agent runs as a single container with Python (Hermes Agent), Node.js (ArgoCD MCP + GitHub MCP), and all dependencies pre-installed.

### 1.1 Containerfile

```dockerfile
# RHOAI Copilot — Hermes Runtime
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash curl git ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /sandbox && python3 -m venv /sandbox/.venv

RUN /sandbox/.venv/bin/pip install --no-cache-dir \
      "hermes-agent>=0.19.0" \
      aiohttp \
      "mcp>=1.8.1,<2.0" \
      pyyaml \
      fastapi \
      "uvicorn[standard]" \
      websockets

ARG NODE_VERSION=22.16.0
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
      | tar -xJf - -C /usr/local --strip-components=1 \
    && node --version && npm --version

# Pre-install MCP server binaries (avoids npx download at runtime)
RUN npm install -g argocd-mcp@latest
RUN npm install -g @modelcontextprotocol/server-github@latest

ENV HERMES_HOME=/sandbox/.hermes \
    HOME=/sandbox \
    PATH="/sandbox/.venv/bin:/usr/local/bin:$PATH" \
    BOOTSTRAP_DEPS=0

EXPOSE 18789
```

### 1.2 Option A: Use Pre-built Image (Fastest)

The CI publishes a ready-to-use image on every push to main:

```bash
# Edit runtimes/hermes/deployment.yaml:
#   image: ghcr.io/rrbanda/rhoai-copilot:latest
```

No build step needed — skip to Phase 2.

### 1.3 Option B: Local Build with Podman

OpenShift runs on AMD64. If you're building on an ARM Mac (Apple Silicon), you MUST specify the platform:

```bash
podman build --platform linux/amd64 \
  -t quay.io/YOUR_ORG/rhoai-copilot:latest \
  -f runtimes/hermes/Containerfile .

podman push quay.io/YOUR_ORG/rhoai-copilot:latest
```

Without `--platform linux/amd64`, the image will fail with `exec format error` on OpenShift.

### 1.2 Build Option B: OpenShift Binary Build

If you don't have podman/docker, use OpenShift's built-in build system:

```bash
# Create BuildConfig and ImageStream
oc new-project rhoai-copilot

oc create imagestream rhoai-copilot -n rhoai-copilot

oc create -f - <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: rhoai-copilot
  namespace: rhoai-copilot
spec:
  output:
    to:
      kind: ImageStreamTag
      name: rhoai-copilot:latest
  source:
    type: Binary
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: runtimes/hermes/Containerfile
EOF

# Trigger build from local directory
oc start-build rhoai-copilot -n rhoai-copilot --from-dir=.
```

The OpenShift build nodes are AMD64, so no platform flag is needed.

For disconnected environments, push to your internal registry instead.

---

## Phase 2: Deploy Core Infrastructure

### 2.1 Create Namespace

```bash
oc new-project rhoai-copilot
```

### 2.2 Create RBAC

The agent needs read-only access to cluster resources for the OpenShift MCP:

```yaml
# rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rhoai-copilot
  namespace: rhoai-copilot
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rhoai-copilot-cluster-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-reader
subjects:
  - kind: ServiceAccount
    name: rhoai-copilot
    namespace: rhoai-copilot
```

```bash
oc apply -f rbac.yaml
```

The `cluster-reader` ClusterRole is a built-in OpenShift role that grants read-only access to all cluster resources. This is required for the OpenShift MCP to list pods, nodes, events, and namespaces.

### 2.3 Create Persistent Storage

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rhoai-copilot-data
  namespace: rhoai-copilot
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
```

```bash
oc apply -f pvc.yaml
```

### 2.4 Create Secrets

```bash
oc create secret generic rhoai-copilot-secrets \
  --from-literal=gemini-api-key='YOUR_GEMINI_API_KEY' \
  --from-literal=argocd-api-token='YOUR_ARGOCD_TOKEN' \
  --from-literal=dashboard-password='YOUR_DASHBOARD_PASSWORD' \
  --from-literal=github-token='YOUR_GITHUB_PAT' \
  -n rhoai-copilot
```

See [Obtaining Credentials](../guides/obtaining-credentials.md) for how to get each value.

### 2.5 Deploy with Kustomize

From the repo root:

```bash
oc apply -k .
```

This creates:
- Namespace (`rhoai-copilot`)
- ServiceAccount + ClusterRoleBinding (`cluster-reader`)
- PVC for persistent agent state (2Gi)
- 25 ConfigMaps (entrypoint, soul, config, + 22 skills)
- Agent Deployment with all skill mounts
- RHOAI MCP Deployment + Service
- Service (ClusterIP on port 18789)
- Route (TLS edge termination with 300s timeout for long responses)

### 2.6 Verify Deployment

```bash
# Quick check
oc get pods -n rhoai-copilot
# NAME                             READY   STATUS    RESTARTS   AGE
# rhoai-copilot-xxxxx              1/1     Running   0          2m
# rhoai-mcp-xxxxx                  1/1     Running   0          2m

# Full validation (checks pods, MCP connectivity, Route, skills)
./scripts/validate-deployment.sh
```

Expected output:
```
=== RHOAI Copilot Deployment Validation ===
--- Core Components ---
  [PASS] Agent pod — Running (0 restarts)
  [PASS] RHOAI MCP pod — Running
  [PASS] Route — https://rhoai-copilot-rhoai-copilot.apps.YOUR_CLUSTER (HTTP 401)
  [PASS] PVC — Bound
  [PASS] Secret — 4 keys configured
--- MCP Server Connectivity ---
  [PASS] RHOAI MCP — Responding (HTTP 200)
--- Configuration ---
  [PASS] Skill ConfigMaps — 22 skills mounted
=== Summary ===
  Result: ALL CHECKS PASSED
```

---

## Phase 3: Deploy MCP Servers

The agent connects to 5 MCP servers. ArgoCD and GitHub MCP run as embedded processes (stdio transport). RHOAI, OpenShift, and MLflow MCP run as separate pods (HTTP transport).

See [MCP Server Setup Guide](../guides/mcp-server-setup.md) for detailed per-server instructions.

### Quick Summary

| MCP Server | Transport | Deployment | Namespace |
|-----------|-----------|-----------|-----------|
| ArgoCD | stdio (embedded) | Pre-installed in image | Same pod |
| GitHub | stdio (embedded) | Pre-installed in image | Same pod |
| RHOAI | HTTP (streamable-http) | Separate Deployment or MCPServer CR | `rhoai-copilot` |
| OpenShift | HTTP (streamable-http) | Separate Deployment | `ocp-mcp-server` |
| MLflow | HTTP (streamable-http) | MCPServer CR | `redhat-ods-applications` |

### 3.1 ArgoCD MCP (No extra deployment needed)

The `argocd-mcp` binary is pre-installed in the agent image. It only needs:
- `ARGOCD_BASE_URL` — Your ArgoCD server URL
- `ARGOCD_API_TOKEN` — API token for authentication

Both are injected from the secret at runtime by `entrypoint.sh`.

### 3.2 RHOAI MCP

Deploy the RHOAI MCP server in the agent namespace:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rhoai-mcp
  namespace: rhoai-copilot
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rhoai-mcp
  template:
    metadata:
      labels:
        app: rhoai-mcp
    spec:
      serviceAccountName: rhoai-mcp
      containers:
        - name: rhoai-mcp
          image: quay.io/opendatahub/rhoai-mcp:latest
          ports:
            - containerPort: 8000
---
apiVersion: v1
kind: Service
metadata:
  name: rhoai-mcp
  namespace: rhoai-copilot
spec:
  selector:
    app: rhoai-mcp
  ports:
    - port: 8000
      targetPort: 8000
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rhoai-mcp
  namespace: rhoai-copilot
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rhoai-mcp-cluster-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-reader
subjects:
  - kind: ServiceAccount
    name: rhoai-mcp
    namespace: rhoai-copilot
```

The config.yaml references it as:
```yaml
rhoai:
  url: "http://rhoai-mcp.rhoai-copilot.svc:8000/mcp"
```

### 3.3 OpenShift MCP

Deploy in its own namespace. See [MCP Server Setup](../guides/mcp-server-setup.md#openshift-mcp) for full manifests.

The config.yaml references it as:
```yaml
openshift:
  url: "http://openshift-mcp-server.ocp-mcp-server.svc.cluster.local:8080/mcp"
```

Authentication is handled by injecting the agent's ServiceAccount token as a Bearer header in `entrypoint.sh`.

### 3.4 MLflow MCP

Requires a custom image. See [MCP Server Setup](../guides/mcp-server-setup.md#mlflow-mcp) for the Containerfile and deployment.

### 3.5 GitHub MCP (Optional)

Pre-installed in the agent image. Only needs `GITHUB_TOKEN` in the secret.

---

## Phase 4: Access the Dashboard

### 4.1 Get the Route URL

```bash
oc get route rhoai-copilot -n rhoai-copilot -o jsonpath='{.spec.host}'
```

### 4.2 Login

Open the URL in your browser. Login with:
- Username: `admin`
- Password: The value you set in `dashboard-password`

### 4.3 Verify MCP Connectivity

In the chat interface, type:

> "List all ArgoCD applications"

The agent should return a list of applications with their health and sync status.

---

## Phase 5: Verify All MCP Servers

Run these verification commands from within the agent pod:

```bash
AGENT_POD=$(oc get pods -n rhoai-copilot -l app=rhoai-copilot -o jsonpath='{.items[0].metadata.name}')

# Verify RHOAI MCP
oc exec $AGENT_POD -n rhoai-copilot -- curl -s http://rhoai-mcp.rhoai-copilot.svc:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"capabilities":{}},"id":1}'

# Verify OpenShift MCP (using SA token)
TOKEN=$(oc exec $AGENT_POD -n rhoai-copilot -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
oc exec $AGENT_POD -n rhoai-copilot -- curl -s \
  http://openshift-mcp-server.ocp-mcp-server.svc.cluster.local:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"capabilities":{}},"id":1}'

# Verify MLflow MCP
oc exec $AGENT_POD -n rhoai-copilot -- curl -s \
  http://mlflow-mcp.redhat-ods-applications.svc.cluster.local:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"capabilities":{}},"id":1}'
```

Expected: Each returns a JSON response with `"result"` containing server capabilities.

### Expected Tool Counts

| MCP Server | Tools |
|-----------|-------|
| ArgoCD | 16 discovered, 10 whitelisted |
| RHOAI | 88 discovered, 38 whitelisted |
| OpenShift | 13+ |
| MLflow | ~50 |
| GitHub | 26 discovered, 8 whitelisted |
| **Total** | **130+** |

---

## Phase 6: Test Core Interactions

Use the dashboard to verify key capabilities:

| Test | What to Type | Expected Result |
|------|--------------|-----------------|
| Platform health | "What's the health of my RHOAI platform?" | Lists ArgoCD apps with health/sync status |
| Model status | "Which models are serving?" | Lists InferenceServices across projects |
| Drift detection | "Which apps are out of sync?" | Identifies drifted apps with root causes |
| Cluster overview | "Explore the cluster" | Shows projects, models, GPUs, workbenches |
| MLflow | "Search my MLflow experiments" | Returns experiment list |

---

## Deployment Architecture (Final State)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  rhoai-copilot namespace                                                │
│                                                                         │
│  ┌─────────────────────────────┐    ┌────────────────────────────────┐  │
│  │ Agent Pod (Hermes)          │    │ RHOAI MCP Pod                  │  │
│  │ - Gemini 2.5 Flash LLM      │───▶│ - streamable-http :8000        │  │
│  │ - 22 skills loaded           │    │ - 88 tools / 38 selected      │  │
│  │ - Dashboard :18789           │    │ - SA: rhoai-mcp (cluster-read) │  │
│  │ - ArgoCD MCP (stdio, embed)  │    └────────────────────────────────┘  │
│  │ - GitHub MCP (stdio, embed)  │                                        │
│  └──────────────┬───────────────┘                                        │
│                 │                                                         │
└─────────────────┼─────────────────────────────────────────────────────────┘
                  │ HTTP
    ┌─────────────┼───────────────────────────────────────────┐
    │             ▼                                           │
    │  ┌──────────────────────┐    ┌───────────────────────┐  │
    │  │ OpenShift MCP        │    │ MLflow MCP             │  │
    │  │ (ocp-mcp-server ns)  │    │ (redhat-ods-apps ns)   │  │
    │  │ - 13 tools            │    │ - ~50 tools            │  │
    │  │ - Bearer token auth   │    │ - SA token + workspace │  │
    │  └──────────────────────┘    └───────────────────────┘  │
    │                                                         │
    │  External:                                              │
    │  ┌──────────────────────┐                               │
    │  │ ArgoCD Server        │                               │
    │  │ (openshift-gitops)   │                               │
    │  │ - API token auth      │                               │
    │  └──────────────────────┘                               │
    └─────────────────────────────────────────────────────────┘
```

---

## Next Steps

- [MCP Server Setup (detailed)](../guides/mcp-server-setup.md) — Full deployment manifests for each MCP server
- [Troubleshooting](../guides/troubleshooting.md) — Common errors and their fixes
- [Obtaining Credentials](../guides/obtaining-credentials.md) — How to get ArgoCD tokens, Gemini keys, etc.
- [Disconnected Setup](disconnected-setup.md) — Air-gapped deployment adjustments
- [Adding Custom Skills](../guides/custom-skills.md) — Extend the agent's capabilities
