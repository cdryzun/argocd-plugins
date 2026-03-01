#!/bin/bash
#
# End-to-end verification script for the plugin system.
# Run locally or in CI: bash scripts/verify.sh
# Skip docker build:    SKIP_DOCKER=1 bash scripts/verify.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TMP_DIR="$(mktemp -d)"
BINARY="${TMP_DIR}/baseCharter"
FAIL=0

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GRN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=1; }
info() { echo -e "${YLW}[INFO]${NC} $1"; }
skip() { echo -e "${YLW}[SKIP]${NC} $1"; }
section() { echo ""; echo "=== $1 ==="; }

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

cd "${PROJECT_DIR}"
info "project: ${PROJECT_DIR}"
info "go: $(go version)"
info "helm: $(helm version --short 2>/dev/null || echo 'not found')"
info "kustomize: $(kustomize version 2>/dev/null || echo 'not found')"

# ------------------------------------------------------------------
# 1. go vet
# ------------------------------------------------------------------
section "go vet"
if go vet ./... 2>&1; then
    pass "go vet ./..."
else
    fail "go vet ./..."
fi

# ------------------------------------------------------------------
# 2. go build
# ------------------------------------------------------------------
section "go build"
if GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
       go build -trimpath -ldflags="-s -w" -o "${BINARY}" . 2>&1; then
    pass "go build → ${BINARY}"
else
    fail "go build"
fi

# ------------------------------------------------------------------
# 3. YAML syntax
# ------------------------------------------------------------------
section "YAML syntax"
for f in plugin.yaml deploy/argocd-cmp-values.yaml; do
    if python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>&1; then
        pass "yaml valid: $f"
    else
        fail "yaml broken: $f"
    fi
done

# ------------------------------------------------------------------
# 4. plugin.yaml structure (CMP v2 spec)
# ------------------------------------------------------------------
section "plugin.yaml structure"
python3 - <<'PYEOF' && pass "plugin.yaml CMP v2 structure" || fail "plugin.yaml CMP v2 structure"
import yaml, sys
doc = yaml.safe_load(open('plugin.yaml'))
assert doc.get('apiVersion') == 'argoproj.io/v1alpha1', \
    f"wrong apiVersion: {doc.get('apiVersion')}"
assert doc.get('kind') == 'ConfigManagementPlugin', \
    f"wrong kind: {doc.get('kind')}"
assert 'generate' in doc.get('spec', {}), "spec.generate missing"
assert 'command' in doc['spec']['generate'], "spec.generate.command missing"
print(f"  name={doc['metadata']['name']} command={doc['spec']['generate']['command']}")
PYEOF

# ------------------------------------------------------------------
# 5. Functional test (requires helm + kustomize)
# ------------------------------------------------------------------
section "Functional test (binary + chart rendering)"
if ! command -v helm &>/dev/null; then
    skip "helm not found, skipping functional test"
elif ! command -v kustomize &>/dev/null; then
    skip "kustomize not found, skipping functional test"
elif [[ ! -f "${BINARY}" ]]; then
    skip "binary not built, skipping functional test"
else
    TEST_WORK="${TMP_DIR}/test-run"
    cp -r test/baseCharter "${TEST_WORK}"

    set +e
    OUTPUT=$(cd "${TEST_WORK}" && CHART_HOME="${PROJECT_DIR}/charts" "${BINARY}" 2>&1)
    EXIT_CODE=$?
    set -e

    if [[ ${EXIT_CODE} -ne 0 ]]; then
        fail "binary exited ${EXIT_CODE}: ${OUTPUT}"
    else
        # Validate output is valid multi-doc YAML containing expected resource kinds
        python3 - <<PYEOF && pass "output: valid YAML with expected resources" || fail "output: missing required resources"
import yaml, sys

docs = [d for d in yaml.safe_load_all("""${OUTPUT}""") if d]
assert len(docs) > 0, "empty output"
kinds = {d.get('kind') for d in docs}
print(f"  rendered {len(docs)} resources: {sorted(kinds)}")
assert 'Deployment'    in kinds, f"Deployment missing (got {kinds})"
assert 'ServiceAccount' in kinds, f"ServiceAccount missing"
assert 'ConfigMap'     in kinds, f"ConfigMap missing (config/ processing failed)"
PYEOF

        # Verify temporary file cleanup (defer must have run)
        if [[ -f "${TEST_WORK}/kustomization.yaml" ]]; then
            fail "kustomization.yaml leaked (defer did not run)"
        else
            pass "kustomization.yaml cleaned up by defer"
        fi
    fi
fi

# ------------------------------------------------------------------
# 6. Docker build (optional; set SKIP_DOCKER=1 to skip)
# ------------------------------------------------------------------
section "Docker build"
if [[ "${SKIP_DOCKER:-0}" == "1" ]]; then
    skip "SKIP_DOCKER=1, skipping docker build"
elif ! command -v docker &>/dev/null; then
    skip "docker not found"
else
    DOCKER_CMD="docker"
    # In CI docker is usually accessible directly; fall back to sudo for local environments
    if ! docker info &>/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    fi

    if ${DOCKER_CMD} build -t "basecharter-verify:local" . 2>&1; then
        pass "docker build"
        ${DOCKER_CMD} rmi "basecharter-verify:local" &>/dev/null || true
    else
        fail "docker build"
    fi
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "================================================"
if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GRN}All checks passed${NC}"
    exit 0
else
    echo -e "${RED}One or more checks FAILED${NC}"
    exit 1
fi
