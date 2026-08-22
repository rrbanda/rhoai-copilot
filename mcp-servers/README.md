# MCP Server Integrations

This directory contains deployment manifests and tool catalogs for each Model Context Protocol (MCP) server the agent connects to.

## Architecture

```
┌─────────────────┐     ┌────────────────────┐
│  RHOAI Copilot  │────▶│  ArgoCD MCP        │──▶ ArgoCD API
│  (Agent)        │────▶│  RHOAI MCP         │──▶ OpenShift AI APIs
│                 │────▶│  OpenShift MCP     │──▶ Kubernetes API
│                 │────▶│  MLflow MCP        │──▶ MLflow Server
│                 │────▶│  GitHub MCP        │──▶ GitHub API
└─────────────────┘     └────────────────────┘
```

## Server Summary

| Server | Transport | Tools | Tier | Source |
|--------|-----------|-------|------|--------|
| ArgoCD | stdio | 10 | 1+2 | [argoproj-labs/mcp-for-argocd](https://github.com/argoproj-labs/mcp-for-argocd) |
| RHOAI | HTTP (streamable) | 35+ | 1+2 | [opendatahub-io/rhoai-mcp](https://github.com/opendatahub-io/rhoai-mcp) |
| OpenShift | HTTP (streamable) | 20+ | 1 | Community |
| MLflow | HTTP (streamable) | 15+ | 1 | Built-in (`mlflow mcp run`) |
| GitHub | stdio | 26 | 2 | [@modelcontextprotocol/server-github](https://github.com/modelcontextprotocol/servers) |

## Disconnected Environments

In air-gapped clusters:
- All HTTP-based MCP servers run as internal Services (no external egress)
- `ArgoCD MCP` binary is embedded in the agent container image
- `GitHub MCP` is typically replaced with a Gitea or GitLab MCP, or disabled
- Container images for MCP servers must be pre-mirrored to the internal registry
