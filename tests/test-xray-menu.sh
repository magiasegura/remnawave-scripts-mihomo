#!/usr/bin/env bash
# Exercise the original menus with fixture GitHub responses, no Docker/network.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export DATA_DIR="$sandbox/data" COMPOSE_FILE="$sandbox/compose" XRAY_FILE="$sandbox/data/xray"
mkdir -p "$DATA_DIR"
export SCRIPT_VERSION=test ARCH=64 REMNANODE_DIR="$sandbox"
load_function() {
    local code
    code=$(awk -v name="$1" '$0 == name "() {" { inside=1 } inside { print } inside && $0 == "}" { exit }' "$ROOT/$script")
    [ -n "$code" ] || { echo "Missing $1 in $script"; exit 1; }
    eval "$code"
}
for script in remnanode.sh remnanode-xray-update.sh; do
    eval "$(sed -n '/^# BEGIN XRAY SOURCE/,/^# END XRAY SOURCE/p' "$ROOT/$script")"
    load_function get_xray_core
    if [ "$script" = remnanode-xray-update.sh ]; then
        load_function fetch_versions
        load_function print_menu
        validate_version() { xray_validate_version "$1"; }
    fi
    clear() { :; }
    colorized_echo() { echo "$2"; }
    identify_the_operating_system_and_architecture() { ARCH=64; }
    get_current_xray_core_version() { echo 'Not installed'; return 1; }
    is_xray_mounted() { return 1; }
    dpkg() { return 0; }
    xray_backup() { :; }
    xray_rollback() { echo rollback > "$sandbox/result"; }
    xray_install_release() { printf '%s %s\n' "$XRAY_REPO" "$1" > "$sandbox/result"; }
    curl() {
        echo "$*" >> "$sandbox/requests"
        if [ "${offline:-false}" = true ]; then return 22; fi
        if [[ "$*" = *releases/tags/* ]]; then
            echo '{"tag_name":"v1.2.3"}'
        else
            printf '[\n{"tag_name": "v1.2.3",\n"prerelease": false},\n{"tag_name": "v2.0.0-beta",\n"prerelease": true}\n]\n'
        fi
    }
    printf '\np\n2\n1\n' | (get_xray_core) > "$sandbox/menu"
    [ "$(cat "$sandbox/result")" = 'Jolymmiles/Xray-core v1.2.3' ]
    grep -q 'Jolymmiles/Xray-core/releases?per_page=100' "$sandbox/requests"
    echo "PASS: $script source switch and numbered version use selected repository"
    printf '1\nm\nv1.2.3\n' | (get_xray_core) > "$sandbox/menu"
    [ "$(cat "$sandbox/result")" = 'XTLS/Xray-core v1.2.3' ]
    echo "PASS: $script manual tag validation uses selected source"
    printf '\na\n2\ny\n' | (get_xray_core) > "$sandbox/menu"
    [ "$(cat "$sandbox/result")" = 'XTLS/Xray-core v2.0.0-beta' ]
    echo "PASS: $script pre-release toggle and confirmation still work"
    printf '\ns\nr\nq\n' | (get_xray_core) > "$sandbox/menu"
    echo "PASS: $script stable filter, refresh and quit remain available"
    offline=true
    printf '\nb\ny\n' | (get_xray_core) > "$sandbox/menu"
    [ "$(cat "$sandbox/result")" = rollback ]
    echo "PASS: $script rollback menu remains available when GitHub is offline"
    offline=false
done
sed -n '/^# BEGIN XRAY SOURCE/,/^# END XRAY SOURCE/p' "$ROOT/remnanode.sh" > "$sandbox/main-block"
sed -n '/^# BEGIN XRAY SOURCE/,/^# END XRAY SOURCE/p' "$ROOT/remnanode-xray-update.sh" > "$sandbox/updater-block"
cmp "$sandbox/main-block" "$sandbox/updater-block"
echo 'PASS: both standalone scripts embed identical source/backup logic'
