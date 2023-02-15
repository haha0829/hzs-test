#!/bin/bash

set -eo pipefail

DOCKER_CREDS=$1
ALIYUN_CREDS=$2
FILE_NAME=$3

while read -r line
do
   skopeo sync --all \
      --src-creds "$DOCKER_CREDS" \
      --dest-creds "$ALIYUN_CREDS" \
      --src docker \
      --dest docker \
      docker.io/$line \
      registry.cn-hangzhou.aliyuncs.com/apecloud
done < $FILE_NAME
