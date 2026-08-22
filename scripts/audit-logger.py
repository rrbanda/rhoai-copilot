#!/usr/bin/env python3
"""RHOAI Copilot Audit Logger.

Configures structured JSON audit logging for the agent runtime.
Logs are written to the persistent volume for compliance and review.

Audit events captured:
  - Agent startup/shutdown
  - MCP tool invocations (tool name, server, duration)
  - Tier 2 operations (write actions requiring confirmation)
  - Skill activations
  - Session lifecycle (start, end, duration)
  - Errors and safety constraint activations

Usage:
  Called from entrypoint.sh before starting Hermes:
    python3 /scripts/audit-logger.py setup

  Or imported as a module:
    from audit_logger import AuditLogger
    logger = AuditLogger("/persistent/audit")
    logger.log_event("tool_call", {...})
"""

import json
import logging
import os
import sys
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Dict, Optional


AUDIT_SCHEMA_VERSION = "1.0.0"

AUDIT_EVENT_TYPES = [
    "agent_startup",
    "agent_shutdown",
    "session_start",
    "session_end",
    "tool_call",
    "tool_result",
    "tool_error",
    "skill_activation",
    "tier2_request",
    "tier2_confirmation",
    "tier2_rejection",
    "safety_violation",
    "config_change",
    "workflow_start",
    "workflow_step",
    "workflow_complete",
    "escalation",
]


class AuditLogger:
    """Structured JSON audit logger for RHOAI Copilot."""

    def __init__(
        self,
        log_dir: str = "/persistent/audit",
        max_bytes: int = 50 * 1024 * 1024,  # 50MB per file
        backup_count: int = 10,
        agent_version: str = "0.1.0",
    ):
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.agent_version = agent_version

        self.logger = logging.getLogger("rhoai-copilot-audit")
        self.logger.setLevel(logging.INFO)
        self.logger.propagate = False

        if not self.logger.handlers:
            handler = RotatingFileHandler(
                self.log_dir / "audit.jsonl",
                maxBytes=max_bytes,
                backupCount=backup_count,
            )
            handler.setFormatter(logging.Formatter("%(message)s"))
            self.logger.addHandler(handler)

    def log_event(
        self,
        event_type: str,
        details: Optional[Dict[str, Any]] = None,
        session_id: Optional[str] = None,
        user: Optional[str] = None,
        tier: int = 1,
    ) -> Dict[str, Any]:
        """Log a structured audit event."""
        event = {
            "schema_version": AUDIT_SCHEMA_VERSION,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "event_type": event_type,
            "agent_version": self.agent_version,
            "tier": tier,
        }
        if session_id:
            event["session_id"] = session_id
        if user:
            event["user"] = user
        if details:
            event["details"] = details

        self.logger.info(json.dumps(event, default=str))
        return event

    def log_startup(self, config_summary: Optional[Dict] = None):
        """Log agent startup with configuration summary."""
        details = {
            "hostname": os.environ.get("HOSTNAME", "unknown"),
            "namespace": os.environ.get("POD_NAMESPACE", "unknown"),
        }
        if config_summary:
            details["config"] = config_summary
        self.log_event("agent_startup", details)

    def log_tool_call(
        self,
        tool_name: str,
        mcp_server: str,
        parameters: Optional[Dict] = None,
        session_id: Optional[str] = None,
        tier: int = 1,
    ):
        """Log an MCP tool invocation."""
        details = {
            "tool": tool_name,
            "server": mcp_server,
        }
        if parameters:
            sanitized = {k: v for k, v in parameters.items()
                        if k.lower() not in ("token", "password", "secret", "api_key", "credential")}
            details["parameters"] = sanitized
        self.log_event("tool_call", details, session_id=session_id, tier=tier)

    def log_tier2_operation(
        self,
        operation: str,
        target: str,
        confirmed: bool,
        session_id: Optional[str] = None,
        user: Optional[str] = None,
    ):
        """Log a Tier 2 write operation and its confirmation status."""
        event_type = "tier2_confirmation" if confirmed else "tier2_rejection"
        details = {
            "operation": operation,
            "target": target,
            "confirmed": confirmed,
        }
        self.log_event(event_type, details, session_id=session_id, user=user, tier=2)

    def log_safety_violation(
        self,
        rule: str,
        context: str,
        session_id: Optional[str] = None,
    ):
        """Log when a safety constraint is activated."""
        details = {
            "rule_violated": rule,
            "context": context,
        }
        self.log_event("safety_violation", details, session_id=session_id, tier=0)


def setup_audit_logging():
    """Initialize audit logging for the agent runtime."""
    log_dir = os.environ.get("AUDIT_LOG_DIR", "/persistent/audit")
    agent_version = os.environ.get("AGENT_VERSION", "0.1.0")

    logger = AuditLogger(log_dir=log_dir, agent_version=agent_version)
    logger.log_startup({
        "mcp_servers": os.environ.get("MCP_SERVERS", "not-parsed"),
        "model": os.environ.get("MODEL_DEFAULT", "gemini-2.5-flash"),
        "runtime": "hermes",
    })
    print(f"Audit logging initialized: {log_dir}/audit.jsonl")
    return logger


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "setup":
        setup_audit_logging()
    else:
        print(__doc__)
