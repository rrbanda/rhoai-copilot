# RHOAI Copilot

An AI agent that manages, operates, deploys, and configures **Red Hat OpenShift AI** via GitOps — in both connected and disconnected (air-gapped) environments.

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-22-green.svg)](skills/)
[![MCP Servers](https://img.shields.io/badge/MCP_Tools-130+-purple.svg)](mcp-servers/)

---

## What It Does

```
You:    Deploy RHOAI 2.19 on my disconnected cluster.
        Internal registry is registry.lab.internal:5000.

Agent:  I'll guide you through the full disconnected deployment.

        1. First, let me check your current cluster state...
           [calls: list_applications, cluster_summary]

        2. For RHOAI 2.19 in a disconnected environment, you need:

           ▸ Mirror operator catalogs with oc-mirror
           ▸ Create ImageDigestMirrorSet for your registry
           ▸ Configure CatalogSource pointing to mirrored index
           ▸ Deploy operators via GitOps overlay

        3. Here's your ImageSetConfiguration:
           [generates YAML for registry.lab.internal:5000]

        4. After mirroring, apply this Kustomize overlay:
           [generates disconnected overlay patches]

        Shall I create a PR with these changes to your GitOps repo?
```

## Architecture

```
┌─────────────────────┐         ┌──────────────────────────────┐
│   RHOAI Copilot     │         │      MCP Servers (130+ tools)│
│                     │         │                              │
│  soul.md (identity) │────────▶│  ArgoCD    — GitOps lifecycle│
│  rules.md (safety)  │────────▶│  RHOAI     — AI platform ops│
│  22 skills          │────────▶│  OpenShift — Cluster ops     │
│  4 workflows        │────────▶│  MLflow    — Experiment mgmt │
│                     │────────▶│  GitHub    — Git operations  │
└─────────────────────┘         └──────────────────────────────┘
```

## Skills by RHOAI Lifecycle Phase

| Phase | Skills | Description |
|-------|--------|-------------|
| **Install** | `rhoai-disconnected-deploy`, `rhoai-disconnected-helper`, `rhoai-install-validator`, `gitops-config-generator` | Deploy RHOAI operators and prerequisites |
| **Plan** | `capacity-forecaster`, `serving-runtime-advisor`, `training-planner` | Resource estimation and architecture planning |
| **Administer** | `rhoai-dsc-inspector`, `rhoai-platform-status`, `rhoai-upgrade-advisor` | Platform configuration and maintenance |
| **Develop** | `experiment-tracker`, `workbench-troubleshooter`, `pipeline-debugger` | ML development workflow support |
| **Deploy** | `model-promotion-workflow`, `rhoai-model-lifecycle`, `maas-enable`, `maas-deploy-model` | Model serving, MaaS gateway, and promotion |
| **Monitor** | `argocd-health-check`, `argocd-diagnose-sync`, `daily-report-generator`, `incident-runbook`, `maas-debug` | Observability and incident response |
| **Train** | *(planned)* | Training job management |
| **Evaluate** | *(planned)* | Model benchmarking and comparison |
| **Maintain Safety** | *(planned)* | Guardrails and compliance |

## Connected vs. Disconnected

| Capability | Connected | Disconnected |
|------------|-----------|--------------|
| ArgoCD MCP | Yes | Yes (internal) |
| RHOAI MCP | Yes | Yes (internal) |
| OpenShift MCP | Yes | Yes (internal) |
| MLflow MCP | Yes | Yes (internal) |
| GitHub MCP | Yes | Replaced with Gitea/GitLab |
| Image mirroring guidance | N/A | Full support via `rhoai-disconnected-deploy` |
| Operator deployment | Direct | Via mirrored CatalogSource |

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

See [Quick Start](docs/getting-started/quickstart.md) for the 5-minute version, or the [Full Deployment Guide](docs/getting-started/deployment-guide.md) for the complete step-by-step walkthrough.

## Repository Structure

```
rhoai-copilot/
├── agent/              # Agent identity, config, safety rules
│   ├── soul.md         # Who the agent is and how it behaves
│   ├── rules.md        # Hard safety constraints
│   ├── config.yaml     # MCP server connections and tool whitelist
│   └── profiles/       # Environment-specific variables
├── skills/             # Capabilities organized by RHOAI lifecycle
│   ├── platform-setup/ # Platform deployment and prerequisites
│   ├── plan/           # Capacity and architecture planning
│   ├── administer/     # Platform configuration and upgrades
│   ├── develop/        # ML development workflows
│   ├── deploy/         # Model serving and promotion
│   ├── monitor/        # Health, drift, incident response
│   └── SKILL_SPEC.md   # Skill authoring specification
├── workflows/          # Multi-step autonomous procedures
├── personas/           # Target user definitions and skill mappings
├── mcp-servers/        # MCP server docs and deployment manifests
├── runtimes/           # Pluggable agent harness deployments
│   ├── base/           # Shared K8s resources (RBAC, PVC, Service)
│   ├── hermes/         # Default runtime (NousResearch Hermes)
│   ├── langgraph/      # Planned: LangGraph runtime
│   └── crewai/         # Planned: CrewAI runtime
├── eval/               # Agent evaluation scenarios and scoring
├── docs/               # Documentation (getting-started, concepts, guides)
└── examples/           # Example interactions and templates
```

## Autonomy Tiers

| Tier | Mode | Operations | Confirmation |
|------|------|-----------|--------------|
| 1 | Read-Only Advisory | Diagnostics, reports, recommendations | None needed |
| 2 | Controlled Actuator | Sync, workbench ops, PR creation | Required |
| 3 | Autonomous Operator | Scheduled health checks, drift alerts | Pre-approved |

## Target Personas

- **AI Engineer** — Build AI/agentic applications, deploy models via MaaS/OGX, RAG pipelines
- **Platform Engineer** — Install, configure, and maintain the RHOAI platform
- **MLOps Engineer** — Manage model pipelines, serving, and promotion
- **Data Scientist** — Experiment, train, and debug ML workflows
- **SRE/Operations** — Monitor platform health and respond to incidents

## Documentation

| Document | Description |
|----------|-------------|
| [Quick Start](docs/getting-started/quickstart.md) | 5-minute deployment |
| [Full Deployment Guide](docs/getting-started/deployment-guide.md) | Complete end-to-end deployment with all 5 MCP servers |
| [MCP Server Setup](docs/guides/mcp-server-setup.md) | Detailed per-server deployment (ArgoCD, RHOAI, OpenShift, MLflow, GitHub) |
| [Obtaining Credentials](docs/guides/obtaining-credentials.md) | How to get each required credential |
| [Troubleshooting](docs/guides/troubleshooting.md) | Common errors and their resolutions |
| [Environment Variables](docs/reference/environment-variables.md) | All environment variables reference |
| [Disconnected Setup](docs/getting-started/disconnected-setup.md) | Air-gapped deployment guide |
| [Architecture](docs/concepts/architecture.md) | System design and MCP topology |
| [Custom Skills](docs/guides/custom-skills.md) | How to add new agent capabilities |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Key entry points:

- **Add a skill**: Follow [skills/SKILL_SPEC.md](skills/SKILL_SPEC.md)
- **Add a runtime**: See [runtimes/README.md](runtimes/README.md)
- **Add an eval scenario**: See [eval/README.md](eval/README.md)

## Acknowledgments

- MaaS (Models-as-a-Service) skills adapted from [MichalSteczko/rhoai-agentic-skills](https://github.com/MichalSteczko/rhoai-agentic-skills) — production-tested on RHOAI 3.5 / OCP 4.21

## License

Apache License 2.0. See [LICENSE](LICENSE).
