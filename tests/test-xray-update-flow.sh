#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export DATA_DIR="$sandbox/data" COMPOSE_FILE="$sandbox/docker-compose.yml" APP_NAME=remnanode
export XRAY_FILE="$DATA_DIR/xray" GEOIP_FILE="$DATA_DIR/geoip.dat" GEOSITE_FILE="$DATA_DIR/geosite.dat"
mkdir -p "$DATA_DIR"
load_function() {
    awk -v name="$1" '$0 == name "() {" { inside=1 } inside { print } inside && $0 == "}" { exit }' "$ROOT/remnanode.sh" >> "$sandbox/worker"
}
sed -n '/^# BEGIN XRAY SOURCE/,/^# END XRAY SOURCE/p' "$ROOT/remnanode.sh" > "$sandbox/worker"
for fn in update_core_command_impl restore_to_container_default create_backup restore_backup; do load_function "$fn"; done
cat >> "$sandbox/worker" <<'SH'
check_running_as_root() { :; }
colorized_echo() { echo "$2"; }
validate_compose_file() { [ "$FAIL_AT" != validation ]; }
restart_command() { echo restart >> "$DATA_DIR/restarts"; [ "$FAIL_AT" != restart ]; }
xray_restart() { echo recovery >> "$DATA_DIR/recovery"; }
xray_check_running() { [ "$FAIL_AT" != health ]; }
cleanup_old_backups() { :; }
get_xray_core() { selected_version=test; xray_backup; echo new > "$XRAY_FILE"; }
run_builtin() { xray_backup; restore_to_container_default; }
if [ "$FAIL_AT" = builtin ]; then
    xray_transaction run_builtin
else
    xray_transaction update_core_command_impl
fi
SH
for FAIL_AT in none validation restart health builtin; do
    export FAIL_AT
    echo old > "$XRAY_FILE"
    cat > "$COMPOSE_FILE" <<'YAML'
services:
  remnanode:
    image: remnawave/node:latest
    restart: unless-stopped
YAML
    cp "$COMPOSE_FILE" "$sandbox/before"
    set +e
    bash -e "$sandbox/worker" < /dev/null > "$sandbox/result" 2>&1
    rc=$?
    set -e
    case "$FAIL_AT" in
        none)
            [ "$rc" -eq 0 ]; [ "$(cat "$XRAY_FILE")" = new ]
            grep -q '/usr/local/bin/xray' "$COMPOSE_FILE"
            echo 'PASS: EOF at final backup question keeps successful update and reports exit 0' ;;
        builtin)
            [ "$rc" -eq 0 ]; ! grep -q '/usr/local/bin/xray' "$COMPOSE_FILE"
            echo 'PASS: builtin restore handles EOF at final backup question' ;;
        *)
            [ "$rc" -ne 0 ]; [ "$(cat "$XRAY_FILE")" = old ]
            cmp "$COMPOSE_FILE" "$sandbox/before"
            [ -s "$DATA_DIR/recovery" ]
            echo "PASS: real update workflow rolls back on $FAIL_AT failure" ;;
    esac
done
