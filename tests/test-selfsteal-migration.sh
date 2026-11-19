#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
APP_NAME=selfsteal APP_DIR="$sandbox/app" SELFSTEAL_SOURCE="$ROOT/selfsteal.sh"
GRAY='' NC=''
mkdir -p "$APP_DIR/html" "$APP_DIR/ssl" "$sandbox/bin"
printf 'original CLI\n' > "$sandbox/bin/selfsteal"
printf 'existing domain settings\n' > "$APP_DIR/.env"
printf 'existing Compose settings\n' > "$APP_DIR/docker-compose.yml"
printf 'existing Nginx settings\n' > "$APP_DIR/nginx.conf"
printf 'custom website\n' > "$APP_DIR/html/index.html"
printf 'existing certificate\n' > "$APP_DIR/ssl/fullchain.crt"
before=$(find "$APP_DIR" -type f -exec sha256sum {} \; | sort)
log_info() { :; }
log_success() { :; }
log_error() { echo "$*" >&2; }
log_warning() { :; }
curl() { echo 'FAIL: local migration attempted a download' >&2; return 1; }
docker() { echo docker > "$sandbox/side-effect"; return 1; }
crontab() { echo cron > "$sandbox/side-effect"; return 1; }
code=$(awk '
    /^install_management_script\(\) \{/ { found=1 }
    found && /^[a-zA-Z_][a-zA-Z_0-9]*\(\) \{/ && !/^install_management_script\(/ { exit }
    found { print }
' "$ROOT/selfsteal.sh")
[ -n "$code" ]
code=${code//\$0/\$SELFSTEAL_SOURCE}
code=${code//\/usr\/local\/bin/$sandbox/bin}
eval "$code"
install_management_script > "$sandbox/result" 2>&1
cmp "$ROOT/selfsteal.sh" "$sandbox/bin/selfsteal"
[ "$(cat "$sandbox"/bin/selfsteal.backup.*)" = 'original CLI' ]
[ "$before" = "$(find "$APP_DIR" -type f -exec sha256sum {} \; | sort)" ]
[ ! -e "$sandbox/side-effect" ]
echo 'PASS: migration replaces only the CLI, backs up the original, and preserves website/configuration/certificates'

installed=$(sha256sum "$sandbox/bin/selfsteal")
SELFSTEAL_SOURCE="$sandbox/invalid-script"
printf '<html>download error</html>\n' > "$SELFSTEAL_SOURCE"
if install_management_script > "$sandbox/result" 2>&1; then echo 'FAIL: migration accepted an invalid script'; exit 1; fi
[ "$installed" = "$(sha256sum "$sandbox/bin/selfsteal")" ]
[ "$before" = "$(find "$APP_DIR" -type f -exec sha256sum {} \; | sort)" ]
echo 'PASS: an invalid CLI leaves the installed command and all settings untouched'
