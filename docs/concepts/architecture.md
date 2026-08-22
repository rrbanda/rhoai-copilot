# Architecture

## Overview

RHOAI Copilot is an AI agent that manages Red Hat OpenShift AI through Model Context Protocol (MCP) integrations. It operates within GitOps workflows, ensuring all configuration changes flow through Git.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        OpenShift Cluster                         │
│                                                                 │
│  ┌──────────────────┐    ┌─────────────────────────────────┐   │
│  │  RHOAI Copilot   │    │       MCP Servers                │   │
│  │  ┌────────────┐  │    │  ┌─────────┐  ┌──────────────┐  │   │
│  │  │ Agent Soul │  │───▶│  │ ArgoCD  │  │   RHOAI      │  │   │
│  │  │ + Rules    │  │    │  │  MCP    │  │    MCP       │  │   │
│  │  ├────────────┤  │    │  └────┬────┘  └──────┬───────┘  │   │
│  │  │  Skills    │  │    │       │               │          │   │
│  │  │ (22 total) │  │───▶│  ┌────┴────┐  ┌──────┴───────┐  │   │
│  │  ├────────────┤  │    │  │OpenShift│  │   MLflow     │  │   │
│  │  │ Workflows  │  │    │  │  MCP    │  │    MCP       │  │   │
│  │  └────────────┘  │    │  └─────────┘  └──────────────┘  │   │
│  └──────────────────┘    └─────────────────────────────────┘   │
│           │                                                     │
│           ▼                                                     │
│  ┌──────────────────┐    ┌─────────────────────────────────┐   │
│  │   GitHub MCP     │    │   Target Systems                 │   │
│  │  (stdio process) │    │  - ArgoCD Server                 │   │
│  └────────┬─────────┘    │  - OpenShift AI (DSC, models)    │   │
│           │               │  - MLflow Tracking Server        │   │
└───────────┼───────────────┴─────────────────────────────────────┘
            │
            ▼
    ┌───────────────┐
    │   GitHub.com  │
    │  (GitOps repo)│
    └───────────────┘
```

## Key Design Decisions

### 1. Skills as Markdown

Skills are plain Markdown files, not code. This makes them:
- Runtime-agnostic (works with Hermes, LangGraph, CrewAI)
- Easy to review in PRs
- Versionable alongside config
- Readable by any LLM without special parsing

### 2. MCP as the Integration Layer

All external system access goes through MCP servers. This provides:
- Standardized tool interfaces
- Clear permission boundaries
- Easy to add new integrations
- Testable in isolation

### 3. GitOps-Native Operations

The agent never mutates cluster state directly for configuration changes. Instead:
- It generates Kustomize patches
- Creates pull requests via GitHub MCP
- ArgoCD handles the actual reconciliation

### 4. Tiered Autonomy

Three operational tiers prevent the agent from causing harm:
- **Tier 1**: Read-only (default) — diagnostics, reports, recommendations
- **Tier 2**: Controlled writes (requires confirmation) — sync, workbench creation
- **Tier 3**: Autonomous (scheduled) — health reports, drift detection

### 5. Disconnected-First

Air-gapped environments are not an afterthought:
- All MCP servers run as internal cluster Services
- No external network egress required for core operations
- Image mirroring guidance is a first-class skill
- Registry configuration is part of the installation flow
