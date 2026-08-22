# Contributing to rhoai-copilot

Thank you for your interest in contributing! This project is an AI agent for managing Red Hat OpenShift AI via GitOps, and we welcome contributions of all kinds.

## Ways to Contribute

### Add a New Skill

Skills are the agent's primary capabilities. Each skill lives in `skills/<lifecycle-phase>/<skill-name>/SKILL.md`.

1. Identify which RHOAI lifecycle phase your skill belongs to: `install`, `plan`, `administer`, `develop`, `train`, `evaluate`, `deploy`, `monitor`, or `maintain-safety`
2. Copy `skills/_template/SKILL.md.template` to `skills/<phase>/<your-skill-name>/SKILL.md`
3. Follow the format in `skills/SKILL_SPEC.md`
4. Submit a PR with the `new-skill` label

### Add a New Workflow

Workflows compose multiple skills into multi-step autonomous procedures. See `workflows/README.md`.

### Add a New Runtime

To support a new agent harness (e.g., LangGraph, CrewAI), create a directory under `runtimes/` with the required manifests. See `runtimes/README.md`.

### Report Issues

- **Bug**: Something isn't working as expected
- **New Skill Request**: Propose a skill the agent should learn
- **Safety Concern**: Report an agent behavior that violates safety rules

## Development Setup

```bash
# Clone the repo
git clone https://github.com/rrbanda/rhoai-copilot.git
cd rhoai-copilot

# Validate skills
make validate

# Build container image
make build

# Deploy to OpenShift (requires oc login)
make deploy
```

## Pull Request Process

1. Fork the repo and create a feature branch
2. Make your changes following the existing patterns
3. Run `make validate` to ensure skill format compliance
4. Submit a PR with a clear description of what and why
5. A maintainer will review within 48 hours

## Commit Convention

Use conventional commits:

```
feat(skills/install): add operator-prerequisite-checker skill
fix(runtimes/hermes): correct entrypoint token injection
docs(personas): add mlops-engineer journey mapping
```

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.
