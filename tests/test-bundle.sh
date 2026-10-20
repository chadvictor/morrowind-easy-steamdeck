#!/usr/bin/env bash
# Exercise the generated player's extraction, not just the source-tree assets.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
installer="$root/dist/install-morrowind.sh"
[[ -s $installer ]] || { printf 'Build the installer first.\n' >&2; exit 1; }
# Replace only the final menu dispatch; keep the actual extraction and cleanup.
# shellcheck disable=SC2016
[[ $(tail -n 1 "$installer") == 'source "$MES_BUNDLE_TMP/src/main.sh"' ]] || {
    printf 'Unexpected installer footer; update the bundle test.\n' >&2; exit 1;
}
temp=$(mktemp -d "$root/dist/bundle-test.XXXXXXXX")
cleanup_test() {
    case $temp in "$root/dist/bundle-test."*) rm -rf -- "$temp";; esac
}
trap cleanup_test EXIT
head -n -1 "$installer" > "$temp/probe.sh"
cat >> "$temp/probe.sh" <<'CHECKS'
# shellcheck source=/dev/null
source "$MES_LIB_DIR/core.sh"
mkdir -p -- "$MES_BUNDLE_TMP/profile"
unset MES_NATIVE_LIBRARY
mes_copy_controller_helper "$MES_BUNDLE_TMP/profile"
(cd -- "$MES_BUNDLE_TMP/profile" && sha256sum --check controller-helper.sha256)
(cd -- "$MES_BUNDLE_TMP/profile/keyboard" && sha256sum --check ../keyboard-files.sha256)
cmp -- "$MES_BUNDLE_TMP/assets/keyboard/mes_keyboard.omwscripts" "$MES_BUNDLE_TMP/profile/keyboard/mes_keyboard.omwscripts"
printf 'PASS: generated installer extracts and installs byte-exact native/Lua assets\n'
CHECKS
# An argument prevents the graphical Konsole relaunch in non-interactive tests.
bash "$temp/probe.sh" --help
