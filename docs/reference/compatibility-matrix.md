# Compatibility Matrix

Supported version combinations for RHOAI Copilot.

## Current Support

| Agent Version | RHOAI Versions | OCP Versions | Runtime | Default Model |
|---------------|----------------|--------------|---------|---------------|
| 0.1.0 | 3.5 | 4.17, 4.18 | Hermes >= 0.19.0 | Gemini 2.5 Flash |

## MCP Server Compatibility

| MCP Server | Version / Image | Transport | Required By |
|------------|----------------|-----------|-------------|
| ArgoCD MCP | argocd-mcp@latest (npm) | stdio | All monitor/admin skills |
| RHOAI MCP | quay.io/opendatahub/odh-rhoai-mcp:odh-stable | HTTP (streamable) | Most RHOAI skills |
| OpenShift MCP | quay.io/rbrhssa/openshift-mcp-server:latest | HTTP (streamable) | Cluster diagnostics |
| MLflow MCP | quay.io/rbrhssa/mlflow-mcp:3.15.0-v2 | HTTP (streamable) | Experiment tracking |
| GitHub MCP | @modelcontextprotocol/server-github@latest (npm) | stdio | GitOps write operations |

## Dependency Operators

These operators must be installed on the cluster for full RHOAI functionality:

| Operator | Minimum Version | Required For |
|----------|----------------|--------------|
| OpenShift GitOps (ArgoCD) | 1.12+ | All GitOps-managed deployments |
| cert-manager | 1.14+ | TLS certificates, prerequisite for RHOAI |
| NVIDIA GPU Operator | 24.3+ | GPU workloads (model serving, training) |
| Node Feature Discovery | 4.17+ | GPU node detection |
| Service Mesh (Istio) | 2.5+ | KServe model serving |
| Kueue | 0.8+ | GPU quota management |

## Model Provider Support

The agent communicates with LLMs via OpenAI-compatible API. Any provider exposing this interface is supported:

| Provider | Tested Models | Notes |
|----------|--------------|-------|
| Google Gemini | gemini-2.5-flash | Default configuration |
| IBM watsonx.ai | granite-3.3-8b-instruct | Red Hat aligned |
| Local vLLM | Any supported model | For disconnected/air-gapped environments |
| OpenAI | gpt-4o | Requires API key |
| Anthropic (via proxy) | claude-sonnet-4 | Requires OpenAI-compatible proxy |

## Disconnected Environment Requirements

| Component | Requirement |
|-----------|------------|
| Container Registry | Internal registry accessible from cluster |
| Image Mirroring | oc-mirror CLI on bastion host |
| Git Server | Gitea or GitLab (replaces GitHub MCP) |
| LLM Access | Local vLLM or proxy with LLM API access |
| Network | All MCP servers as internal ClusterIP Services |

## Version Policy

- **Major versions** (1.0, 2.0): May include breaking changes to skill format, config schema, or MCP requirements
- **Minor versions** (0.1, 0.2): New skills, features, and non-breaking enhancements
- **Patch versions** (0.1.1): Bug fixes, documentation updates, security patches

The agent follows [Semantic Versioning 2.0.0](https://semver.org/).
