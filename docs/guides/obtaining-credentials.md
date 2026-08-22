# Obtaining Credentials

How to obtain each credential required by RHOAI Copilot. All credentials are stored in a single Kubernetes secret.

## Secret Structure

```bash
oc create secret generic rhoai-copilot-secrets \
  --from-literal=gemini-api-key='...' \
  --from-literal=argocd-api-token='...' \
  --from-literal=dashboard-password='...' \
  --from-literal=github-token='...' \
  -n rhoai-copilot
```

| Key | Required | Used By | Purpose |
|-----|----------|---------|---------|
| `gemini-api-key` | Yes | Agent LLM | Powers the AI reasoning |
| `argocd-api-token` | Yes | ArgoCD MCP | Authenticates to ArgoCD API |
| `dashboard-password` | Yes | Dashboard | Login to web UI |
| `github-token` | No | GitHub MCP | PR creation, code search |

---

## Gemini API Key

The agent uses Google's Gemini 2.5 Flash as its LLM backend.

### Steps

1. Go to [Google AI Studio](https://aistudio.google.com/)
2. Sign in with your Google account
3. Click **"Get API Key"** in the left sidebar
4. Click **"Create API Key"**
5. Select or create a Google Cloud project
6. Copy the generated key (starts with `AIza...`)

### Alternative: Other LLM Providers

The agent supports any OpenAI-compatible API. To use a different provider, modify `agent/config.yaml`:

```yaml
model:
  default: "gpt-4o"
  base_url: "https://api.openai.com/v1/"
  provider: custom
  api_key: "${LLM_API_KEY}"
```

Supported backends:
- Google Gemini (default)
- OpenAI (GPT-4o, GPT-4)
- Azure OpenAI
- Any vLLM/TGI endpoint with OpenAI-compatible API
- Local models via Ollama

### Cost Estimate

Gemini 2.5 Flash pricing (as of 2026):
- Input: ~$0.15 per 1M tokens
- Output: ~$0.60 per 1M tokens
- Typical session (10 queries): ~$0.02

---

## ArgoCD API Token

### Option 1: Generate from Admin Account

```bash
# Get the ArgoCD admin password
ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d)

# Get the ArgoCD route
ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops \
  -o jsonpath='{.spec.host}')

# Login
argocd login $ARGOCD_URL \
  --username admin \
  --password $ARGOCD_PASSWORD \
  --insecure

# Generate a token (valid indefinitely by default)
argocd account generate-token --account admin
```

### Option 2: Create a Dedicated Agent Account (Recommended)

1. Edit the ArgoCD ConfigMap to add a new account:

```bash
oc edit configmap argocd-cm -n openshift-gitops
```

Add under `data`:
```yaml
accounts.hermes-agent: apiKey
accounts.hermes-agent.enabled: "true"
```

2. Configure RBAC for the account:

```bash
oc edit configmap argocd-rbac-cm -n openshift-gitops
```

Add under `data.policy.csv`:
```
p, role:copilot-agent, applications, get, */*, allow
p, role:copilot-agent, applications, sync, */*, allow
p, role:copilot-agent, clusters, get, *, allow
p, role:copilot-agent, projects, get, *, allow
p, role:copilot-agent, logs, get, */*, allow
g, hermes-agent, role:copilot-agent
```

3. Generate the token:

```bash
argocd account generate-token --account hermes-agent
```

### Token Rotation

ArgoCD tokens don't expire by default. To set an expiry:

```bash
argocd account generate-token --account hermes-agent --expires-in 720h  # 30 days
```

Set up a CronJob or manual reminder to rotate before expiry.

---

## Dashboard Password

The dashboard password is used for basic auth login to the agent's web UI. Choose any strong password.

### Requirements
- Minimum 8 characters
- Used to log in as `admin` user
- Hashed at runtime using scrypt (the plaintext is never stored in the pod)

### How It Works

The `entrypoint.sh` reads the plaintext password from the secret and generates a scrypt hash at startup:

```python
import hashlib, secrets, base64
salt = secrets.token_bytes(16)
key = hashlib.scrypt(pw.encode(), salt=salt, n=16384, r=8, p=1, dklen=32)
```

This hash is then injected into `config.yaml` before the agent starts.

---

## GitHub Personal Access Token (Optional)

Required only if you want the agent to create pull requests, search code, or manage branches.

### Steps

1. Go to [GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta)
2. Click **"Generate new token"**
3. Configure:
   - **Token name**: `rhoai-copilot`
   - **Expiration**: 90 days (recommended)
   - **Repository access**: Select repositories the agent should manage
   - **Permissions**:
     - Contents: Read and Write
     - Pull requests: Read and Write
     - Metadata: Read-only (auto-selected)

4. Click "Generate token" and copy immediately

### Classic Token Alternative

If using classic tokens:
1. Go to [GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)](https://github.com/settings/tokens)
2. Click "Generate new token (classic)"
3. Select scope: `repo` (full control of private repositories)
4. Generate and copy

### Adding After Initial Deployment

If you initially deployed without a GitHub token:

```bash
oc patch secret rhoai-copilot-secrets -n rhoai-copilot \
  --type merge -p '{"data":{"github-token":"'$(echo -n "ghp_YOUR_TOKEN_HERE" | base64)'"}}'

# Restart to pick up new credential
oc rollout restart deployment/rhoai-copilot -n rhoai-copilot
```

---

## MLflow Credentials (Automatic)

The MLflow MCP server authenticates using the ServiceAccount token that's automatically mounted in the pod. No manual credential creation is needed.

The `sitecustomize.py` reads the token from:
```
/var/run/secrets/kubernetes.io/serviceaccount/token
```

### Requirements
- The MLflow MCP pod's ServiceAccount must have read access to the MLflow tracking server
- The MLflow tracking server must accept ServiceAccount token authentication
- The `MLFLOW_WORKSPACE` must be set to a valid workspace (e.g., `team-alpha`)

---

## OpenShift MCP Credentials (Automatic)

The OpenShift MCP authenticates using the agent's ServiceAccount token, injected at runtime by `entrypoint.sh`. No manual credential creation is needed.

### Requirements
- The agent's ServiceAccount must have `cluster-reader` ClusterRole bound:

```bash
oc adm policy add-cluster-role-to-user cluster-reader \
  system:serviceaccount:rhoai-copilot:rhoai-copilot
```

---

## Security Best Practices

1. **Never commit credentials to Git** — Use Kubernetes secrets or external secret managers
2. **Use fine-grained permissions** — Dedicated ArgoCD account with minimal RBAC, GitHub fine-grained tokens
3. **Rotate regularly** — GitHub PAT every 90 days, ArgoCD token as needed
4. **Use External Secrets Operator** — For production, sync from Vault/AWS Secrets Manager:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rhoai-copilot-secrets
  namespace: rhoai-copilot
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: rhoai-copilot-secrets
  data:
    - secretKey: gemini-api-key
      remoteRef:
        key: rhoai-copilot/gemini
        property: api_key
    - secretKey: argocd-api-token
      remoteRef:
        key: rhoai-copilot/argocd
        property: token
```

5. **Mark tokens as optional in deployments** — So the pod starts even if GitHub token is missing:

```yaml
env:
  - name: GITHUB_TOKEN
    valueFrom:
      secretKeyRef:
        name: rhoai-copilot-secrets
        key: github-token
        optional: true
```
