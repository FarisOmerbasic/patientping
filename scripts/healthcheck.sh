#!/usr/bin/env bash
set -Eeuo pipefail
failed=0
for url in "$@"; do
  status=$(curl -s -o /dev/null -w "%{http_code}" "$url" || true)
  if [[ "$status" == "200" ]]; then
     echo "$url $status OK"
else
     echo "$url $status FAIL"
failed=$((failed + 1))
fi
done
exit "$failed"
