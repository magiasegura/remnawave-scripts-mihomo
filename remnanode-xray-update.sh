#!/bin/bash
# Version: 1.0.0-jm.3
set -e
# RemnaNode Xray-core Updater
# Created by DigneZzZ

echo -e "\e[1m\e[33mOur community: https://gig.ovh\n\e[0m"
sleep 2s

echo -e "\e[1m\e[33mThis script installs/updates Xray-core for RemnaNode\n\e[0m"
sleep 1


# Color scheme
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'

# Colored output function

colorized_echo() {
    local color=$1
    local text=$2
    local style=${3:-0}

    case $color in
        "red") printf "\e[${style};91m${text}\e[0m\n" ;;
        "green") printf "\e[${style};92m${text}\e[0m\n" ;;
        "yellow") printf "\e[${style};93m${text}\e[0m\n" ;;
        "blue") printf "\e[${style};94m${text}\e[0m\n" ;;
        "magenta") printf "\e[${style};95m${text}\e[0m\n" ;;
        "cyan") printf "\e[${style};96m${text}\e[0m\n" ;;
        *) echo "${text}" ;;
    esac
}

# System architecture detection
identify_the_operating_system_and_architecture() {
    if [[ "$(uname)" == 'Linux' ]]; then
        case "$(uname -m)" in
            'i386' | 'i686') ARCH='32' ;;
            'amd64' | 'x86_64') ARCH='64' ;;
            'armv5tel') ARCH='arm32-v5' ;;
            'armv6l') ARCH='arm32-v6'; grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5' ;;
            'armv7' | 'armv7l') ARCH='arm32-v7a'; grep Features /proc/cpuinfo | grep -qw 'vfp' || ARCH='arm32-v5' ;;
            'armv8' | 'aarch64') ARCH='arm64-v8a' ;;
            'mips') ARCH='mips32' ;;
            'mipsle') ARCH='mips32le' ;;
            'mips64') ARCH='mips64'; lscpu | grep -q "Little Endian" && ARCH='mips64le' ;;
            'mips64le') ARCH='mips64le' ;;
            'ppc64') ARCH='ppc64' ;;
            'ppc64le') ARCH='ppc64le' ;;
            'riscv64') ARCH='riscv64' ;;
            's390x') ARCH='s390x' ;;
            *) echo "error: The architecture is not supported."; exit 1 ;;
        esac
    else
        echo "error: This operating system is not supported."
        exit 1
    fi
}

# Find RemnaNode directory
find_remnanode_directory() {
    local possible_paths=(
        "/opt/remnanode"
        "/opt/remna"
        "/var/lib/remnanode"
        "/var/lib/remna"
    )
    
    colorized_echo blue "Searching for RemnaNode directory..."
    
    for path in "${possible_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/docker-compose.yml" ]; then
            REMNANODE_DIR="$path"
            colorized_echo green "Found RemnaNode directory: $REMNANODE_DIR"
            return 0
        fi
    done
    
    local found_dirs=$(find / -type d -name "*remna*" -exec test -f "{}/docker-compose.yml" \; -print 2>/dev/null)
    
    if [ -n "$found_dirs" ]; then
        local first_dir=$(echo "$found_dirs" | head -1)
        REMNANODE_DIR="$first_dir"
        colorized_echo green "Found RemnaNode directory: $REMNANODE_DIR"
        return 0
    fi
    
    colorized_echo red "RemnaNode directory not found!"
    colorized_echo yellow "Make sure RemnaNode is installed and contains docker-compose.yml file"
    exit 1
}

# Get current Xray version
get_current_xray_core_version() {
    local xray_file="/var/lib/remnanode/xray"
    if [ -f "$xray_file" ]; then
        if version_output=$("$xray_file" -version 2>/dev/null); then
            version=$(echo "$version_output" | head -n1 | awk '{print $2}')
            echo "$version"
            return
        fi
    fi
    echo "Not installed"
}

# BEGIN XRAY SOURCE
# Embedded in both entrypoints so curl | bash installs remain self-contained.
xray_load_source() {
    XRAY_REPO=XTLS/Xray-core
    if [ -f "$DATA_DIR/xray-source" ]; then
        IFS= read -r XRAY_REPO < "$DATA_DIR/xray-source" || return 1
    fi
    case "$XRAY_REPO" in
        XTLS/Xray-core|Jolymmiles/Xray-core) ;;
        *) echo "Invalid Xray source in $DATA_DIR/xray-source" >&2; return 1 ;;
    esac
}

xray_choose_source() {
    local choice
    while true; do
        clear
        echo -e "\033[1;37m⚡ Xray-core Source\033[0m"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo
        printf '   \033[38;5;15m%-15s\033[0m \033[38;5;117m%s\033[0m\n' 'Current source:' "$XRAY_REPO"
        echo
        echo -e "\033[1;37m🌐 Available Sources:\033[0m"
        echo -e "   \033[38;5;15m1)\033[0m 📦 XTLS/Xray-core"
        echo -e "   \033[38;5;15m2)\033[0m 📦 Jolymmiles/Xray-core"
        echo
        echo -e "   \033[38;5;15mEnter)\033[0m Keep current source"
        echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
        echo -e "   \033[38;5;15mQ)\033[0m 🔙 Cancel"
        echo
        read -r -p "$(echo -e "\033[1;37mSelect option [1-2, Enter, Q]:\033[0m ")" choice || return 1
        case "$choice" in
            1) XRAY_REPO=XTLS/Xray-core; return 0 ;;
            2) XRAY_REPO=Jolymmiles/Xray-core; return 0 ;;
            '') return 0 ;;
            q|Q) return 1 ;;
        esac
    done
}

xray_valid_tag() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,127}$ ]]
}

xray_validate_version() {
    local response tag
    if xray_valid_tag "$1" && response=$(curl -fsSL --connect-timeout 15 --max-time 60 "https://api.github.com/repos/$XRAY_REPO/releases/tags/$1"); then
        tag=$(printf '%s\n' "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
        if [ "$tag" = "$1" ]; then echo valid; return; fi
    fi
    echo invalid
}

xray_backup() {
    local snapshot file contents
    mkdir -p "$DATA_DIR/xray-backups" || return 1
    chmod 700 "$DATA_DIR/xray-backups" || return 1
    snapshot=$(mktemp -d "$DATA_DIR/xray-backups/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX") || return 1
    for file in xray geoip.dat geosite.dat xray-source xray-version; do
        if [ -d "$DATA_DIR/$file" ]; then
            contents=$(find "$DATA_DIR/$file" -mindepth 1 -maxdepth 1 -print -quit) || return 1
            if [ -L "$DATA_DIR/$file" ] || [ -n "$contents" ]; then
                echo "Expected a file at $DATA_DIR/$file; this is not an empty directory. Inspect and move it aside manually before retrying." >&2
                return 1
            fi
            cp -a "$DATA_DIR/$file" "$snapshot/$file" || return 1
        elif [ -e "$DATA_DIR/$file" ]; then
            cp -p "$DATA_DIR/$file" "$snapshot/$file" || return 1
        fi
    done
    if [ -f "$COMPOSE_FILE" ]; then cp -p "$COMPOSE_FILE" "$snapshot/compose" || return 1; fi
    touch "$snapshot/complete" || return 1
    printf '%s\n' "${snapshot##*/}" > "$DATA_DIR/xray-backups/latest" || return 1
    XRAY_TRANSACTION_BACKUP="$snapshot"
    echo "Xray backup: $snapshot"
}

xray_restore() {
    local snapshot="$1" file temporary
    [ -f "$snapshot/complete" ] || { echo 'Incomplete Xray backup' >&2; return 1; }
    for file in xray geoip.dat geosite.dat xray-source xray-version; do
        if [ -d "$DATA_DIR/$file" ]; then rmdir "$DATA_DIR/$file" || return 1; fi
        if [ -d "$snapshot/$file" ]; then
            rm -f "$DATA_DIR/$file" || return 1
            cp -a "$snapshot/$file" "$DATA_DIR/$file" || return 1
        elif [ -f "$snapshot/$file" ]; then
            # Rename the executable: overwriting a running ELF can fail with ETXTBSY.
            if [ "$file" = xray ]; then
                temporary=$(mktemp "$DATA_DIR/.xray-restore.XXXXXX") || return 1
                if ! cp -p "$snapshot/$file" "$temporary" || ! mv -fT "$temporary" "$DATA_DIR/$file"; then
                    rm -f "$temporary"
                    return 1
                fi
            else
                cp -p "$snapshot/$file" "$DATA_DIR/$file" || return 1
            fi
        else
            rm -f "$DATA_DIR/$file" || return 1
        fi
    done
    if [ -f "$snapshot/compose" ]; then
        cp -p "$snapshot/compose" "$COMPOSE_FILE" || return 1
    else
        rm -f "$COMPOSE_FILE" || return 1
    fi
    xray_load_source
}

xray_rollback() {
    local name snapshot
    IFS= read -r name < "$DATA_DIR/xray-backups/latest" || { echo 'No Xray backup available' >&2; return 1; }
    [[ "$name" =~ ^[a-zA-Z0-9.]+$ ]] || return 1
    snapshot="$DATA_DIR/xray-backups/$name"
    [ -f "$snapshot/complete" ] || return 1
    xray_backup || return 1
    xray_restore "$snapshot" || return 1
    if [ -f "$COMPOSE_FILE" ]; then xray_restart && xray_check_running restored || return 1; fi
    echo "Xray restored from $snapshot"
}

xray_edit_compose() {
    local mode="$1" temporary
    [ -f "$COMPOSE_FILE" ] || return 1
    temporary=$(mktemp "${COMPOSE_FILE}.xray.XXXXXX") || return 1
    cp -p "$COMPOSE_FILE" "$temporary" || { rm -f "$temporary"; return 1; }
    # shortcut: block YAML with short volume entries only; reject other forms until a YAML parser is available.
    if ! awk -v mode="$mode" -v app="$APP_NAME" -v data="$DATA_DIR" \
        -v geoip="$(test -f "$DATA_DIR/geoip.dat" && echo yes)" \
        -v geosite="$(test -f "$DATA_DIR/geosite.dat" && echo yes)" '
        function fail(message) { print "Compose: " message > "/dev/stderr"; bad=1; exit 1 }
        function indent(line) { match(line, /[^ ]/); return RSTART-1 }
        function value(line) { sub(/^[^:]*:[ ]*/, "", line); gsub(/["\047]/, "", line); sub(/[ ]+#.*/, "", line); return line }
        { lines[NR]=$0 }
        END {
            for (i=1; i<=NR; i++) {
                line=lines[i]
                if (line ~ /\t|\r/) fail("tabs or CRLF are unsupported")
                if (line ~ /^services:[ ]*$/) { services=1; continue }
                if (!services) continue
                if (line ~ /^[^ #]/) { if (current) ends[current]=i-1; break }
                if (!level && line !~ /^[ ]*(#.*)?$/) {
                    if (line !~ /^ +[A-Za-z0-9_-]+:[ ]*$/) fail("unsupported service declaration")
                    level=indent(line)
                }
                if (level && indent(line)==level && line !~ /^[ ]*(#.*)?$/ && line !~ /^ +[A-Za-z0-9_-]+:[ ]*$/) fail("unsupported service declaration")
                if (level && indent(line)==level && line ~ /^ +[A-Za-z0-9_-]+:[ ]*$/) {
                    if (current) ends[current]=i-1
                    current++; starts[current]=i; ends[current]=NR
                } else if (current) {
                    if (line ~ /^ +container_name:/ && value(line)==app) named[current]=1
                    if (line ~ /^ +image:/ && value(line) ~ /(^|\/)remnawave\/node(:|@|$)/) image[current]=1
                }
            }
            for (n=1; n<=current; n++) if (named[n]) { target=n; matches++ }
            if (!matches) for (n=1; n<=current; n++) if (image[n]) { target=n; matches++ }
            if (matches!=1) fail("expected exactly one node service; use a unique container_name")
            start=starts[target]; end=ends[target]; prop=level+2
            for (i=start+1; i<=end; i++) if (lines[i] ~ /^ +[A-Za-z0-9_-]+:/) {
                if (!foundprop || indent(lines[i])<prop) prop=indent(lines[i])
                foundprop=1
            }
            spaces=sprintf("%*s", prop, "")
            for (i=start+1; i<=end; i++) if (indent(lines[i])==prop && lines[i] ~ /^ +volumes:/) {
                if (vs) fail("duplicate volumes key")
                if (lines[i] !~ /^ +volumes:[ ]*(#.*)?$/) fail("inline volumes are unsupported")
                vs=i; ve=i
                for (j=i+1; j<=end; j++) {
                    entry=lines[j]
                    if (entry ~ /^[ ]*(#.*)?$/) { kept[++count]=entry; ve=j; continue }
                    if (indent(entry)<=prop) break
                    if (entry !~ /^ +-[ ]+/ || entry ~ /^ +-[ ]*(type:|\{)/) fail("long volume syntax is unsupported")
                    ve=j
                    if (entry ~ /:\/usr\/local\/bin\/xray([:"\047 ]|$)/ || entry ~ /:\/usr\/local\/share\/xray\/(geoip|geosite)\.dat([:"\047 ]|$)/) continue
                    kept[++count]=entry; items++
                }
            }
            insertion=vs ? vs : start+1
            for (i=1; i<=NR+1; i++) {
                if (i==insertion) {
                    if (mode=="install" || items) print spaces "volumes:"
                    for (j=1; j<=count; j++) print kept[j]
                    if (mode=="install") {
                        print spaces "  - " data "/xray:/usr/local/bin/xray"
                        if (geoip=="yes") print spaces "  - " data "/geoip.dat:/usr/local/share/xray/geoip.dat"
                        if (geosite=="yes") print spaces "  - " data "/geosite.dat:/usr/local/share/xray/geosite.dat"
                    }
                }
                if (i<=NR && !(vs && i>=vs && i<=ve)) print lines[i]
            }
        }' "$COMPOSE_FILE" > "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    mv -f "$temporary" "$COMPOSE_FILE"
}

xray_check_running() {
    local mode="${1:-external}" attempt state mount hashes expected='' consecutive=0
    if [ "$mode" = external ]; then expected=$(sha256sum "$DATA_DIR/xray") || return 1; expected=${expected%% *}; fi
    for attempt in {1..30}; do
        state=$(docker inspect -f '{{.State.Running}} {{.State.Restarting}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$APP_NAME" 2>/dev/null) || state=''
        mount=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/usr/local/bin/xray"}}{{.Source}}{{end}}{{end}}' "$APP_NAME" 2>/dev/null) || mount=''
        # Hash the live executable, rather than launching a second Xray just to print its version.
        hashes=$(docker exec "$APP_NAME" sh -c 'for exe in /proc/[0-9]*/exe; do
            target=$(readlink "$exe" 2>/dev/null) || continue
            case "$target" in */xray|*/xray\ \(deleted\)) sha256sum "$exe" 2>/dev/null ;; esac
        done' 2>/dev/null | awk '{print $1}') || hashes=''
        if [[ "$state" = 'true false '* ]] && [[ "$state" != *unhealthy* && "$state" != *starting* ]] && [ -n "$hashes" ] && \
            { [ "$mode" != external ] || { [ "$mount" = "$DATA_DIR/xray" ] && grep -Fxq "$expected" <<< "$hashes"; }; } && \
            { [ "$mode" != builtin ] || [ -z "$mount" ]; }; then
            consecutive=$((consecutive+1))
            [ "$consecutive" -ge 2 ] && return 0
        else
            consecutive=0
        fi
        sleep 2
    done
    echo "Xray readiness failed: check node health, live process and external mount ($mode)" >&2
    return 1
}

xray_finish_transaction() {
    local rc="$1"
    trap - EXIT
    if [ "$rc" -ne 0 ] && [ -n "$XRAY_TRANSACTION_BACKUP" ]; then
        echo 'Xray operation failed; restoring previous files and source' >&2
        if xray_restore "$XRAY_TRANSACTION_BACKUP"; then
            if [ -f "$COMPOSE_FILE" ]; then
                (xray_restart && xray_check_running restored) || echo "Recovery restart failed; backup: $XRAY_TRANSACTION_BACKUP" >&2
            fi
        else
            echo "RESTORE FAILED; backup: $XRAY_TRANSACTION_BACKUP" >&2
        fi
    fi
    if [ -n "$XRAY_STAGE" ]; then rm -rf "$XRAY_STAGE"; fi
    exit "$rc"
}

xray_transaction() (
    set -e
    command -v flock >/dev/null || { echo 'flock (util-linux) is required' >&2; exit 1; }
    mkdir -p "$DATA_DIR"
    exec 9> "$DATA_DIR/.xray-update.lock"
    flock -n 9 || { echo 'Another Xray operation is running' >&2; exit 1; }
    XRAY_TRANSACTION_BACKUP=''
    XRAY_STAGE=''
    trap 'xray_finish_transaction "$?"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    "$@"
)

xray_install_release() {
    local version="$1" file
    xray_valid_tag "$version" || return 1
    case "$XRAY_REPO" in XTLS/Xray-core|Jolymmiles/Xray-core) ;; *) return 1 ;; esac
    XRAY_STAGE=$(mktemp -d "$DATA_DIR/.xray-stage.XXXXXX") || return 1
    echo "Downloading $XRAY_REPO $version ($ARCH)"
    curl -fL --connect-timeout 15 --max-time 300 --retry 2 \
        "https://github.com/$XRAY_REPO/releases/download/$version/Xray-linux-$ARCH.zip" \
        -o "$XRAY_STAGE/release.zip" || return 1
    # Extract only known members; archive paths and symlinks never reach DATA_DIR.
    unzip -p "$XRAY_STAGE/release.zip" xray > "$XRAY_STAGE/xray" || return 1
    [ -s "$XRAY_STAGE/xray" ] || return 1
    chmod 755 "$XRAY_STAGE/xray" || return 1
    "$XRAY_STAGE/xray" -version || return 1
    for file in geoip.dat geosite.dat; do
        if unzip -Z1 "$XRAY_STAGE/release.zip" | grep -qx "$file"; then
            unzip -p "$XRAY_STAGE/release.zip" "$file" > "$XRAY_STAGE/$file" || return 1
            [ -s "$XRAY_STAGE/$file" ] || return 1
        fi
    done
    xray_backup || return 1
    for file in xray geoip.dat geosite.dat; do
        # A fork may omit geodata; retain the installed databases in that case.
        if [ -f "$XRAY_STAGE/$file" ]; then
            if [ -d "$DATA_DIR/$file" ]; then rmdir "$DATA_DIR/$file" || return 1; fi
            mv -fT "$XRAY_STAGE/$file" "$DATA_DIR/$file" || return 1
        fi
    done
    printf '%s\n' "$XRAY_REPO" > "$DATA_DIR/xray-source" || return 1
    printf '%s\n' "$version" > "$DATA_DIR/xray-version" || return 1
}
# END XRAY SOURCE


xray_restart() { restart_remnanode; }

# Version validation via GitHub API
validate_version() { xray_validate_version "$1"; }

# Fetch version list from GitHub
fetch_versions() {
    local include_prereleases="$1"
    colorized_echo blue "🔍 Fetching Xray-core version list..."
    
    if [ "$include_prereleases" = true ]; then
        colorized_echo cyan "   Including pre-releases..."
        latest_releases=$(curl -fsSL --connect-timeout 15 --max-time 60 "https://api.github.com/repos/$XRAY_REPO/releases?per_page=8")
    else
        colorized_echo cyan "   Stable releases only..."
        # XTLS помечает большинство релизов как pre-release: последний
        # стабильный тег может находиться глубоко в списке (15+ записей).
        # При маленькой per_page в выборку попадают только pre-release, и
        # фильтр ниже не находит ни одной стабильной версии.
        latest_releases=$(curl -fsSL --connect-timeout 15 --max-time 60 "https://api.github.com/repos/$XRAY_REPO/releases?per_page=100")
    fi
    
    if [ -z "$latest_releases" ] || echo "$latest_releases" | grep -q '"message":'; then
        colorized_echo red "❌ Failed to fetch version list. Check your internet connection."
        return 1
    fi
    
    versions=()
    prereleases=()
    
    local temp_file=$(mktemp)
    echo "$latest_releases" | grep -E '"(tag_name|prerelease)"' > "$temp_file"
    
    local current_version=""
    local count=0
    local max_count=6
    
    while IFS= read -r line; do
        if [[ "$line" =~ \"tag_name\":[[:space:]]*\"([^\"]+)\" ]]; then
            current_version="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"prerelease\":[[:space:]]*(true|false) ]]; then
            local is_prerelease="${BASH_REMATCH[1]}"
            
            if [ "$include_prereleases" = false ] && [ "$is_prerelease" = "true" ]; then
                current_version=""
                continue
            fi
            
            if [ -n "$current_version" ] && [ $count -lt $max_count ]; then
                versions+=("$current_version")
                prereleases+=("$is_prerelease")
                ((count++)) || true
            fi
            current_version=""
        fi
    done < "$temp_file"
    
    rm "$temp_file"
    
    if [ ${#versions[@]} -eq 0 ]; then
        colorized_echo red "❌ No versions found."
        return 1
    fi
    
    colorized_echo green "✅ Found ${#versions[@]} versions"
    return 0
}

# Interactive version selection menu
print_menu() {
    clear
    
    echo -e "\033[1;37m⚡ Xray-core Installer for RemnaNode\033[0m"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
    echo
    
    current_version=$(get_current_xray_core_version || true)
    echo -e "\033[1;37m🌐 Current Status:\033[0m"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Xray Version:" "$current_version"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Architecture:" "$ARCH"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;117m%s\033[0m\n" "Current source:" "$XRAY_REPO"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "RemnaNode:" "$REMNANODE_DIR"
    echo
    
    echo -e "\033[1;37m🎯 Release Mode:\033[0m"
    if [ "$show_prereleases" = true ]; then
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m \033[38;5;244m(Including pre-releases)\033[0m\n" "Current:" "All releases"
    else
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m \033[1;37m(Stable only)\033[0m\n" "Current:" "Stable releases"
    fi
    echo
    
    echo -e "\033[1;37m🚀 Available Versions:\033[0m"
    for ((i=0; i<${#versions[@]}; i++)); do
        local version_num=$((i + 1))
        local version_name="${versions[i]}"
        local is_prerelease="${prereleases[i]}"
        
        if [ "$is_prerelease" = "true" ]; then
            echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[38;5;244m(Pre-release)\033[0m"
        elif [ $i -eq 0 ] && [ "$is_prerelease" = "false" ]; then
            echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[1;37m(Latest stable)\033[0m"
        else
            echo -e "   \033[38;5;15m${version_num}:\033[0m \033[38;5;250m${version_name}\033[0m \033[38;5;8m(Stable)\033[0m"
        fi
    done
    echo
    
    echo -e "\033[1;37m🔧 Options:\033[0m"
    printf "   \033[38;5;15m%-3s\033[0m %s\n" "M:" "📝 Enter version manually"
    if [ "$show_prereleases" = true ]; then
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "S:" "🔒 Show stable releases only"
    else
        printf "   \033[38;5;15m%-3s\033[0m %s\n" "A:" "🧪 Show all releases (including pre-releases)"
    fi
    printf "   \033[38;5;15m%-3s\033[0m %s\n" "R:" "🔄 Refresh version list"
    printf "   \033[38;5;15m%-3s\033[0m %s\n" "P:" "🌐 Choose source"
    printf "   \033[38;5;15m%-3s\033[0m %s\n" "B:" "💾 Roll back last Xray backup"
    printf "   \033[38;5;15m%-3s\033[0m %s\n" "Q:" "❌ Exit installer"
    echo
    
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
    echo -e "\033[1;37m📖 Usage:\033[0m"
    echo -e "   Select number \033[38;5;15m(1-${#versions[@]})\033[0m, \033[38;5;15mM\033[0m for manual input, \033[38;5;15mA/S\033[0m to toggle releases, \033[38;5;15mP\033[0m to choose source, \033[38;5;15mB\033[0m to roll back, or \033[38;5;15mQ\033[0m to exit"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
}

# Интерактивный выбор и загрузка Xray-core
get_xray_core() {
    xray_load_source || exit 1
    xray_choose_source || exit 0
    identify_the_operating_system_and_architecture
    clear
    
    local show_prereleases=false
    
    if ! fetch_versions "$show_prereleases"; then
        # Стабильных релизов может не оказаться в выборке GitHub (XTLS помечает
        # pre-release почти все релизы). Не вылетаем, а откатываемся на показ
        # всех релизов — иначе до меню с опцией A вообще не добраться.
        colorized_echo yellow "   Falling back to all releases (incl. pre-releases)..."
        show_prereleases=true
        versions=(); prereleases=()
        fetch_versions "$show_prereleases" || true
    fi
    
    while true; do
        print_menu
        echo -n -e "\033[1;37mSelect option [number, M, A/S, R, P, B, Q]:\033[0m "
        read choice
        
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#versions[@]}" ]; then
            choice=$((choice - 1))
            selected_version=${versions[choice]}
            local selected_prerelease=${prereleases[choice]}
            
            echo
            if [ "$selected_prerelease" = "true" ]; then
                colorized_echo yellow "⚠️  Selected pre-release version: $selected_version"
                colorized_echo cyan "   Pre-releases may contain bugs and are not recommended for production."
                read -p "Are you sure you want to continue? (y/n): " -r confirm_prerelease
                if [[ ! $confirm_prerelease =~ ^[Yy]$ ]]; then
                    colorized_echo red "❌ Installation cancelled."
                    continue
                fi
            else
                colorized_echo green "✅ Selected stable version: $selected_version"
            fi
            break
            
        elif [[ "$choice" = [Pp] ]]; then
            xray_choose_source || continue
            versions=(); prereleases=()
            fetch_versions "$show_prereleases" || { show_prereleases=true; fetch_versions true || true; }
        elif [[ "$choice" = [Bb] ]]; then
            clear
            echo -e "\033[1;37m💾 Roll Back Xray Backup\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
            echo
            echo -e "   \033[38;5;250mRestore the last Xray backup and restart the node.\033[0m"
            echo
            read -r -p "$(echo -e "\033[1;37mContinue? [y/N]:\033[0m ")" confirm_rollback
            if [[ "$confirm_rollback" = [Yy] ]]; then xray_rollback; exit $?; fi
        elif [ "$choice" == "M" ] || [ "$choice" == "m" ]; then
            clear
            echo -e "\033[1;37m📝 Manual Version Entry\033[0m"
            echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 55))\033[0m"
            echo
            printf '   \033[38;5;15m%-15s\033[0m \033[38;5;117m%s\033[0m\n' 'Current source:' "$XRAY_REPO"
            echo
            while true; do
                echo -n -e "\033[1;37mEnter version (e.g., v1.8.4):\033[0m "
                read custom_version
                
                if [ -z "$custom_version" ]; then
                    colorized_echo red "❌ Version cannot be empty. Try again."
                    continue
                fi
                
                colorized_echo blue "🔍 Checking version $custom_version..."
                if [ "$(validate_version "$custom_version")" == "valid" ]; then
                    selected_version="$custom_version"
                    colorized_echo green "✅ Version $custom_version found!"
                    break 2
                else
                    colorized_echo red "❌ Version $custom_version not found. Try again."
                    colorized_echo cyan "   Hint: Check https://github.com/$XRAY_REPO/releases"
                    echo
                fi
            done
            
        elif [ "$choice" == "A" ] || [ "$choice" == "a" ]; then
            if [ "$show_prereleases" = false ]; then
                show_prereleases=true
                if ! fetch_versions "$show_prereleases"; then
                    show_prereleases=false
                    continue
                fi
            fi
            
        elif [ "$choice" == "S" ] || [ "$choice" == "s" ]; then
            if [ "$show_prereleases" = true ]; then
                show_prereleases=false
                if ! fetch_versions "$show_prereleases"; then
                    show_prereleases=true
                    continue
                fi
            fi
            
        elif [ "$choice" == "R" ] || [ "$choice" == "r" ]; then
            if ! fetch_versions "$show_prereleases"; then
                continue
            fi
            
        elif [ "$choice" == "Q" ] || [ "$choice" == "q" ]; then
            echo
            colorized_echo red "❌ Installation cancelled by user."
            exit 0
            
        else
            echo
            colorized_echo red "❌ Invalid choice: '$choice'"
            colorized_echo cyan "   Enter number from 1 to ${#versions[@]}, M for manual input, A/S to toggle releases, R to refresh, or Q to exit."
            echo
            echo -n -e "\033[38;5;8mPress Enter to continue...\033[0m"
            read
        fi
    done
    
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    colorized_echo blue "🚀 Starting installation"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    
    if ! dpkg -s unzip >/dev/null 2>&1; then
        colorized_echo blue "📦 Installing required packages..."
        apt update -qq >/dev/null 2>&1
        apt install -y unzip >/dev/null 2>&1
        colorized_echo green "✅ Packages installed successfully"
    fi
    
    xray_install_release "$selected_version" || exit 1

}

# Backup management
create_backup() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$file" ]; then
        cp "$file" "$backup_file"
        echo "$backup_file"
        return 0
    else
        return 1
    fi
}

restore_backup() {
    local backup_file="$1"
    local original_file="$2"
    
    if [ -f "$backup_file" ]; then
        cp "$backup_file" "$original_file"
        return 0
    else
        return 1
    fi
}

# Working with indentation in docker-compose.yml
get_service_property_indentation() {
    local compose_file="$1"
    local base_indent=""
    local property_indent=""
    
    if [ -f "$compose_file" ]; then
        local service_line=$(grep -E "^\s*[a-zA-Z0-9_-]*remna[a-zA-Z0-9_-]*:" "$compose_file" | head -1)
        if [ -n "$service_line" ]; then
            base_indent=$(echo "$service_line" | sed 's/[a-zA-Z0-9_-]*remna[a-zA-Z0-9_-]*:.*//' | grep -o '^[[:space:]]*')
        fi
        
        local in_remna_service=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*$ ]]; then
                local current_service=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/:[[:space:]]*$//')
                if [[ "$current_service" =~ remna ]]; then
                    in_remna_service=true
                else
                    in_remna_service=false
                fi
                continue
            fi
            
            if [ "$in_remna_service" = true ]; then
                if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                    property_indent=$(echo "$line" | sed 's/[a-zA-Z0-9_-]*:.*//' | grep -o '^[[:space:]]*')
                    break
                fi
            fi
        done < "$compose_file"
    fi
    
    if [ -z "$property_indent" ]; then
        if [ -z "$base_indent" ]; then
            base_indent="  "
        fi
        property_indent="${base_indent}  "
    fi
    
    echo "$property_indent"
}

escape_for_sed() {
    local text="$1"
    echo "$text" | sed 's/[]\.*^$()+?{|[]/\\&/g' | sed 's/\t/\\t/g'
}

# Update docker-compose.yml configuration
update_docker_compose() {
    local compose_file="$REMNANODE_DIR/docker-compose.yml"
    local xray_file="/var/lib/remnanode/xray"
    local geoip_file="/var/lib/remnanode/geoip.dat"
    local geosite_file="/var/lib/remnanode/geosite.dat"
    
    if [ ! -f "$compose_file" ]; then
        colorized_echo red "docker-compose.yml file not found in $REMNANODE_DIR"
        exit 1
    fi
    
    colorized_echo blue "Creating backup of docker-compose.yml..."
    backup_file=$(create_backup "$compose_file")
    if [ $? -eq 0 ]; then
        colorized_echo green "Backup created: $backup_file"
    else
        colorized_echo red "Failed to create backup"
        exit 1
    fi
    
    xray_edit_compose install || exit 1

    colorized_echo green "docker-compose.yml configuration updated"
    
    # Show what was mounted
    colorized_echo blue "📋 Mounted volumes:"
    colorized_echo green "   ✅ xray → /usr/local/bin/xray"
    if [ -f "$geoip_file" ]; then
        colorized_echo green "   ✅ geoip.dat → /usr/local/share/xray/geoip.dat"
    fi
    if [ -f "$geosite_file" ]; then
        colorized_echo green "   ✅ geosite.dat → /usr/local/share/xray/geosite.dat"
    fi
}

# Restart RemnaNode
restart_remnanode() {
    if ! command -v docker >/dev/null 2>&1; then
        colorized_echo red "Docker not found!"
        exit 1
    fi
    
    local compose_cmd=""
    if docker compose >/dev/null 2>&1; then
        compose_cmd='docker compose'
    elif docker-compose >/dev/null 2>&1; then
        compose_cmd='docker-compose'
    else
        colorized_echo red "Docker Compose not found!"
        exit 1
    fi
    
    local compose_file="$REMNANODE_DIR/docker-compose.yml"
    local app_name=$(basename "$REMNANODE_DIR")
    
    colorized_echo blue "Restarting RemnaNode..."
    
    cd "$REMNANODE_DIR"
    
    $compose_cmd -f "$compose_file" -p "$app_name" config >/dev/null
    $compose_cmd -f "$compose_file" -p "$app_name" down >/dev/null 2>&1
    
    if $compose_cmd -f "$compose_file" -p "$app_name" up -d --remove-orphans >/dev/null 2>&1; then
        colorized_echo green "✅ RemnaNode restarted successfully"
    else
        colorized_echo red "❌ RemnaNode restart error"
        colorized_echo yellow "Restoring backup..."
        if restore_backup "$backup_file" "$compose_file"; then
            colorized_echo green "Backup restored"
        fi
        exit 1
    fi
}

# Main script logic
main() {
    DATA_DIR=/var/lib/remnanode
    xray_transaction main_impl
}

main_impl() {
    find_remnanode_directory
    COMPOSE_FILE="$REMNANODE_DIR/docker-compose.yml"
    APP_NAME=$(basename "$REMNANODE_DIR")
    get_xray_core
    
    colorized_echo blue "Updating docker-compose.yml configuration..."
    update_docker_compose
    restart_remnanode
    xray_check_running || exit 1
    
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    colorized_echo green "🎉 Xray-core update completed!"
    
    echo
    colorized_echo blue "📋 Installation details:"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Version:" "$selected_version"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Architecture:" "$ARCH"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Install path:" "/var/lib/remnanode/xray"
    printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "RemnaNode:" "$REMNANODE_DIR"
    
    echo
    colorized_echo blue "🔍 Checking installation..."
    if installed_version=$("/var/lib/remnanode/xray" -version 2>/dev/null | head -n1 | awk '{print $2}'); then
        colorized_echo green "✅ Xray-core working correctly"
        printf "   \033[38;5;15m%-15s\033[0m \033[38;5;250m%s\033[0m\n" "Running version:" "$installed_version"
    else
        colorized_echo yellow "⚠️  Installation completed, but verification failed"
        colorized_echo cyan "   Binary file may be incompatible with your system"
    fi
    
    echo
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
    colorized_echo cyan "💡 RemnaNode restarted with new Xray-core version"
    colorized_echo cyan "💡 Backup saved: $backup_file"
    echo -e "\033[38;5;8m$(printf '─%.0s' $(seq 1 60))\033[0m"
}

main "$@"
