# Environment Variables Reference

Complete reference of all environment variables used by RHOAI Copilot and its MCP servers.

---

## Agent Pod Environment Variables

These are set in the Deployment manifest and consumed by `entrypoint.sh` or the agent runtime.

### Credentials (from Secret)

| Variable | Source | Required | Description |
|----------|--------|----------|-------------|
| `GEMINI_API_KEY` | `rhoai-copilot-secrets.gemini-api-key` | Yes | Google Gemini API key for LLM inference |
| `ARGOCD_API_TOKEN` | `rhoai-copilot-secrets.argocd-api-token` | Yes | ArgoCD API token for authentication |
| `ARGOCD_BASE_URL` | `rhoai-copilot-secrets.argocd-api-token` (or env) | Yes | ArgoCD server URL (e.g., `https://openshift-gitops-server-openshift-gitops.apps.CLUSTER`) |
| `DASHBOARD_PASSWORD` | `rhoai-copilot-secrets.dashboard-password` | Yes | Plaintext password for dashboard basic auth (hashed at startup) |
| `GITHUB_TOKEN` | `rhoai-copilot-secrets.github-token` | No | GitHub PAT for PR creation and code operations |

### Runtime Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMES_HOME` | `/sandbox/.hermes` | Base directory for Hermes agent state |
| `HOME` | `/sandbox` | Container home directory |
| `PATH` | `/sandbox/.venv/bin:/usr/local/bin:$PATH` | Includes Python venv and Node.js binaries |
| `BOOTSTRAP_DEPS` | `0` | Skip dependency installation at startup (pre-installed in image) |

### ArgoCD MCP (stdio transport)

| Variable | Set By | Description |
|----------|--------|-------------|
| `ARGOCD_BASE_URL` | entrypoint.sh | ArgoCD server URL, injected into config at startup |
| `ARGOCD_API_TOKEN` | entrypoint.sh | ArgoCD bearer token, injected into config at startup |
| `ARGOCD_INSECURE` | config.yaml | `"true"` to skip TLS verification for self-signed certs |

### GitHub MCP (stdio transport)

| Variable | Set By | Description |
|----------|--------|-------------|
| `GITHUB_PERSONAL_ACCESS_TOKEN` | config.yaml | Maps from `${GITHUB_TOKEN}` secret key |

---

## RHOAI MCP Server Environment Variables

Set in the RHOAI MCP Deployment or MCPServer CR.

| Variable | Default | Description |
|----------|---------|-------------|
| `RHOAI_MCP_READ_ONLY_MODE` | `"true"` | Set to `"false"` to enable write operations (create workbench, deploy model) |
| `RHOAI_MCP_PORT` | `8000` | Port the server listens on |
| `RHOAI_MCP_TRANSPORT` | `streamable-http` | MCP transport protocol |

---

## OpenShift MCP Server Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OCP_MCP_PORT` | `8080` | Port the server listens on |
| `OCP_MCP_TRANSPORT` | `streamable-http` | MCP transport protocol |

Authentication is handled via the Bearer token header injected by the agent's `entrypoint.sh`:

```python
ocp_mcp['headers'] = {'Authorization': f'Bearer {sa_token}'}
```

---

## MLflow MCP Server Environment Variables

These are set in the MLflow MCP Deployment/MCPServer CR.

### Container Image ENV (baked into Containerfile)

| Variable | Value | Description |
|----------|-------|-------------|
| `FASTMCP_PORT` | `8080` | Port FastMCP listens on |
| `FASTMCP_HOST` | `0.0.0.0` | Bind address |
| `FASTMCP_TRANSPORT` | `streamable-http` | Transport protocol (critical — must not use stdio) |
| `FASTMCP_WORKER_COUNT` | `2` | Number of worker processes |

### Deployment ENV (set in manifest)

| Variable | Value | Description |
|----------|-------|-------------|
| `MLFLOW_TRACKING_URI` | `http://mlflow-server.redhat-ods-applications.svc:5000` | MLflow tracking server URL |
| `PYTHONPATH` | `/mnt/startup` | Path to `sitecustomize.py` for auto-loading |

### Runtime ENV (set by sitecustomize.py at startup)

| Variable | Source | Description |
|----------|--------|-------------|
| `MLFLOW_TRACKING_TOKEN` | ServiceAccount token file | Bearer token for MLflow auth |
| `MLFLOW_WORKSPACE` | Hardcoded in sitecustomize.py | Multi-tenant workspace name (e.g., `team-alpha`) |
| `MLFLOW_TRACKING_URI` | Modified by sitecustomize.py | Appends `/mlflow` suffix if missing |

---

## Deployment Manifest Example

Complete environment section for the agent Deployment:

```yaml
spec:
  containers:
    - name: rhoai-copilot
      env:
        - name: GEMINI_API_KEY
          valueFrom:
            secretKeyRef:
              name: rhoai-copilot-secrets
              key: gemini-api-key
        - name: ARGOCD_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: rhoai-copilot-secrets
              key: argocd-api-token
        - name: ARGOCD_BASE_URL
          value: "https://openshift-gitops-server-openshift-gitops.apps.YOUR_CLUSTER"
        - name: DASHBOARD_PASSWORD
          valueFrom:
            secretKeyRef:
              name: rhoai-copilot-secrets
              key: dashboard-password
        - name: GITHUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: rhoai-copilot-secrets
              key: github-token
              optional: true
        - name: HERMES_HOME
          value: "/sandbox/.hermes"
        - name: HOME
          value: "/sandbox"
        - name: BOOTSTRAP_DEPS
          value: "0"
```

---

## Environment Profiles

### Connected Cluster

```bash
# agent/profiles/connected.env
GEMINI_API_KEY=<your-key>
ARGOCD_BASE_URL=https://openshift-gitops-server-openshift-gitops.apps.YOUR_CLUSTER
ARGOCD_INSECURE=true
RHOAI_MCP_READ_ONLY_MODE=false
```

### Disconnected Cluster

```bash
# agent/profiles/disconnected.env
GEMINI_API_KEY=<your-key>
ARGOCD_BASE_URL=https://openshift-gitops-server-openshift-gitops.apps.YOUR_CLUSTER
ARGOCD_INSECURE=true
RHOAI_MCP_READ_ONLY_MODE=false
# Override image references to internal registry
AGENT_IMAGE=registry.internal.example.com/rhoai-copilot:latest
RHOAI_MCP_IMAGE=registry.internal.example.com/rhoai-mcp:latest
MLFLOW_MCP_IMAGE=registry.internal.example.com/mlflow-mcp:3.15.0-v2
```

---

## Validating Environment

After deployment, verify all environment variables are correctly set:

```bash
AGENT_POD=$(oc get pods -n rhoai-copilot -l app=rhoai-copilot -o jsonpath='{.items[0].metadata.name}')

# Check critical vars are set (values redacted)
oc exec $AGENT_POD -n rhoai-copilot -- env | grep -E "GEMINI|ARGOCD|DASHBOARD|GITHUB|HERMES"

# Verify config was correctly patched by entrypoint
oc exec $AGENT_POD -n rhoai-copilot -- cat /tmp/work/.hermes/config.yaml | grep -A2 "argocd"
```
