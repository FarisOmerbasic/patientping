#!/usr/bin/env bash
set -Eeuo pipefail
usage() {
    echo "Script checks the health of a list of URLs provided as arguments."
    echo "Number of failed URLs will be returned as the exit code."
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

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi


failed=0
for url in "$@"; do
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" || true)
  if [[ "$status" == "200" ]]; then
     echo "$url $status OK"
else
     echo "$url $status FAIL"
failed=$((failed + 1))
fi
done
exit "$failed"
