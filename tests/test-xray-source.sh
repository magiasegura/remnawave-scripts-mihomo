#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for script in remnanode.sh remnanode-xray-update.sh; do
    code=$(sed -n '/^# BEGIN XRAY SOURCE/,/^# END XRAY SOURCE/p' "$ROOT/$script")
    [ -n "$code" ] || { echo "FAIL: missing source support in $script"; exit 1; }
    eval "$code"
    health_function=$(declare -f xray_check_running)
    sandbox=$(mktemp -d)
    trap 'rm -rf "$sandbox"' EXIT
    DATA_DIR="$sandbox/data"
    COMPOSE_FILE="$sandbox/docker-compose.yml"
    mkdir -p "$DATA_DIR"
    xray_load_source
    [ "$XRAY_REPO" = XTLS/Xray-core ]
    printf 'Jolymmiles/Xray-core\n' > "$DATA_DIR/xray-source"
    xray_load_source
    [ "$XRAY_REPO" = Jolymmiles/Xray-core ]
    printf 'evil/repo\n' > "$DATA_DIR/xray-source"
    if xray_load_source; then echo 'FAIL: accepted untrusted source'; exit 1; fi
    printf 'XTLS/Xray-core\n' > "$DATA_DIR/xray-source"
    xray_load_source
    printf 'old binary\n' > "$DATA_DIR/xray"
    printf 'old geo\n' > "$DATA_DIR/geoip.dat"
    printf 'old compose\n' > "$COMPOSE_FILE"
    xray_backup
    saved="$XRAY_TRANSACTION_BACKUP"
    printf 'new binary\n' > "$DATA_DIR/xray"
    printf 'new geo\n' > "$DATA_DIR/geosite.dat"
    printf 'new compose\n' > "$COMPOSE_FILE"
    xray_restore "$saved"
    [ "$(cat "$DATA_DIR/xray")" = 'old binary' ]
    [ "$(cat "$DATA_DIR/geoip.dat")" = 'old geo' ]
    [ ! -e "$DATA_DIR/geosite.dat" ]
    [ "$(cat "$COMPOSE_FILE")" = 'old compose' ]
    echo "PASS: $script source validation and full snapshot restore"
    # Only downloads and the container lifecycle are stubbed. File staging,
    # executable validation, backups and EXIT recovery are production functions.
    ARCH=64
    APP_NAME=test-node
    mode=good
    curl() {
        printf '%s\n' "$*" >> "$sandbox/requests"
        [ "$mode" != network ] || return 22
        if [[ "$*" = *releases/tags/* ]]; then
            case "$mode" in
                api_error) echo '{"message":"rate limited"}' ;;
                *) echo '{"tag_name":"v1.2.3"}' ;;
            esac
        else
            local arg target=''
            while [ "$#" -gt 0 ]; do
                arg="$1"; shift
                if [ "$arg" = -o ]; then target="$1"; shift; fi
            done
            printf 'fixture archive\n' > "$target"
        fi
    }
    unzip() {
        [ "$mode" != corrupt ] || return 9
        case "$1:$3" in
            -Z1:*) printf 'xray\ngeoip.dat\n' ;;
            -p:xray)
                if [ "$mode" = bad_binary ]; then
                    printf '#!/usr/bin/env bash\nexit 1\n'
                else
                    printf '#!/usr/bin/env bash\necho "Xray 1.2.3"\n'
                fi ;;
            -p:geoip.dat) echo 'new geo' ;;
            *) return 1 ;;
        esac
    }
    xray_restart() { echo restart >> "$sandbox/restarts"; }
    xray_check_running() { :; }
    [ "$(xray_validate_version v1.2.3)" = valid ]
    mode=api_error
    [ "$(xray_validate_version v1.2.3)" = invalid ]
    mode=network
    [ "$(xray_validate_version v1.2.3)" = invalid ]
    [ "$(xray_validate_version '../evil')" = invalid ]
    echo "PASS: $script validates exact release tag and rejects API/network failures"
    for mode in network corrupt bad_binary; do
        # Invoke in a separate shell so the assertion's if cannot disable errexit.
        export DATA_DIR COMPOSE_FILE XRAY_REPO ARCH APP_NAME sandbox mode
        export -f curl unzip xray_restart xray_check_running
        functions=$(declare -f xray_transaction xray_install_release xray_backup xray_restore xray_load_source xray_valid_tag xray_finish_transaction)
        if bash -ec "$functions; xray_transaction xray_install_release v1.2.3"; then
            echo "FAIL: accepted $mode"; exit 1
        fi
        [ "$(cat "$DATA_DIR/xray")" = 'old binary' ]
        [ "$(cat "$DATA_DIR/xray-source")" = XTLS/Xray-core ]
        [ "$(cat "$COMPOSE_FILE")" = 'old compose' ]
        [ -z "$(find "$DATA_DIR" -maxdepth 1 -type d -name '.xray-stage.*' -print)" ]
        echo "PASS: $script $mode leaves installed files unchanged and cleans staging"
    done
    mode=good
    XRAY_REPO=Jolymmiles/Xray-core
    export mode XRAY_REPO
    bash -ec "$functions; xray_transaction xray_install_release v1.2.3"
    [ "$(cat "$DATA_DIR/xray-source")" = Jolymmiles/Xray-core ]
    [ "$(cat "$DATA_DIR/xray-version")" = v1.2.3 ]
    [ "$(cat "$DATA_DIR/geoip.dat")" = 'new geo' ]
    grep -q 'Jolymmiles/Xray-core/releases/download/v1.2.3/Xray-linux-64.zip' "$sandbox/requests"
    [ "$("$DATA_DIR/xray" -version)" = 'Xray 1.2.3' ]
    echo "PASS: $script installs selected source, executable, geodata and version"
    xray_rollback
    [ "$(cat "$DATA_DIR/xray-source")" = XTLS/Xray-core ]
    [ "$(cat "$DATA_DIR/xray")" = 'old binary' ]
    [ ! -e "$DATA_DIR/xray-version" ]
    xray_rollback
    [ "$(cat "$DATA_DIR/xray-source")" = Jolymmiles/Xray-core ]
    [ "$(cat "$DATA_DIR/xray-version")" = v1.2.3 ]
    echo "PASS: $script rollback restores prior source and can undo the rollback"
    # Simulate a failure after both binary replacement and Compose mutation.
    XRAY_REPO=XTLS/Xray-core
    export XRAY_REPO
    if bash -ec "$functions; fail_update() { xray_install_release v1.2.3; echo broken > \"\$COMPOSE_FILE\"; exit 17; }; xray_transaction fail_update"; then
        echo 'FAIL: update unexpectedly succeeded'; exit 1
    fi
    [ "$(cat "$DATA_DIR/xray-source")" = Jolymmiles/Xray-core ]
    [ "$(cat "$COMPOSE_FILE")" = 'old compose' ]
    [ -s "$sandbox/restarts" ]
    echo "PASS: $script post-install failure restores files, source and Compose, restarts node"
    xray_rollback
    echo "PASS: $script manual rollback uses last complete snapshot"
    before=$(wc -l < "$sandbox/requests")
    if bash -ec "$functions; exec 8> \"\$DATA_DIR/.xray-update.lock\"; flock -n 8; xray_transaction xray_install_release v1.2.3"; then
        echo 'FAIL: concurrent operation acquired lock'; exit 1
    fi
    [ "$(wc -l < "$sandbox/requests")" = "$before" ]
    echo "PASS: $script rejects concurrent operation before download or mutation"
    eval "$health_function"
    sleep() { :; }
    docker() {
        [ "$healthy" = true ] || return 1
        case "$*" in
            *'.State.Running'*) echo 'true false healthy' ;;
            *'.Mounts'*) echo "$DATA_DIR/xray" ;;
            exec*) sha256sum "$DATA_DIR/xray" ;;
            *) return 1 ;;
        esac
    }
    healthy=true
    xray_check_running
    healthy=false
    if xray_check_running; then echo 'FAIL: unhealthy container accepted'; exit 1; fi
    echo "PASS: $script container smoke check detects success and persistent failure"
    rm -rf "$sandbox"
done
