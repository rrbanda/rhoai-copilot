# Audit Logging

RHOAI Copilot produces structured audit logs for every significant agent action. These logs support enterprise compliance requirements (SOC2, FedRAMP, HIPAA) and operational review.

## Audit Event Schema (v1.0.0)

Every audit event is a single JSON line in `audit.jsonl`:

```json
{
  "schema_version": "1.0.0",
  "timestamp": "2026-08-22T14:30:00.000000+00:00",
  "event_type": "tool_call",
  "agent_version": "0.1.0",
  "tier": 1,
  "session_id": "abc-123",
  "user": "admin",
  "details": {
    "tool": "list_applications",
    "server": "argocd"
  }
}
```

## Event Types

| Event Type | Tier | Description |
|------------|------|-------------|
| `agent_startup` | — | Agent process started, config summary logged |
| `agent_shutdown` | — | Agent process stopped gracefully |
| `session_start` | — | New user session opened |
| `session_end` | — | User session closed, duration recorded |
| `tool_call` | 1-2 | MCP tool invocation (tool name, server, parameters) |
| `tool_result` | 1-2 | MCP tool result received |
| `tool_error` | 1-2 | MCP tool call failed |
| `skill_activation` | 1 | Agent activated a skill |
| `tier2_request` | 2 | Write operation requested (pending confirmation) |
| `tier2_confirmation` | 2 | User confirmed a Tier 2 operation |
| `tier2_rejection` | 2 | User rejected a Tier 2 operation |
| `safety_violation` | 0 | Safety constraint activated (blocked action) |
| `config_change` | 2 | Agent configuration modified |
| `workflow_start` | 3 | Autonomous workflow started |
| `workflow_step` | 3 | Workflow step completed |
| `workflow_complete` | 3 | Autonomous workflow finished |
| `escalation` | 3 | Workflow escalation triggered |

## Storage

Audit logs are stored on the persistent volume:

```
/persistent/audit/
├── audit.jsonl         # Current log file
├── audit.jsonl.1       # First rotation backup
├── audit.jsonl.2       # Second rotation backup
└── ...                 # Up to 10 backups (500MB total)
```

- **Format:** JSON Lines (one JSON object per line)
- **Rotation:** 50MB per file, 10 backups retained
- **Retention:** Configurable via `AUDIT_RETENTION_DAYS` (default: unlimited on PVC)

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `AUDIT_LOG_DIR` | `/persistent/audit` | Directory for audit log files |
| `AGENT_VERSION` | `0.1.0` | Agent version recorded in events |

## Security

- **Credential stripping:** Parameters containing `token`, `password`, `secret`, `api_key`, or `credential` keys are automatically filtered from audit logs
- **Immutability:** Audit logs are append-only; the agent has no delete capability on the audit directory
- **Separation:** Audit logs are stored separately from agent state (memory, sessions)

## Integration with Enterprise Log Aggregators

### Splunk / Elastic (Filebeat)

```yaml
filebeat.inputs:
  - type: log
    paths:
      - /persistent/audit/audit.jsonl*
    json.keys_under_root: true
    json.add_error_key: true
```

### OpenShift Cluster Logging (Vector)

```yaml
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: rhoai-copilot-audit
spec:
  inputs:
    - name: audit-logs
      application:
        namespaces:
          - rhoai-copilot
  outputs:
    - name: splunk-audit
      type: splunk
      splunk:
        endpoint: https://splunk.internal:8088
  pipelines:
    - name: audit-pipeline
      inputRefs: [audit-logs]
      outputRefs: [splunk-audit]
```

## Querying Audit Logs

```bash
# All Tier 2 operations
cat /persistent/audit/audit.jsonl | jq 'select(.tier == 2)'

# Safety violations
cat /persistent/audit/audit.jsonl | jq 'select(.event_type == "safety_violation")'

# Tool calls for a specific session
cat /persistent/audit/audit.jsonl | jq 'select(.session_id == "abc-123" and .event_type == "tool_call")'

# Daily tool call counts
cat /persistent/audit/audit.jsonl | jq -r 'select(.event_type == "tool_call") | .timestamp[:10]' | sort | uniq -c
```
