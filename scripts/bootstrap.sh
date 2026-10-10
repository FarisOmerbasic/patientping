#!/usr/bin/env bash
# bootstrap.sh: install the DevOps toolbelt into WSL Ubuntu.
#
# Read this file top to bottom before running it.
# Idempotent: tools that are already installed are skipped unless you pass --upgrade.
#
# Usage: scripts/bootstrap.sh [--upgrade] [--only tool1,tool2] [--list]

set -Eeuo pipefail

# ---------- settings ----------
BIN_DIR="/usr/local/bin"
UPGRADE=false
ONLY=""

APT_PACKAGES=(
  build-essential make git curl wget ca-certificates gnupg unzip zip bzip2 jq tree
  shellcheck htop dnsutils net-tools iproute2 traceroute netcat-openbsd tcpdump
  strace lsof sysstat openssl bash-completion
)

# Order matters only for readability. Each name maps to an install_<name> function below.
TOOLS=(gh terraform tflint helm kind hadolint trivy gitleaks sqlcmd ssm_plugin)

# ---------- helpers ----------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✘\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# Run as root without sudo (e.g. inside a container), otherwise use sudo.
if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
trap 'die "failed at line $LINENO (exit $?)"' ERR

case "$(uname -m)" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }

# should_install <command> -> true if we need to (re)install it
should_install() {
  if [[ -n "$ONLY" && ",$ONLY," != *",$2,"* ]]; then return 1; fi
  if have "$1" && [[ "$UPGRADE" == false ]]; then
    ok "$2 already installed ($(command -v "$1"))"
    return 1
  fi
  return 0
}

# latest_tag owner/repo -> prints the latest GitHub release tag (e.g. v1.2.3)
latest_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name'
}

download() { curl -fsSL --retry 3 -o "$2" "$1"; }

install_bin() { $SUDO install -m 0755 "$1" "$BIN_DIR/$2"; }

# ---------- tool installers ----------
install_gh() {
  should_install gh gh || return 0
  log "GitHub CLI (apt repo)"
  $SUDO mkdir -p -m 755 /etc/apt/keyrings
  download https://cli.github.com/packages/githubcli-archive-keyring.gpg "$TMP_DIR/gh.gpg"
  $SUDO install -m 0644 "$TMP_DIR/gh.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  $SUDO apt-get update -qq && $SUDO apt-get install -y -qq gh
}

install_terraform() {
  should_install terraform terraform || return 0
  # Official zip from releases.hashicorp.com (works on any Ubuntu codename).
  local v
  v="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version')"
  log "Terraform $v"
  download "https://releases.hashicorp.com/terraform/${v}/terraform_${v}_linux_${ARCH}.zip" "$TMP_DIR/tf.zip"
  unzip -oq "$TMP_DIR/tf.zip" -d "$TMP_DIR/tf"
  install_bin "$TMP_DIR/tf/terraform" terraform
}

install_tflint() {
  should_install tflint tflint || return 0
  local tag; tag="$(latest_tag terraform-linters/tflint)"
  log "tflint $tag"
  download "https://github.com/terraform-linters/tflint/releases/download/${tag}/tflint_linux_${ARCH}.zip" "$TMP_DIR/tflint.zip"
  unzip -oq "$TMP_DIR/tflint.zip" -d "$TMP_DIR/tflint"
  install_bin "$TMP_DIR/tflint/tflint" tflint
}

install_helm() {
  should_install helm helm || return 0
  local tag; tag="$(latest_tag helm/helm)"
  log "Helm $tag"
  download "https://get.helm.sh/helm-${tag}-linux-${ARCH}.tar.gz" "$TMP_DIR/helm.tgz"
  tar -xzf "$TMP_DIR/helm.tgz" -C "$TMP_DIR"
  install_bin "$TMP_DIR/linux-${ARCH}/helm" helm
}

install_kind() {
  should_install kind kind || return 0
  local tag; tag="$(latest_tag kubernetes-sigs/kind)"
  log "kind $tag"
  download "https://github.com/kubernetes-sigs/kind/releases/download/${tag}/kind-linux-${ARCH}" "$TMP_DIR/kind"
  install_bin "$TMP_DIR/kind" kind
}

install_hadolint() {
  should_install hadolint hadolint || return 0
  local tag a; tag="$(latest_tag hadolint/hadolint)"
  [[ "$ARCH" == amd64 ]] && a="x86_64" || a="arm64"
  log "hadolint $tag"
  # Asset naming changed case between releases, so try both.
  download "https://github.com/hadolint/hadolint/releases/download/${tag}/hadolint-linux-${a}" "$TMP_DIR/hadolint" \
    || download "https://github.com/hadolint/hadolint/releases/download/${tag}/hadolint-Linux-${a}" "$TMP_DIR/hadolint"
  install_bin "$TMP_DIR/hadolint" hadolint
}

install_trivy() {
  should_install trivy trivy || return 0
  local tag a; tag="$(latest_tag aquasecurity/trivy)"
  [[ "$ARCH" == amd64 ]] && a="64bit" || a="ARM64"
  log "trivy $tag"
  download "https://github.com/aquasecurity/trivy/releases/download/${tag}/trivy_${tag#v}_Linux-${a}.tar.gz" "$TMP_DIR/trivy.tgz"
  tar -xzf "$TMP_DIR/trivy.tgz" -C "$TMP_DIR" trivy
  install_bin "$TMP_DIR/trivy" trivy
}

install_gitleaks() {
  should_install gitleaks gitleaks || return 0
  local tag a; tag="$(latest_tag gitleaks/gitleaks)"
  [[ "$ARCH" == amd64 ]] && a="x64" || a="arm64"
  log "gitleaks $tag"
  download "https://github.com/gitleaks/gitleaks/releases/download/${tag}/gitleaks_${tag#v}_linux_${a}.tar.gz" "$TMP_DIR/gitleaks.tgz"
  tar -xzf "$TMP_DIR/gitleaks.tgz" -C "$TMP_DIR" gitleaks
  install_bin "$TMP_DIR/gitleaks" gitleaks
}

install_sqlcmd() {
  # go-sqlcmd: Microsoft's modern, single-binary sqlcmd (SQL Server CLI).
  should_install sqlcmd sqlcmd || return 0
  local tag; tag="$(latest_tag microsoft/go-sqlcmd)"
  log "sqlcmd (go-sqlcmd) $tag"
  download "https://github.com/microsoft/go-sqlcmd/releases/download/${tag}/sqlcmd-linux-${ARCH}.tar.bz2" "$TMP_DIR/sqlcmd.tar.bz2"
  tar -xjf "$TMP_DIR/sqlcmd.tar.bz2" -C "$TMP_DIR" sqlcmd
  install_bin "$TMP_DIR/sqlcmd" sqlcmd
}

install_ssm_plugin() {
  # Needed for `aws ssm start-session` (shell into EC2 without SSH or open port 22).
  should_install session-manager-plugin ssm_plugin || return 0
  local d; [[ "$ARCH" == amd64 ]] && d="ubuntu_64bit" || d="ubuntu_arm64"
  log "AWS Session Manager plugin"
  download "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${d}/session-manager-plugin.deb" "$TMP_DIR/ssm.deb"
  $SUDO dpkg -i "$TMP_DIR/ssm.deb" >/dev/null
}

check_preinstalled() {
  # These are expected to be installed already; just report them.
  local c
  for c in go aws kubectl docker; do
    if have "$c"; then ok "$c present ($(command -v "$c"))"; else warn "$c not found: install it before continuing"; fi
  done
  if have docker && ! docker info >/dev/null 2>&1; then
    warn "docker CLI found but daemon not reachable: start Docker Desktop and enable WSL integration for Ubuntu"
  fi
}

# ---------- main ----------
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --upgrade) UPGRADE=true ;;
      --only)    ONLY="${2:?--only needs a comma-separated list}"; shift ;;
      --list)    printf '%s\n' "${TOOLS[@]}"; exit 0 ;;
      -h|--help) usage 0 ;;
      *)         warn "unknown argument: $1"; usage 1 ;;
    esac
    shift
  done

  if [[ -z "$ONLY" ]]; then
    log "apt packages"
    $SUDO apt-get update -qq
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "${APT_PACKAGES[@]}" >/dev/null
    ok "apt packages installed"
  fi

  local t
  for t in "${TOOLS[@]}"; do
    "install_${t}"
  done

  check_preinstalled
  log "Installed versions"
  local c
  for c in gh terraform tflint helm kind hadolint trivy gitleaks sqlcmd session-manager-plugin; do
    if have "$c"; then printf '   %-24s %s\n' "$c" "$(command -v "$c")"; else warn "missing: $c"; fi
  done
  log "Done. Open a new terminal so PATH changes apply."
}

main "$@"
