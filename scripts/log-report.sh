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
    echo
}

print_status_codes() {
    local logfile="$1"
    echo "== Status codes"
    awk '{print $9}' "$logfile" | sort | uniq -c
    echo
}

print_top_ips() {
    local logfile="$1"
    echo "== Top 5 IPs"
    awk '{print $1}' "$logfile" | sort | uniq -c | sort -rn | head -n 5
    echo
}

print_top_paths() {
    local logfile="$1"
    echo "== Top 5 paths"
    awk '{print $7}' "$logfile" | sort | uniq -c | sort -rn | head -n 5
    echo
}
print_5xx() {
    local logfile="$1"
    echo "== 5xx errors"
    local total count
    total=$(wc -l < "$logfile")
    count=$(grep -cE '" 5[0-9][0-9] ' "$logfile") 
    echo "5xx errors: $count ($((count * 100 / total))%)"
    echo
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
print_status_codes "$file"
print_top_ips "$file"
print_top_paths "$file"
print_5xx "$file"