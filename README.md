# argocd-plugins

[![CI](https://github.com/cdryzun/argocd-plugins/actions/workflows/ci.yml/badge.svg)](https://github.com/cdryzun/argocd-plugins/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Go](https://img.shields.io/badge/go-1.26-00ADD8.svg)](https://go.dev/)

A production-ready **ArgoCD Config Management Plugin (CMP v2)** that enables application teams to deploy to Kubernetes with only a `values.yaml` file — no Helm chart management required.

Platform teams ship one base chart (`app-base`). Application teams consume it through ArgoCD without owning it.

---

## The Problem

In a multi-team Kubernetes platform, every team managing their own Helm chart leads to:

- Duplicate boilerplate across dozens of charts (Deployment, Service, HPA, Ingress, RBAC...)
- Inconsistent resource limits, probe configurations, and security contexts
- No central place to enforce platform-wide standards

**This plugin solves it**: platform engineers maintain one base chart; application teams just write `values.yaml`.

---

## How It Works

```
Application Git Repo              Plugin Container (sidecar in ArgoCD)
┌──────────────────┐              ┌─────────────────────────────────┐
│  values.yaml     │              │  basecharter binary             │
│  config/         │─────────────▶│  + app-base chart (bundled)     │
│    nginx.conf    │    ArgoCD    │  + helm + kustomize             │
└──────────────────┘    CMP v2   └─────────────┬───────────────────┘
                                               │
                                               ▼ kustomize + helm render
                                  ┌─────────────────────────┐
                                  │  Kubernetes Manifests   │
                                  │  Deployment / Service   │
                                  │  Ingress / HPA / RBAC   │
                                  │  ConfigMap (from config/)│
                                  └─────────────────────────┘
```

The `basecharter` plugin:
1. Reads `CHART_HOME` and `APP_BASE_NAME` from environment (or ArgoCD Application spec)
2. Generates a `kustomization.yaml` pointing to the bundled base chart
3. Auto-detects a `config/` directory and creates ConfigMaps for each file
4. Runs `kustomize + helm` and streams YAML to ArgoCD stdout

---

## Quick Start

### 1. Install the Plugin Sidecar into ArgoCD

```bash
# Add the argo-cd Helm repo (if not already added)
helm repo add argo-cd https://argoproj.github.io/argo-helm

# Inject the basecharter sidecar into argocd-repo-server
helm upgrade argocd argo-cd/argo-cd \
  --namespace argocd \
  --reuse-values \
  -f deploy/argocd-cmp-values.yaml
```

> Edit `deploy/argocd-cmp-values.yaml` and set your image tag if using a custom registry.

Verify the sidecar is running:

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server
kubectl logs -n argocd \
  -l app.kubernetes.io/name=argocd-repo-server \
  -c basecharter
```

### 2. Create an Application Repository

Your application repo only needs these files:

```
my-app/
├── values.yaml       # required
└── config/           # optional: files become ConfigMaps
    └── nginx.conf
```

See [`examples/nginx-app/`](examples/nginx-app/) for a complete example.

### 3. Create an ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/nginx-app.git
    targetRevision: main
    path: .
    plugin:
      name: basecharter              # explicit plugin selection
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## values.yaml Reference

The base chart exposes the following configuration. All fields are optional with sensible defaults.

### Core

| Field | Default | Description |
|-------|---------|-------------|
| `appName` | `""` | Application name (used as resource name prefix) |
| `replicaCount` | `1` | Number of pod replicas |
| `containerPort` | `80` | Port the container listens on |

### Image

| Field | Default | Description |
|-------|---------|-------------|
| `image.repository` | `nginx` | Container image repository |
| `image.tag` | `latest` | Image tag |
| `image.pullPolicy` | `IfNotPresent` | `Always`, `Never`, or `IfNotPresent` |

### Environment Variables

```yaml
envVars:
  - name: "TZ"
    value: "Asia/Shanghai"

# Inject values from a Kubernetes Secret
secretVarsSecretName: "my-app-secrets"   # default: "app-secrets"
secretVars:
  DB_PASSWORD: "db-password"             # key inside the Secret
```

### Resources

```yaml
resources:
  limits:
    cpu: 500m
    memory: 1024Mi
  requests:
    cpu: 50m
    memory: 128Mi
```

### Config Files → ConfigMaps

Drop any file into `config/` in your app repo. The plugin auto-creates a ConfigMap and mounts it:

```yaml
configMount:
  configList:
    nginx.conf: "/etc/nginx/conf.d/nginx.conf"
```

### Ingress

```yaml
ingress:
  enabled: true
  hosts:
    - host: myapp.example.com
      paths:
        - /
```

### Autoscaling (HPA)

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### Persistence

```yaml
persistence:
  enabled: true
  size: 10Gi
  mountPath: "/data"
  storageClassName: "standard"
```

---

## Plugin Configuration

The plugin reads environment variables from the ArgoCD Application spec or from the sidecar container:

| Variable | Default | Description |
|----------|---------|-------------|
| `CHART_HOME` | `/home/argocd/charts` | Directory containing the base chart |
| `APP_BASE_NAME` | `app-base` | Name of the Helm chart directory inside `CHART_HOME` |

Override per-application via ArgoCD Application spec:

```yaml
source:
  plugin:
    name: basecharter
    env:
      - name: APP_BASE_NAME
        value: my-custom-chart
```

---

## Building the Image

The plugin ships as a Docker image published to [GitHub Container Registry](https://ghcr.io).

```bash
# Pull the latest image
docker pull ghcr.io/cdryzun/basecharter:latest

# Or build locally
docker build -t basecharter:local .
```

The image bundles:
- `basecharter` Go binary
- `helm` v3.17.3
- `kustomize` v5.8.1
- `app-base` Helm chart

---

## Development

### Prerequisites

- Go 1.21+
- helm 3.x
- kustomize 5.x
- Docker (optional, for `docker build` check)

### Build & Test

```bash
# Build binary
go build -o bin/basecharter .

# Run all checks (go vet, yaml lint, functional test, docker build)
bash scripts/verify.sh

# Skip docker build (faster for development)
SKIP_DOCKER=1 bash scripts/verify.sh
```

### Project Structure

```
argocd-plugins/
├── baseCharter.go              # CMP plugin source (single file)
├── plugin.yaml                 # CMP v2 spec
├── Dockerfile                  # Multi-stage build
├── go.mod / go.sum
├── charts/
│   └── app-base/               # Base Helm chart (the core value)
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── deploy/
│   └── argocd-cmp-values.yaml  # Helm values for sidecar injection
├── examples/
│   └── nginx-app/              # Minimal working example
├── scripts/
│   ├── build.sh
│   └── verify.sh               # End-to-end validation script
└── test/
    └── basecharter/            # Integration test fixtures
```

---

## Comparison

| | This Plugin | Raw Helm | Raw Kustomize | app-template |
|---|---|---|---|---|
| Teams own chart? | No | Yes | Partial | Optional |
| Config → ConfigMap auto | Yes | No | Manual | No |
| CMP v2 compatible | Yes | Yes | Yes | Yes |
| Base chart updates centralized | Yes | No | No | No |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache License 2.0](LICENSE)
