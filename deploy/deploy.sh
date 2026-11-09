#!/usr/bin/env bash
set -Eeuo pipefail

# Deploys one release of PatientPing on the dev server. Run Command starts it as root:
#   bash deploy.sh sha-<commit>
# A second run with the same tag changes nothing. Never run it with bash -x: what it prints
# ends up in Run Command's output, and -x would print the two passwords.

# Any step that fails ends the script with 1 and its line number, so 2 stays for wrong usage.
trap 'echo "deploy.sh: failed at line $LINENO" >&2; exit 1' ERR

repo_url="https://github.com/FarisOmerbasic/patientping"
registry="586631277130.dkr.ecr.us-east-1.amazonaws.com"
export AWS_REGION="us-east-1"

usage() {
    echo "Usage: deploy.sh TAG"
    echo "Fetches the release of TAG's commit, starts it on this server and waits until it's healthy."
    echo "TAG is sha- and the full 40-character commit, the tag CI gives the images."
    echo "Exit codes: 0 deployed and healthy, 1 a step failed or the app didn't become healthy, 2 wrong usage."
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
    # The file is readable by root only. One > for the whole group writes it fresh on every
    # run, so a second run leaves the same four lines. No line here prints a value.
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
    # Up to 20 tries, 2 seconds apart, each waiting at most 5 seconds for an answer:
    # between about 40 seconds and 2.5 minutes before it gives up.
    if ! ./scripts/healthcheck.sh -r 20 -t 5 http://localhost/api/patients; then
        echo "deploy.sh: ${tag} failed health check" >&2
        exit 1
    fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 1 ]]; then
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

# On a fresh server, Run Command can start this before user data has installed Docker and
# Compose. This waits until user data has finished.
cloud-init status --wait > /dev/null
fetch_release
ecr_login
write_env
start_stack
wait_healthy
echo "deploy.sh: $tag is healthy"
