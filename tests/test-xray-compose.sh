#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export DATA_DIR="$sandbox/data" COMPOSE_FILE="$sandbox/docker-compose.yml" APP_NAME=remnanode
mkdir -p "$DATA_DIR"
for script in remnanode.sh remnanode-xray-update.sh; do
    eval "$(sed -n '/^# BEGIN XRAY SOURCE/,/^# END XRAY SOURCE/p' "$ROOT/$script")"
    declare -f xray_edit_compose >/dev/null || { echo 'FAIL: service-scoped Compose editor missing'; exit 1; }
    cat > "$COMPOSE_FILE" <<'YAML'
services:
  sidecar:
    image: example/sidecar
    volumes:
      - ./geoip.dat:/data/geoip.dat
  remnanode:
    image: remnawave/node:latest
    restart: unless-stopped
YAML
    xray_edit_compose install
    [ "$(grep -c '/usr/local/bin/xray' "$COMPOSE_FILE")" -eq 1 ]
    grep -q './geoip.dat:/data/geoip.dat' "$COMPOSE_FILE"
    xray_edit_compose install
    [ "$(grep -c '/usr/local/bin/xray' "$COMPOSE_FILE")" -eq 1 ]
    echo "PASS: $script inserts one mount regardless of restart policy and preserves other services"
    xray_edit_compose builtin
    ! grep -q '/usr/local/bin/xray' "$COMPOSE_FILE"
    grep -q './geoip.dat:/data/geoip.dat' "$COMPOSE_FILE"
    echo "PASS: $script builtin restore only removes mounts from the node service"
    cat > "$COMPOSE_FILE" <<'YAML'
services:
  custom:
    container_name: remnanode
    image: custom/node
    volumes:
      - ./logs:/var/log/node
      - /old/core:/usr/local/bin/xray:ro
YAML
    xray_edit_compose install
    [ "$(grep -c '/usr/local/bin/xray' "$COMPOSE_FILE")" -eq 1 ]
    grep -q './logs:/var/log/node' "$COMPOSE_FILE"
    echo "PASS: $script supports custom service names and replaces old mounts"
    for kind in flow long ambiguous quoted anchored; do
        case "$kind" in
            quoted) printf 'services:\n  sidecar:\n    image: example/sidecar\n  "remnanode":\n    image: remnawave/node:latest\n' > "$COMPOSE_FILE" ;;
            anchored) printf 'services:\n  sidecar:\n    image: example/sidecar\n  remnanode: &node\n    image: remnawave/node:latest\n' > "$COMPOSE_FILE" ;;
            flow) printf 'services:\n  remnanode:\n    image: remnawave/node:latest\n    volumes: ["./a:/b"]\n' > "$COMPOSE_FILE" ;;
            long) printf 'services:\n  remnanode:\n    image: remnawave/node:latest\n    volumes:\n      - type: bind\n        source: ./a\n        target: /b\n' > "$COMPOSE_FILE" ;;
            ambiguous) printf 'services:\n  one:\n    image: remnawave/node:latest\n  two:\n    image: remnawave/node:latest\n' > "$COMPOSE_FILE" ;;
        esac
        cp "$COMPOSE_FILE" "$sandbox/before"
        if xray_edit_compose install; then echo "FAIL: accepted $kind"; exit 1; fi
        cmp "$COMPOSE_FILE" "$sandbox/before"
        echo "PASS: $script rejects $kind without changing Compose"
    done
done
