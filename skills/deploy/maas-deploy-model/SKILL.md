---
skill: deploy-maas-model
description: Deploy a model to Models-as-a-Service (MaaS) on OpenShift AI — creates MaaSSubscription, MaaSAuthPolicy, and an API key, then verifies access via the MaaS gateway
tags: [openshift, rhoai, maas, subscription, authpolicy, api-key, models, kuadrant, gateway]
---

# Deploy Model to MaaS

Add a model to Models-as-a-Service (MaaS) by creating the required governance resources and issuing an API key for gateway access.

## Agent Behavior Rules (MANDATORY — never skip)

### 1. Always use AskUserQuestion for every decision point
**Never ask the user a question in plain text.** Every question — namespace, resource name, vLLM args, deploy mode, subscription owner, rate limits — MUST be presented via the `AskUserQuestion` tool with a menu of options. The user selects from a list; they do not type free-form answers.

### 2. Always show default vLLM args before asking the user
Before presenting the vLLM args question, run:

```bash
./get-default-args.sh "<resolved-model-name>"
```

This script reads `model-configs.json` and outputs one arg per line, detecting family + variant + size automatically. Display the full output as a code block in the **first option** of the AskUserQuestion menu, with the label:

> **"Use defaults (Recommended)"**

Always offer at least one common override option (e.g. reduced `--max-model-len`) and an "Other" free-text fallback. The user must never be asked about vLLM args without seeing the defaults first.

---

## Namespace Reference

| Resource | Namespace |
|---|---|
| MaaSSubscription, MaaSAuthPolicy | `models-as-a-service` |
| MaaSModelRef | model's own namespace (e.g. `<model-namespace>`) |
| maas-api, maas-postgres | `redhat-ai-gateway-infra` |
| Kuadrant AuthPolicy, Gateway | `openshift-ingress` |

## API Group

All MaaS CRs use **`maas.opendatahub.io/v1alpha1`** — not `models.opendatahub.io/v1alpha1`.

## Gateway URL

```bash
MAAS_HOST=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.host}')
TLS=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
SCHEME=$([[ -n "$TLS" ]] && echo "https" || echo "http")
MAAS_URL="${SCHEME}://${MAAS_HOST}"
```

> The exact URL is also printed by `check_maas_availability.sh` and `deploy-llm.sh` upon success.

---

## Phase 0 — MaaS Availability Pre-flight (ALWAYS run first)

Before doing anything else, verify MaaS is healthy. Run:

```bash
cd ~/.claude/skills/deploy-maas-model
./check_maas_availability.sh
```

All checks must pass (0 failures) before proceeding. If any check fails, stop and direct the user to `/debug-maas` with the relevant issue letter shown in the output.

---

## Phase 1 — Model Pre-Validation

These three steps are **independent** — each can be run on its own without the others. All scripts live in:

```bash
cd ~/.claude/skills/deploy-maas-model
```

---

### Step 1A — Search Model Catalog (`check-catalog.sh`)

Searches the internal OpenShift model catalog (PostgreSQL). Skip this step entirely if the user is bringing a model from HuggingFace.

```bash
cd ~/.claude/skills/deploy-maas-model

# Search by keyword (case-insensitive, partial match)
./check-catalog.sh search llama
./check-catalog.sh search "8b.*fp8"

# List all models
./check-catalog.sh list

# Filter by family/tag
./check-catalog.sh list qwen

# Show all available family/tag names
./check-catalog.sh list-families
```

**If multiple models match**, show all results to the user and ask which specific variant (including quantization) they want. Use **only** the exact name returned — do not guess or modify it.

If the model is **not in the catalog** (HuggingFace model), proceed directly to Step 1B with the HuggingFace model ID (e.g. `meta-llama/Llama-3.1-8B-Instruct`).

---

### Step 1B — Check VRAM Requirements (`check-vram.sh`)

Estimates how much VRAM the model needs. Works with **any** model source — catalog name, HuggingFace ID, or a manual GB override. Does not touch the cluster.

```bash
cd ~/.claude/skills/deploy-maas-model

# Catalog model
./check-vram.sh "RedHatAI/Qwen3-8B-FP8-dynamic"

# HuggingFace model (queries HF API automatically)
./check-vram.sh "meta-llama/Llama-3.1-70B-Instruct"

# Verbose breakdown (shows precision, overhead multiplier, calculation steps)
./check-vram.sh "RedHatAI/Qwen3-8B-FP8-dynamic" -v

# Manual override — skip all calculation
./check-vram.sh "my-custom-model" --vram 24
```

**Resolution order** (automatic):
1. `--vram` flag → use directly, skip everything else
2. Internal catalog DB → uses stored `min_vram_gb` or precision tags
3. HuggingFace API → reads `safetensors.parameters` for param count + dtype
4. Name heuristics → parses `8B`, `70B` etc. from the model name + precision tags

**Machine-readable output** (always the last line on stdout):
```
VRAM_GB=18.36
```

Capture it for use in Step 1C:
```bash
VRAM=$(./check-vram.sh "org/model" | grep ^VRAM_GB= | cut -d= -f2)
./check-machines.sh cluster --vram "$VRAM"
```

---

### Step 1C — Check Available Machines (`check-machines.sh`)

Checks whether the cluster has suitable free GPUs, or recommends AWS instances. Completely decoupled from model identity — only needs a VRAM number.

```bash
cd ~/.claude/skills/deploy-maas-model

# Check live cluster GPU availability
./check-machines.sh cluster --vram 18

# Verbose — shows all nodes including fully-occupied ones
./check-machines.sh cluster --vram 18 -v

# If cluster has no capacity — recommend AWS instances
./check-machines.sh aws --vram 18
./check-machines.sh aws --vram 18 --top 10
```

AWS scoring prefers:
- Memory efficiency (1.2–1.5× the VRAM requirement)
- Single-GPU fit over multi-GPU where possible
- Right-sized CPU and RAM (not oversized)

> If no GPUs are available on the cluster, inform the user before proceeding to Phase 2. A MaaSModelRef only exists once the underlying model is deployed and running.

---

## Phase 2 — Model Deployment (LLMInferenceService)

Deploy the model to the cluster using `deploy-llm.sh`. This creates a `LLMInferenceService` (`serving.kserve.io/v1alpha2`) wired to the MaaS gateway. The script runs MaaS health checks automatically before deploying.

### Deployment modes

The script prompts for a deployment mode interactively when run from a TTY, or accepts `--deploy-mode <mode>`:

| Mode | When to use | What it creates |
|---|---|---|
| `vllm` **(default)** | Single-node, standard vLLM inference | Local `LLMInferenceServiceConfig` cloned from the matching single-node template (same pattern as `qwen3-8b-fp8-dynamic`, `redhataibge-m3`) |
| `llm-d` | Multi-node / prefill-decode split scheduling | Clones a user-selected global `LLMInferenceServiceConfig` from `redhat-ods-applications` into the model namespace |

Both modes create a local `LLMInferenceServiceConfig` named after the model in the model namespace, then reference it via `spec.baseRefs`.

```bash
cd ~/.claude/skills/deploy-maas-model

# vLLM mode (default) — same pattern as running models
./deploy-llm.sh -n qwen3-8b -ns <model-namespace> \
  -s "RedHatAI/Qwen3-8B-FP8-dynamic" \
  --gpu 1 --cpu 2 --memory 16Gi

# Explicit vLLM mode
./deploy-llm.sh -n my-llama -ns <model-namespace> \
  --deploy-mode vllm \
  -s "meta-llama/Llama-3.1-8B-Instruct" \
  --gpu 1 --cpu 4 --memory 20Gi \
  --args "--dtype=bfloat16,--max-model-len=32768,--enable-auto-tool-choice"

# llm-d mode — prompts to select a global config (e.g. multi-node PD split)
./deploy-llm.sh -n my-llama -ns <model-namespace> \
  --deploy-mode llm-d \
  -s "meta-llama/Llama-3.1-8B-Instruct" \
  --gpu 2 --cpu 8 --memory 40Gi

# HuggingFace model
./deploy-llm.sh -n my-model -ns <model-namespace> \
  -s "hf://org/model-name" \
  --gpu 1 --cpu 4 --memory 16Gi

# With a custom request timeout (20 min — for large reasoning models)
./deploy-llm.sh -n my-model -ns <model-namespace> \
  -s "RedHatAI/Qwen3-8B-FP8-dynamic" \
  --gpu 1 --cpu 2 --memory 16Gi \
  --request-timeout 1200

# Dry-run — preview manifests without applying
./deploy-llm.sh -n my-model -ns <model-namespace> -s "RedHatAI/Qwen3-8B-FP8-dynamic" \
  --gpu 1 --cpu 2 --memory 16Gi --dry-run

# Clone from existing LLMInferenceService
./deploy-llm.sh --clone-from <model-namespace>/<existing-model> -n qwen3-copy --dry-run

# Skip LLMInferenceServiceConfig creation — use an existing local config
./deploy-llm.sh -n my-model -ns <model-namespace> -s "..." --llm-config my-existing-config
```

**What the script does (in order):**
1. Resolves the storage URI (OCI from catalog, or hf://, or s3://)
2. Prompts for deployment mode (vllm or llm-d) if not specified
3. Creates a local `LLMInferenceServiceConfig` in the model namespace
4. Creates a connection secret for the RHOAI dashboard
5. **Always** creates `<name>-hw-profile` in `redhat-ods-applications` from the deployment resources (CPU/memory/GPU); pass `--hardware-profile <existing>` to use a pre-existing profile instead
6. Applies the `LLMInferenceService` manifest (referencing the local config via `spec.baseRefs`)
7. Applies RBAC (Role + RoleBinding for `system:authenticated`)
8. Waits up to `--timeout` seconds for the `Ready` condition, then prints the gateway URL and a `create-governance.sh` hint
9. If `--request-timeout` was given (or a non-zero value was chosen interactively), patches the HTTPRoute and attempts to write the timeout into the LLMInferenceService spec for durability

### Request timeout

Three layers must all agree — the shortest one wins:

| Layer | Resource | Default | Scope |
|---|---|---|---|
| **HAProxy** | OpenShift Route annotation | **60s** — cuts TCP regardless of Envoy | shared across all models on the gateway |
| **Envoy** | HTTPRoute `timeouts.request` | `0s` (no limit) | per model |
| **Durable** | `LLMInferenceService.spec.router.route.http.spec.rules` | — | per model; controller reads this on reconciliation |

Both scripts set all three layers automatically:

```bash
# At deployment time
./deploy-llm.sh ... --request-timeout 1200   # 20 min

# After deployment (update existing model)
./set-timeout.sh -n <name> -ns <namespace> --timeout-seconds 1200

# Remove explicit timeout (back to gateway default)
./set-timeout.sh -n <name> -ns <namespace> --timeout-seconds 0

# Preview what would change
./set-timeout.sh -n <name> -ns <namespace> --timeout-seconds 600 --dry-run
```

> **HAProxy note:** The OpenShift Route (`maas-default-gateway`) is shared across all models. Raising the timeout there affects every model on the gateway — use the largest timeout needed in the cluster.
>
> **Durability note:** The LLMInferenceService spec patch can be blocked by the admission webhook if the hardware profile referenced in the model's annotations no longer exists. `set-timeout.sh` detects this upfront and offers to recreate the profile from the model's own resources before proceeding.

---

## Phase 3 — MaaS Governance (`create-governance.sh`)

After `deploy-llm.sh` reports Ready, run `create-governance.sh` to create all three governance objects in one step:

```bash
cd ~/.claude/skills/deploy-maas-model

# Single user, default rate limits (1M/h, 10M/24h)
./create-governance.sh -n <name> -ns <namespace> --user <oc-username>

# Group access with higher limits
./create-governance.sh -n <name> -ns <namespace> \
  --group <group-name> --rate-hour 10000000 --rate-day 100000000

# Both user and group
./create-governance.sh -n <name> -ns <namespace> \
  --user <username> --group <group-name>

# Dry-run — preview manifests only
./create-governance.sh -n <name> -ns <namespace> --user <username> --dry-run
```

**What the script does (in order):**

| # | Action | Detail |
|---|---|---|
| 1 | Create `MaaSModelRef` | In the model namespace — links the LLMInferenceService into MaaS |
| 2 | Create `MaaSSubscription` | In `models-as-a-service` — grants access and sets token rate limits |
| 3 | Create `MaaSAuthPolicy` | In `models-as-a-service` — defines who can authenticate |
| 4 | Verify all three phases | Waits ~10s then prints phase of each resource |
| 5 | Generate test scripts | Writes `create-apikey.sh` and `test-<name>.sh` to the current directory so the user can immediately create an API key and send a test request |

**Field notes:**
- `--user` / `--group` — at least one required; both can be passed simultaneously
- `--rate-hour` / `--rate-day` — token rate limits; window units: `s`, `m`, `h` (no `d`)
- `--priority` — higher wins when a user has multiple subscriptions (default: 10)
- `--sub-name` / `--auth-name` — override generated resource names (`<name>-sub`, `<name>-auth`)

After both MaaSSubscription and MaaSAuthPolicy exist, the maas-controller will:
1. Transition the MaaSModelRef from `Pending` → `Ready`
2. Auto-create a Kuadrant `AuthPolicy` (`maas-gateway-auth`) in `openshift-ingress` that wires up OpenShift token validation and API key auth

```bash
# Verify all three resources
oc get maasmodelref <name> -n <namespace> -o jsonpath='{.status.phase}'
# Expected: Ready

oc get maassubscription <name>-sub -n models-as-a-service -o jsonpath='{.status.phase}'
# Expected: Active

oc get maasauthpolicy <name>-auth -n models-as-a-service -o jsonpath='{.status.phase}'
# Expected: Active

# Verify Kuadrant AuthPolicy was created
oc get authpolicy -n openshift-ingress
# Expected: maas-gateway-auth  (Accepted + Enforced)
```

---

### Step 6 — Create an API Key

Use your OpenShift Bearer token — Kuadrant validates it via Kubernetes TokenReview and injects `X-MaaS-Username` and `X-MaaS-Group` automatically.

```bash
OC_TOKEN=$(oc whoami -t)
MAAS_HOST=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.host}')
TLS=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
MAAS_URL="$([[ -n "$TLS" ]] && echo "https" || echo "http")://${MAAS_HOST}"

curl -s -X POST \
  -H "Authorization: Bearer $OC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"<key-name>","expirationDays":30}' \
  "$MAAS_URL/v1/api-keys"
```

Expected response:

```json
{
  "key": "sk-oai-<token>",
  "keyPrefix": "sk-oai-...",
  "id": "<uuid>",
  "name": "<key-name>",
  "subscription": "<subscription-name>",
  "createdAt": "...",
  "expiresAt": "...",
  "ephemeral": false
}
```

Save the `key` value — it is shown only once.

**API key management endpoints** (authenticated with OC Bearer token):

```bash
# List your subscriptions
curl -s -H "Authorization: Bearer $OC_TOKEN" "$MAAS_URL/v1/subscriptions"

# Delete a key by ID
curl -s -X DELETE -H "Authorization: Bearer $OC_TOKEN" "$MAAS_URL/v1/api-keys/<key-id>"
```

---

### Step 7 — List Models via MaaS Gateway

```bash
API_KEY="sk-oai-<your-key>"
MAAS_HOST=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.host}')
TLS=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
MAAS_URL="$([[ -n "$TLS" ]] && echo "https" || echo "http")://${MAAS_HOST}"

curl -s -H "Authorization: Bearer $API_KEY" "$MAAS_URL/maas-api/v1/models"
```

> **Path note:** Use `/maas-api/v1/models` (prefix gets URL-rewritten to `/` inside the gateway, then `/v1/models` is served by maas-api).

Expected response: list of model objects with `id`, `url`, `ready`, `subscriptions`.

---

## Troubleshooting

### POST /v1/api-keys returns 500 — "Exception thrown while generating token"

**Cause:** The `X-MaaS-Username` or `X-MaaS-Group` headers are missing. This means the Kuadrant `AuthPolicy` (`maas-gateway-auth`) is not yet deployed.

**Fix:** Ensure both MaaSSubscription and MaaSAuthPolicy exist. The `maas-gateway-auth` AuthPolicy is auto-created only after the first pairing is established.

```bash
oc get authpolicy -n openshift-ingress
```

### MaaSModelRef stuck in Pending — "No active subscription and auth policy pairing found"

**Fix:** Create the MaaSSubscription and MaaSAuthPolicy referencing this model. Both are required — one alone is not enough.

### GET /v1/models returns empty list `{"data":[]}`

**Cause 1:** No MaaSModelRef exists (model not published to MaaS).
**Cause 2:** Calling without auth or with expired/invalid API key.
**Cause 3:** No active subscription for the authenticated user.

### HTTPS returns 503 or "Application is not available"

The Route TLS termination must be `edge` (not `reencrypt`). With `edge`, HAProxy terminates TLS using the wildcard cert and forwards plain HTTP to Envoy on port 80. With `reencrypt`, HAProxy tries to connect to the backend on HTTPS/443, but the Istio-intercepted Envoy pod doesn't serve TLS on that port directly.

```bash
oc patch route maas-default-gateway -n openshift-ingress --type=merge -p '{
  "spec": {
    "port": {"targetPort": "http"},
    "tls": {
      "termination": "edge",
      "insecureEdgeTerminationPolicy": "Redirect"
    }
  }
}'
```

### Model not found in catalog (Step 1A)

If `./check_nodes.sh list-models | grep -i "<term>"` returns nothing:
- Try broader search terms (family name only, e.g. `llama`, `qwen`, `deepseek`)
- Run `./check_nodes.sh list-families` to see available model families
- The model may not be in the catalog yet — contact the model ops team
