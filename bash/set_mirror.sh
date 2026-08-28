#!/usr/bin/env bash

# Configure common package-manager mirrors for networks that are closer to
# mirrors hosted in mainland China. The script only changes installed tools.

set -Eeuo pipefail

readonly SCRIPT_NAME=${0##*/}
readonly ALL_MANAGERS=(
    maven pnpm npm uv pip cargo nvm apt conda yum flatpak gradle tlmgr
)

MODE=set
DRY_RUN=0
REFRESH_APT=0
SELECTED_MANAGERS=()

# Default mirrors can be overridden in the environment.
MIRROR_MAVEN=${MIRROR_MAVEN:-https://maven.aliyun.com/repository/public}
MIRROR_NPM=${MIRROR_NPM:-https://mirrors.huaweicloud.com/repository/npm/}
MIRROR_PYPI=${MIRROR_PYPI:-https://pypi.tuna.tsinghua.edu.cn/simple}
MIRROR_CRATES=${MIRROR_CRATES:-sparse+https://mirrors.ustc.edu.cn/crates.io-index/}
MIRROR_NVM_NODE=${MIRROR_NVM_NODE:-https://npmmirror.com/mirrors/node/}
MIRROR_APT_HOST=${MIRROR_APT_HOST:-mirrors.tuna.tsinghua.edu.cn}
MIRROR_CONDA=${MIRROR_CONDA:-https://mirrors.tuna.tsinghua.edu.cn/anaconda}
MIRROR_FLATHUB=${MIRROR_FLATHUB:-https://mirror.sjtu.edu.cn/flathub/}
MIRROR_GRADLE=${MIRROR_GRADLE:-https://maven.aliyun.com/repository/public}
MIRROR_GRADLE_PLUGIN=${MIRROR_GRADLE_PLUGIN:-https://maven.aliyun.com/repository/gradle-plugin}
MIRROR_GRADLE_GOOGLE=${MIRROR_GRADLE_GOOGLE:-https://maven.aliyun.com/repository/google}
MIRROR_TLMGR=${MIRROR_TLMGR:-https://mirrors.tuna.tsinghua.edu.cn/CTAN/systems/texlive/tlnet}
MIRROR_FLATHUB_UPSTREAM=${MIRROR_FLATHUB_UPSTREAM:-https://dl.flathub.org/repo/}
MIRROR_TLMGR_UPSTREAM=${MIRROR_TLMGR_UPSTREAM:-https://mirror.ctan.org/systems/texlive/tlnet}

TARGET_USER=${SUDO_USER:-${USER:-$(id -un)}}
TARGET_PASSWD=$(getent passwd "$TARGET_USER") || {
    printf '%s: cannot determine target user\n' "$SCRIPT_NAME" >&2
    exit 1
}
TARGET_GROUP=$(id -gn "$TARGET_USER")
REAL_HOME=$(printf '%s\n' "$TARGET_PASSWD" | cut -d: -f6)
TARGET_SHELL=$(printf '%s\n' "$TARGET_PASSWD" | cut -d: -f7)
if [[ -z $REAL_HOME || ! -d $REAL_HOME ]]; then
    printf '%s: target user has no usable home directory: %s\n' \
        "$SCRIPT_NAME" "$TARGET_USER" >&2
    exit 1
fi

REAL_XDG_CONFIG_HOME=$REAL_HOME/.config
REAL_XDG_STATE_HOME=$REAL_HOME/.local/state
STATE_DIR=${SET_MIRROR_STATE_DIR:-$REAL_XDG_STATE_HOME/set_mirror}
BASELINE_DIR=$STATE_DIR/baseline
USER_PATH=$REAL_HOME/.local/bin:$REAL_HOME/.cargo/bin:$REAL_HOME/miniconda3/bin:$REAL_HOME/anaconda3/bin:/opt/conda/bin:$PATH

color_output=0
if [[ -t 2 ]]; then
    color_output=1
fi

info() {
    if (( color_output )); then
        printf '\033[36m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"
    else
        printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
    fi
}

warn() {
    if (( color_output )); then
        printf '\033[33m[%s] WARNING:\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2
    else
        printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2
    fi
}

error() {
    if (( color_output )); then
        printf '\033[31m[%s] ERROR:\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2
    else
        printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
    fi
}

usage() {
    cat <<'EOF'
Usage:
  set_mirror.sh [options] [manager ...]

Managers:
  maven pnpm npm uv pip cargo nvm apt conda yum flatpak gradle tlmgr
  "flatpack" is accepted as an alias for flatpak.

If no manager is given, all detected managers are configured.

Options:
  -n, --dry-run   Show actions without changing files or running commands.
  -r, --restore   Restore the first backup taken by this script.
      --refresh   Run apt-get update after configuring apt.
  -l, --list      List supported managers and whether they were detected.
  -h, --help      Show this help.

Configuration and backups:
  User files are written for the invoking user. When the script is run with
  sudo, SUDO_USER's home is used. System sources for apt, yum and flatpak use
  sudo when required. The first modification of each manager stores a baseline
  under ~/.local/state/set_mirror/baseline.

Common mirror overrides:
  MIRROR_MAVEN, MIRROR_NPM, MIRROR_PYPI, MIRROR_CRATES,
  MIRROR_NVM_NODE, MIRROR_APT_HOST, MIRROR_CONDA, MIRROR_FLATHUB,
  MIRROR_GRADLE, MIRROR_GRADLE_PLUGIN, MIRROR_GRADLE_GOOGLE, MIRROR_TLMGR
EOF
}

run_root() {
    if (( EUID == 0 )); then
        "$@"
    else
        sudo "$@"
    fi
}

run_as_target() {
    if (( EUID == 0 )); then
        runuser -u "$TARGET_USER" -- \
            env HOME="$REAL_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
            XDG_CONFIG_HOME="$REAL_XDG_CONFIG_HOME" \
            XDG_STATE_HOME="$REAL_XDG_STATE_HOME" \
            PATH="$USER_PATH" "$@"
    else
        env HOME="$REAL_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
            XDG_CONFIG_HOME="$REAL_XDG_CONFIG_HOME" \
            XDG_STATE_HOME="$REAL_XDG_STATE_HOME" \
            PATH="$USER_PATH" "$@"
    fi
}

find_user_bin() {
    local name=$1 binary
    binary=$(PATH=$USER_PATH command -v "$name" 2>/dev/null || true)
    [[ -n $binary ]] && printf '%s\n' "$binary"
}

system_bin() {
    command -v "$1" >/dev/null 2>&1
}

manager_available() {
    case $1 in
        maven) [[ -n $(find_user_bin mvn) ]] ;;
        pnpm) [[ -n $(find_user_bin pnpm) ]] ;;
        npm) [[ -n $(find_user_bin npm) ]] ;;
        uv) [[ -n $(find_user_bin uv) ]] ;;
        pip) [[ -n $(find_user_bin pip || find_user_bin pip3) ]] ;;
        cargo) [[ -n $(find_user_bin cargo) ]] ;;
        nvm)
            [[ -s ${NVM_DIR:-$REAL_HOME/.nvm}/nvm.sh ||
                -s $REAL_XDG_CONFIG_HOME/nvm/nvm.sh ]]
            ;;
        apt) system_bin apt-get ;;
        conda) [[ -n $(find_user_bin conda) ]] ;;
        yum) system_bin dnf || system_bin yum ;;
        flatpak) system_bin flatpak ;;
        gradle) [[ -n $(find_user_bin gradle) ]] ;;
        tlmgr) [[ -n $(find_user_bin tlmgr) ]] ;;
        *) return 1 ;;
    esac
}

list_managers() {
    local manager available
    printf '%-10s %s\n' MANAGER DETECTED
    for manager in "${ALL_MANAGERS[@]}"; do
        if manager_available "$manager"; then
            available=yes
        else
            available=no
        fi
        printf '%-10s %s\n' "$manager" "$available"
    done
}

ensure_state_dir() {
    if (( EUID == 0 )); then
        run_root install -d -o "$TARGET_USER" -g "$TARGET_GROUP" \
            "$STATE_DIR" "$BASELINE_DIR"
    else
        mkdir -p "$STATE_DIR" "$BASELINE_DIR"
    fi
}

encoded_path() {
    local path=$1
    printf '%s\n' "${path//\//%2F}"
}

backup_file() {
    local manager=$1 path=$2 manifest backup_path
    (( DRY_RUN )) && return 0

    manifest=$BASELINE_DIR/$manager.manifest
    ensure_state_dir
    if [[ -f $manifest ]] && grep -Fq "$(printf '%s\t' "$path")" "$manifest"; then
        return 0
    fi

    backup_path=$BASELINE_DIR/$manager/$(encoded_path "$path")
    if (( EUID == 0 )); then
        run_as_target mkdir -p "$(dirname "$backup_path")"
    else
        mkdir -p "$(dirname "$backup_path")"
    fi
    if [[ -e $path ]]; then
        if [[ -r $path ]]; then
            cp -a -- "$path" "$backup_path"
        else
            run_root cp -a -- "$path" "$backup_path"
        fi
        printf '%s\t1\n' "$path" >>"$manifest"
    else
        printf '%s\t0\n' "$path" >>"$manifest"
    fi
    if (( EUID == 0 )); then
        chown "$TARGET_USER:$TARGET_GROUP" "$manifest"
    fi
}

path_needs_root() {
    local path=$1
    [[ $path == /etc/* || $path == /var/* || $path == /usr/* || $path == /opt/* ]]
}

restore_backup_files() {
    local manager=$1 manifest=$BASELINE_DIR/$manager.manifest path existed backup_path
    [[ -f $manifest ]] || return 0

    while IFS=$'\t' read -r path existed || [[ -n ${path:-} ]]; do
        backup_path=$BASELINE_DIR/$manager/$(encoded_path "$path")
        if [[ $existed == 1 ]]; then
            if path_needs_root "$path" || (( EUID == 0 )); then
                run_root cp -a -- "$backup_path" "$path"
            else
                cp -a -- "$backup_path" "$path"
            fi
        elif [[ -e $path ]]; then
            if path_needs_root "$path" || (( EUID == 0 )); then
                run_root rm -f -- "$path"
            else
                rm -f -- "$path"
            fi
        fi
    done <"$manifest"
}

target_mode() {
    local path=$1 default_mode=$2
    if [[ -e $path ]]; then
        stat -c '%a' "$path"
    else
        printf '%s\n' "$default_mode"
    fi
}

install_user_temp() {
    local path=$1 mode=$2 temporary=$3 parent
    parent=$(dirname "$path")
    if (( EUID == 0 )); then
        run_root install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$parent"
        run_root install -o "$TARGET_USER" -g "$TARGET_GROUP" -m "$mode" \
            "$temporary" "$path"
    else
        mkdir -p "$parent"
        install -m "$mode" "$temporary" "$path"
    fi
    rm -f "$temporary"
}

write_user_text() {
    local path=$1 mode=$2 text=$3 temporary
    (( DRY_RUN )) && return 0
    temporary=$(mktemp)
    printf '%s' "$text" >"$temporary"
    install_user_temp "$path" "$mode" "$temporary"
}

set_plain_key() {
    local path=$1 key=$2 value=$3 temporary mode
    (( DRY_RUN )) && return 0

    mode=$(target_mode "$path" 644)
    temporary=$(mktemp)
    if [[ -f $path ]]; then
        sed -E "s@^[[:space:]]*${key}[[:space:]]*=.*\$@${key}=${value}@" \
            "$path" >"$temporary"
        if ! grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$temporary"; then
            printf '%s=%s\n' "$key" "$value" >>"$temporary"
        fi
    else
        printf '%s=%s\n' "$key" "$value" >"$temporary"
    fi
    install_user_temp "$path" "$mode" "$temporary"
}

set_ini_section_key() {
    local path=$1 section=$2 key=$3 value=$4 temporary mode input
    (( DRY_RUN )) && return 0

    mode=$(target_mode "$path" 644)
    temporary=$(mktemp)
    [[ -f $path ]] && input=$path || input=/dev/null
    awk -v section="$section" -v key="$key" -v value="$value" '
        function is_header(line, s) {
            return line ~ ("^[[:space:]]*\\[" s "[[:space:]]*\\][[:space:]]*$")
        }
        function is_key(line, k) {
            return line ~ ("^[[:space:]]*" k "[[:space:]]*=")
        }
        BEGIN { in_section = 0; has_section = 0; written = 0 }
        {
            if ($0 ~ /^[[:space:]]*\[/) {
                if (in_section && !written) {
                    print key "=" value
                    written = 1
                }
                in_section = is_header($0, section)
                if (in_section) {
                    has_section = 1
                }
                print
                next
            }
            if (in_section && is_key($0, key)) {
                if (!written) {
                    print key "=" value
                    written = 1
                }
                next
            }
            print
        }
        END {
            if (!has_section) {
                print ""
                print "[" section "]"
                print key "=" value
            } else if (!written) {
                print key "=" value
            }
        }
    ' "$input" >"$temporary" 2>/dev/null || : >"$temporary"
    install_user_temp "$path" "$mode" "$temporary"
}

rewrite_toml_tables() {
    local path=$1 tables=$2 block=$3 temporary mode input
    (( DRY_RUN )) && return 0

    mode=$(target_mode "$path" 644)
    temporary=$(mktemp)
    [[ -f $path ]] && input=$path || input=/dev/null
    awk -v tables="$tables" -v block="$block" '
        BEGIN {
            count = split(tables, wanted, " ")
            for (i = 1; i <= count; i++) {
                wanted_table["[" wanted[i] "]"] = 1
                wanted_table["[[" wanted[i] "]]"] = 1
            }
        }
        {
            header = $0
            gsub(/^[[:space:]]+/, "", header)
            gsub(/[[:space:]]+$/, "", header)
            gsub(/[[:space:]]+/, "", header)
            if ($0 ~ /^[[:space:]]*\[/) {
                skip = header in wanted_table
                if (!skip) {
                    print
                }
                next
            }
            if (!skip) {
                print
            }
        }
        END {
            printf "%s", block
        }
    ' "$input" >"$temporary" 2>/dev/null || : >"$temporary"
    install_user_temp "$path" "$mode" "$temporary"
}

update_rc_block() {
    local path=$1 text=$2 temporary mode input
    (( DRY_RUN )) && return 0

    mode=$(target_mode "$path" 644)
    temporary=$(mktemp)
    [[ -f $path ]] && input=$path || input=/dev/null
    awk -v block="$text" '
        BEGIN {
            begin = "# >>> set_mirror >>>"
            end = "# <<< set_mirror <<<"
            skipping = 0
            seen = 0
        }
        {
            if ($0 == begin) {
                print begin
                printf "%s", block
                print end
                skipping = 1
                seen = 1
                next
            }
            if (skipping && $0 == end) {
                skipping = 0
                next
            }
            if (!skipping) {
                print
            }
        }
        END {
            if (skipping) {
                print end
            }
            if (!seen) {
                print ""
                print begin
                printf "%s", block
                print end
            }
        }
    ' "$input" >"$temporary" 2>/dev/null || : >"$temporary"
    install_user_temp "$path" "$mode" "$temporary"
}

configure_npm() {
    local path=$REAL_HOME/.npmrc
    backup_file npm "$path"
    info "npm: registry -> $MIRROR_NPM"
    set_plain_key "$path" registry "$MIRROR_NPM"
}

configure_pnpm() {
    local path=$REAL_XDG_CONFIG_HOME/pnpm/rc
    backup_file pnpm "$path"
    info "pnpm: registry -> $MIRROR_NPM"
    set_plain_key "$path" registry "$MIRROR_NPM"
}

configure_pip() {
    local path=$REAL_XDG_CONFIG_HOME/pip/pip.conf
    backup_file pip "$path"
    info "pip: index-url -> $MIRROR_PYPI"
    set_ini_section_key "$path" global index-url "$MIRROR_PYPI"
}

configure_uv() {
    local path=$REAL_XDG_CONFIG_HOME/uv/uv.toml
    backup_file uv "$path"
    info "uv: default index -> $MIRROR_PYPI"
    rewrite_toml_tables "$path" index \
"[[index]]
url = \"$MIRROR_PYPI\"
default = true
"
}

configure_cargo() {
    local path=$REAL_HOME/.cargo/config.toml
    backup_file cargo "$path"
    info "cargo: crates.io index -> $MIRROR_CRATES"
    rewrite_toml_tables "$path" "source.crates-io source.set-mirror" \
"[source.crates-io]
replace-with = \"set-mirror\"

[source.set-mirror]
registry = \"$MIRROR_CRATES\"
"
}

configure_nvm() {
    local block fish_path
    block="export NVM_NODE_DOWNLOAD_MIRROR=\"$MIRROR_NVM_NODE\"
"
    info "nvm: node download mirror -> $MIRROR_NVM_NODE"
    backup_file nvm "$REAL_HOME/.bashrc"
    update_rc_block "$REAL_HOME/.bashrc" "$block"
    if [[ -s $REAL_HOME/.zshrc ]]; then
        backup_file nvm "$REAL_HOME/.zshrc"
        update_rc_block "$REAL_HOME/.zshrc" "$block"
    fi

    fish_path=$REAL_XDG_CONFIG_HOME/fish/conf.d/set-mirror.fish
    if [[ $TARGET_SHELL == */fish || -d $REAL_XDG_CONFIG_HOME/fish ]]; then
        backup_file nvm "$fish_path"
        write_user_text "$fish_path" 644 \
"set -gx NVM_NODE_DOWNLOAD_MIRROR \"$MIRROR_NVM_NODE\"
"
    fi
}

configure_maven() {
    local path=$REAL_HOME/.m2/settings.xml
    backup_file maven "$path"
    info "maven: central -> $MIRROR_MAVEN"
    (( DRY_RUN )) && return 0

    run_as_target mkdir -p "$(dirname "$path")"
    run_as_target python3 - "$path" "$MIRROR_MAVEN" <<'PY'
from pathlib import Path
from xml.dom import minidom

path = Path(__import__("sys").argv[1])
mirror_url = __import__("sys").argv[2]

if path.exists():
    document = minidom.parse(str(path))
else:
    document = minidom.parseString(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"/>'
    )

root = document.documentElement
namespace = root.namespaceURI

def new_element(name):
    if namespace:
        return document.createElementNS(namespace, name)
    return document.createElement(name)

def child_by_name(node, name):
    return next(
        (item for item in node.childNodes
         if item.nodeType == item.ELEMENT_NODE and item.localName == name),
        None,
    )

def text_of(node):
    return "".join(
        item.data for item in node.childNodes if item.nodeType == item.TEXT_NODE
    ).strip()

mirrors = child_by_name(root, "mirrors")
if mirrors is None:
    mirrors = new_element("mirrors")
    root.appendChild(mirrors)

for mirror in list(mirrors.childNodes):
    if mirror.nodeType != mirror.ELEMENT_NODE or mirror.localName != "mirror":
        continue
    mirror_id = child_by_name(mirror, "id")
    if mirror_id is not None and text_of(mirror_id) == "set-mirror":
        mirrors.removeChild(mirror)

mirror = new_element("mirror")
for name, value in (
    ("id", "set-mirror"),
    ("name", "Mainland China Maven mirror"),
    ("url", mirror_url),
    ("mirrorOf", "central"),
):
    node = new_element(name)
    node.appendChild(document.createTextNode(value))
    mirror.appendChild(node)
mirrors.appendChild(mirror)

with path.open("w", encoding="utf-8") as output:
    document.writexml(output, indent="  ", addindent="  ", newl="\n", encoding="utf-8")
PY
}

configure_gradle() {
    local path=$REAL_HOME/.gradle/init.d/set-mirror.init.gradle
    backup_file gradle "$path"
    info "gradle: Maven repositories -> $MIRROR_GRADLE"
    write_user_text "$path" 644 \
"def addMirrorRepositories(repositories) {
    repositories.maven {
        name = 'Aliyun Maven mirror'
        url = uri('$MIRROR_GRADLE')
    }
    repositories.mavenCentral()
    repositories.gradlePluginPortal()
    repositories.maven {
        name = 'Aliyun Google mirror'
        url = uri('$MIRROR_GRADLE_GOOGLE')
    }
}

settingsEvaluated { settings ->
    settings.pluginManagement.repositories.maven {
        name = 'Aliyun Gradle plugin mirror'
        url = uri('$MIRROR_GRADLE_PLUGIN')
    }
    addMirrorRepositories(settings.pluginManagement.repositories)
}

allprojects {
    repositories {
        addMirrorRepositories(repositories)
    }
    buildscript {
        repositories {
            addMirrorRepositories(repositories)
        }
    }
}
"
}

configure_conda() {
    local conda_bin path=$REAL_HOME/.condarc
    conda_bin=$(find_user_bin conda || true)
    [[ -n $conda_bin ]] || return 1

    backup_file conda "$path"
    info "conda: channel alias -> $MIRROR_CONDA"
    if (( DRY_RUN )); then
        return 0
    fi

    run_as_target "$conda_bin" config --add channels \
        "$MIRROR_CONDA/cloud/conda-forge/" || return 1
    run_as_target "$conda_bin" config --add channels defaults || return 1
    run_as_target "$conda_bin" config --remove-key default_channels \
        >/dev/null 2>&1 || true
    while read -r channel; do
        run_as_target "$conda_bin" config --add default_channels "$channel" || return 1
    done <<EOF
$MIRROR_CONDA/pkgs/msys2/
$MIRROR_CONDA/pkgs/r/
$MIRROR_CONDA/pkgs/main/
EOF
    run_as_target "$conda_bin" config --set channel_alias "$MIRROR_CONDA" || return 1
}

apt_source_files() {
    local file
    [[ -e /etc/apt/sources.list ]] && printf '%s\n' /etc/apt/sources.list
    for file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -e $file ]] && printf '%s\n' "$file"
    done
}

configure_apt() {
    local file files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(apt_source_files)
    [[ ${#files[@]} -gt 0 ]] || {
        warn "no apt source files were found"
        return 0
    }

    for file in "${files[@]}"; do
        backup_file apt "$file"
    done
    info "apt: official Ubuntu/Debian hosts -> $MIRROR_APT_HOST"
    (( DRY_RUN )) && return 0

    run_root sed -i -E \
        -e "s@https?://([^/]+[.])*(archive|security)[.]ubuntu[.]com@https://$MIRROR_APT_HOST@g" \
        -e "s@https?://([^/]+[.])*ports[.]ubuntu[.]com/ubuntu-ports@https://$MIRROR_APT_HOST/ubuntu-ports@g" \
        -e "s@https?://deb[.]debian[.]org@https://$MIRROR_APT_HOST@g" \
        -e "s@https?://security[.]debian[.]org@https://$MIRROR_APT_HOST@g" \
        -- "${files[@]}"

    if (( REFRESH_APT )); then
        run_root env DEBIAN_FRONTEND=noninteractive apt-get update || return 1
    fi
}

yum_repo_files() {
    local file
    for file in /etc/yum.repos.d/*.repo; do
        [[ -e $file ]] && printf '%s\n' "$file"
    done
}

configure_yum() {
    local file files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(yum_repo_files)
    [[ ${#files[@]} -gt 0 ]] || return 0

    for file in "${files[@]}"; do
        backup_file yum "$file"
    done
    info "yum/dnf: common CentOS/Fedora/Rocky/Alma URLs -> Aliyun/OpenEuler mirrors"
    (( DRY_RUN )) && return 0

    run_root perl -pi -e '
        my $official = qr/(?:centos|stream[.]centos|fedoraproject|rockylinux|almalinux|openeuler)/i;
        if (/^(?:metalink|mirrorlist)=/ && /$official/) {
            s/^/#/;
        }
        if (/^#baseurl=/ && /$official/) {
            s/^#//;
        }
        s{https?://mirror[.]stream[.]centos[.]org}{https://mirrors.aliyun.com/centos-stream}g;
        s{https?://vault[.]centos[.]org/centos}{https://mirrors.aliyun.com/centos-vault}g;
        s{https?://vault[.]centos[.]org}{https://mirrors.aliyun.com/centos-vault}g;
        s{https?://mirror[.]centos[.]org/centos}{https://mirrors.aliyun.com/centos}g;
        s{https?://mirror[.]centos[.]org}{https://mirrors.aliyun.com/centos}g;
        s{https?://download[.]fedoraproject[.]org/pub/fedora/linux}{https://mirrors.aliyun.com/fedora/linux}g;
        s{https?://dl[.]fedoraproject[.]org/pub/fedora/linux}{https://mirrors.aliyun.com/fedora/linux}g;
        s{https?://download[.]rockylinux[.]org/pub/rocky}{https://mirrors.aliyun.com/rockylinux}g;
        s{https?://repo[.]almalinux[.]org/almalinux}{https://mirrors.aliyun.com/almalinux}g;
        s{https?://repo[.]openeuler[.]org}{https://mirrors.tuna.tsinghua.edu.cn/openeuler}g;
    ' "${files[@]}"

    if run_root grep -HEn '^(metalink|mirrorlist)=.*(centos|fedoraproject|rockylinux|almalinux|openeuler)' \
        -- "${files[@]}" 2>/dev/null; then
        warn "some official yum metalinks remain; inspect the lines above or configure those repos manually"
    fi
    return 0
}

flatpak_snapshot_path() {
    printf '%s/flatpak-%s.json\n' "$BASELINE_DIR" "$1"
}

save_flatpak_snapshot() {
    local scope=$1 binary=$2 snapshot temporary
    (( DRY_RUN )) && return 0
    snapshot=$(flatpak_snapshot_path "$scope")
    [[ -e $snapshot ]] && return 0

    ensure_state_dir
    temporary=$(mktemp)
    if [[ $scope == user ]]; then
        run_as_target "$binary" remotes --user --json --columns=name,url >"$temporary" || {
            rm -f "$temporary"
            return 1
        }
    else
        run_root "$binary" remotes --system --json --columns=name,url >"$temporary" || {
            rm -f "$temporary"
            return 1
        }
    fi
    if (( EUID == 0 )); then
        chown "$TARGET_USER:$TARGET_GROUP" "$temporary"
    fi
    mv "$temporary" "$snapshot"
}

configure_flatpak() {
    local binary
    binary=$(command -v flatpak)
    save_flatpak_snapshot user "$binary" || return 1
    save_flatpak_snapshot system "$binary" || return 1

    info "flatpak: flathub -> $MIRROR_FLATHUB"
    (( DRY_RUN )) && return 0
    run_as_target "$binary" --user remote-modify --if-exists --url \
        "$MIRROR_FLATHUB" flathub || return 1
    run_root "$binary" --system remote-modify --if-exists --url \
        "$MIRROR_FLATHUB" flathub
}

restore_flatpak() {
    local binary scope snapshot name url
    restore_backup_files flatpak
    binary=$(command -v flatpak)

    for scope in user system; do
        snapshot=$(flatpak_snapshot_path "$scope")
        if [[ ! -f $snapshot ]]; then
            info "flatpak: no $scope snapshot; using upstream flathub URL"
            if [[ $scope == user ]]; then
                run_as_target "$binary" --user remote-modify --if-exists --url \
                    "$MIRROR_FLATHUB_UPSTREAM" flathub || return 1
            else
                run_root "$binary" --system remote-modify --if-exists --url \
                    "$MIRROR_FLATHUB_UPSTREAM" flathub || return 1
            fi
            continue
        fi

        while IFS=$'\t' read -r name url; do
            [[ -n $name && -n $url ]] || continue
            info "flatpak: $scope remote $name -> $url"
            if [[ $scope == user ]]; then
                run_as_target "$binary" --user remote-modify --if-exists \
                    --url "$url" "$name" || return 1
            else
                run_root "$binary" --system remote-modify --if-exists \
                    --url "$url" "$name" || return 1
            fi
        done < <(python3 - "$snapshot" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    for remote in json.load(stream):
        name = remote.get("name")
        url = remote.get("url")
        if name and url:
            print(f"{name}\t{url}")
PY
        )
    done
}

configure_tlmgr() {
    local binary
    binary=$(find_user_bin tlmgr || true)
    [[ -n $binary ]] || return 1
    info "tlmgr: repository -> $MIRROR_TLMGR"
    (( DRY_RUN )) && return 0

    if [[ $binary == "$REAL_HOME"/* ]]; then
        run_as_target "$binary" option repository "$MIRROR_TLMGR"
    else
        run_root "$binary" option repository "$MIRROR_TLMGR"
    fi
}

restore_tlmgr() {
    local binary
    binary=$(find_user_bin tlmgr || true)
    [[ -n $binary ]] || return 0
    info "tlmgr: repository -> $MIRROR_TLMGR_UPSTREAM"
    (( DRY_RUN )) && return 0

    if [[ $binary == "$REAL_HOME"/* ]]; then
        run_as_target "$binary" option repository "$MIRROR_TLMGR_UPSTREAM"
    else
        run_root "$binary" option repository "$MIRROR_TLMGR_UPSTREAM"
    fi
}

restore_maven() { restore_backup_files maven; }
restore_gradle() { restore_backup_files gradle; }
restore_npm() { restore_backup_files npm; }
restore_pnpm() { restore_backup_files pnpm; }
restore_uv() { restore_backup_files uv; }
restore_pip() { restore_backup_files pip; }
restore_cargo() { restore_backup_files cargo; }
restore_nvm() { restore_backup_files nvm; }
restore_apt() { restore_backup_files apt; }
restore_conda() { restore_backup_files conda; }
restore_yum() { restore_backup_files yum; }

run_manager_action() {
    local manager=$1 action=$2 function_name
    if [[ $action == set ]]; then
        function_name=configure_$manager
    else
        function_name=restore_$manager
    fi
    if declare -f "$function_name" >/dev/null; then
        "$function_name"
    elif [[ $action == restore ]]; then
        restore_backup_files "$manager"
    else
        return 1
    fi
}

parse_arguments() {
    local argument
    while (( $# > 0 )); do
        argument=$1
        shift
        case $argument in
            -n|--dry-run) DRY_RUN=1 ;;
            -r|--restore) MODE=restore ;;
            --refresh) REFRESH_APT=1 ;;
            -l|--list)
                list_managers
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --) break ;;
            -*) usage >&2; return 1 ;;
            flatpack) SELECTED_MANAGERS+=(flatpak) ;;
            *)
                if ! printf '%s\n' "${ALL_MANAGERS[@]}" | grep -Fxq "$argument"; then
                    error "unsupported manager: $argument"
                    return 1
                fi
                SELECTED_MANAGERS+=("$argument")
                ;;
        esac
    done

    if (( $# > 0 )); then
        for argument in "$@"; do
            if ! printf '%s\n' "${ALL_MANAGERS[@]}" | grep -Fxq "$argument"; then
                error "unsupported manager: $argument"
                return 1
            fi
            SELECTED_MANAGERS+=("$argument")
        done
    fi

    if (( ${#SELECTED_MANAGERS[@]} == 0 )); then
        SELECTED_MANAGERS=("${ALL_MANAGERS[@]}")
    fi
}

main() {
    local manager failed=0 explicit=0 action
    parse_arguments "$@" || exit 2
    (( ${#SELECTED_MANAGERS[@]} != ${#ALL_MANAGERS[@]} )) && explicit=1
    [[ $MODE == restore ]] && action=restore || action=set

    for manager in "${SELECTED_MANAGERS[@]}"; do
        if ! manager_available "$manager"; then
            if (( explicit )); then
                warn "$manager is not installed or not in PATH; skipping"
                failed=1
            else
                info "$manager: not detected; skipping"
            fi
            continue
        fi

        info "$action $manager"
        if run_manager_action "$manager" "$action"; then
            info "$manager: done"
        else
            error "$manager: failed"
            failed=1
        fi
    done

    if (( DRY_RUN == 0 )) && [[ $MODE == set ]]; then
        info "new shells may be required for nvm and other environment-based tools"
    fi
    exit "$failed"
}

main "$@"
