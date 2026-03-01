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

# 安装运行时依赖
RUN apk add --no-cache ca-certificates curl tar gzip

# 安装 helm
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 linux-amd64/helm

# 安装 kustomize
RUN curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin kustomize

COPY --from=builder /usr/local/bin/baseCharter /usr/local/bin/baseCharter
COPY plugin.yaml /home/argocd/cmp-server/plugin.yaml

# uid 999 是 ArgoCD 约定的非 root 用户
# 不指定 gid，避免与 alpine 基础镜像内置组冲突
RUN addgroup -S argocd && adduser -S -u 999 -G argocd argocd

USER 999

# argocd-cmp-server 由 ArgoCD repo-server 的 initContainer 挂载到 /var/run/argocd
ENTRYPOINT ["/var/run/argocd/argocd-cmp-server"]
