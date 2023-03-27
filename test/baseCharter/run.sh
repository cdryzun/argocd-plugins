#!/bin/bash

WORK_PATH=$(pwd)
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

cd ${WORK_PATH}/$(dirname $0)
export CHART_HOME='.'
../../bin/baseCharter-$OS-$ARCH 

cd ${WORK_PATH}