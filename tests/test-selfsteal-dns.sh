#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
load_function() {
    local code
    code=$(awk -v name="$1" '
        $0 == name "() {" { found=1 }
        found && /^[a-zA-Z_][a-zA-Z_0-9]*\(\) \{/ && $0 != name "() {" { exit }
        found { print }
    ' "$ROOT/selfsteal.sh")
    [ -n "$code" ] || { echo "Missing function: $1"; exit 1; }
    eval "$code"
}
for fn in load_cloudflare_credentials run_cloudflare_acme update_cloudflare_certificate_files save_cloudflare_settings load_dns_settings issue_cloudflare_certificate setup_dns_auto_renewal renew_dns_ssl_command; do load_function "$fn"; done
export APP_DIR="$sandbox/app" ACME_HOME="$sandbox/acme" CALLS="$sandbox/calls"
export RENEW_SSL_DIR="$APP_DIR/ssl"
export CF_FIXTURE_MODE=ok
ACME_DNS_PROVIDER=cloudflare
ACME_DNS_CREDENTIALS="$sandbox/cloudflare.env"
WEB_SERVER=nginx
CONTAINER_NAME=nginx-selfsteal
FIXTURE_OWNER=0 FIXTURE_PERMISSIONS=600
mkdir -p "$APP_DIR/ssl" "$ACME_HOME"
printf 'CF_Token=fixture-token\nCF_Zone_ID=0123456789abcdef0123456789abcdef\n' > "$ACME_DNS_CREDENTIALS"
stat() {
    case "$1:$2" in
        -c:%u) echo "$FIXTURE_OWNER" ;;
        -c:%a) echo "$FIXTURE_PERMISSIONS" ;;
        *) command stat "$@" ;;
    esac
}
log_info() { :; }
log_success() { :; }
log_error() { echo "$*" >&2; }
log_warning() { :; }
check_acme_installed() { return 0; }
ensure_valid_acme_account() { return 0; }
ensure_cron_installed() { return 0; }
check_running_as_root() { :; }
docker() { printf '%s\n' "$*" >> "$sandbox/docker-calls"; return 1; }
iptables() { echo 'FAIL: DNS-01 touched iptables' >&2; return 1; }
cat > "$ACME_HOME/acme.sh" <<'SH'
#!/usr/bin/env bash
set -eu
[ "$CF_Token" = fixture-token ]
[ "$CF_Zone_ID" = 0123456789abcdef0123456789abcdef ]
printf '%s\n' "$*" >> "$CALLS"
echo 'fixture-token should never reach the console'
if [[ " $* " = *' --renew '* ]] && [ "$CF_FIXTURE_MODE" = partial_renew ]; then
    echo 'incomplete renewal key' > "$RENEW_SSL_DIR/private.key"
    exit 1
fi
[ "$CF_FIXTURE_MODE" != failure ] || exit 1
[ "$CF_FIXTURE_MODE" != notdue ] || exit 2
while [ "$#" -gt 0 ]; do
    case "$1" in
        --key-file) echo 'new key' > "$2"; [ "$CF_FIXTURE_MODE" != partial ] || exit 1; shift ;;
        --fullchain-file) echo 'new certificate' > "$2"; shift ;;
    esac
    shift
done
SH
chmod 755 "$ACME_HOME/acme.sh"

for bad in permissions owner injection missing; do
    FIXTURE_OWNER=0 FIXTURE_PERMISSIONS=600
    case "$bad" in
        permissions) FIXTURE_PERMISSIONS=644 ;;
        owner) FIXTURE_OWNER=1000 ;;
        injection) printf 'CF_Token=$(touch %s/pwned)\nCF_Zone_ID=0123456789abcdef0123456789abcdef\n' "$sandbox" > "$ACME_DNS_CREDENTIALS" ;;
        missing) printf 'CF_Token=fixture-token\n' > "$ACME_DNS_CREDENTIALS" ;;
    esac
    if (load_cloudflare_credentials "$ACME_DNS_CREDENTIALS") > "$sandbox/result" 2>&1; then echo "FAIL: accepted $bad credentials"; exit 1; fi
    [ ! -e "$sandbox/pwned" ]
    ! grep -q fixture-token "$sandbox/result"
done
FIXTURE_OWNER=0 FIXTURE_PERMISSIONS=600
printf 'CF_Token=fixture-token\nCF_Zone_ID=0123456789abcdef0123456789abcdef\n' > "$ACME_DNS_CREDENTIALS"
echo 'PASS: credentials require a private root-owned file and never execute file contents'
cp "$ACME_DNS_CREDENTIALS" "$APP_DIR/unsafe.env"
if (load_cloudflare_credentials "$APP_DIR/unsafe.env") > "$sandbox/result" 2>&1; then echo 'FAIL: accepted credentials in the installation tree'; exit 1; fi
echo 'PASS: credentials cannot be placed in the web server installation tree'

issue_cloudflare_certificate reality.example.com "$APP_DIR/ssl" true > "$sandbox/result" 2>&1
grep -q -- '--dns dns_cf' "$CALLS"
grep -q -- '--install-cert --ecc' "$CALLS"
! grep -q -- '--standalone\|--alpn\|--tlsport' "$CALLS"
! grep -q fixture-token "$sandbox/result"
[ "$(cat "$APP_DIR/ssl/private.key")" = 'new key' ]
[ "$(cat "$APP_DIR/ssl/fullchain.crt")" = 'new certificate' ]
[ "$(cat "$APP_DIR/.dns01-credentials")" = "$ACME_DNS_CREDENTIALS" ]
ACME_DNS_PROVIDER='' ACME_DNS_CREDENTIALS=''
load_dns_settings
[ "$ACME_DNS_PROVIDER" = cloudflare ] && [ "$ACME_DNS_CREDENTIALS" = "$sandbox/cloudflare.env" ]
echo 'PASS: DNS-01 issues through Cloudflare without standalone ports and remembers the credentials path'

printf 'old key\n' > "$APP_DIR/ssl/private.key"
printf 'old certificate\n' > "$APP_DIR/ssl/fullchain.crt"
CF_FIXTURE_MODE=partial
if issue_cloudflare_certificate reality.example.com "$APP_DIR/ssl" > "$sandbox/result" 2>&1; then echo 'FAIL: accepted partial installation'; exit 1; fi
[ "$(cat "$APP_DIR/ssl/private.key")" = 'old key' ]
[ "$(cat "$APP_DIR/ssl/fullchain.crt")" = 'old certificate' ]
! grep -q fixture-token "$sandbox/result"
CF_FIXTURE_MODE=ok
echo 'PASS: failed certificate installation restores the previous key and certificate without exposing credentials'

CF_FIXTURE_MODE=partial
if issue_cloudflare_certificate reality.example.com "$APP_DIR/empty-ssl" > "$sandbox/result" 2>&1; then echo 'FAIL: accepted incomplete first issuance'; exit 1; fi
[ ! -e "$APP_DIR/empty-ssl/private.key" ] && [ ! -e "$APP_DIR/empty-ssl/fullchain.crt" ]
cp() {
    case "${2:-}" in */.dns01-backup.*/private.key) return 1 ;; esac
    command cp "$@"
}
if issue_cloudflare_certificate reality.example.com "$APP_DIR/ssl" > "$sandbox/result" 2>&1; then echo 'FAIL: accepted recovery failure'; exit 1; fi
grep -q 'backup kept at' "$sandbox/result"
recovery=$(find "$APP_DIR/ssl" -maxdepth 1 -type d -name '.dns01-backup.*' -print -quit)
[ "$(cat "$recovery/private.key")" = 'old key' ]
unset -f cp
cp "$recovery/private.key" "$APP_DIR/ssl/private.key"
CF_FIXTURE_MODE=ok
echo 'PASS: incomplete first issuance leaves no partial pair; failed recovery retains the original key backup'

export FIXTURE_OWNER FIXTURE_PERMISSIONS
export -f stat
printf '0 1 * * * /root/another-job\n' > "$sandbox/crontab"
crontab() {
    if [ "$1" = -l ]; then cat "$sandbox/crontab"; else cat > "$sandbox/crontab"; fi
}
setup_dns_auto_renewal reality.example.com
setup_dns_auto_renewal reality.example.com
if [ "$(uname -s)" = Linux ]; then
    [ "$(command stat -c %a "$ACME_HOME")" = 700 ]
    [ "$(command stat -c %a "$ACME_HOME/selfsteal-dns.log")" = 600 ]
    [ "$(command stat -c %a "$APP_DIR/acme-renew.sh")" = 700 ]
fi
[ "$(grep -c 'acme-renew.sh' "$sandbox/crontab")" = 1 ]
grep -q '/root/another-job' "$sandbox/crontab"
! grep -q fixture-token "$APP_DIR/acme-renew.sh"
! grep -q iptables "$APP_DIR/acme-renew.sh"
CF_FIXTURE_MODE=notdue bash "$APP_DIR/acme-renew.sh" > "$sandbox/result" 2>&1
! grep -q fixture-token "$sandbox/result"
if CF_FIXTURE_MODE=partial_renew bash "$APP_DIR/acme-renew.sh" > "$sandbox/result" 2>&1; then echo 'FAIL: accepted partial automatic renewal'; exit 1; fi
[ "$(cat "$APP_DIR/ssl/private.key")" = 'old key' ]
[ "$(cat "$APP_DIR/ssl/fullchain.crt")" = 'old certificate' ]
echo 'PASS: daily DNS renewal accepts not-due status, preserves other cron jobs and never changes firewall rules'
echo 'PASS: partial automatic renewal restores the previously served certificate pair'

printf 'SELF_STEAL_DOMAIN=reality.example.com\n' > "$APP_DIR/.env"
CF_FIXTURE_MODE=notdue
renew_dns_ssl_command > "$sandbox/result" 2>&1
CF_FIXTURE_MODE=ok
renew_dns_ssl_command true > "$sandbox/result" 2>&1
grep -q -- '--renew --ecc -d reality.example.com --force' "$CALLS"
! grep -q -- 'compose stop\|iptables\|--tlsport' "$CALLS"
echo 'PASS: manual renewal and forced reissue use DNS without stopping the web server'

WEB_SERVER=caddy
issue_cloudflare_certificate reality.example.com "$APP_DIR/ssl" > "$sandbox/result" 2>&1
grep -q 'docker restart caddy-selfsteal' "$CALLS"
for fn in create_caddy_config create_nginx_config; do load_function "$fn"; done
WHITE='' GRAY='' GREEN='' YELLOW='' NC='' CYAN='' NODE_IP=127.0.0.1 DEBUG_MODE=false FORCE_MODE=false
HTML_DIR="$APP_DIR/html" CADDY_VERSION=2.11.4 NGINX_VERSION=1.30.7-alpine
VOLUME_PREFIX=caddy CONTAINER_NAME=caddy-selfsteal
MANUAL_SSL_CERT="$APP_DIR/ssl/fullchain.crt" MANUAL_SSL_KEY="$APP_DIR/ssl/private.key"
create_dir_safe() { mkdir -p "$1"; }
show_ssl_certificate_info() { :; }
create_caddy_config reality.example.com 9443 > "$sandbox/result" 2>&1
grep -q 'tls /etc/caddy/ssl/fullchain.crt /etc/caddy/ssl/private.key' "$APP_DIR/Caddyfile"
grep -q './ssl:/etc/caddy/ssl:ro' "$APP_DIR/docker-compose.yml"
! grep -q fixture-token "$APP_DIR/.env" "$APP_DIR/docker-compose.yml" "$APP_DIR/Caddyfile"
WEB_SERVER=nginx USE_SOCKET=true SOCKET_PATH=/dev/shm/nginx.sock
CONTAINER_NAME=nginx-selfsteal VOLUME_PREFIX=nginx
create_nginx_config reality.example.com 9443 > "$sandbox/result" 2>&1
grep -q 'ssl_certificate.*fullchain.crt' "$APP_DIR/conf.d/selfsteal.conf"
! grep -q fixture-token "$APP_DIR/.env" "$APP_DIR/docker-compose.yml" "$APP_DIR/conf.d/selfsteal.conf"
echo 'PASS: both Caddy and Nginx use issued certificates without embedding Cloudflare credentials in their configuration'

for fn in issue_ssl_certificate renew_ssl_command reissue_cert_command; do load_function "$fn"; done
issue_ssl_certificate reality.example.com "$APP_DIR/ssl" true > "$sandbox/result" 2>&1
renew_ssl_command > "$sandbox/result" 2>&1
reissue_cert_command > "$sandbox/result" 2>&1
[ ! -s "$sandbox/docker-calls" ]
! grep -q fixture-token "$sandbox/result"
echo 'PASS: existing issuance, renewal and reissue entrypoints route to DNS-01 without stopping Nginx'

bash "$ROOT/selfsteal.sh" --help > "$sandbox/help"
grep -q -- '--dns-cloudflare' "$sandbox/help"
grep -q -- '--dns-credentials' "$sandbox/help"
if bash "$ROOT/selfsteal.sh" --dns-credentials > "$sandbox/result" 2>&1; then echo 'FAIL: accepted missing credentials argument'; exit 1; fi
echo 'PASS: CLI documents DNS options and rejects a missing credentials path'

load_function configure_dns01_command
clear() { :; }
rm "$APP_DIR/.dns01-credentials"
ACME_DNS_PROVIDER='' ACME_DNS_CREDENTIALS="$sandbox/cloudflare.env"
rm "$ACME_DNS_CREDENTIALS"
configure_dns01_command <<< "$(printf 'fixture-token\n0123456789abcdef0123456789abcdef\ny\n')" > "$sandbox/menu" 2>&1
[ "$ACME_DNS_PROVIDER" = cloudflare ]
[ "$ACME_DNS_CREDENTIALS" = "$sandbox/cloudflare.env" ]
grep -qx 'CF_Token=fixture-token' "$ACME_DNS_CREDENTIALS"
grep -qx 'CF_Zone_ID=0123456789abcdef0123456789abcdef' "$ACME_DNS_CREDENTIALS"
# Windows Git Bash does not expose POSIX permissions; Linux CI checks the real mode.
if [ "$(uname -s)" = Linux ]; then [ "$(command stat -c %a "$ACME_DNS_CREDENTIALS")" = 600 ]; fi
! grep -q fixture-token "$sandbox/menu"
before=$(wc -l < "$CALLS")
cp "$ACME_DNS_CREDENTIALS" "$sandbox/credentials-before"
if configure_dns01_command <<< $'replacement-token\ninvalid-zone\ny' > "$sandbox/menu" 2>&1; then echo 'FAIL: accepted invalid interactive credentials'; exit 1; fi
cmp "$sandbox/credentials-before" "$ACME_DNS_CREDENTIALS"
configure_dns01_command <<< $'replacement-token\n0123456789abcdef0123456789abcdef\nn' > "$sandbox/menu" 2>&1
cmp "$sandbox/credentials-before" "$ACME_DNS_CREDENTIALS"
configure_dns01_command <<< q > "$sandbox/menu" 2>&1
[ "$(wc -l < "$CALLS")" = "$before" ]
configure_dns01_command <<< $'\ny' > "$sandbox/menu" 2>&1
echo 'PASS: interactive DNS setup creates private credentials, preserves them on invalid input/cancellation, and supports reuse'

eval "$(awk '/^main_menu\(\) \{/ { inside=1 } inside { print } inside && /^}$/ { exit }' "$ROOT/selfsteal.sh")"
report_nginx_version() { :; }
check_for_updates_silent() { :; }
print_menu_ssl_line() { return 0; }
docker() { [ "$*" != 'compose ps --format {{.State}}' ] || echo running; }
SCRIPT_VERSION=test BLUE='' RED=''
(main_menu <<< 0) > "$sandbox/menu" 2>&1
grep -q '15).*Cloudflare DNS-01' "$sandbox/menu"
grep -q 'DNS-01:.*Cloudflare' "$sandbox/menu"
WEB_SERVER=caddy
(main_menu <<< 0) > "$sandbox/menu" 2>&1
! grep -q '15).*Cloudflare DNS-01' "$sandbox/menu"
echo 'PASS: the Nginx menu exposes DNS-01 configuration and active status'
