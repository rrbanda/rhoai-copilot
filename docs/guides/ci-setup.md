# CI Pipeline Setup

How to configure the GitHub Actions CI pipelines for building the agent image and running agent tests.

## Pipelines Overview

| Workflow | Trigger | What It Does |
|----------|---------|-------------|
| `validate.yaml` | Push/PR to main | Lint skills, validate Kustomize, yamllint, eval format check |
| `build-image.yaml` | Push to main (path-filtered) + tags | Gitleaks scan, build image, Trivy vulnerability scan, SBOM, push to ghcr.io + quay.io |
| `release.yaml` | Version tags (`v*`) | Create GitHub Release, trigger image build |
| `agent-test.yaml` | PR (skills/agent changes) + manual | Run agent in sandbox via agentic-ci with gitleaks + sensitive-files gates |

## Required GitHub Secrets

### For image builds (build-image.yaml)

| Secret | Required | How to Get It |
|--------|:--------:|---------------|
| `GITHUB_TOKEN` | Auto | Built-in, no setup needed. Used for ghcr.io push. |
| `QUAY_USERNAME` | Optional | Create a Robot Account on quay.io (see below) |
| `QUAY_PASSWORD` | Optional | Robot Account token from quay.io |

If `QUAY_USERNAME` is not set, the pipeline only pushes to ghcr.io. The quay.io push step is skipped gracefully.

### For agent tests (agent-test.yaml)

| Secret | Required | How to Get It |
|--------|:--------:|---------------|
| `ANTHROPIC_API_KEY` | Optional | From console.anthropic.com. Only needed for agent testing. |

If `ANTHROPIC_API_KEY` is not set, the agent-test job is skipped entirely. The gitleaks scan still runs.

## Setting Up Quay.io Robot Account

Do NOT use your personal quay.io password. Create a scoped Robot Account:

1. Go to [quay.io](https://quay.io) and navigate to your repository
2. Click **Settings** > **Robot Accounts** > **Create Robot Account**
3. Name it something like `rhoai-copilot-ci`
4. Grant it **Write** permission on the `rhoai-copilot` repository only
5. Copy the generated token

Then in your GitHub repository:

1. Go to **Settings** > **Secrets and variables** > **Actions**
2. Add `QUAY_USERNAME` = `rbrhssa+rhoai-copilot-ci` (the robot account name)
3. Add `QUAY_PASSWORD` = (the generated token)

## Security Features

### Gitleaks Pre-Build Gate

Every image build starts with a gitleaks scan of the full git history. If secrets are detected, the build stops — no image is built or pushed.

The scan uses custom rules from [.gitleaks.toml](../../.gitleaks.toml) that catch:
- Password assignments (`password = value`)
- Base64-encoded credentials near keyword markers
- `oc login` commands with inline passwords
- Registry passwords in configs

### Trivy Vulnerability Scan

After building the image, Trivy scans it for known CVEs. Results are uploaded as SARIF to GitHub's Security tab. Currently set to report (not block) on CRITICAL/HIGH findings — change `exit-code: '0'` to `'1'` to make it blocking.

### SBOM Generation

An SPDX-format Software Bill of Materials is generated for every image build and uploaded as a build artifact (retained 90 days).

### agentic-ci Post-Gates

When the agent runs via agentic-ci, two post-gates validate its output:

| Gate | What It Catches |
|------|----------------|
| `sensitive-files` | Blocks commits touching `.env`, `*.pem`, `*.key`, `credentials.json` |
| `gitleaks` | Scans agent-generated commits for secrets using gitleaks |

These gates run OUTSIDE the agent's control — the agent cannot bypass them.

## Running Agent Tests Manually

```bash
# Trigger via GitHub Actions UI
# Go to Actions > Agent Test > Run workflow > Enter prompt

# Or run locally with agentic-ci
pip install agentic-ci
export ANTHROPIC_API_KEY=<your-key>
agentic-ci run --backend local \
  "Run make eval-list and verify all scenarios load" \
  --post-gates sensitive-files,gitleaks
```

## Credential Safety Summary

```
Code committed → gitleaks pre-commit hook (local)
           ↓ (if hook bypassed or not installed)
PR opened    → gitleaks-action in CI (blocks merge)
           ↓ (if somehow merged)
Image build  → gitleaks gate runs BEFORE build (blocks image)
           ↓ (for agent-generated changes)
Agent test   → agentic-ci post-gates (blocks agent commits)
           ↓ (final backstop)
GitHub       → Push protection (server-side, if enabled)
```

Five layers. No single point of failure.
