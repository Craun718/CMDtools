#!/usr/bin/env bash

# Ubuntu 22.04 LTS server initialization script.
# Unattended usage:
#   TARGET_USER=ubuntu ./ubuntu_deploy.sh            # root or passwordless sudo
#   sudo -n env TARGET_USER=ubuntu ./ubuntu_deploy.sh

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

log() {
    printf '[ubuntu-deploy] %s\n' "$*"
}

die() {
    printf '[ubuntu-deploy] ERROR: %s\n' "$*" >&2
    exit 1
}

trap 'rc=$?; printf "[ubuntu-deploy] ERROR: command failed at line %s (exit %s)\n" "$LINENO" "$rc" >&2' ERR

if [[ ! -r /etc/os-release ]]; then
    die "cannot read /etc/os-release"
fi
. /etc/os-release
if [[ ${ID:-} != "ubuntu" || ${VERSION_ID:-} != "22.04" ]]; then
    die "this script only supports Ubuntu 22.04, got ${PRETTY_NAME:-unknown}"
fi

# cloud-init runs as root, where SUDO_USER is normally absent.
TARGET_USER=${TARGET_USER:-${SUDO_USER:-${USER:-}}}
if [[ -z $TARGET_USER || $TARGET_USER == "root" ]]; then
    TARGET_USER="ubuntu"
fi
TARGET_PASSWD=$(getent passwd "$TARGET_USER") || die "target user does not exist: $TARGET_USER"
TARGET_HOME=$(printf '%s\n' "$TARGET_PASSWD" | cut -d: -f6)
[[ -n $TARGET_HOME && -d $TARGET_HOME ]] || die "target user has no usable home directory: $TARGET_USER"

run_root() {
    if [[ ${EUID} -eq 0 ]]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

run_user() {
    if [[ ${EUID} -eq 0 ]]; then
        runuser -u "$TARGET_USER" -- "$@"
    else
        sudo -n -Hu "$TARGET_USER" -- "$@"
    fi
}

apt_get() {
    run_root env \
        DEBIAN_FRONTEND=noninteractive \
        NEEDRESTART_MODE=a \
        apt-get \
        -y \
        -o Acquire::Retries=5 \
        -o DPkg::Lock::Timeout=600 \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        "$@"
}

fetch() {
    curl --fail --location --retry 5 --retry-delay 5 --connect-timeout 15 \
        "$1" -o "$2"
}

printf '==========================================\n'
printf 'Ubuntu 22.04 LTS unattended server setup\n'
printf 'Target user: %s\n' "$TARGET_USER"
printf '==========================================\n'

DPKG_ARCH=$(dpkg --print-architecture)
case "$(uname -m)" in
    x86_64) GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac

# 0. Optionally replace Ubuntu archive/security sources.
if [[ ${USE_TENCENT_APT_MIRROR:-0} == "1" ]]; then
    log "[0/13] switching APT sources to Tencent mirror"
    run_root cp -a /etc/apt/sources.list /etc/apt/sources.list.pre-tencent
    run_root sed -i -E 's@https?://([^/]+\.)*(archive|security)\.ubuntu\.com@http://mirrors.tencentyun.com@g' /etc/apt/sources.list
else
    log "[0/13] keeping configured APT sources"
fi

# 1. Update packages without service-restart or conffile prompts.
log "[1/13] updating packages"
apt_get update
apt_get upgrade

# 2. Install base tools.
log "[2/13] installing base tools"
apt_get install ca-certificates curl wget gnupg lsb-release apt-transport-https

# 3. Install Docker CE from Tencent's Docker mirror.
log "[3/13] installing Docker"
apt_get remove docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc
fetch "https://mirrors.cloud.tencent.com/docker-ce/linux/ubuntu/gpg" /tmp/docker.asc
run_root install -m 0755 -d /etc/apt/keyrings
run_root install -m 0644 /tmp/docker.asc /etc/apt/keyrings/docker.asc
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.cloud.tencent.com/docker-ce/linux/ubuntu %s stable\n' \
    "$DPKG_ARCH" "$VERSION_CODENAME" |
    run_root tee /etc/apt/sources.list.d/docker.list >/dev/null
apt_get update
apt_get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

DOCKER_REGISTRY_MIRROR=${DOCKER_REGISTRY_MIRROR-https://mirror.ccs.tencentyun.com}
if [[ -n $DOCKER_REGISTRY_MIRROR ]]; then
    log "[3.1/13] configuring Docker registry mirror"
    run_root mkdir -p /etc/docker
    printf '{\n  "registry-mirrors": ["%s"]\n}\n' "$DOCKER_REGISTRY_MIRROR" |
        run_root tee /etc/docker/daemon.json >/dev/null
    run_root systemctl daemon-reload
fi
run_root systemctl enable --now docker
if [[ -n $DOCKER_REGISTRY_MIRROR ]]; then
    run_root systemctl restart docker
fi
if ! id -nG "$TARGET_USER" | grep -qw docker; then
    run_root usermod -aG docker "$TARGET_USER"
fi

# 4. Install Java 21.
log "[4/13] installing Java 21"
apt_get install openjdk-21-jdk
JAVA_HOME="/usr/lib/jvm/java-21-openjdk-${DPKG_ARCH}"
if [[ ! -d $JAVA_HOME ]]; then
    JAVA_HOME=$(dirname "$(dirname "$(readlink -f /usr/bin/java)")")
fi

# 5. Install native compilers.
log "[5/13] installing gcc, g++, and clang"
apt_get install gcc g++ clang

# 6. Install common utilities, including Nginx.
log "[6/13] installing common utilities and Nginx"
apt_get install git htop vim net-tools unzip zip tree ffmpeg nginx
run_root systemctl enable --now nginx

# 7. Install Node.js 20 and package-manager versions that do not drift.
log "[7/13] installing Node.js 20"
fetch "https://deb.nodesource.com/setup_20.x" /tmp/nodesource-setup.sh
run_root env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a bash /tmp/nodesource-setup.sh
apt_get install nodejs
run_root corepack enable

PNPM_VERSION=${PNPM_VERSION:-10.12.1}
YARN_VERSION=${YARN_VERSION:-1.22.22}
USER_PATH="$TARGET_HOME/.cargo/bin:$TARGET_HOME/.local/bin:/usr/local/go/bin:/usr/bin:/bin"
NPM_REGISTRY=${NPM_REGISTRY:-http://mirrors.tencentyun.com/npm/}

run_user env PATH="$USER_PATH" npm config set registry "$NPM_REGISTRY"
run_user env PATH="$USER_PATH" COREPACK_NPM_REGISTRY="$NPM_REGISTRY" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack prepare "pnpm@${PNPM_VERSION}" --activate
run_user env PATH="$USER_PATH" pnpm config set registry "$NPM_REGISTRY"
run_user env PATH="$USER_PATH" COREPACK_NPM_REGISTRY="$NPM_REGISTRY" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack prepare "yarn@${YARN_VERSION}" --activate
run_user env PATH="$USER_PATH" yarn config set registry "$NPM_REGISTRY"

# 8. Install Rust for the target user.
log "[8/13] installing Rust"
RUSTUP_DIST_SERVER=${RUSTUP_DIST_SERVER:-https://rsproxy.cn}
RUSTUP_UPDATE_ROOT=${RUSTUP_UPDATE_ROOT:-https://rsproxy.cn/rustup}
fetch "https://sh.rustup.rs" /tmp/rustup-init.sh
run_user env \
    RUSTUP_DIST_SERVER="$RUSTUP_DIST_SERVER" \
    RUSTUP_UPDATE_ROOT="$RUSTUP_UPDATE_ROOT" \
    sh /tmp/rustup-init.sh -y --no-modify-path

CARGO_REGISTRY=${CARGO_REGISTRY:-sparse+https://mirrors.ustc.edu.cn/crates.io-index/}
run_user mkdir -p "$TARGET_HOME/.cargo"
printf '[source.crates-io]\nreplace-with = "ustc"\n[source.ustc]\nregistry = "%s"\n[registries.ustc]\nindex = "%s"\n' \
    "$CARGO_REGISTRY" "$CARGO_REGISTRY" |
    run_user tee "$TARGET_HOME/.cargo/config.toml" >/dev/null

# 9. Install uv and Python for the target user.
log "[9/13] installing Python with uv"
run_user env PATH="$USER_PATH" cargo install --locked uv
PYTHON_VERSION=${PYTHON_VERSION:-3.10}
PYPI_INDEX=${PYPI_INDEX:-http://mirrors.tencentyun.com/pypi/simple}
run_user env PATH="$USER_PATH" uv config set global.index-url "$PYPI_INDEX"
run_user env PATH="$USER_PATH" uv python install "$PYTHON_VERSION" --default

run_user mkdir -p "$TARGET_HOME/.config/pip"
printf '[global]\nindex-url = %s\ntrusted-host = mirrors.tencentyun.com\n' "$PYPI_INDEX" |
    run_user tee "$TARGET_HOME/.config/pip/pip.conf" >/dev/null

# 10. Install Go for all users and verify the archive before extraction.
log "[10/13] installing Go"
GO_VERSION=${GO_VERSION:-1.22.0}
GO_TARBALL="/tmp/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_SHA256=${GO_SHA256:-}
if [[ -z $GO_SHA256 && $GO_VERSION == "1.22.0" ]]; then
    case "$GO_ARCH" in
        amd64) GO_SHA256="f6c8a87aa03b92c4b0bf3d558e28ea03006eb29db78917daec5cfb6ec1046265" ;;
        arm64) GO_SHA256="6a63fef0e050146f275bf02a0896badfe77c11b6f05499bb647e7bd613a45a10" ;;
    esac
fi
[[ -n $GO_SHA256 ]] || die "GO_VERSION overrides require GO_SHA256"
fetch "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" "$GO_TARBALL"
GO_ACTUAL_SHA256=$(sha256sum "$GO_TARBALL" | awk '{print $1}')
[[ $GO_ACTUAL_SHA256 == "$GO_SHA256" ]] || die "Go archive checksum mismatch"
run_root rm -rf -- /usr/local/go
run_root tar -C /usr/local -xzf "$GO_TARBALL"
rm -f "$GO_TARBALL"

GO_PROXY=${GO_PROXY:-http://mirrors.tencentyun.com/goproxy/,direct}
run_user mkdir -p "$TARGET_HOME/go"
run_user env PATH="/usr/local/go/bin:/usr/bin:/bin" go env -w GOPROXY="$GO_PROXY"
run_user env PATH="/usr/local/go/bin:/usr/bin:/bin" go env -w GOSUMDB=off

# 11. Configure Maven for the target user.
log "[11/13] configuring Maven"
MAVEN_URL=${MAVEN_URL:-http://mirrors.tencentyun.com/nexus/repository/maven-public/}
run_user mkdir -p "$TARGET_HOME/.m2"
run_user tee "$TARGET_HOME/.m2/settings.xml" >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                              https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <mirrors>
    <mirror>
      <id>tencentyun</id>
      <name>Tencent Cloud Maven</name>
      <url>REPLACE_MAVEN_URL</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
  </mirrors>
</settings>
EOF
run_user sed -i "s|REPLACE_MAVEN_URL|$MAVEN_URL|g" "$TARGET_HOME/.m2/settings.xml"

# 12. Put user-local and tool-specific binaries on login PATH.
log "[12/13] configuring login environment"
PROFILE_FILE=/etc/profile.d/99-dev-toolchain.sh
{
    printf '# Added by ubuntu_deploy.sh\n'
    printf 'export JAVA_HOME=%q\n' "$JAVA_HOME"
    printf 'export GOPATH="$HOME/go"\n'
    printf 'export PATH="$JAVA_HOME/bin:/usr/local/go/bin:$HOME/.cargo/bin:$HOME/.local/bin:$GOPATH/bin:$PATH"\n'
} | run_root tee "$PROFILE_FILE" >/dev/null
run_root chmod 0644 "$PROFILE_FILE"

# Keep the current cloud-init/CI process usable without another login shell.
export JAVA_HOME PATH="$JAVA_HOME/bin:/usr/local/go/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.local/bin:$TARGET_HOME/go/bin:$PATH"

printf '==========================================\n'
printf 'Setup complete\n'
printf '==========================================\n'
printf 'Notes:\n'
printf '1. Docker and Nginx are enabled and running.\n'
printf '2. Docker group membership takes effect after %s logs in again.\n' "$TARGET_USER"
printf '3. Java, Go, Rust, uv, and user-local Python binaries are on login PATH.\n'
printf '4. Run python in a new login shell as %s; use uv pip inside projects.\n' "$TARGET_USER"
printf '\nVerification:\n'
printf '  sudo docker --version\n'
printf '  sudo docker compose version\n'
printf '  java -version\n'
printf '  python --version\n'
printf '  node --version\n'
printf '  npm --version\n'
printf '  gcc --version\n'
printf '  clang --version\n'
printf '  git --version\n'
printf '  nginx -v\n'
printf '  ffmpeg -version\n'
printf '  rustc --version\n'
printf '  cargo --version\n'
printf '  go version\n'
