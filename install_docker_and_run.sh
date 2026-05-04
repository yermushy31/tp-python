#!/usr/bin/env bash
# =============================================================================
# install-docker-git.sh
# Automatically installs: Docker Engine, Docker CLI, Docker Compose, Git
# Supported: Debian / Ubuntu
# Run as root or with sudo.
# =============================================================================

set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}━━━  $*  ━━━${RESET}"; }

# ── root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Please run as root:  sudo bash $0"

# ── detect OS ────────────────────────────────────────────────────────────────
[[ -f /etc/os-release ]] || error "/etc/os-release not found — unsupported OS."
source /etc/os-release
OS_ID="${ID}"
OS_CODENAME="${VERSION_CODENAME:-}"
[[ "$OS_ID" =~ ^(ubuntu|debian)$ ]] || error "Unsupported OS: $OS_ID"

info "OS       : $PRETTY_NAME"
info "Codename : $OS_CODENAME"

# =============================================================================
# 1. SYSTEM UPDATE
# =============================================================================
section "System update"
apt-get update -qq
apt-get upgrade -y -qq
success "System up to date."

# =============================================================================
# 2. GIT
# =============================================================================
section "Git"
apt-get install -y -qq git
success "Git $(git --version) installed."

# =============================================================================
# 3. DOCKER PREREQUISITES
# =============================================================================
section "Docker prerequisites"
apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
success "Prerequisites ready."

# =============================================================================
# 4. DOCKER GPG KEY + APT REPO
# =============================================================================
section "Docker repository"

KEYRING="/etc/apt/keyrings/docker.asc"
mkdir -p /etc/apt/keyrings

if [[ ! -f "$KEYRING" ]]; then
    info "Downloading Docker GPG key…"
    curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" -o "$KEYRING"
    chmod a+r "$KEYRING"
    success "GPG key saved."
else
    info "Docker GPG key already present."
fi

DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
if [[ ! -f "$DOCKER_LIST" ]]; then
    info "Adding Docker APT repository…"
    ARCH=$(dpkg --print-architecture)
    echo "deb [arch=${ARCH} signed-by=${KEYRING}] \
https://download.docker.com/linux/${OS_ID} ${OS_CODENAME} stable" \
        > "$DOCKER_LIST"
    success "Docker repo added."
else
    info "Docker APT repo already configured."
fi

# =============================================================================
# 5. DOCKER ENGINE + CLI + COMPOSE
# =============================================================================
section "Installing Docker"
apt-get update -qq
apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable --now docker
success "Docker Engine v$(docker version --format '{{.Server.Version}}') installed and running."
success "Docker Compose v$(docker compose version --short) installed."

# =============================================================================
# 6. ADD CURRENT SUDO USER TO docker GROUP (optional but convenient)
# =============================================================================
section "Docker group"
REAL_USER="${SUDO_USER:-}"
if [[ -n "$REAL_USER" ]]; then
    usermod -aG docker "$REAL_USER"
    success "User '$REAL_USER' added to the docker group."
    info "Log out and back in (or run 'newgrp docker') to use Docker without sudo."
else
    info "No sudo user detected — skipping docker group assignment."
fi

# =============================================================================
# 7. LAUNCH ML ENVIRONMENT (docker compose)
# =============================================================================
section "Launching ML environment"
unzip algo.zip
cd algo/
# Look for docker-compose.yml in current directory or one level up
COMPOSE_FILE=""
if [[ -f "docker-compose.yml" || -f "docker-compose.yaml" || -f "compose.yml" ]]; then
    COMPOSE_FILE="."
elif [[ -f "../docker-compose.yml" || -f "../docker-compose.yaml" ]]; then
    COMPOSE_FILE=".."
fi

if [[ -z "$COMPOSE_FILE" ]]; then
    info "No docker-compose.yml found in current directory — skipping auto-launch."
    info "To launch manually, cd into your project folder and run the commands below."
else
    info "Found docker-compose file — starting containers…"
    cd "$COMPOSE_FILE"

    # Start containers in detached mode
    docker compose up -d
    success "Containers started."

    # Show running containers
    section "Container status"
    docker compose ps

    # Run unit tests inside the ml-env container
    section "Running unit tests"
    docker compose exec ml-env python -m pytest tests/ -v || warn "Tests failed or tests/ folder not found."

    # Run code quality checks
    section "Running quality checks"
    docker compose exec ml-env make quality || warn "Quality checks failed or Makefile not found."

    success "ML environment is up and running."
    echo ""
    info "Useful commands:"
    echo -e "  ${CYAN}docker compose ps${RESET}                               # check container status"
    echo -e "  ${CYAN}docker compose exec ml-env python main.py${RESET}       # run main.py"
    echo -e "  ${CYAN}docker compose exec ml-env bash${RESET}                 # open interactive shell"
    echo -e "  ${CYAN}docker compose exec ml-env python -m pytest tests/ -v${RESET}  # run tests"
    echo -e "  ${CYAN}docker compose exec ml-env make quality${RESET}         # run quality checks"
    echo -e "  ${CYAN}docker compose down${RESET}                             # stop containers"
    echo ""
    info "Jupyter Lab is available at → http://localhost:8888"
fi

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}All done!${RESET}"
echo -e "  Git            : $(git --version)"
echo -e "  Docker Engine  : v$(docker version --format '{{.Server.Version}}')"
echo -e "  Docker Compose : v$(docker compose version --short)"
echo ""
