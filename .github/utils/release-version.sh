#!/bin/bash
TOKEN=$1

echo `curl --silent -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3.raw" \
  -s "https://api.github.com/repos/apecloud/kubeblocks/releases/latest" | jq -r '.tag_name[1:]'`