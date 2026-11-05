#!/usr/bin/env bash
set -Eeuo pipefail

# This script is executed on the EC2 instance during the user data phase of the deployment.

dnf install -y docker
systemctl enable docker
systemctl start docker
docker run -d --name my-container -p 80:80 public.ecr.aws/nginx/nginx:1.30.6-alpine-slim

