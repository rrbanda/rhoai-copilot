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

- Skills must be framework-agnostic (no Hermes-specific code in skill definitions)
- The agent/rules.md file contains hard safety constraints — never weaken them
- Disconnected environment support is a primary concern, not an afterthought

## Credential Safety (CRITICAL)

AI coding agents MUST follow these rules without exception:

1. **Never write credentials to ANY file that could be committed.** This includes:
   - Passwords, tokens, API keys, secrets of any kind
   - Cluster API URLs with embedded auth
   - Registry passwords or login commands with inline passwords
   - Base64-encoded credentials
   - SSH private keys or PEM contents

2. **Never write cluster-specific hostnames or URLs to committed files.** Use `<PLACEHOLDER>` values instead. Real URLs identify infrastructure and aid targeted attacks.

3. **Context files (`_context/*.md`) are committed to Git.** Never put credentials, passwords, cluster URLs, or environment-specific hostnames in them. Use `<REDACTED>` or `<CLUSTER_API_URL>` placeholders.

4. **Shell commands with credentials are acceptable** — they exist only in the terminal session, not in files. But prefer environment variables over inline passwords:
   - Good: `oc login -u admin -p "$CLUSTER_PASSWORD" "$API_URL"`
   - Bad: hardcoding the password directly in the command

5. **If a credential is accidentally written to a file:**
   - Remove it from the file immediately
   - Do NOT commit with a message mentioning "leaked" or "credential" — this creates evidence
   - Use `git filter-branch` or `git filter-repo` to scrub history
   - Force push to overwrite remote history
   - Rotate the compromised credential
   - Run `git gc --prune=now --aggressive` to remove dangling objects

6. **Pre-commit hooks are installed** (gitleaks + detect-secrets). They scan every commit for secrets. If a commit is blocked, fix the file — do not bypass with `--no-verify`.
