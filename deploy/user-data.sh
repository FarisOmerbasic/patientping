#!/usr/bin/env bash
set -Eeuo pipefail

# User data: cloud-init runs this once, as root, at the end of the server's first boot.
# It doesn't run again after a reboot. Its output and errors go to /var/log/cloud-init-output.log.

dnf install -y docker
systemctl enable docker
systemctl start docker
docker run -d --name my-container --restart unless-stopped -p 80:80 public.ecr.aws/nginx/nginx:1.30.6-alpine-slim

