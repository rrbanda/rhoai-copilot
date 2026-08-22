#!/usr/bin/env bash
# Add mirror registry credentials to the cluster's global pull secret.
#
# Usage:
#   MIRROR_REGISTRY=bastion.lab:8443 \
#   MIRROR_REGISTRY_USER=init \
#   MIRROR_REGISTRY_PASSWORD=<password> \
#   bash pull-secret-patch.sh
#
# This must be run BEFORE applying IDMS/ITMS, because the node reboot
# triggered by IDMS will try to pull from the mirror immediately.
set -euo pipefail

: "${MIRROR_REGISTRY:?Set MIRROR_REGISTRY (e.g. bastion.lab:8443)}"
: "${MIRROR_REGISTRY_USER:?Set MIRROR_REGISTRY_USER (e.g. init)}"
: "${MIRROR_REGISTRY_PASSWORD:?Set MIRROR_REGISTRY_PASSWORD}"

echo "Extracting current pull secret..."
oc get secret/pull-secret -n openshift-config \
  --template='{{index .data ".dockerconfigjson" | base64decode}}' > /tmp/ps.json

echo "Adding mirror registry credentials..."
oc registry login --registry="${MIRROR_REGISTRY}" \
  --auth-basic="${MIRROR_REGISTRY_USER}:${MIRROR_REGISTRY_PASSWORD}" \
  --to=/tmp/ps.json

echo "Updating cluster pull secret..."
oc set data secret/pull-secret -n openshift-config \
  --from-file=.dockerconfigjson=/tmp/ps.json

rm -f /tmp/ps.json
echo "Pull secret updated for ${MIRROR_REGISTRY}"
