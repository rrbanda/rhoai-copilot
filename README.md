# RHOAI Copilot

An AI agent that manages, operates, deploys, and configures **Red Hat OpenShift AI** via GitOps — in both connected and disconnected (air-gapped) environments.

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-41-green.svg)](skills/)
[![Eval](https://img.shields.io/badge/Eval_Scenarios-44-orange.svg)](eval/)
[![MCP Servers](https://img.shields.io/badge/MCP_Servers-5-purple.svg)](mcp-servers/)
[![OCP](https://img.shields.io/badge/OCP-4.17%2B-red.svg)](docs/reference/compatibility-matrix.md)
[![RHOAI](https://img.shields.io/badge/RHOAI-3.5-red.svg)](docs/reference/compatibility-matrix.md)

---

## What It Does

```
You:    Deploy RHOAI 2.19 on my disconnected cluster.
        Internal registry is registry.lab.internal:5000.

Agent:  I'll guide you through the full disconnected deployment.

        1. First, let me check your current cluster state...
           [calls: list_applications, cluster_summary]

        2. For RHOAI 2.19 in a disconnected environment, you need:

           - Mirror operator catalogs with oc-mirror
           - Create ImageDigestMirrorSet for your registry
           - Configure CatalogSource pointing to mirrored index
           - Deploy operators via GitOps overlay

        3. Here's your ImageSetConfiguration:
           [generates YAML for registry.lab.internal:5000]

        4. After mirroring, apply this Kustomize overlay:
           [generates disconnected overlay patches]

        Shall I create a PR with these changes to your GitOps repo?
```

---

## Architecture

![RHOAI Copilot Architecture](docs/images/architecture-overview.png)

---

## Lifecycle Coverage

The agent's 41 skills map to the full RHOAI lifecycle across all 9 phases.

![RHOAI Lifecycle Coverage](docs/images/lifecycle-coverage.png)

| Phase | Skills | What It Covers |
|-------|--------|----------------|
| **Platform Setup** | `rhoai-disconnected-deploy` `rhoai-disconnected-helper` `rhoai-install-validator` `gitops-config-generator` | Operator deployment, disconnected/air-gapped clusters, install validation, Kustomize generation |
| **Plan** | `capacity-forecaster` `serving-runtime-advisor` `training-planner` `model-catalog-advisor` | GPU/CPU forecasting, runtime selection, training estimation, model catalog discovery |
| **Administer** | `rhoai-dsc-inspector` `rhoai-platform-status` `rhoai-upgrade-advisor` `kueue-quota-manager` `hardware-profile-manager` `feature-store-setup` | DSC inspection, platform readiness, upgrades, Kueue quotas, hardware profiles, Feast Feature Store |
| **Develop** | `experiment-tracker` `workbench-troubleshooter` `pipeline-debugger` `model-registry-manager` `workbench-provisioner` `ogx-rag-builder` `autorag-optimizer` `genai-playground-guide` | MLflow tracking, workbench debug + provisioning, pipelines, model registry, OGX RAG, AutoRAG, GenAI Playground |
| **Deploy** | `model-promotion-workflow` `rhoai-model-lifecycle` `maas-enable` `maas-deploy-model` `llmd-deployment-manager` `kserve-model-deployer` `maas-subscription-manager` `maas-external-models` | GitOps promotion, MaaS lifecycle, llm-d distributed inference, KServe serving, MaaS governance, external models |
| **Monitor** | `argocd-health-check` `argocd-diagnose-sync` `daily-report-generator` `incident-runbook` `maas-debug` `model-drift-monitor` | Sync health, drift root-cause, daily reports, incidents, MaaS debug, TrustyAI bias/drift monitoring |
| **Train** | `distributed-training-setup` `automl-trainer` | RayJob/PyTorchJob with Kueue, AutoML optimization |
| **Evaluate** | `lm-eval-runner` | LMEvalJob benchmarks via EvalHub (MMLU, HellaSwag, GSM8K) |
| **Maintain Safety** | `nemo-guardrails-configurator` `garak-security-scanner` | NeMo Guardrails (PII, content filtering), Garak vulnerability scanning |

---

## Safety Model

The agent operates under a strict 3-tier autonomy model defined in [`agent/rules.md`](agent/rules.md).

| Tier | Mode | Example Operations | Guard Rails |
|:----:|------|-------------------|-------------|
| 1 | Read-Only Advisory | Health checks, reports, capacity analysis, diagnostics | No confirmation needed |
| 2 | Controlled Writes | ArgoCD sync (dry-run first), workbench creation (`sandbox-*` only), PR creation | Human confirmation required |
| 3 | Autonomous | Daily health reports, drift detection alerts, status summaries | Pre-approved scope, no destructive actions |

**Hard constraints (never violated):** No deletes. No writes in `redhat-ods-*` or `openshift-*` namespaces. No direct cluster mutations for config changes (GitOps only). No credential exposure. No self-approval of Tier 2 operations.

---

## Connected vs. Disconnected

| Capability | Connected | Disconnected (Air-Gapped) |
|------------|:---------:|:-------------------------:|
| ArgoCD MCP | In-cluster | In-cluster |
| RHOAI MCP | In-cluster | In-cluster |
| OpenShift MCP | In-cluster | In-cluster |
| MLflow MCP | In-cluster | In-cluster |
| GitHub MCP | github.com | Gitea / GitLab (internal) |
| LLM Provider | Gemini API | Local vLLM / Ollama |
| Image sources | Public registries | Internal mirror registry |
| Deploy command | `oc apply -k .` | `oc apply -k runtimes/hermes/overlays/disconnected/` |

---

## Quick Start

```bash
# Clone
git clone https://github.com/rrbanda/rhoai-copilot.git
cd rhoai-copilot

# Create secrets
oc new-project rhoai-copilot
oc create secret generic rhoai-copilot-secrets \
  --from-literal=gemini-api-key=YOUR_KEY \
  --from-literal=argocd-api-token=YOUR_TOKEN \
  --from-literal=argocd-base-url=https://YOUR_ARGOCD_URL \
  --from-literal=dashboard-password=YOUR_PASSWORD

# Build and deploy (or use pre-built: ghcr.io/rrbanda/rhoai-copilot:latest)
make build push
make deploy  # runs: oc apply -k .

# Validate
./scripts/validate-deployment.sh
```

See [Quick Start](docs/getting-started/quickstart.md) for the 5-minute version, or the [Full Deployment Guide](docs/getting-started/deployment-guide.md) for the complete walkthrough.

---

## Target Personas

| Persona | Primary Phases | Key Skills | MCP Servers |
|---------|---------------|------------|-------------|
| **AI Engineer** | Deploy, Develop, Plan | `maas-enable` `maas-deploy-model` `serving-runtime-advisor` | RHOAI, MLflow, ArgoCD |
| **Platform Engineer** | Install, Administer, Monitor | `rhoai-disconnected-deploy` `rhoai-platform-status` `argocd-diagnose-sync` | ArgoCD, OpenShift, GitHub |
| **MLOps Engineer** | Deploy, Plan, Monitor | `model-promotion-workflow` `capacity-forecaster` `experiment-tracker` | RHOAI, MLflow, ArgoCD |
| **Data Scientist** | Develop, Train, Evaluate | `workbench-troubleshooter` `pipeline-debugger` `training-planner` | RHOAI, MLflow, OpenShift |
| **SRE / Operations** | Monitor, Administer, Plan | `incident-runbook` `daily-report-generator` `argocd-health-check` | ArgoCD, OpenShift, RHOAI |

---

## Repository Structure

```
rhoai-copilot/
├── agent/                  # Agent identity, config, safety rules
│   ├── soul.md             #   Who the agent is and how it behaves
│   ├── rules.md            #   Hard safety constraints (protected via CODEOWNERS)
│   ├── config.yaml         #   MCP server connections and tool whitelist
│   └── profiles/           #   Environment-specific variables (connected / disconnected)
├── skills/                 # 22 capabilities organized by RHOAI lifecycle phase
│   ├── platform-setup/     #   (4) Deployment, disconnected, validation, config gen
│   ├── plan/               #   (3) Capacity, runtime advisor, training planner
│   ├── administer/         #   (3) DSC inspector, platform status, upgrade advisor
│   ├── develop/            #   (3) Experiments, workbenches, pipelines
│   ├── deploy/             #   (4) Model promotion, MaaS, lifecycle
│   ├── monitor/            #   (5) Health, drift, reports, incidents, MaaS debug
│   └── SKILL_SPEC.md       #   Skill authoring specification
├── workflows/              # 3 multi-step autonomous procedures
├── mcp-servers/            # MCP server docs and deployment manifests
│   ├── argocd/             #   GitOps lifecycle (stdio, 10 tools)
│   ├── rhoai/              #   OpenShift AI ops (HTTP, 35+ tools)
│   ├── openshift/          #   Cluster operations (HTTP, 20+ tools)
│   ├── mlflow/             #   Experiment tracking (HTTP, 15+ tools)
│   └── github/             #   Git operations (stdio, 8 whitelisted tools)
├── runtimes/               # Pluggable agent harness deployments
│   ├── base/               #   Shared K8s resources (Namespace, RBAC, PVC, NetworkPolicy)
│   ├── hermes/             #   Production runtime (python:3.13-slim)
│   ├── langgraph/          #   Planned
│   └── crewai/             #   Planned
├── eval/                   # 25 evaluation scenarios + automated runner
│   ├── scenarios/          #   22 skill scenarios + 3 adversarial safety tests
│   ├── scoring/            #   Rubric (accuracy, completeness, safety, efficiency)
│   └── run_eval.py         #   Eval runner with filtering and reporting
├── personas/               # 5 target user persona definitions
├── docs/                   # Docs (getting-started, concepts, guides, reference)
├── examples/               # Example interactions and templates
├── scripts/                # Deployment validation, audit logging
└── _context/               # Strategic planning knowledge base (8 files)
```

---

## Workflows

Three autonomous procedures compose skills into multi-step pipelines:

![Workflow Pipelines](docs/images/workflow-pipelines.png)

---

## Evaluation

44 eval scenarios cover 100% of skills across all 5 personas:

```bash
make eval-list                 # List all scenarios
make eval-report               # Generate evaluation report
make eval-persona PERSONA=sre  # Filter by persona
make eval-phase PHASE=monitor  # Filter by lifecycle phase
```

| Metric | Coverage |
|--------|----------|
| Skills with eval scenarios | 41/41 (100%) |
| Personas covered | 5/5 |
| Lifecycle phases covered | 9/9 |
| Adversarial safety tests | 3 |

---

## Documentation

| Document | Description |
|----------|-------------|
| [Quick Start](docs/getting-started/quickstart.md) | 5-minute deployment |
| [Full Deployment Guide](docs/getting-started/deployment-guide.md) | End-to-end deployment with all 5 MCP servers |
| [MCP Server Setup](docs/guides/mcp-server-setup.md) | Per-server deployment (ArgoCD, RHOAI, OpenShift, MLflow, GitHub) |
| [Obtaining Credentials](docs/guides/obtaining-credentials.md) | How to get each required credential |
| [Troubleshooting](docs/guides/troubleshooting.md) | Common errors and resolutions |
| [Disconnected Setup](docs/guides/disconnected-setup.md) | Air-gapped deployment guide |
| [Custom Skills](docs/guides/custom-skills.md) | How to add new agent capabilities |
| [Architecture](docs/concepts/architecture.md) | System design and MCP topology |
| [Autonomy Tiers](docs/concepts/autonomy-tiers.md) | Safety model and operational boundaries |
| [Environment Variables](docs/reference/environment-variables.md) | All environment variables reference |
| [Compatibility Matrix](docs/reference/compatibility-matrix.md) | Supported version combinations |
| [Audit Logging](docs/reference/audit-logging.md) | Structured audit trail for compliance |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Key entry points:

- **Add a skill**: Follow [skills/SKILL_SPEC.md](skills/SKILL_SPEC.md) — every new skill must include an eval scenario
- **Add a runtime**: See [runtimes/README.md](runtimes/README.md)
- **Add an eval scenario**: See [eval/README.md](eval/README.md) and `eval/scenarios/_template.yaml`
- **Report a bug**: Use the [bug report template](.github/ISSUE_TEMPLATE/bug-report.md)

```bash
make validate    # Lint skills and config
make build       # Build container image
make deploy      # Deploy to OpenShift
make eval-list   # List evaluation scenarios
```

## Acknowledgments

- MaaS (Models-as-a-Service) skills adapted from [MichalSteczko/rhoai-agentic-skills](https://github.com/MichalSteczko/rhoai-agentic-skills) — production-tested on RHOAI 3.5 / OCP 4.21

## License

Apache License 2.0. See [LICENSE](LICENSE).
