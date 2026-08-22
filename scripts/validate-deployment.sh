#!/usr/bin/env bash
# Validate RHOAI Copilot deployment end-to-end.
# Usage: ./scripts/validate-deployment.sh [NAMESPACE]
set -euo pipefail

NAMESPACE="${1:-rhoai-copilot}"
PASS=0
FAIL=0
SKIP=0

print_result() {
  local status="$1" component="$2" detail="$3"
  case "$status" in
    PASS) echo "  [PASS] $component — $detail"; PASS=$((PASS + 1)) ;;
    FAIL) echo "  [FAIL] $component — $detail"; FAIL=$((FAIL + 1)) ;;
    SKIP) echo "  [SKIP] $component — $detail"; SKIP=$((SKIP + 1)) ;;
  esac
}

echo "=== RHOAI Copilot Deployment Validation ==="
echo "Namespace: $NAMESPACE"
echo ""

# --- 1. Check agent pod ---
echo "--- Core Components ---"
AGENT_STATUS=$(oc get pods -n "$NAMESPACE" -l app=rhoai-copilot -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$AGENT_STATUS" = "Running" ]; then
  RESTARTS=$(oc get pods -n "$NAMESPACE" -l app=rhoai-copilot -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
  print_result PASS "Agent pod" "Running ($RESTARTS restarts)"
else
  print_result FAIL "Agent pod" "Status: $AGENT_STATUS"
fi

# --- 2. Check RHOAI MCP pod ---
RHOAI_STATUS=$(oc get pods -n "$NAMESPACE" -l app=rhoai-mcp -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$RHOAI_STATUS" = "Running" ]; then
  print_result PASS "RHOAI MCP pod" "Running"
else
  print_result FAIL "RHOAI MCP pod" "Status: $RHOAI_STATUS"
fi

# --- 3. Check Route ---
ROUTE_HOST=$(oc get route rhoai-copilot -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$ROUTE_HOST" ]; then
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$ROUTE_HOST" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "200" ]; then
    print_result PASS "Route" "https://$ROUTE_HOST (HTTP $HTTP_CODE)"
  else
    print_result FAIL "Route" "https://$ROUTE_HOST returned HTTP $HTTP_CODE"
  fi
else
  print_result FAIL "Route" "Not found"
fi

# --- 4. Check PVC ---
PVC_STATUS=$(oc get pvc rhoai-copilot-data -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$PVC_STATUS" = "Bound" ]; then
  print_result PASS "PVC" "Bound"
else
  print_result FAIL "PVC" "Status: $PVC_STATUS"
fi

# --- 5. Check Secret ---
SECRET_KEYS=$(oc get secret rhoai-copilot-secrets -n "$NAMESPACE" -o jsonpath='{.data}' 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$SECRET_KEYS" -ge 3 ]; then
  print_result PASS "Secret" "$SECRET_KEYS keys configured"
else
  print_result FAIL "Secret" "Only $SECRET_KEYS keys (need at least 3: gemini-api-key, argocd-api-token, dashboard-password)"
fi

# --- 6. Check MCP connectivity from agent pod ---
echo ""
echo "--- MCP Server Connectivity ---"
AGENT_POD=$(oc get pods -n "$NAMESPACE" -l app=rhoai-copilot -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$AGENT_POD" ]; then
  print_result SKIP "MCP tests" "Agent pod not running"
else
  # RHOAI MCP
  RHOAI_RESP=$(oc exec "$AGENT_POD" -n "$NAMESPACE" -- curl -s -o /dev/null -w "%{http_code}" \
    "http://rhoai-mcp.$NAMESPACE.svc:8000/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"initialize","params":{"capabilities":{}},"id":1}' 2>/dev/null || echo "000")
  if [ "$RHOAI_RESP" = "200" ]; then
    print_result PASS "RHOAI MCP" "Responding (HTTP 200)"
  else
    print_result FAIL "RHOAI MCP" "HTTP $RHOAI_RESP from agent pod"
  fi

  # OpenShift MCP (optional)
  OCP_RESP=$(oc exec "$AGENT_POD" -n "$NAMESPACE" -- curl -s -o /dev/null -w "%{http_code}" \
    "http://openshift-mcp-server.ocp-mcp-server.svc.cluster.local:8080/mcp" 2>/dev/null || echo "000")
  if [ "$OCP_RESP" = "200" ] || [ "$OCP_RESP" = "400" ] || [ "$OCP_RESP" = "405" ]; then
    print_result PASS "OpenShift MCP" "Reachable (HTTP $OCP_RESP)"
  elif [ "$OCP_RESP" = "000" ]; then
    print_result SKIP "OpenShift MCP" "Not deployed (optional)"
  else
    print_result FAIL "OpenShift MCP" "HTTP $OCP_RESP"
  fi

  # MLflow MCP (optional)
  MLF_RESP=$(oc exec "$AGENT_POD" -n "$NAMESPACE" -- curl -s -o /dev/null -w "%{http_code}" \
    "http://mlflow-mcp.redhat-ods-applications.svc.cluster.local:8080/mcp" 2>/dev/null || echo "000")
  if [ "$MLF_RESP" = "200" ] || [ "$MLF_RESP" = "400" ] || [ "$MLF_RESP" = "405" ]; then
    print_result PASS "MLflow MCP" "Reachable (HTTP $MLF_RESP)"
  elif [ "$MLF_RESP" = "000" ]; then
    print_result SKIP "MLflow MCP" "Not deployed (optional)"
  else
    print_result FAIL "MLflow MCP" "HTTP $MLF_RESP"
  fi
fi

# --- 7. Check ConfigMaps ---
echo ""
echo "--- Configuration ---"
CM_COUNT=$(oc get configmaps -n "$NAMESPACE" -l app.kubernetes.io/part-of=rhoai-copilot --no-headers 2>/dev/null | wc -l || echo "0")
SKILL_CMS=$(oc get configmaps -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "skill-" || echo "0")
if [ "$SKILL_CMS" -ge 20 ]; then
  print_result PASS "Skill ConfigMaps" "$SKILL_CMS skills mounted"
else
  print_result FAIL "Skill ConfigMaps" "Only $SKILL_CMS found (expected 22)"
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
TOTAL=$((PASS + FAIL + SKIP))
echo "  Total checks: $TOTAL"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Skipped: $SKIP"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "Result: ALL CHECKS PASSED"
  exit 0
else
  echo "Result: $FAIL CHECKS FAILED — see above for details"
  exit 1
fi
