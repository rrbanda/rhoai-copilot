# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please email: [rrbanda@redhat.com](mailto:rrbanda@redhat.com)

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide a detailed response within 7 days.

## Agent Safety

This project deploys an AI agent that interacts with production infrastructure. If you observe the agent:

- Taking actions outside its defined safety rules (`agent/rules.md`)
- Accessing resources it should not have access to
- Generating recommendations that could cause data loss or outages

Please report this as a safety concern using the GitHub issue template or via the email above.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.x     | Yes       |

## Security Best Practices for Deployers

- Always deploy with least-privilege RBAC (see `runtimes/base/rbac.yaml`)
- Use read-only mode (Tier 1) until you have validated agent behavior
- Never store credentials in the Git repository; use OpenShift Secrets
- Review `agent/rules.md` before promoting to Tier 2 (write operations)
