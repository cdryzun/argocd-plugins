# Contributing to argocd-plugins

Thank you for your interest in contributing!

## How to Contribute

### Reporting Issues

- Search existing issues before opening a new one
- Include ArgoCD version, Kubernetes version, and plugin version
- Attach relevant logs (`kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -c basecharter`)

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Make your changes
4. Run the verification script: `bash scripts/verify.sh`
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `chore:`
6. Open a PR against `main`

### Development Setup

```bash
# Prerequisites
go 1.21+
helm 3.x
kustomize 5.x
docker

# Clone
git clone https://github.com/YOUR_ORG/argocd-plugins.git
cd argocd-plugins

# Build
go build -o bin/basecharter .

# Run all checks
bash scripts/verify.sh
```

### Adding a New Base Chart Feature

The base chart lives in `charts/app-base/`. It follows standard Helm chart conventions.

- Add new values with sensible defaults in `charts/app-base/values.yaml`
- Document every new field with a comment
- Add a test case in `test/basecharter/` that exercises the new feature

### Extending the Plugin

The plugin source is `baseCharter.go`. Key extension points:

- `processConfigFiles()` — add custom pre-processing logic
- `main()` — add new environment variable controls via `getEnv()`

## Code Style

- Go: run `go vet ./...` before committing
- YAML: consistent 2-space indentation
- Shell: `set -euo pipefail` at the top of every script

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
