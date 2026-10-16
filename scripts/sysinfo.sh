#!/usr/bin/env bash
set -Eeuo pipefail
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "CPUs: $(nproc)"
echo "OS: $(awk -F= '/^PRETTY_NAME/{print $2}' /etc/os-release | tr -d '"')"    
echo "Uptime: $(uptime -p)"
echo "Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
echo "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2}')"
echo "IP Address: $(hostname -I | awk '{print $1}'))"