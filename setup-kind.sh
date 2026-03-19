#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${1:-netpol-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Kind Cluster Setup with Calico CNI"
echo "============================================"

# Check prerequisites
for cmd in kind kubectl helm; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}Error: '$cmd' is not installed.${NC}"
    exit 1
  fi
done

# Delete existing cluster if it exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo -e "${YELLOW}Cluster '${CLUSTER_NAME}' already exists. Deleting...${NC}"
  kind delete cluster --name "$CLUSTER_NAME"
fi

# Create Kind cluster with custom config
echo -e "\n${YELLOW}[1/4] Creating Kind cluster '${CLUSTER_NAME}'...${NC}"
kind create cluster --name "$CLUSTER_NAME" --config "$SCRIPT_DIR/kind-config.yaml"

# Wait for nodes (they will be NotReady until CNI is installed)
echo -e "\n${YELLOW}[2/4] Waiting for nodes to appear...${NC}"
kubectl wait --for=condition=Ready=false node --all --timeout=60s 2>/dev/null || true

# Install Calico CNI
echo -e "\n${YELLOW}[3/4] Installing Calico CNI...${NC}"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# Wait for the operator to be ready
kubectl wait --for=condition=Available deployment/tigera-operator -n tigera-operator --timeout=120s

# Apply Calico custom resource
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
        cidr: 192.168.0.0/16
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

# Wait for Calico pods to be ready
echo -e "\n${YELLOW}[4/4] Waiting for Calico to be ready...${NC}"
echo "This may take 1-2 minutes..."
kubectl wait --for=condition=Ready pod -l k8s-app=calico-node -n calico-system --timeout=180s 2>/dev/null || \
  kubectl wait --for=condition=Ready pod -l k8s-app=calico-node -n kube-system --timeout=180s 2>/dev/null || true

# Wait for all nodes to be Ready
kubectl wait --for=condition=Ready node --all --timeout=120s

# Verify
echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  Cluster '${CLUSTER_NAME}' is ready!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
kubectl get nodes
echo ""
echo "Next steps:"
echo "  ./test-connectivity.sh"
echo ""
echo "To delete the cluster later:"
echo "  kind delete cluster --name ${CLUSTER_NAME}"
