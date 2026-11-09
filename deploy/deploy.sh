#!/usr/bin/env bash
set -eEuo pipefail

repo_url="https://github.com/FarisOmerbasic/patientping"
registry="586631277130.dkr.ecr.us-east-1.amazonaws.com"
export AWS_REGION="us-east-1"

usage() {
    echo "Usage: deploy.sh TAG"
    echo "TAG: The tag of the Docker image to deploy"
}

fetch_release() {
    cd /opt
    curl -fsSL "$repo_url/archive/$commit.tar.gz" | tar xz
    cd "patientping-$commit"
}

ecr_login() {
    aws ecr get-login-password | docker login --username AWS --password-stdin "$registry"
}

write_env() {
umask 077
{
echo "ECR_REGISTRY=$registry"
echo "TAG=$tag"
echo "MSSQL_SA_PASSWORD=$(aws ssm get-parameter --name /patientping/dev/mssql_sa_password --with-decryption --query Parameter.Value --output text)" 
echo "PP_DB_PASSWORD=$(aws ssm get-parameter --name /patientping/dev/db_password --with-decryption --query Parameter.Value --output text)"
} > deploy/.env
}

start_stack() {
    docker compose -f deploy/compose.prod.yml up -d
}

wait_healthy() {
    if ! ./scripts/healthcheck.sh -r 20 -t 5 http://localhost/api/patients; then
        echo "deploy.sh: ${tag} failed health check" >&2
        exit 1
    fi
}

if [ "$#" -ne 1 ]; then
    usage
    exit 2
fi

tag="$1"

if [[ ! "$tag" =~ ^sha-[0-9a-f]{40}$ ]]; then
    echo "deploy.sh: TAG must be in the format sha-<40 hex characters>: $tag" >&2
    usage
    exit 2
fi

commit="${tag#sha-}"

cloud-init status --wait > /dev/null
fetch_release
ecr_login
write_env
start_stack
wait_healthy
echo "deploy.sh: $tag is healthy"