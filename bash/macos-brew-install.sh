#!/usr/bin/env bash

# Batch-install the Homebrew packages used on the current Mac.
# The lists below were generated from `brew leaves` and `brew list --cask`.
#
# Usage:
#   ./macos-brew-install.sh
#   ./macos-brew-install.sh --dry-run
#   ./macos-brew-install.sh --no-casks
#   ./macos-brew-install.sh --no-formulae

set -Eeuo pipefail

DRY_RUN=0
INSTALL_FORMULAE=1
INSTALL_CASKS=1
FAILED=()

usage() {
    cat <<'EOF'
Usage: ./macos-brew-install.sh [options]

Options:
  --dry-run        Print the operations without installing anything.
  --no-formulae    Skip Homebrew formulae.
  --no-casks       Skip Homebrew casks.
  -h, --help       Show this help.

Homebrew environment variables such as HOMEBREW_BOTTLE_DOMAIN,
HOMEBREW_API_DOMAIN, and HOMEBREW_BREW_GIT_REMOTE are inherited as-is.
EOF
}

while (($#)); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --no-formulae)
            INSTALL_FORMULAE=0
            ;;
        --no-casks)
            INSTALL_CASKS=0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

log() {
    printf '[macos-brew-install] %s\n' "$*"
}

die() {
    printf '[macos-brew-install] ERROR: %s\n' "$*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || die "this script only supports macOS"

find_brew() {
    local candidate

    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi

    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

install_homebrew() {
    log "Homebrew was not found; installing it"
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl --fail --location --silent --show-error https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

# Prepare Homebrew before defining or reading the package lists.
if ! BREW="$(find_brew)"; then
    if ((DRY_RUN)); then
        BREW="brew"
        log "dry-run: Homebrew is not installed"
    else
        install_homebrew
        BREW="$(find_brew)" || die "Homebrew installation finished but brew was not found"
    fi
fi

TAPS=(
    "anomalyco/tap"
    "gromgit/fuse"
    "mhaeuser/mhaeuser"
    "momenbasel/pesty"
    "shaunsingh/sfmono-nerd-font-ligaturized"
)

FORMULAE=(
    "anomalyco/tap/opencode"
    "bun"
    "cmake"
    "coreutils"
    "dpkg"
    "dust"
    "fakeroot"
    "fastfetch"
    "fish"
    "gdal"
    "gh"
    "git-lfs"
    "gradle"
    "gromgit/fuse/ntfs-3g-mac"
    "jpeg"
    "kotlin"
    "lld"
    "mingw-w64"
    "mono"
    "nvm"
    "openjdk@17"
    "p7zip"
    "python-gdbm@3.14"
    "python-tk@3.14"
    "rpm"
    "rtk"
    "rustup"
    "sevenzip"
    "starship"
    "tokei"
    "uv"
    "wget"
    "yazi"
    "zig"
    "zsh"
)

# macfuse is installed before formulae because ntfs-3g-mac depends on it.
PREREQUISITE_CASKS=(
    "macfuse"
)

CASKS=(
    "android-commandlinetools"
    "android-platform-tools"
    "mhaeuser/mhaeuser/battery-toolkit"
    "cc-switch"
    "claude-code"
    "docker-desktop"
    "font-meslo-lg-nerd-font"
    "font-sf-mono-nerd-font-ligaturized"
    "gstreamer-runtime"
    "mounty"
    "pesty"
    "stolendata-mpv"
    "wine-stable"
    "zed"
)

print_list() {
    local title="$1"
    shift
    local item

    printf '%s:\n' "$title"
    if (($# == 0)); then
        printf '  (none)\n'
        return
    fi
    for item in "$@"; do
        printf '  %s\n' "$item"
    done
}

trust_tap() {
    local tap="$1"

    # Homebrew 6 requires explicit trust before loading non-official taps.
    # Older versions do not have `brew trust`; installation is still attempted.
    if "$BREW" trust --tap "$tap" >/dev/null 2>&1; then
        return 0
    fi

    if "$BREW" trust --help >/dev/null 2>&1; then
        log "ERROR: could not trust tap: $tap"
        return 1
    fi
}

run_or_record() {
    local kind="$1"
    local package="$2"
    shift 2

    log "installing $kind: $package"
    if "$@" "$package"; then
        return 0
    fi

    log "ERROR: failed to install $kind: $package"
    FAILED+=("$kind:$package")
    return 0
}

if ((DRY_RUN)); then
    printf '%s\n' "Dry run. Homebrew command: $BREW"
    print_list "Taps" "${TAPS[@]}"
    print_list "Prerequisite casks" "${PREREQUISITE_CASKS[@]}"
    print_list "Formulae" "${FORMULAE[@]}"
    print_list "Casks" "${CASKS[@]}"
    exit 0
fi

log "using Homebrew: $BREW"
log "updating Homebrew"
if ! "$BREW" update; then
    log "ERROR: brew update failed; continuing with the existing package indexes"
    FAILED+=("brew:update")
fi

for tap in "${TAPS[@]}"; do
    log "tapping: $tap"
    if ! "$BREW" tap "$tap"; then
        log "ERROR: failed to tap: $tap"
        FAILED+=("tap:$tap")
        continue
    fi
    if ! trust_tap "$tap"; then
        FAILED+=("trust-tap:$tap")
    fi
done

if ((INSTALL_CASKS)); then
    for cask in "${PREREQUISITE_CASKS[@]}"; do
        run_or_record "cask" "$cask" "$BREW" install --cask
    done
fi

if ((INSTALL_FORMULAE)); then
    for formula in "${FORMULAE[@]}"; do
        run_or_record "formula" "$formula" "$BREW" install --formula
    done
fi

if ((INSTALL_CASKS)); then
    for cask in "${CASKS[@]}"; do
        run_or_record "cask" "$cask" "$BREW" install --cask
    done
fi

if ((${#FAILED[@]})); then
    printf '\n'
    log "completed with failures:"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi

printf '\n'
log "all requested packages are installed"
