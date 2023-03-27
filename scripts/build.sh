#!/bin/bash


ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
GO_PROJECT=$(git remote -v|awk 'NR==1{print $2}'|awk -F '//' '{print $2}'|sed "s#\.git##g")

go mod init ${GO_PROJECT}
go mod tidy

for plugin in $(ls *.go);do
    GOOS=$OS GOARCH=$ARCH CGO_ENABLED=0 go build -gcflags="all=-N -l" -o bin/baseCharter-$OS-$ARCH ${plugin}
done