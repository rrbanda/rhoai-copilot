# MCP Server Setup Guide

Detailed deployment instructions for each MCP (Model Context Protocol) server that connects to RHOAI Copilot.

## Overview

| MCP Server | Transport | Auth | Tools | Purpose |
|-----------|-----------|------|-------|---------|
| ArgoCD | stdio (embedded) | API token | 16 (10 used) | GitOps application lifecycle |
| RHOAI | streamable-http | Service Account | 88 (38 used) | RHOAI platform operations |
| OpenShift | streamable-http | Bearer token | 13 | Cluster resource queries |
| MLflow | streamable-http | SA token + workspace | ~50 | Experiment tracking |
| GitHub | stdio (embedded) | PAT | 26 (8 used) | PR-based GitOps |

---

## ArgoCD MCP

**Source**: [argoproj-labs/mcp-for-argocd](https://github.com/argoproj-labs/mcp-for-argocd)

### Deployment

The ArgoCD MCP binary is pre-installed in the agent image via `npm install -g argocd-mcp@latest`. No separate deployment needed.

### Configuration in config.yaml

```yaml
mcp_servers:
  argocd:
    command: "argocd-mcp"
    args: ["stdio"]
    env:
      ARGOCD_BASE_URL: "${ARGOCD_BASE_URL}"
      ARGOCD_API_TOKEN: "${ARGOCD_API_TOKEN}"
      ARGOCD_INSECURE: "true"
    timeout: 60
    connect_timeout: 30
    supports_parallel_tool_calls: true
    tools:
      resources: false
      prompts: false
      include:
        - list_applications
        - get_application
        - get_application_resource_tree
        - get_application_managed_resources
        - get_application_workload_logs
        - get_resource_events
        - get_resource_actions
        - list_clusters
        - get_appproject
        - sync_application
```

### Required Environment Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `ARGOCD_BASE_URL` | ArgoCD Route URL | e.g., `https://openshift-gitops-server-openshift-gitops.apps.CLUSTER_DOMAIN` |
| `ARGOCD_API_TOKEN` | ArgoCD account token | Generated via `argocd account generate-token` |
| `ARGOCD_INSECURE` | `"true"` | Skip TLS verification for self-signed certs |

### Generate ArgoCD API Token

```bash
# Option 1: Using ArgoCD CLI
argocd login openshift-gitops-server-openshift-gitops.apps.YOUR_CLUSTER \
  --username admin \
  --password $(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d) \
  --insecure

# Create a service account for the agent
argocd account generate-token --account hermes-agent

# Option 2: From OpenShift secret (if using default admin)
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d
```

### RBAC for ArgoCD

If you create a dedicated ArgoCD account (`hermes-agent`), configure its RBAC in the ArgoCD `argocd-rbac-cm` ConfigMap:

```
p, role:hermes-agent, applications, get, */*, allow
p, role:hermes-agent, applications, sync, */*, allow
p, role:hermes-agent, clusters, get, *, allow
p, role:hermes-agent, projects, get, *, allow
p, role:hermes-agent, logs, get, */*, allow
g, hermes-agent, role:hermes-agent
```

### Verification

Ask the agent: "List all ArgoCD applications"

Expected: Returns application list with health status, sync status, and namespace.

---

## RHOAI MCP

**Source**: [opendatahub-io/rhoai-mcp](https://github.com/opendatahub-io/rhoai-mcp)

### Deployment Option A: Standalone Deployment

```yaml
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
---
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
              name: http
          env:
            - name: RHOAI_MCP_READ_ONLY_MODE
              value: "false"
          resources:
            requests:
              memory: 128Mi
              cpu: 100m
            limits:
              memory: 256Mi
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
      name: http
```

### Deployment Option B: MCPServer Custom Resource

If you have the MCP Lifecycle Operator installed:

```yaml
apiVersion: mcp.opendatahub.io/v1alpha1
kind: MCPServer
metadata:
  name: rhoai-mcp
  namespace: rhoai-copilot
spec:
  image: quay.io/opendatahub/rhoai-mcp:latest
  port: 8000
  transport: streamable-http
  serviceAccountName: rhoai-mcp
  env:
    - name: RHOAI_MCP_READ_ONLY_MODE
      value: "false"
```

### Configuration in config.yaml

```yaml
rhoai:
  url: "http://rhoai-mcp.rhoai-copilot.svc:8000/mcp"
  timeout: 60
  connect_timeout: 30
  tools:
    include:
      - list_data_science_projects
      - get_project_details
      - cluster_summary
      # ... (38 tools total, see agent/config.yaml for full list)
```

### Verification

Ask the agent: "Explore the cluster"

Expected: Returns project count, model count, GPU availability, workbench count.

---

## OpenShift MCP

### Deployment

Deploy in a separate namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ocp-mcp-server
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openshift-mcp-server
  namespace: ocp-mcp-server
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-mcp-server-cluster-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-reader
subjects:
  - kind: ServiceAccount
    name: openshift-mcp-server
    namespace: ocp-mcp-server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openshift-mcp-server
  namespace: ocp-mcp-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: openshift-mcp-server
  template:
    metadata:
      labels:
        app: openshift-mcp-server
    spec:
      serviceAccountName: openshift-mcp-server
      containers:
        - name: ocp-mcp
          image: quay.io/YOUR_ORG/openshift-mcp-server:latest
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: openshift-mcp-server
  namespace: ocp-mcp-server
spec:
  selector:
    app: openshift-mcp-server
  ports:
    - port: 8080
      targetPort: 8080
```

### Authentication

The OpenShift MCP requires a Bearer token from a ServiceAccount with `cluster-reader` permissions. The agent's `entrypoint.sh` handles this automatically:

```python
# From entrypoint.sh — injects SA token as Bearer header
sa_token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'
if os.path.isfile(sa_token_path):
    with open(sa_token_path) as tf:
        sa_token = tf.read().strip()
    ocp_mcp = cfg.setdefault('mcp_servers', {}).setdefault('openshift', {})
    ocp_mcp['headers'] = {'Authorization': f'Bearer {sa_token}'}
```

This uses the agent pod's own ServiceAccount token (which must have `cluster-reader` bound to it).

### Configuration in config.yaml

```yaml
openshift:
  url: "http://openshift-mcp-server.ocp-mcp-server.svc.cluster.local:8080/mcp"
  timeout: 60
  connect_timeout: 30
```

### Verification

Ask the agent: "List namespaces in the cluster"

Expected: Returns 100+ namespaces.

---

## MLflow MCP

The MLflow MCP requires a custom container image because the stock MLflow MCP server has specific version and configuration requirements.

### Build Custom MLflow MCP Image

```dockerfile
# mlflow-mcp/Containerfile
FROM python:3.13-slim

RUN pip install --no-cache-dir "mlflow[mcp]==3.15.0"

ENV FASTMCP_PORT=8080 \
    FASTMCP_HOST=0.0.0.0 \
    FASTMCP_TRANSPORT=streamable-http \
    FASTMCP_WORKER_COUNT=2

EXPOSE 8080

ENTRYPOINT ["mlflow", "mcp", "run"]
```

Key details:
- **Must use `mlflow[mcp]==3.15.0`** — Earlier versions (3.13.x) don't support the `--transport` flag
- **`FASTMCP_*` environment variables are baked in** — The MLflow MCP server uses FastMCP internally and reads these env vars
- **No `--transport` CLI flag needed** — The env vars handle it

```bash
podman build --platform linux/amd64 \
  -t quay.io/YOUR_ORG/mlflow-mcp:3.15.0-v2 \
  -f mlflow-mcp/Containerfile .

podman push quay.io/YOUR_ORG/mlflow-mcp:3.15.0-v2
```

### Deploy with sitecustomize.py for Auth

The MLflow MCP server needs authentication to talk to the MLflow tracking server. This is done via a `sitecustomize.py` file that gets loaded automatically by Python at startup:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mlflow-mcp-startup
  namespace: redhat-ods-applications
data:
  sitecustomize.py: |
    """Auto-loaded by Python from PYTHONPATH at startup."""
    import os

    # Read SA token for MLflow authentication
    token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'
    if os.path.isfile(token_path):
        os.environ['MLFLOW_TRACKING_TOKEN'] = open(token_path).read().strip()

    # Set workspace for multi-tenant MLflow
    os.environ['MLFLOW_WORKSPACE'] = 'team-alpha'

    # Fix tracking URI to include /mlflow prefix
    uri = os.environ.get('MLFLOW_TRACKING_URI', '')
    if uri and not uri.endswith('/mlflow'):
        os.environ['MLFLOW_TRACKING_URI'] = uri + '/mlflow'
```

### Deployment via MCPServer CR

```yaml
apiVersion: mcp.opendatahub.io/v1alpha1
kind: MCPServer
metadata:
  name: mlflow-mcp
  namespace: redhat-ods-applications
spec:
  image: quay.io/YOUR_ORG/mlflow-mcp:3.15.0-v2
  port: 8080
  transport: streamable-http
  env:
    - name: MLFLOW_TRACKING_URI
      value: "http://mlflow-server.redhat-ods-applications.svc:5000"
    - name: PYTHONPATH
      value: "/mnt/startup"
  volumeMounts:
    - name: startup
      mountPath: /mnt/startup
  volumes:
    - name: startup
      configMap:
        name: mlflow-mcp-startup
```

### Alternative: Manual Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-mcp
  namespace: redhat-ods-applications
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow-mcp
  template:
    metadata:
      labels:
        app: mlflow-mcp
    spec:
      serviceAccountName: mlflow-mcp
      containers:
        - name: mlflow-mcp
          image: quay.io/YOUR_ORG/mlflow-mcp:3.15.0-v2
          ports:
            - containerPort: 8080
          env:
            - name: MLFLOW_TRACKING_URI
              value: "http://mlflow-server.redhat-ods-applications.svc:5000"
            - name: PYTHONPATH
              value: "/mnt/startup"
          volumeMounts:
            - name: startup
              mountPath: /mnt/startup
      volumes:
        - name: startup
          configMap:
            name: mlflow-mcp-startup
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow-mcp
  namespace: redhat-ods-applications
spec:
  selector:
    app: mlflow-mcp
  ports:
    - port: 8080
      targetPort: 8080
```

### Configuration in config.yaml

```yaml
mlflow:
  url: "http://mlflow-mcp.redhat-ods-applications.svc.cluster.local:8080/mcp"
  timeout: 60
  connect_timeout: 30
```

### Verification

Ask the agent: "Search my MLflow experiments"

Expected: Returns list of experiments with IDs and names.

---

## GitHub MCP

**Source**: [@modelcontextprotocol/server-github](https://www.npmjs.com/package/@modelcontextprotocol/server-github)

### Deployment

Pre-installed in the agent image via `npm install -g @modelcontextprotocol/server-github@latest`. No separate deployment needed.

### Configuration in config.yaml

```yaml
github:
  command: "npx"
  args: ["-y", "@modelcontextprotocol/server-github"]
  env:
    GITHUB_PERSONAL_ACCESS_TOKEN: "${GITHUB_TOKEN}"
  timeout: 30
  connect_timeout: 15
  tools:
    include:
      - create_pull_request
      - get_file_contents
      - push_files
      - create_branch
      - list_branches
      - search_code
      - create_or_update_file
      - list_commits
```

### Required Credential

A GitHub Personal Access Token (PAT) with `repo` scope. Add to the agent secret:

```bash
oc patch secret rhoai-copilot-secrets -n rhoai-copilot \
  --type merge -p '{"data":{"github-token":"'$(echo -n "ghp_YOUR_TOKEN" | base64)'"}}'
```

### Verification

Ask the agent: "List branches in the rhoai-copilot repository"

Expected: Returns branch list from the configured repository.

---

## Agent config.yaml (Complete Reference)

The full `config.yaml` with all 5 MCP servers configured:

```yaml
model:
  default: "gemini-2.5-flash"
  base_url: "https://generativelanguage.googleapis.com/v1beta/openai/"
  provider: custom
  api_key: "${GEMINI_API_KEY}"

mcp_servers:
  argocd:
    command: "argocd-mcp"
    args: ["stdio"]
    env:
      ARGOCD_BASE_URL: "${ARGOCD_BASE_URL}"
      ARGOCD_API_TOKEN: "${ARGOCD_API_TOKEN}"
      ARGOCD_INSECURE: "true"
    timeout: 60
    connect_timeout: 30
    supports_parallel_tool_calls: true
    tools:
      resources: false
      prompts: false
      include:
        - list_applications
        - get_application
        - get_application_resource_tree
        - get_application_managed_resources
        - get_application_workload_logs
        - get_resource_events
        - get_resource_actions
        - list_clusters
        - get_appproject
        - sync_application

  rhoai:
    url: "http://rhoai-mcp.rhoai-copilot.svc:8000/mcp"
    timeout: 60
    connect_timeout: 30
    tools:
      include:
        - list_data_science_projects
        - get_project_details
        - get_project_status
        - get_cluster_resources
        - cluster_summary
        - project_summary
        - list_workbenches
        - get_workbench
        - get_workbench_url
        - list_notebook_images
        - list_inference_services
        - get_inference_service
        - list_serving_runtimes
        - get_model_endpoint
        - prepare_model_deployment
        - check_deployment_prerequisites
        - estimate_serving_resources
        - list_registered_models
        - get_registered_model
        - list_model_versions
        - get_model_artifacts
        - list_training_jobs
        - get_training_progress
        - list_training_runtimes
        - estimate_resources
        - list_data_connections
        - list_storage
        - get_pipeline_server
        - explore_cluster
        - diagnose_resource
        - multi_resource_status
        - resource_status
        - list_resource_names
        - create_workbench
        - start_workbench
        - stop_workbench
        - create_s3_data_connection
        - deploy_model

  openshift:
    url: "http://openshift-mcp-server.ocp-mcp-server.svc.cluster.local:8080/mcp"
    timeout: 60
    connect_timeout: 30

  mlflow:
    url: "http://mlflow-mcp.redhat-ods-applications.svc.cluster.local:8080/mcp"
    timeout: 60
    connect_timeout: 30

  github:
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: "${GITHUB_TOKEN}"
    timeout: 30
    connect_timeout: 15
    tools:
      include:
        - create_pull_request
        - get_file_contents
        - push_files
        - create_branch
        - list_branches
        - search_code
        - create_or_update_file
        - list_commits

gateway:
  enabled: false

dashboard:
  enabled: true
  host: "0.0.0.0"
  port: 18789
  basic_auth:
    enabled: true
    username: admin
    password_hash: "placeholder"  # Computed at startup by entrypoint.sh

tools:
  code_execution:
    enabled: "on"
    backend: local
  file_operations:
    enabled: "on"
  web_search:
    enabled: "off"
  browser:
    enabled: "off"

toolsets:
  skills: true
  memory: true
  session_search: true
  delegation: true
  cronjob: true
  kanban: false

delegation:
  max_concurrent_children: 3

memory:
  enabled: true
  providers: []

skills:
  enabled: true
  directory: /sandbox/.hermes/skills
  curator:
    enabled: true
```

---

## Troubleshooting MCP Connections

See [Troubleshooting Guide](troubleshooting.md) for common MCP issues. Quick checks:

```bash
# Check if MCP server pods are running
oc get pods -n rhoai-copilot -l app=rhoai-mcp
oc get pods -n ocp-mcp-server
oc get pods -n redhat-ods-applications -l app=mlflow-mcp

# Test HTTP connectivity from agent pod
AGENT_POD=$(oc get pods -n rhoai-copilot -l app=rhoai-copilot -o jsonpath='{.items[0].metadata.name}')
oc exec $AGENT_POD -n rhoai-copilot -- curl -s http://rhoai-mcp.rhoai-copilot.svc:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}'
```
