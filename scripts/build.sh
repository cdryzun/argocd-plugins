#!/bin/bash

set -euo pipefail

ARCH=${1:?Usage: build.sh <arch> <os> <output_path>}
OS=${2:?Usage: build.sh <arch> <os> <output_path>}
OUTPUT_PATH=${3:?Usage: build.sh <arch> <os> <output_path>}

GOOS=${OS} GOARCH=${ARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" \
    -o "${OUTPUT_PATH}/baseCharter-${OS}-${ARCH}" .
