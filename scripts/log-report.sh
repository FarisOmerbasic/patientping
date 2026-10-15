#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    echo "Usage: log-report.sh LOGFILE"
    echo "Script prints the name of the log file it was given"

}
print_total() {
    local logfile="$1"
    echo "== Total requests"
    wc -l < "$logfile"
}


if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
usage
exit 2
fi
file="$1"

if [[ ! -f "$file" ]]; then
echo "log-report.sh: not a file: $file" >&2
exit 1
fi

if [[ ! -r "$file" ]]; then
echo "log-report.sh: Can't be read: $file" >&2
exit 1
fi

print_total "$file"