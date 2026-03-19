# Kubernetes Network Policy Demo — Helm Charts

Two Helm charts demonstrating Kubernetes NetworkPolicy:
- **frontend-app**: nginx deployed in the `app` namespace
- **database**: PostgreSQL deployed in the `db` namespace

Uses standard `networking.k8s.io/v1` NetworkPolicy — works on **both Kind and EKS**.

## Prerequisites

### Option A: Local Kind Cluster

1. Install [kind](https://kind.sigs.k8s.io/), [kubectl](https://kubernetes.io/docs/tasks/tools/), and [helm](https://helm.sh/docs/intro/install/)

2. Create a Kind cluster with Calico (Kind's default `kindnet` CNI does not enforce NetworkPolicy):
   ```bash
   chmod +x setup-kind.sh
   ./setup-kind.sh
   ```
   This creates a cluster named `netpol-demo` with Calico CNI installed.

### Option B: EKS Cluster

1. Enable NetworkPolicy support on the VPC CNI addon:
   ```bash
   aws eks update-addon --cluster-name <CLUSTER> \
     --addon-name vpc-cni \
     --configuration-values '{"enableNetworkPolicy": "true"}' \
     --resolve-conflicts OVERWRITE
   ```

2. Verify the network policy agent is running:
   ```bash
   kubectl get daemonset -n kube-system aws-node
   ```

## Deploy

Deploy each chart independently (same commands for both Kind and EKS):

```bash
# Deploy database first
helm upgrade --install database ./database --wait

# Deploy frontend app
helm upgrade --install frontend-app ./frontend-app --wait
```

## Customization

All network policy rules are configurable via `values.yaml`. Key sections:

### Namespace Labels (used for cross-namespace matching)
```yaml
namespace:
  labels:
    ns: app          # this label is referenced by the database chart
    environment: dev
  annotations:
    team: "my-team"
```

### Network Policy Toggles
```yaml
networkPolicy:
  enabled: true              # master switch
  defaultDenyIngress: true   # deny all ingress by default
  defaultDenyEgress: true    # deny all egress by default
```

### Adding More Allowed Namespaces to Database
```yaml
# In database/values.yaml
networkPolicy:
  ingress:
    allowedNamespaces:
      - name: app-namespace
        namespaceLabels:
          ns: app
        ports:
          - port: 5432
            protocol: TCP
      - name: monitoring
        namespaceLabels:
          ns: monitoring
        ports:
          - port: 5432
            protocol: TCP
```

### Adding External Services
```yaml
# In frontend-app/values.yaml
networkPolicy:
  egress:
    external:
      rules:
        - name: my-api
          cidr: 10.1.0.0/16
          ports:
            - port: 443
              protocol: TCP
```

## Test Connectivity

```bash
chmod +x test-connectivity.sh
./test-connectivity.sh
```

The test script auto-detects Kind vs EKS and runs 5 connectivity tests:
- **Test 1**: app → db:5432 — should PASS (allowed by policy)
- **Test 2**: app → db:3306 — should FAIL (wrong port, blocked by policy)
- **Test 3**: default ns → db:5432 — should FAIL (wrong namespace, blocked by policy)
- **Test 4**: DNS resolution from app ns — should PASS
- **Test 5**: app → db via short DNS name — should PASS

## Cleanup

```bash
helm uninstall frontend-app
helm uninstall database
kubectl delete namespace app db

# If using Kind:
kind delete cluster --name netpol-demo
```

## File Structure

```
helm-charts/
├── README.md
├── kind-config.yaml
├── setup-kind.sh
├── test-connectivity.sh
├── frontend-app/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── namespace.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── networkpolicy-default-deny.yaml
│       ├── networkpolicy-ingress.yaml
│       └── networkpolicy-egress.yaml
└── database/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── namespace.yaml
        ├── deployment.yaml
        ├── service.yaml
        ├── networkpolicy-default-deny.yaml
        ├── networkpolicy-ingress.yaml
        └── networkpolicy-egress.yaml
```
# network_policies
