#!/usr/bin/env bash
set -euo pipefail

if ! command -v hermes >/dev/null 2>&1; then
  echo "ERROR: hermes not found in image PATH. Rebuild with Containerfile." >&2
  exit 1
fi

WORK_DIR="${HERMES_HOME:-/tmp/work/.hermes}"
PERSIST_DIR="/persistent"
SKILLS_DIR="${WORK_DIR}/skills"
SKILL_MOUNT_PREFIX="/mnt/skill-"

mkdir -p "$PERSIST_DIR"/{memory,sessions,profiles,auto-skills,db}
mkdir -p /tmp/work/.local /tmp/work/data /tmp/work/output "$WORK_DIR"

ln -sfn "$PERSIST_DIR/memory" "$WORK_DIR/memory"
ln -sfn "$PERSIST_DIR/sessions" "$WORK_DIR/sessions"
ln -sfn "$PERSIST_DIR/profiles" "$WORK_DIR/profiles"
ln -sfn "$PERSIST_DIR/auto-skills" "$WORK_DIR/auto-skills"
ln -sfn "$PERSIST_DIR/db" "$WORK_DIR/db"

for f in USER.md MEMORY.md; do
  [ -f "$PERSIST_DIR/$f" ] && cp "$PERSIST_DIR/$f" "$WORK_DIR/$f"
done

# Copy skills from mounted ConfigMaps
for mount in /mnt/skill-*; do
  [ -d "$mount" ] || continue
  skill_name="${mount#$SKILL_MOUNT_PREFIX}"
  mkdir -p "$SKILLS_DIR/$skill_name"
  [ -f "$mount/SKILL.md" ] && cp "$mount/SKILL.md" "$SKILLS_DIR/$skill_name/SKILL.md"
done

# Copy soul and config (resolve env var placeholders)
[ -f /mnt/soul/SOUL.md ] && cp /mnt/soul/SOUL.md "$WORK_DIR/SOUL.md"
if [ -f /mnt/config/config.yaml ]; then
  envsubst < /mnt/config/config.yaml > "$WORK_DIR/config.yaml"
fi

# Remove MCP servers with empty URLs (not deployed)
python3 -c "
import yaml
with open('${WORK_DIR}/config.yaml') as f:
    cfg = yaml.safe_load(f)
servers = cfg.get('mcp_servers', {})
to_remove = [k for k, v in servers.items() if isinstance(v, dict) and v.get('url') == '']
for k in to_remove:
    del servers[k]
    print(f'Removed MCP server \"{k}\" (not configured)')
with open('${WORK_DIR}/config.yaml', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False)
"

# Generate dashboard password hash
HASH=$(python3 -c "
import hashlib, secrets, base64, os
pw = os.environ.get('DASHBOARD_PASSWORD', '')
if not pw:
    raise ValueError('DASHBOARD_PASSWORD must be set via secret')
salt = secrets.token_bytes(16)
key = hashlib.scrypt(pw.encode(), salt=salt, n=16384, r=8, p=1, dklen=32)
s = base64.b64encode(salt).decode()
k = base64.b64encode(key).decode()
print(f'scrypt\$16384\$8\$1\${s}\${k}')
")

# Inject runtime credentials into config
python3 <<PY
import os, yaml
with open('${WORK_DIR}/config.yaml') as f:
    cfg = yaml.safe_load(f)
cfg.setdefault('dashboard', {}).setdefault('basic_auth', {})['password_hash'] = """${HASH}"""
cfg.setdefault('skills', {})['directory'] = '${WORK_DIR}/skills'

argocd_url = os.environ.get('ARGOCD_BASE_URL')
argocd_token = os.environ.get('ARGOCD_API_TOKEN')
if argocd_url:
    cfg.setdefault('mcp_servers', {}).setdefault('argocd', {}).setdefault('env', {})['ARGOCD_BASE_URL'] = argocd_url
if argocd_token:
    cfg.setdefault('mcp_servers', {}).setdefault('argocd', {}).setdefault('env', {})['ARGOCD_API_TOKEN'] = argocd_token

sa_token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'
if os.path.isfile(sa_token_path):
    with open(sa_token_path) as tf:
        sa_token = tf.read().strip()
    ocp_mcp = cfg.setdefault('mcp_servers', {}).setdefault('openshift', {})
    ocp_mcp['headers'] = {'Authorization': f'Bearer {sa_token}'}
    print(f'OpenShift MCP: SA token injected ({len(sa_token)} chars)')

with open('${WORK_DIR}/config.yaml', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False)
print('Config updated: credentials injected')
PY

# Initialize audit logging
mkdir -p "$PERSIST_DIR/audit"
export AUDIT_LOG_DIR="$PERSIST_DIR/audit"
export AGENT_VERSION="${AGENT_VERSION:-0.1.0}"
if [ -f /scripts/audit-logger.py ]; then
  python3 /scripts/audit-logger.py setup
elif [ -f /mnt/entrypoint/audit-logger.py ]; then
  python3 /mnt/entrypoint/audit-logger.py setup
fi

trap 'cp ${WORK_DIR}/USER.md ${WORK_DIR}/MEMORY.md ${PERSIST_DIR}/ 2>/dev/null || true; echo State saved' SIGTERM SIGINT

echo "=== Starting Hermes gateway (background) ==="
hermes gateway run > /tmp/hermes-gateway.log 2>&1 &
sleep 5

echo "=== Starting Hermes dashboard ==="
exec hermes dashboard --host 0.0.0.0 --port 18789 --no-open --skip-build
