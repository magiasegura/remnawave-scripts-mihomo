#!/usr/bin/env bash
# Exercise script delivery without network access or writing to /usr/local/bin.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
load_function() {
    local code
    code=$(awk -v name="$1" '$0 == name "() {" { inside=1 } inside { print } inside && $0 == "}" { exit }' "$ROOT/remnanode.sh")
    [ -n "$code" ] || exit 1
    code=${code//\/usr\/local\/bin/$sandbox}
    eval "$code"
}
eval "$(sed -n '/^SCRIPT_VERSION=/p; /^SCRIPT_REPO=/p; /^SCRIPT_REF=/p; /^SCRIPT_FILE=/p; /^SCRIPT_URL=/p; /^SCRIPT_URL_OVERRIDDEN=/p' "$ROOT/remnanode.sh")"
[ "$SCRIPT_REPO" = magiasegura/remnawave-scripts-mihomo ]
[ "$SCRIPT_REF" = feature/jolymmiles-xray ]
for fn in version_gte script_mirror_urls script_download_is_valid fetch_script_file script_file_version ensure_latest_script; do
    load_function "$fn"
done
[[ "$SCRIPT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-jm\.[0-9]+$ ]]
version_gte 4.6.2-jm.10 4.6.2-jm.2
! version_gte 4.6.2-jm.2 4.6.2-jm.10
version_gte 4.6.3-jm.1 4.6.2-jm.10
echo 'PASS: fork releases sort by upstream version and numeric fork revision'
APP_NAME=test-node
SCRIPT_ORIGINAL_ARGS=(menu --name 'test node')
colorized_echo() { :; }
install() { cp "$3" "$4"; }
exec() { printf '%s\n' "$@" > "$sandbox/exec"; }
curl() {
    printf '%s\n' "$*" >> "$sandbox/requests"
    [ "$mode" != offline ] || return 22
    local out=""
    while [ "$#" -gt 0 ]; do
        if [ "$1" = -o ]; then out="$2"; break; fi
        shift
    done
    if [ "$mode" = invalid ]; then
        echo '<html>not a script</html>' > "$out"
    else
        sed "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$remote_version\"/" "$ROOT/remnanode.sh" > "$out"
    fi
}
mode=valid
remote_version="$SCRIPT_VERSION"
ensure_latest_script
[ ! -e "$sandbox/$APP_NAME" ]
grep -q 'raw.githubusercontent.com/magiasegura/remnawave-scripts-mihomo/feature/jolymmiles-xray/remnanode.sh' "$sandbox/requests"
echo 'PASS: current version stays installed and checks our repository'
next_version="${SCRIPT_VERSION%.*}.$((${SCRIPT_VERSION##*.} + 1))"
remote_version="$next_version"
ensure_latest_script
[ "$(script_file_version "$sandbox/$APP_NAME")" = "$next_version" ]
printf '%s\n' "$sandbox/$APP_NAME" "${SCRIPT_ORIGINAL_ARGS[@]}" > "$sandbox/expected-exec"
cmp "$sandbox/expected-exec" "$sandbox/exec"
[ "$REMNANODE_SELFUPDATE_DONE" = 1 ]
echo 'PASS: newer version installs and preserves the original arguments'
rm "$sandbox/requests"
ensure_latest_script
[ ! -e "$sandbox/requests" ]
unset REMNANODE_SELFUPDATE_DONE
for mode in valid offline invalid; do
    remote_version=1.0.0
    ensure_latest_script
    [ "$(script_file_version "$sandbox/$APP_NAME")" = "$next_version" ]
done
echo 'PASS: older versions, offline mirrors and invalid downloads preserve the script'
SCRIPT_URL_OVERRIDDEN=true
SCRIPT_URL=https://example.test/custom.sh
[ "$(script_mirror_urls)" = "$SCRIPT_URL" ]
rm "$sandbox/requests"
ensure_latest_script
[ ! -e "$sandbox/requests" ]
echo 'PASS: custom sources and the re-exec guard skip automatic replacement'
