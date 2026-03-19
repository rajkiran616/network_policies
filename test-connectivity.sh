#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  Network Policy Test Script"
echo "  Works on: Kind (Calico) and EKS (VPC CNI)"
echo "============================================"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_IMAGE="busybox:1.36"
DB_HOST="postgres-db.db.svc.cluster.local"
DB_PORT="5432"
WRONG_PORT="3306"
PASS=0
FAIL=0

cleanup() {
  echo -e "\n${YELLOW}Cleaning up test pods...${NC}"
  kubectl delete pod test-from-app -n app --ignore-not-found=true --wait=false 2>/dev/null || true
  kubectl delete pod test-from-default -n default --ignore-not-found=true --wait=false 2>/dev/null || true
}
trap cleanup EXIT

# -------------------------------------------
# Step 1: Detect environment
# -------------------------------------------
echo -e "\n${YELLOW}[1/7] Detecting environment...${NC}"
if kind get clusters 2>/dev/null | grep -q .; then
  echo -e "Detected: ${GREEN}Kind cluster${NC} (using Calico for NetworkPolicy)"
else
  echo -e "Detected: ${GREEN}EKS or other cluster${NC}"
fi
echo "Current context: $(kubectl config current-context)"

# -------------------------------------------
# Step 2: Deploy both Helm charts
# -------------------------------------------
echo -e "\n${YELLOW}[2/7] Deploying database chart...${NC}"
helm upgrade --install database "$SCRIPT_DIR/database" --wait --timeout 120s

echo -e "\n${YELLOW}[3/7] Deploying frontend-app chart...${NC}"
helm upgrade --install frontend-app "$SCRIPT_DIR/frontend-app" --wait --timeout 120s

echo -e "\n${YELLOW}[4/7] Waiting for application pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=postgres-db -n db --timeout=90s
kubectl wait --for=condition=ready pod -l app=frontend -n app --timeout=90s

echo -e "\n${GREEN}Pods running:${NC}"
kubectl get pods -n app -o wide
kubectl get pods -n db -o wide

# -------------------------------------------
# Step 3: Verify network policies
# -------------------------------------------
echo -e "\n${YELLOW}[5/7] Listing network policies...${NC}"
echo -e "\n--- app namespace ---"
kubectl get networkpolicies -n app
echo -e "\n--- db namespace ---"
kubectl get networkpolicies -n db

# -------------------------------------------
# Step 4: Launch dedicated test pods
# Uses busybox which has nc and nslookup
# -------------------------------------------
echo -e "\n${YELLOW}[6/7] Creating test pods...${NC}"

# Test pod in 'app' namespace — labeled as frontend so it matches egress policies
kubectl run test-from-app -n app \
  --image="$TEST_IMAGE" \
  --restart=Never \
  --labels="app=frontend" \
  --overrides='{"spec":{"terminationGracePeriodSeconds":0}}' \
  --command -- sleep 300 2>/dev/null || true

# Test pod in 'default' namespace — should be blocked by db ingress policy
kubectl run test-from-default -n default \
  --image="$TEST_IMAGE" \
  --restart=Never \
  --overrides='{"spec":{"terminationGracePeriodSeconds":0}}' \
  --command -- sleep 300 2>/dev/null || true

kubectl wait --for=condition=ready pod/test-from-app -n app --timeout=60s
kubectl wait --for=condition=ready pod/test-from-default -n default --timeout=60s

# -------------------------------------------
# Step 5: Run connectivity tests
# -------------------------------------------
echo -e "\n${YELLOW}[7/7] Running connectivity tests...${NC}"

# Test 1: app -> db on correct port (SHOULD SUCCEED)
echo -e "\n--- Test 1: app ns -> db:${DB_PORT} (expect PASS) ---"
if kubectl exec test-from-app -n app -- nc -z -w 5 "$DB_HOST" "$DB_PORT" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS: app can reach db on port ${DB_PORT}${NC}"
  ((PASS++))
else
  echo -e "${RED}✗ FAIL: app cannot reach db on port ${DB_PORT}${NC}"
  ((FAIL++))
fi

# Test 2: app -> db on wrong port (SHOULD FAIL)
echo -e "\n--- Test 2: app ns -> db:${WRONG_PORT} (expect FAIL) ---"
if kubectl exec test-from-app -n app -- nc -z -w 5 "$DB_HOST" "$WRONG_PORT" 2>/dev/null; then
  echo -e "${RED}✗ FAIL: app can reach db on port ${WRONG_PORT} (unexpected)${NC}"
  ((FAIL++))
else
  echo -e "${GREEN}✓ PASS: app correctly blocked from db on port ${WRONG_PORT}${NC}"
  ((PASS++))
fi

# Test 3: default namespace -> db (SHOULD FAIL)
echo -e "\n--- Test 3: default ns -> db:${DB_PORT} (expect FAIL) ---"
if kubectl exec test-from-default -n default -- nc -z -w 5 "$DB_HOST" "$DB_PORT" 2>/dev/null; then
  echo -e "${RED}✗ FAIL: default namespace can reach db (unexpected)${NC}"
  ((FAIL++))
else
  echo -e "${GREEN}✓ PASS: default namespace correctly blocked from db${NC}"
  ((PASS++))
fi

# Test 4: DNS resolution from app namespace (SHOULD SUCCEED)
echo -e "\n--- Test 4: DNS resolution from app ns (expect PASS) ---"
if kubectl exec test-from-app -n app -- nslookup "$DB_HOST" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS: DNS resolution works from app namespace${NC}"
  ((PASS++))
else
  echo -e "${RED}✗ FAIL: DNS resolution failed from app namespace${NC}"
  ((FAIL++))
fi

# Test 5: app -> db via short DNS name (SHOULD SUCCEED)
echo -e "\n--- Test 5: app ns -> db via short DNS name (expect PASS) ---"
if kubectl exec test-from-app -n app -- nc -z -w 5 "postgres-db.db" "$DB_PORT" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS: app can reach db via short DNS name${NC}"
  ((PASS++))
else
  echo -e "${RED}✗ FAIL: app cannot reach db via short DNS name${NC}"
  ((FAIL++))
fi

# -------------------------------------------
# Results
# -------------------------------------------
echo -e "\n============================================"
echo -e "  ${GREEN}Passed: ${PASS}${NC}  |  ${RED}Failed: ${FAIL}${NC}"
echo -e "============================================"
echo ""
echo "To uninstall:"
echo "  helm uninstall frontend-app"
echo "  helm uninstall database"
echo "  kubectl delete namespace app db"
if kind get clusters 2>/dev/null | grep -q .; then
  echo "  kind delete cluster --name <cluster-name>"
fi
