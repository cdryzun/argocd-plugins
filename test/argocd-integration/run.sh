#!/bin/bash
#
# ArgoCD CMP Integration Test for baseCharter plugin
#
# This script performs end-to-end testing:
# 1. Build plugin image and push to Zot registry
# 2. Run plugin binary to render Kubernetes manifests
# 3. Validate manifests with kubectl --dry-run
# 4. Apply manifests to test namespace
# 5. Verify deployment and resources
# 6. Test with ArgoCD if sidecar is available (optional)
#
# Prerequisites:
# - k3s cluster with kubectl access
# - sudo docker access
# - helm and kustomize installed
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"
TEST_NS="basecharter-test-$$"
TIMEOUT_SECONDS=120

# Colors
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GRN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=1; }
info() { echo -e "${BLU}[INFO]${NC} $1"; }
warn() { echo -e "${YLW}[WARN]${NC} $1"; }
section() { echo ""; echo -e "${BLU}=== $1 ===${NC}"; }

cleanup() {
    info "Cleaning up test resources..."
    kubectl delete ns "${TEST_NS}" --ignore-not-found=true 2>/dev/null || true
}
trap cleanup EXIT

# ------------------------------------------------------------------
# 1. Build and push plugin image
# ------------------------------------------------------------------
section "Building plugin image"
IMAGE_TAG="zot.treesir.pub:5000/devops/argocd-plugins/basecharter:test-$$"

info "Building image: ${IMAGE_TAG}"
if sudo docker build -t "${IMAGE_TAG}" "${PROJECT_DIR}" 2>&1 | tail -5; then
    pass "Image built successfully"
else
    fail "Failed to build image"
    exit 1
fi

info "Pushing image to Zot registry"
if sudo docker push "${IMAGE_TAG}" 2>&1 | tail -3; then
    pass "Image pushed to Zot registry"
else
    fail "Failed to push image"
    exit 1
fi

# Import into k3s for faster access
info "Importing into k3s containerd"
sudo docker save "${IMAGE_TAG}" | sudo k3s ctr images import - 2>/dev/null && pass "Imported to k3s" || warn "k3s import skipped"

# ------------------------------------------------------------------
# 2. Build plugin binary and render manifests
# ------------------------------------------------------------------
section "Rendering Kubernetes manifests"

BINARY="${PROJECT_DIR}/bin/basecharter-test-$$"
mkdir -p "${PROJECT_DIR}/bin"

info "Building plugin binary"
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o "${BINARY}" "${PROJECT_DIR}" 2>&1
pass "Binary built: ${BINARY}"

# Create a temporary test directory with values.yaml
TEST_DIR=$(mktemp -d)
cp -r "${PROJECT_DIR}/examples/nginx-app"/* "${TEST_DIR}/"

info "Running plugin to render manifests"
cd "${TEST_DIR}"
export CHART_HOME="${PROJECT_DIR}/charts"
OUTPUT=$("${BINARY}" 2>&1) || {
    fail "Plugin execution failed"
    echo "${OUTPUT}"
    exit 1
}
cd "${PROJECT_DIR}"

# Save output for validation
MANIFEST_FILE="/tmp/basecharter-manifests-$$.yaml"
echo "${OUTPUT}" > "${MANIFEST_FILE}"

RESOURCE_COUNT=$(echo "${OUTPUT}" | grep -c "^---" || echo "0")
info "Rendered $((RESOURCE_COUNT + 1)) YAML documents"

# Validate YAML syntax
info "Validating YAML syntax"
if echo "${OUTPUT}" | python3 -c "import yaml, sys; list(yaml.safe_load_all(sys.stdin))" 2>&1; then
    pass "YAML syntax valid"
else
    fail "Invalid YAML syntax"
    exit 1
fi

# ------------------------------------------------------------------
# 3. Validate with kubectl dry-run
# ------------------------------------------------------------------
section "Validating manifests with kubectl"

kubectl create ns "${TEST_NS}" --dry-run=client -o yaml | kubectl apply -f - 2>&1
pass "Test namespace created"

info "Running kubectl apply --dry-run=client"
if echo "${OUTPUT}" | kubectl apply -n "${TEST_NS}" --dry-run=client -f - 2>&1; then
    pass "kubectl dry-run validation passed"
else
    fail "kubectl dry-run validation failed"
    exit 1
fi

# ------------------------------------------------------------------
# 4. Apply manifests to cluster
# ------------------------------------------------------------------
section "Applying manifests to cluster"

info "Applying to namespace: ${TEST_NS}"
if echo "${OUTPUT}" | kubectl apply -n "${TEST_NS}" -f - 2>&1; then
    pass "Manifests applied successfully"
else
    fail "Failed to apply manifests"
    exit 1
fi

# ------------------------------------------------------------------
# 5. Verify deployed resources
# ------------------------------------------------------------------
section "Verifying deployed resources"

info "Waiting for Deployment to be created..."
sleep 5

info "Waiting for Deployment to be ready..."
# Wait for any deployment in the namespace to be ready
DEPLOYMENT_NAME=$(kubectl get deployment -n "${TEST_NS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "${DEPLOYMENT_NAME}" ]]; then
    if kubectl rollout status deployment/"${DEPLOYMENT_NAME}" -n "${TEST_NS}" --timeout="${TIMEOUT_SECONDS}s" 2>&1; then
        pass "Deployment '${DEPLOYMENT_NAME}' is ready"
    else
        fail "Deployment rollout failed"
        kubectl describe deployment "${DEPLOYMENT_NAME}" -n "${TEST_NS}" 2>&1 || true
    fi
else
    fail "No deployment found in namespace ${TEST_NS}"
fi

info "Checking Service..."
SERVICE_COUNT=$(kubectl get service -n "${TEST_NS}" --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "${SERVICE_COUNT}" -gt 0 ]]; then
    pass "Service exists (${SERVICE_COUNT} found)"
else
    fail "No service found"
fi

info "Checking ConfigMap (from config/ directory)..."
CM_COUNT=$(kubectl get configmap -n "${TEST_NS}" --no-headers 2>/dev/null | grep -v "kube-root-ca.crt" | wc -l || echo "0")
if [[ "${CM_COUNT}" -gt 0 ]]; then
    pass "ConfigMap exists (${CM_COUNT} found, config/ was processed correctly)"
else
    warn "No custom ConfigMap found (may not be required for this test)"
fi

info "Checking ServiceAccount..."
SA_COUNT=$(kubectl get serviceaccount -n "${TEST_NS}" --no-headers 2>/dev/null | grep -v "default" | wc -l || echo "0")
if [[ "${SA_COUNT}" -gt 0 ]]; then
    pass "ServiceAccount exists (${SA_COUNT} found)"
else
    fail "No custom ServiceAccount found"
fi

info "Listing all resources in test namespace:"
kubectl get all,configmap,serviceaccount -n "${TEST_NS}" 2>&1

# ------------------------------------------------------------------
# 6. Test pod is running and healthy
# ------------------------------------------------------------------
section "Testing pod health"

info "Waiting for pod to be ready..."
# Wait for any pod to be ready in the namespace
kubectl wait --for=condition=Ready pod -n "${TEST_NS}" --all --timeout=120s 2>&1 || {
    warn "Pod wait timed out, checking status..."
}

POD_NAME=$(kubectl get pods -n "${TEST_NS}" --no-headers -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "${POD_NAME}" ]]; then
    info "Pod: ${POD_NAME}"

    # Check pod is running
    POD_STATUS=$(kubectl get pod "${POD_NAME}" -n "${TEST_NS}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "${POD_STATUS}" == "Running" ]]; then
        pass "Pod is running"
    else
        fail "Pod status: ${POD_STATUS}"
    fi

    # Test pod connectivity
    info "Testing HTTP connectivity..."
    if kubectl exec -n "${TEST_NS}" "${POD_NAME}" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null | grep -q "200"; then
        pass "Pod is serving HTTP traffic"
    else
        warn "Could not verify HTTP connectivity (curl may not be available)"
    fi
else
    fail "No pod found"
fi

# ------------------------------------------------------------------
# 7. Optional: Test with ArgoCD if available
# ------------------------------------------------------------------
section "ArgoCD Integration (optional)"

if kubectl get ns argocd &>/dev/null && kubectl get deployment argocd-repo-server -n argocd &>/dev/null; then
    info "ArgoCD is installed, checking for basecharter sidecar..."

    SIDECAR_COUNT=$(kubectl get deployment argocd-repo-server -n argocd \
        -o jsonpath='{.spec.template.spec.containers[?(@.name=="basecharter")].name}' 2>/dev/null | wc -l || echo "0")

    if [[ "${SIDECAR_COUNT}" -gt 0 ]]; then
        pass "ArgoCD has basecharter sidecar configured"

        # Check sidecar image
        SIDECAR_IMAGE=$(kubectl get deployment argocd-repo-server -n argocd \
            -o jsonpath='{.spec.template.spec.containers[?(@.name=="basecharter")].image}' 2>/dev/null || echo "unknown")
        info "Sidecar image: ${SIDECAR_IMAGE}"

        # Verify sidecar is running
        SIDECAR_READY=$(kubectl get pods -n argocd \
            -l app.kubernetes.io/name=argocd-repo-server \
            -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="basecharter")].ready}' 2>/dev/null || echo "false")

        if [[ "${SIDECAR_READY}" == "true" ]]; then
            pass "ArgoCD sidecar is running and ready"
        else
            warn "ArgoCD sidecar not ready"
        fi
    else
        info "ArgoCD does not have basecharter sidecar"
        info "To install, run: helm upgrade argocd argo-cd/argo-cd -n argocd -f deploy/argocd-cmp-values.yaml"
    fi
else
    info "ArgoCD not installed, skipping"
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
section "Test Summary"

echo ""
echo "Test namespace: ${TEST_NS}"
echo "Image: ${IMAGE_TAG}"
echo "Manifests: ${MANIFEST_FILE}"
echo ""

if [[ "${FAIL:-0}" -eq 0 ]]; then
    echo -e "${GRN}All integration tests passed!${NC}"
    echo ""
    echo "Resources are still running. To clean up:"
    echo "  kubectl delete ns ${TEST_NS}"
    echo ""
    echo "To keep testing, the namespace will be deleted automatically on exit."
    exit 0
else
    echo -e "${RED}One or more tests failed${NC}"
    echo ""
    echo "Debug commands:"
    echo "  kubectl get all -n ${TEST_NS}"
    echo "  kubectl describe pods -n ${TEST_NS}"
    echo "  kubectl logs -n ${TEST_NS} -l app.kubernetes.io/name=nginx-app"
    exit 1
fi
