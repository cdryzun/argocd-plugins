#!/bin/bash


ARCH=$1
OS=$2
OUTPUT_PATH=$3
GO_PROJECT=$(git remote -v|awk 'NR==1{print $2}'|awk -F '//' '{print $2}'|sed "s#\.git##g"|awk -F '@' '{print $2}')

go mod init ${GO_PROJECT}
go mod tidy

for plugin in $(ls *.go);do
    GOOS=$OS GOARCH=$ARCH CGO_ENABLED=0 go build -gcflags="all=-N -l" -o ${OUTPUT_PATH}/baseCharter-$OS-$ARCH ${plugin}
done