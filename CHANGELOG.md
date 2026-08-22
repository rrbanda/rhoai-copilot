# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-22

### Added
- Initial repository structure with 9 RHOAI lifecycle phases
- 22 agentic skills covering install, plan, administer, develop, deploy, and monitor
  - **platform-setup** (4): rhoai-disconnected-deploy, rhoai-disconnected-helper, rhoai-install-validator, gitops-config-generator
  - **plan** (3): capacity-forecaster, serving-runtime-advisor, training-planner
  - **administer** (3): rhoai-platform-status, rhoai-dsc-inspector, rhoai-upgrade-advisor
  - **develop** (3): workbench-troubleshooter, pipeline-debugger, experiment-tracker
  - **deploy** (4): maas-enable, maas-deploy-model, rhoai-model-lifecycle, model-promotion-workflow
  - **monitor** (5): argocd-health-check, argocd-diagnose-sync, daily-report-generator, incident-runbook, maas-debug
- MaaS (Models-as-a-Service) skills with idempotent shell automation from [rhoai-agentic-skills](https://github.com/MichalSteczko/rhoai-agentic-skills)
  - `maas-enable`: 11-step MaaS bootstrap (DSC, Gateway, Authorino, PostgreSQL, Tenant)
  - `maas-deploy-model`: End-to-end model deployment with VRAM estimation, governance, and API keys
  - `maas-debug`: Comprehensive MaaS troubleshooting (10 known issues with fixes)
- Hermes runtime with OpenShift deployment manifests (python:3.13-slim)
- 5 MCP server integrations (ArgoCD, RHOAI, MLflow, OpenShift, GitHub)
- Agent identity layer: soul.md (personality), rules.md (safety constraints), config.yaml (runtime)
- 3-tier autonomy model (Read-Only, Controlled Write, Scheduled Autonomous)
- Agent evaluation framework with 3 scenario-based tests and scoring rubric
- 3 autonomous workflows (daily health reports, drift detection, incident response)
- Disconnected/air-gapped environment support with dedicated skills
- 5 persona definitions (Platform Engineer, SRE, Data Scientist, MLOps Engineer, AI Engineer)
- Skill specification format (SKILL_SPEC.md) and skill template
- Environment profiles for connected and disconnected clusters
- Disconnected deployment Kustomize overlay
- Product management context files (`_context/`) for strategic planning and knowledge persistence
- Comprehensive documentation: deployment guide, MCP server setup, credentials, troubleshooting
- GitHub Actions CI: skill format validation, Kustomize build checks, container image builds
- Root Kustomize deployment with 22 skill ConfigMaps

### Fixed
- Broken documentation links for disconnected-setup.md (3 locations)
- Stale skill count in architecture.md (19 → 22)
- ArgoCD credential setup docs conflict (standardized on CR patch approach over ConfigMap edit)
- Created previously-referenced but missing paths: agent/profiles/, runtimes/hermes/overlays/disconnected/

### Compatibility
- Validated on OpenShift Container Platform 4.18
- Validated with Red Hat OpenShift AI 3.5
- Default model: Gemini 2.5 Flash (configurable via OpenAI-compatible base_url)
- Runtime: Hermes Agent >= 0.19.0

[Unreleased]: https://github.com/rrbanda/rhoai-copilot/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rrbanda/rhoai-copilot/releases/tag/v0.1.0
