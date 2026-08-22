# Autonomy Tiers

RHOAI Copilot operates within a tiered autonomy model that balances usefulness with safety.

## Tier 1: Read-Only Advisory (Default)

The agent observes and advises but never modifies state.

**Capabilities:**
- Query ArgoCD application status and resource trees
- Inspect DSC configuration and operator health
- List workbenches, models, pipelines, and training jobs
- View MLflow experiments and metrics
- Read pod logs and events
- Generate reports and recommendations

**No confirmation needed.** Safe to use in any environment.

## Tier 2: Controlled Actuator

The agent can perform scoped write operations with human confirmation.

**Capabilities:**
- Sync ArgoCD applications (dry-run first)
- Create workbenches in `sandbox-*` namespaces
- Start/stop workbenches
- Create data connections in user projects
- Deploy models in non-production namespaces
- Create pull requests for configuration changes
- Push GitOps patches to branches

**Requires explicit user confirmation before execution.**

**Guardrails:**
- Write operations are blocked in `redhat-ods-*` and `openshift-*` namespaces
- Sync defaults to dry-run mode
- No delete operations
- Model deployment restricted to non-production namespaces

## Tier 3: Autonomous Operator

The agent performs pre-approved operations on a schedule without human intervention.

**Capabilities:**
- Generate daily health reports
- Detect and alert on configuration drift
- Create GitHub issues for detected problems
- Send summary notifications

**Guardrails:**
- No destructive actions permitted
- Scope limited to observation + alerting
- Actions must be defined in `workflows/` YAML files
- Timeout enforcement on all autonomous runs

## Graduating Between Tiers

```
Tier 1 (default) ──[trust established]──▶ Tier 2 ──[operational confidence]──▶ Tier 3
```

1. Start with Tier 1 to validate the agent understands your environment
2. Enable Tier 2 tools in `agent/config.yaml` when ready for controlled operations
3. Configure workflows in `workflows/` for Tier 3 autonomous operations
