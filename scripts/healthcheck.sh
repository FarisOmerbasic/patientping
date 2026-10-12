#!/usr/bin/env bash
set -Eeuo pipefail
url="$1"
status=$(curl -s -o /dev/null -w "%{http_code}" "$url" || true)
if [[ "$status" == "200" ]]; then
echo "$url $status OK" && exit 0
else
echo "$url $status FAIL" && exit 1
fi
