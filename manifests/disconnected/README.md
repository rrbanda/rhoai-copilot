# Disconnected RHOAI Deployment Templates

Parameterized manifests for deploying Red Hat OpenShift AI on a disconnected (air-gapped) OpenShift cluster. Derived from battle-tested deployments verified on OCP 4.20/4.22 with RHOAI 3.4.x.

## How to Use

1. **Copy** the files you need to your own Git repo
2. **Replace** the `<PLACEHOLDER>` values with your environment-specific settings
3. **Apply** in the order shown below, or use the ArgoCD Applications for GitOps

## Placeholders

| Placeholder | Example Value | Where to Get It |
|-------------|---------------|-----------------|
| `<MIRROR_REGISTRY>` | `bastion.lab:8443` | Your mirror registry hostname:port |
| `<MIRROR_NAMESPACE>` | `rhoai` | The namespace used in `oc-mirror docker://<registry>/<namespace>` |
| `<CATALOG_DIGEST>` | `sha256:0e2fc7...` | `skopeo inspect --raw docker://registry.redhat.io/redhat/redhat-operator-index:v<OCP_VERSION>` |
| `<CERTIFIED_CATALOG_DIGEST>` | `sha256:cb18a1...` | Same for `certified-operator-index` |
| `<OCP_VERSION>` | `4.20` | Your OpenShift minor version |
| `<RHOAI_VERSION>` | `3.4.2` | Target RHOAI version |
| `<RHOAI_CHANNEL>` | `stable-3.4` | Derived: `stable-<major>.<minor>` |
| `<MIRRORED_CATALOG_NAME>` | `cs-redhat-operator-index-sha256-8d67e` | `oc get catalogsource -n openshift-marketplace` after pushing |
| `<CERTIFIED_CATALOG_NAME>` | `cs-certified-operator-index-sha256-ab2ce` | Same command |
| `<MIRROR_CA_PEM>` | Contents of rootCA.pem | Your mirror registry CA certificate |
| `<MIRROR_REGISTRY_FQDN>` | `bastion.lab` | Hostname part (without port) |

## Application Order

```
Phase 1 — Mirror (low side)
  mirror/imageset-config-rhoai.yaml  → oc-mirror --v2

Phase 2 — Cluster config (high side, after oc-mirror push)
  cluster-config/                    → oc apply -f (IDMS/ITMS from oc-mirror output first)

Phase 3 — Operators (high side, wait for each CSV)
  operators/cert-manager.yaml        → wait CSV Succeeded
  operators/servicemesh3.yaml        → wait CSV Succeeded (OCP 4.19-4.21 only)
  operators/nfd.yaml                 → wait CSV Succeeded
  operators/gpu-operator.yaml        → wait CSV Succeeded (optional)
  operators/rhoai.yaml               → wait CSV Succeeded

Phase 4 — RHOAI (high side, wait for each Ready)
  rhoai/dsci.yaml                    → wait DSCI .status.phase=Ready
  rhoai/dsc-v2.yaml                  → wait DSC condition Ready=True

Phase 5 — Verify
  Use the rhoai-install-validator agent skill
```

## For GitOps (ArgoCD)

Use the Application templates in `argocd/` with sync-wave ordering.
