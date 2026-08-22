# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial repository structure with 9 RHOAI lifecycle phases
- 22 agentic skills covering install, plan, administer, develop, deploy, and monitor
- MaaS (Models-as-a-Service) skills with idempotent shell automation from [rhoai-agentic-skills](https://github.com/MichalSteczko/rhoai-agentic-skills)
  - `maas-enable`: 11-step MaaS bootstrap (DSC, Gateway, Authorino, PostgreSQL, Tenant)
  - `maas-deploy-model`: End-to-end model deployment with VRAM estimation, governance, and API keys
  - `maas-debug`: Comprehensive MaaS troubleshooting (10 known issues with fixes)
- Hermes runtime with OpenShift deployment manifests
- 5 MCP server integrations (ArgoCD, RHOAI, MLflow, OpenShift, GitHub)
- Agent evaluation framework with scenario-based testing
- Autonomous workflows (daily health reports, drift detection)
- Disconnected/air-gapped environment support
- Persona-driven documentation (Platform Engineer, MLOps, Data Scientist, SRE)
