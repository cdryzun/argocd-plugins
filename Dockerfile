# ---- builder ----
FROM golang:1.26-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY baseCharter.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /usr/local/bin/baseCharter .

# ---- runtime ----
FROM alpine:3.21

ARG HELM_VERSION=3.17.3
ARG KUSTOMIZE_VERSION=5.8.1

# Install runtime dependencies
RUN apk add --no-cache ca-certificates curl tar gzip

# Install helm
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 linux-amd64/helm

# Install kustomize
RUN curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin kustomize

COPY --from=builder /usr/local/bin/baseCharter /usr/local/bin/baseCharter

# Create config directory and copy plugin manifest
# ArgoCD CMP server expects: /home/argocd/cmp-server/config/plugin.yaml
RUN mkdir -p /home/argocd/cmp-server/config
COPY plugin.yaml /home/argocd/cmp-server/config/plugin.yaml

# Bundle the base chart so the plugin works without external chart sources
COPY charts/ /home/argocd/charts/

# uid 999 is the ArgoCD convention for non-root user
# Do not specify gid to avoid conflicts with alpine built-in groups
RUN addgroup -S argocd && adduser -S -u 999 -G argocd argocd

USER 999

# Default chart location bundled in the image
ENV CHART_HOME=/home/argocd/charts

# argocd-cmp-server is mounted by ArgoCD repo-server initContainer
ENTRYPOINT ["/var/run/argocd/argocd-cmp-server"]
