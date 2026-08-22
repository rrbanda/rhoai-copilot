# Troubleshooting Guide

Common errors encountered during RHOAI Copilot deployment and their resolutions. These are all real issues that were encountered and fixed during the initial deployment.

---

## Container Image Issues

### `exec format error` on Pod Start

**Symptom**: Pod enters CrashLoopBackOff immediately. Logs show:
```
exec /sandbox/.venv/bin/python3: exec format error
```

**Cause**: Image was built on ARM64 (Apple Silicon Mac) but OpenShift runs AMD64 nodes.

**Fix**: Rebuild with explicit platform:
```bash
podman build --platform linux/amd64 \
  -t quay.io/YOUR_ORG/rhoai-copilot:latest \
  -f runtimes/hermes/Containerfile .
```

**Prevention**: Always include `--platform linux/amd64` in build commands when targeting OpenShift.

---

### `ImagePullBackOff`

**Symptom**: Pod stuck in `ImagePullBackOff` state.

**Cause**: Either the image doesn't exist at the specified path, or the registry requires authentication.

**Fix**:
```bash
# Verify image exists
podman pull quay.io/YOUR_ORG/rhoai-copilot:latest

# For private registries, create a pull secret
oc create secret docker-registry my-registry-creds \
  --docker-server=quay.io \
  --docker-username=YOUR_USER \
  --docker-password=YOUR_PASSWORD \
  -n rhoai-copilot

# Link to the ServiceAccount
oc secrets link rhoai-copilot my-registry-creds --for=pull -n rhoai-copilot
```

---

## MCP Server Connectivity

### RHOAI MCP: Connection Refused

**Symptom**: Agent reports "MCP server rhoai not reachable" or connection timeout.

**Diagnosis**:
```bash
# Check if pod is running
oc get pods -n rhoai-copilot -l app=rhoai-mcp

# Check service exists
oc get svc rhoai-mcp -n rhoai-copilot

# Test from agent pod
AGENT_POD=$(oc get pods -n rhoai-copilot -l app=rhoai-copilot -o jsonpath='{.items[0].metadata.name}')
oc exec $AGENT_POD -n rhoai-copilot -- curl -v http://rhoai-mcp.rhoai-copilot.svc:8000/mcp
```

**Common Fixes**:
1. Pod not running → Check `oc describe pod` for image/resource issues
2. Service selector mismatch → Verify `app: rhoai-mcp` label on pod
3. Wrong port → RHOAI MCP listens on 8000 by default

---

### OpenShift MCP: RBAC "Forbidden" Errors

**Symptom**: OpenShift MCP tools return 403 Forbidden when listing namespaces or pods.

**Cause**: The agent's ServiceAccount (or the OpenShift MCP server's SA) lacks `cluster-reader` permissions.

**Fix**: Grant `cluster-reader` to the appropriate ServiceAccount:
```bash
# For the agent pod's SA (used when agent injects its own token)
oc adm policy add-cluster-role-to-user cluster-reader \
  system:serviceaccount:rhoai-copilot:rhoai-copilot

# For the OpenShift MCP server's SA
oc adm policy add-cluster-role-to-user cluster-reader \
  system:serviceaccount:ocp-mcp-server:openshift-mcp-server
```

**Verification**:
```bash
oc auth can-i list namespaces --as=system:serviceaccount:rhoai-copilot:rhoai-copilot
# yes
```

---

### MLflow MCP: `No such option '--transport'`

**Symptom**: MLflow MCP pod crashes with:
```
Error: No such option '--transport'.
```

**Cause**: Using MLflow version < 3.15.0. The `--transport` CLI flag was added in MLflow 3.15.0.

**Fix**: Use `mlflow[mcp]==3.15.0` in the Containerfile and set transport via environment variables instead of CLI flags:

```dockerfile
FROM python:3.13-slim
RUN pip install --no-cache-dir "mlflow[mcp]==3.15.0"

# Transport is set via FASTMCP env vars, not CLI
ENV FASTMCP_PORT=8080 \
    FASTMCP_HOST=0.0.0.0 \
    FASTMCP_TRANSPORT=streamable-http \
    FASTMCP_WORKER_COUNT=2

EXPOSE 8080
ENTRYPOINT ["mlflow", "mcp", "run"]
```

The MLflow MCP server uses FastMCP internally and reads `FASTMCP_*` environment variables to configure transport.

---

### MLflow MCP: `MCPEndpointUnavailable` Status

**Symptom**: MCPServer CR shows `MCPEndpointUnavailable` in status, but the pod is running.

**Cause**: Cosmetic issue with the MCP Lifecycle Operator's status reporting. The health check may not properly detect `streamable-http` transport readiness.

**Diagnosis**: Test the endpoint directly:
```bash
curl -s http://mlflow-mcp.redhat-ods-applications.svc.cluster.local:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"capabilities":{}},"id":1}'
```

If you get a valid JSON-RPC response, the server is working — ignore the CR status.

---

### MLflow MCP: Authentication Failure

**Symptom**: MLflow MCP returns 401/403 when querying experiments.

**Cause**: Missing MLflow tracking token or incorrect workspace configuration.

**Fix**: Ensure `sitecustomize.py` is properly mounted:

```yaml
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: mlflow-mcp-startup
data:
  sitecustomize.py: |
    import os
    token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'
    if os.path.isfile(token_path):
        os.environ['MLFLOW_TRACKING_TOKEN'] = open(token_path).read().strip()
    os.environ['MLFLOW_WORKSPACE'] = 'team-alpha'
    uri = os.environ.get('MLFLOW_TRACKING_URI', '')
    if uri and not uri.endswith('/mlflow'):
        os.environ['MLFLOW_TRACKING_URI'] = uri + '/mlflow'
```

Mount as `PYTHONPATH=/mnt/startup` in the deployment so Python auto-loads it.

---

### GitHub MCP: Tools Work but Operations Fail

**Symptom**: GitHub MCP shows 26 tools available, but all operations return authentication errors.

**Cause**: `GITHUB_TOKEN` not set or empty in the secret.

**Fix**:
```bash
# Check if token exists in secret
oc get secret rhoai-copilot-secrets -n rhoai-copilot -o jsonpath='{.data.github-token}' | base64 -d

# If empty, patch it
oc patch secret rhoai-copilot-secrets -n rhoai-copilot \
  --type merge -p '{"data":{"github-token":"'$(echo -n "ghp_YOUR_TOKEN" | base64)'"}}'

# Restart the pod to pick up new secret
oc rollout restart deployment/rhoai-copilot -n rhoai-copilot
```

---

## ArgoCD Issues

### ArgoCD MCP: Permission Denied for Specific Apps

**Symptom**: Agent can list most applications but gets "permission denied" for specific ones (e.g., `rhoai-dsc`).

**Cause**: ArgoCD project-level RBAC restricts which applications the agent's account can access.

**Fix**: Update ArgoCD RBAC policy in `argocd-rbac-cm` ConfigMap:
```
p, role:hermes-agent, applications, get, platform/rhoai-dsc, allow
```

Or grant access to all apps in a project:
```
p, role:hermes-agent, applications, get, platform/*, allow
```

---

### ArgoCD Token Expired

**Symptom**: All ArgoCD MCP operations fail with 401.

**Fix**: Generate a new token:
```bash
# Using ArgoCD CLI
argocd account generate-token --account hermes-agent

# Update the secret
oc patch secret rhoai-copilot-secrets -n rhoai-copilot \
  --type merge -p '{"data":{"argocd-api-token":"'$(echo -n "NEW_TOKEN" | base64)'"}}'

# Restart pod
oc rollout restart deployment/rhoai-copilot -n rhoai-copilot
```

---

## Agent Runtime Issues

### Dashboard Not Accessible

**Symptom**: Route URL returns 502 Bad Gateway.

**Diagnosis**:
```bash
# Check route exists and has proper TLS
oc get route rhoai-copilot -n rhoai-copilot -o yaml

# Check service endpoints
oc get endpoints rhoai-copilot -n rhoai-copilot

# Check pod logs
oc logs deployment/rhoai-copilot -n rhoai-copilot | grep -i "dashboard\|error"
```

**Common Fixes**:
1. Service port mismatch → Ensure service targets port 18789
2. Route termination → Use `edge` TLS termination
3. Pod crash during startup → Check `entrypoint.sh` logs for credential issues

---

### Skills Not Loading

**Symptom**: Agent responds but doesn't use skills (no skill_view calls in tool use).

**Diagnosis**:
```bash
# Check skills directory in pod
oc exec $AGENT_POD -n rhoai-copilot -- ls -la /tmp/work/.hermes/skills/

# Verify ConfigMaps exist
oc get configmaps -n rhoai-copilot | grep skill-
```

**Common Fixes**:
1. ConfigMap not mounted → Check Kustomize `configMapGenerator` includes the skill
2. Skill name not in `SKILLS` variable in `entrypoint.sh`
3. SKILL.md file path wrong → Must be at `/mnt/skill-NAME/SKILL.md`

---

### Memory/State Lost After Restart

**Symptom**: Agent loses memory and conversation history after pod restart.

**Cause**: PVC not mounted or symlinks in `entrypoint.sh` not pointing to PVC.

**Fix**: Ensure PVC is bound and mounted at `/persistent`:
```bash
oc get pvc rhoai-copilot-data -n rhoai-copilot
# Should show: Bound

# Verify in deployment.yaml:
# volumes:
#   - name: persistent-data
#     persistentVolumeClaim:
#       claimName: rhoai-copilot-data
# volumeMounts:
#   - name: persistent-data
#     mountPath: /persistent
```

---

## Disconnected Environment Issues

### Operator CatalogSource Not Found

**Symptom**: OLM operators fail to install with "CatalogSourcesUnhealthy".

**Fix**: Ensure mirrored catalog sources exist:
```bash
oc get catalogsource -n openshift-marketplace
# Should show your mirrored catalogs
```

See [Disconnected Setup Guide](../getting-started/disconnected-setup.md).

---

### Images Not Pulling in Air-Gapped Cluster

**Symptom**: Pods stuck in `ImagePullBackOff` in disconnected cluster.

**Fix**: Verify `ImageDigestMirrorSet` is configured:
```bash
oc get imagedigestmirrorset
oc get imagecontentpolicy
```

Push all required images to your internal registry and ensure the IDMS maps them correctly.

---

## Quick Diagnostic Commands

```bash
# Full status check
oc get pods -n rhoai-copilot
oc get pods -n ocp-mcp-server
oc get pods -n redhat-ods-applications -l app=mlflow-mcp

# Agent logs
oc logs deployment/rhoai-copilot -n rhoai-copilot --tail=50

# MCP connectivity from agent
AGENT_POD=$(oc get pods -n rhoai-copilot -l app=rhoai-copilot -o jsonpath='{.items[0].metadata.name}')
for svc in "rhoai-mcp.rhoai-copilot.svc:8000" "openshift-mcp-server.ocp-mcp-server.svc.cluster.local:8080" "mlflow-mcp.redhat-ods-applications.svc.cluster.local:8080"; do
  echo "Testing $svc..."
  oc exec $AGENT_POD -n rhoai-copilot -- curl -s -o /dev/null -w "%{http_code}" http://$svc/mcp
  echo ""
done

# RBAC check
oc auth can-i list namespaces --as=system:serviceaccount:rhoai-copilot:rhoai-copilot
oc auth can-i get pods --all-namespaces --as=system:serviceaccount:rhoai-copilot:rhoai-copilot
```
