#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
DATA_DIR="$sandbox"; APP_NAME=remnanode
echo binary > "$DATA_DIR/xray"
expected=$(sha256sum "$DATA_DIR/xray"); expected=${expected%% *}
sleep() { :; }
docker() {
    case "$*" in
        *'.State.Running'*)
            case "$HEALTH_CASE" in
                unhealthy) echo 'true false unhealthy' ;;
                restarting) echo 'true true ' ;;
                *) echo 'true false healthy' ;;
            esac ;;
        *'.Mounts'*)
            case "$HEALTH_CASE" in builtin) ;; wrongmount) echo /wrong/xray ;; *) echo "$DATA_DIR/xray" ;; esac ;;
        exec*)
            case "$HEALTH_CASE" in dead) ;; wronghash) echo 'wrong /proc/123/exe' ;; *) echo "$expected /proc/123/exe" ;; esac ;;
        *) return 1 ;;
    esac
}
for script in remnanode.sh remnanode-xray-update.sh; do
    eval "$(sed -n '/^# BEGIN XRAY SOURCE/,/^# END XRAY SOURCE/p' "$ROOT/$script")"
    HEALTH_CASE=good
    xray_check_running
    echo "PASS: $script accepts a healthy node with the selected live executable and mount"
    for HEALTH_CASE in dead wronghash wrongmount unhealthy restarting; do
        if xray_check_running; then echo "FAIL: accepted $HEALTH_CASE"; exit 1; fi
        echo "PASS: $script rejects $HEALTH_CASE"
    done
    HEALTH_CASE=builtin
    xray_check_running builtin
    echo "PASS: $script checks builtin restore without requiring an external mount"
done
