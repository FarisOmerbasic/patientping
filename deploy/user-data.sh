#!/usr/bin/env bash
set -Eeuo pipefail

# User data: cloud-init runs this once, as root, at the end of the server's first boot.
# It doesn't run again after a reboot. Its output and errors go to /var/log/cloud-init-output.log.

dnf install -y docker
systemctl enable docker
systemctl start docker

# Amazon Linux has no package for the Compose plugin, so it comes from Docker's release page,
# checked against its SHA-256, into a folder where docker looks for plugins.
curl -fsSL -o /tmp/docker-compose https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-linux-x86_64
echo "db1889184726840f75c4f9c001048430d4f25b3be3cb084d3ddd762bc0aed576  /tmp/docker-compose" | sha256sum -c -
install -D -m 0755 /tmp/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
