# Agent Runtimes

A runtime is the agent harness that executes the copilot's skills and connects to MCP servers. The copilot is designed to be runtime-agnostic — skills are plain Markdown, configuration is YAML, and the runtime adapts them to its execution model.

## Available Runtimes

| Runtime | Status | Description |
|---------|--------|-------------|
| `hermes/` | Production | NousResearch Hermes Agent with native MCP support |
| `langgraph/` | Planned | LangChain/LangGraph-based agent |
| `crewai/` | Planned | CrewAI multi-agent framework |

## Architecture

```
┌──────────────────────────────────────────────┐
│  runtimes/base/                               │
│  (shared RBAC, ServiceAccount, ConfigMaps)    │
├──────────────────────────────────────────────┤
│  runtimes/hermes/   (or langgraph/, crewai/) │
│  (harness-specific Deployment, image, entry)  │
└──────────────────────────────────────────────┘
```

## Adding a New Runtime

1. Create a directory under `runtimes/<name>/`
2. Include a `kustomization.yaml` that references `../base`
3. Provide a `Containerfile` and `deployment.yaml`
4. Map `agent/config.yaml` into the harness's native config format
5. Ensure skills from `skills/` are mounted at the expected path
6. Document in `runtimes/<name>/README.md`
