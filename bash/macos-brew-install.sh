#!/usr/bin/env bash

# Batch-install the Homebrew packages used on the current Mac.
# The lists below were generated from `brew leaves` and `brew list --cask`.
#
# Usage:
#   ./macos-brew-install.sh
#   ./macos-brew-install.sh --dry-run
#   ./macos-brew-install.sh --no-casks
#   ./macos-brew-install.sh --no-formulae
#   ./macos-brew-install.sh --no-shell-change
#   ./macos-brew-install.sh --no-postinstall

set -Eeuo pipefail

DRY_RUN=0
INSTALL_FORMULAE=1
INSTALL_CASKS=1
CONFIGURE_POSTINSTALL=1
SET_FISH_LOGIN_SHELL=1
FAILED=()

usage() {
    cat <<'EOF'
Usage: ./macos-brew-install.sh [options]

Options:
  --dry-run        Print the operations without installing anything.
  --no-formulae    Skip Homebrew formulae.
  --no-casks       Skip Homebrew casks.
  --no-shell-change
                   Keep the current login shell instead of switching to fish.
  --no-postinstall Skip package configuration and shell setup.
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
        --no-shell-change)
            SET_FISH_LOGIN_SHELL=0
            ;;
        --no-postinstall)
            CONFIGURE_POSTINSTALL=0
            SET_FISH_LOGIN_SHELL=0
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
    "trash"
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

record_postinstall_failure() {
    local step="$1"

    log "ERROR: post-install step failed: $step"
    FAILED+=("postinstall:$step")
}

configure_java() {
    local jdk_target jdk_link

    jdk_target="$BREW_PREFIX/opt/openjdk@17/libexec/openjdk.jdk"
    jdk_link="/Library/Java/JavaVirtualMachines/openjdk-17.jdk"

    if [[ ! -d "$jdk_target" ]]; then
        record_postinstall_failure "openjdk@17-target"
        return 0
    fi

    if [[ -L "$jdk_link" && "$(readlink "$jdk_link")" == "$jdk_target" ]]; then
        return 0
    fi

    if [[ -e "$jdk_link" && ! -L "$jdk_link" ]]; then
        log "ERROR: refusing to replace non-symlink: $jdk_link"
        FAILED+=("postinstall:openjdk@17-link")
        return 0
    fi

    log "registering OpenJDK 17 with macOS"
    if ! sudo mkdir -p /Library/Java/JavaVirtualMachines ||
        ! sudo ln -sfn "$jdk_target" "$jdk_link"; then
        record_postinstall_failure "openjdk@17-link"
        return 0
    fi

    if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
        record_postinstall_failure "openjdk@17-java-home"
    fi
}

configure_fish() {
    local fish_bin fish_config_dir fish_config temp_config

    fish_bin="$BREW_PREFIX/bin/fish"
    fish_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d"
    fish_config="$fish_config_dir/cmdtools.fish"

    if [[ ! -x "$fish_bin" ]]; then
        record_postinstall_failure "fish-binary"
        return 1
    fi

    log "writing fish configuration: $fish_config"
    if ! mkdir -p "$fish_config_dir"; then
        record_postinstall_failure "fish-config-dir"
        return 1
    fi

    if ! temp_config="$(mktemp "$fish_config_dir/.cmdtools.fish.XXXXXX")"; then
        record_postinstall_failure "fish-config-temp"
        return 1
    fi
    if ! cat >"$temp_config" <<EOF
# Managed by CMDtools/macos-brew-install.sh.

# Homebrew is not automatically added to every shell's PATH.
fish_add_path -g "$BREW_PREFIX/bin" "$BREW_PREFIX/sbin"

# Homebrew's versioned Java is keg-only.
set -gx JAVA_HOME "$BREW_PREFIX/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
if test -d "\$JAVA_HOME"
    fish_add_path -g "\$JAVA_HOME/bin"
end

# Android SDK tools and platform tools are not all linked into /opt/homebrew/bin.
set -gx ANDROID_HOME "$BREW_PREFIX/share/android-commandlinetools"
if test -d "\$ANDROID_HOME"
    fish_add_path -g "\$ANDROID_HOME/cmdline-tools/latest/bin"
    fish_add_path -g "\$ANDROID_HOME/platform-tools"
    fish_add_path -g "\$ANDROID_HOME/emulator"
end

# Keg-only tools that need explicit PATH entries.
if test -d "$BREW_PREFIX/opt/rustup/bin"
    fish_add_path -g "$BREW_PREFIX/opt/rustup/bin"
end
if test -d "$BREW_PREFIX/opt/trash/bin"
    fish_add_path -g "$BREW_PREFIX/opt/trash/bin"
end

if status is-interactive; and type -q starship
    starship init fish | source
end

# nvm is implemented in Bash. The bass plugin translates its environment
# changes for fish once bass is installed.
set -gx NVM_DIR "\$HOME/.nvm"
if type -q bass
    function nvm
        bass source "$BREW_PREFIX/opt/nvm/nvm.sh" ';' nvm \$argv
    end
end
EOF
    then
        rm -f "$temp_config"
        record_postinstall_failure "fish-config-write"
        return 1
    fi

    if ! "$fish_bin" -n "$temp_config"; then
        rm -f "$temp_config"
        record_postinstall_failure "fish-config-syntax"
        return 1
    fi

    if ! mv "$temp_config" "$fish_config"; then
        rm -f "$temp_config"
        record_postinstall_failure "fish-config-install"
        return 1
    fi
}

configure_fish_login_shell() {
    local fish_bin

    fish_bin="$BREW_PREFIX/bin/fish"
    if [[ "$SHELL" == "$fish_bin" ]]; then
        return 0
    fi

    if ! grep -Fxq "$fish_bin" /etc/shells; then
        log "adding fish to /etc/shells"
        if ! printf '%s\n' "$fish_bin" | sudo tee -a /etc/shells >/dev/null; then
            record_postinstall_failure "etc-shells"
            return 0
        fi
    fi

    log "setting fish as the login shell for $USER"
    if ! chsh -s "$fish_bin"; then
        record_postinstall_failure "login-shell"
    fi
}

print_manual_steps() {
    local fish_bin steps=()

    fish_bin="$BREW_PREFIX/bin/fish"

    if [[ -x "$fish_bin" ]] && ! "$fish_bin" -c 'type -q bass' >/dev/null 2>&1; then
        steps+=("nvm: install the fish bass plugin, then restart fish; the generated config will expose nvm")
    fi
    if command -v rustup >/dev/null 2>&1 && ! rustup show active-toolchain >/dev/null 2>&1; then
        steps+=("rustup: run 'rustup default stable' to install and select a toolchain")
    fi
    if command -v sdkmanager >/dev/null 2>&1; then
        steps+=("Android SDK: run 'sdkmanager --licenses' and install the required SDK packages")
    fi
    if ((INSTALL_CASKS)); then
        steps+=("macFUSE/Mounty: approve the system extension in Privacy & Security, then reboot if macOS requires it")
        steps+=("Docker Desktop: open /Applications/Docker.app once and complete its privileged setup")
    fi
    if ((SET_FISH_LOGIN_SHELL)); then
        :
    else
        steps+=("fish: run 'chsh -s $fish_bin' when you want it as the login shell")
    fi

    if ((${#steps[@]} == 0)); then
        return 0
    fi

    printf '\n'
    log "manual steps may still be required:"
    printf '  %s\n' "${steps[@]}"
}

configure_postinstall() {
    configure_java
    if configure_fish; then
        if ((SET_FISH_LOGIN_SHELL)); then
            configure_fish_login_shell
        fi
    fi
}

if ((DRY_RUN)); then
    printf '%s\n' "Dry run. Homebrew command: $BREW"
    print_list "Taps" "${TAPS[@]}"
    print_list "Prerequisite casks" "${PREREQUISITE_CASKS[@]}"
    print_list "Formulae" "${FORMULAE[@]}"
    print_list "Casks" "${CASKS[@]}"
    if ((CONFIGURE_POSTINSTALL)); then
        printf 'Post-install configuration: enabled\n'
        printf 'Fish login shell change: '
        ((SET_FISH_LOGIN_SHELL)) && printf 'enabled\n' || printf 'disabled\n'
    else
        printf 'Post-install configuration: disabled\n'
    fi
    exit 0
fi

log "using Homebrew: $BREW"
BREW_PREFIX="$("$BREW" --prefix)"
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

if ((CONFIGURE_POSTINSTALL)); then
    printf '\n'
    log "configuring installed packages"
    configure_postinstall
fi

print_manual_steps

if ((${#FAILED[@]})); then
    printf '\n'
    log "completed with failures:"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi

printf '\n'
log "all requested packages are installed"
