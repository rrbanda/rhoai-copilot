# Instructions for AI Coding Agents

This file provides guidance for AI coding agents (Cursor, Copilot, etc.) working on this repository.

## Repository Purpose

rhoai-copilot is an AI agent that manages, operates, deploys, and configures Red Hat OpenShift AI via GitOps. It works in both connected and disconnected (air-gapped) environments.

## Key Directories

- `agent/` — Agent identity, configuration, and safety rules
- `skills/` — Agentic skills organized by RHOAI lifecycle phase (install, plan, administer, develop, train, evaluate, deploy, monitor, maintain-safety)
- `workflows/` — Multi-step autonomous procedures
- `runtimes/` — Pluggable agent harness deployments (Hermes, LangGraph, etc.)
- `mcp-servers/` — MCP tool server configurations and catalogs
- `eval/` — Agent evaluation scenarios and benchmarks
- `personas/` — Target user persona definitions

## Conventions

- Skills follow the format in `skills/SKILL_SPEC.md`
- Each skill is a single `SKILL.md` file in its own directory under the appropriate lifecycle phase
- Deployment manifests use Kustomize with base/overlay pattern
- Workflows are YAML files describing scheduled or triggered multi-step procedures
- All agent writes go through Git (PRs) — never direct kubectl mutations

## Build and Test

```bash
make validate    # Lint skills and config
make build       # Build container image
make deploy      # Deploy to OpenShift
make eval        # Run evaluation scenarios
```

## Important Rules

- Never add credentials or tokens to any file
- Skills must be framework-agnostic (no Hermes-specific code in skill definitions)
- The agent/rules.md file contains hard safety constraints — never weaken them
- Disconnected environment support is a primary concern, not an afterthought
