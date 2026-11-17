#!/usr/bin/env bash
# Docker can create an empty directory where a missing bind-mounted file belongs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
for script in remnanode.sh remnanode-xray-update.sh; do
    eval "$(sed -n '/^# BEGIN XRAY SOURCE/,/^# END XRAY SOURCE/p' "$ROOT/$script")"
    DATA_DIR="$sandbox/$script"
    COMPOSE_FILE="$DATA_DIR/compose"
    ARCH=64
    XRAY_REPO=Jolymmiles/Xray-core
    mkdir -p "$DATA_DIR/xray" "$DATA_DIR/geoip.dat"
    chmod 750 "$DATA_DIR/xray"
    echo 'original compose' > "$COMPOSE_FILE"
    curl() {
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -o ]; then echo archive > "$2"; return; fi
            shift
        done
        return 1
    }
    unzip() {
        case "$1:${3:-}" in
            -Z1:*) printf 'xray\ngeoip.dat\n' ;;
            -p:xray) printf '#!/usr/bin/env bash\necho "Xray fixture"\n' ;;
            -p:geoip.dat) echo 'fixture geodata' ;;
            *) return 1 ;;
        esac
    }
    xray_install_release v1.2.3
    saved="$XRAY_TRANSACTION_BACKUP"
    [ -f "$DATA_DIR/xray" ] && [ -x "$DATA_DIR/xray" ]
    [ "$("$DATA_DIR/xray" -version)" = 'Xray fixture' ]
    [ -f "$DATA_DIR/geoip.dat" ]
    [ -d "$saved/xray" ] && [ -d "$saved/geoip.dat" ]
    echo "PASS: $script replaces empty bind-mount directories with files"

    echo 'changed compose' > "$COMPOSE_FILE"
    xray_restore "$saved"
    [ -d "$DATA_DIR/xray" ] && [ -d "$DATA_DIR/geoip.dat" ]
    [ -z "$(find "$DATA_DIR/xray" -mindepth 1 -print -quit)" ]
    [ ! -e "$DATA_DIR/xray-source" ] && [ ! -e "$DATA_DIR/xray-version" ]
    [ "$(cat "$COMPOSE_FILE")" = 'original compose' ]
    echo "PASS: $script rollback restores the original empty directories and Compose"

    echo 'keep this' > "$DATA_DIR/xray/.important"
    if xray_install_release v1.2.3 > "$sandbox/rejected" 2>&1; then
        echo 'FAIL: accepted a non-empty binary directory'; exit 1
    fi
    [ "$(cat "$DATA_DIR/xray/.important")" = 'keep this' ]
    [ ! -e "$DATA_DIR/xray/xray" ]
    [ "$(cat "$DATA_DIR/xray-backups/latest")" = "${saved##*/}" ]
    grep -q 'not an empty directory' "$sandbox/rejected"
    echo "PASS: $script rejects non-empty directories without losing hidden files or the last backup"

    rm "$DATA_DIR/xray/.important"
    rmdir "$DATA_DIR/xray"
    printf 'old binary\n' > "$DATA_DIR/xray"
    xray_backup
    saved="$XRAY_TRANSACTION_BACKUP"
    rm "$DATA_DIR/xray"
    mkdir "$DATA_DIR/xray"
    xray_restore "$saved"
    [ -f "$DATA_DIR/xray" ] && [ "$(cat "$DATA_DIR/xray")" = 'old binary' ]
    echo "PASS: $script restores a binary over a recreated empty directory"

    rm "$DATA_DIR/xray"
    mkdir "$DATA_DIR/xray"
    echo 'new data' > "$DATA_DIR/xray/.important"
    if xray_restore "$saved" > "$sandbox/rejected" 2>&1; then
        echo 'FAIL: rollback overwrote a non-empty directory'; exit 1
    fi
    [ "$(cat "$DATA_DIR/xray/.important")" = 'new data' ]
    [ ! -e "$DATA_DIR/xray/xray" ]
    echo "PASS: $script rollback preserves unexpected directory contents"
done
