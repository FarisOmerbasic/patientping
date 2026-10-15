#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    echo "Usage: log-report.sh LOGFILE"
    echo "Script prints the name of the log file it was given"

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

echo "Report for $file"