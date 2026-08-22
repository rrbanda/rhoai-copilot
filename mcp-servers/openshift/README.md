# OpenShift MCP Server

## Overview

The OpenShift MCP server provides general Kubernetes/OpenShift cluster operations — pod management, event retrieval, node status, and resource inspection.

## Transport

`streamable-http` at `/mcp` endpoint.

## Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openshift-mcp-server
  namespace: ocp-mcp-server
spec:
  # Standard deployment with ServiceAccount that has cluster-reader RBAC
```

## Required RBAC

The server's ServiceAccount needs `cluster-reader` ClusterRoleBinding for read-only access across all namespaces.

## Tool Catalog

- `pods_list` — List pods in a namespace
- `pods_get` — Get pod details
- `pods_log` — Retrieve pod logs
- `events_list` — List events in a namespace
- `nodes_list` — List cluster nodes with status
- `nodes_get` — Get node details and conditions
- `namespaces_list` — List all namespaces
- `resources_get` — Get any Kubernetes resource by GVR
- And more (20+ tools total)
