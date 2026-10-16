#!/usr/bin/env bash
set -Eeuo pipefail
usage() {
    echo "Usage: healthcheck.sh [-t TIMEOUT] [-r RETRIES] URL [URL...]"
    echo "Script checks the health of a list of URLs provided as arguments."
    echo "0 indicates all URLs are healthy, 1 indicates at least one URL failed. 2 indicates incorrect usage."
    echo "Options:"
    echo "-t TIMEOUT Set the timeout in seconds (default: 5)"
    echo "-r RETRIES Set the number of retries (default: 3)"
    echo "-h Displaying help message"
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

timeout=5
retries=3

while getopts "r:t:h" opt; do
case $opt in
    r) retries="$OPTARG" ;;
    t) timeout="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac
done
shift $((OPTIND - 1))

if [[ ! "$retries" =~ ^[1-9][0-9]*$ ]]; then
  echo "healthcheck.sh: retries must be a whole number of 1 or more: $retries" >&2
  exit 2
fi

if [[ ! "$timeout" =~ ^[1-9][0-9]*$ ]]; then
  echo "healthcheck.sh: timeout must be a whole number of 1 or more: $timeout" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

failed=0
status="000"
elapsed=0
printf '%-40s %-6s %10s %s \n' "URL" "Status" "Elapsed(s)" "Result"
for url in "$@"; do
for r in $(seq 1 "$retries"); do
  result=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" --max-time "$timeout" "$url" || true)
  read -r status elapsed <<< "$result"
  if [[ "$status" == "200" ]]; then
    break
  fi
  if [[ "$r" -lt $retries ]]; then
    sleep 2
  fi
  done
  if [[ "$status" == "200" ]]; then
     printf  '%-40s %-6s %10s %s \n' "$url" "$status" "$elapsed" "OK"
else
     printf  '%-40s %-6s %10s %s \n' "$url" "$status" "$elapsed" "FAIL"
failed=$((failed + 1))
fi
done
if [[ "$failed" -gt 0 ]]; then
  echo "Failed is greater than 0, exiting with code 1"
  exit 1
fi
echo "All URLs are healthy, exiting with code 0"
exit 0
