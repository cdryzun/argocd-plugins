#!/bin/bash

WORK_PATH=$(pwd)
PLUGIN=$1
ARCH=$2
OS=$3

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHARTS_DIR="${SCRIPT_DIR}/../../charts"

cd "${WORK_PATH}/$(dirname $0)"
export CHART_HOME="${CHARTS_DIR}"
../../bin/$PLUGIN-$OS-$ARCH

cd "${WORK_PATH}"
