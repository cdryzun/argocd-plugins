#!/bin/bash

WORK_PATH=$(pwd)
PLUGIN=$1
ARCH=$2
OS=$3

cd ${WORK_PATH}/$(dirname $0)
export CHART_HOME='.'
../../bin/$PLUGIN-$OS-$ARCH 

cd ${WORK_PATH}