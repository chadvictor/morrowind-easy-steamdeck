#!/usr/bin/env bash
# Reproducible, self-contained shell release. Run from any directory.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
out="$root/dist"
mkdir -p -- "$out"
helper="$out/libmes-controller-text.so"
[[ -s $helper ]] || { printf 'Build the Linux helper first: bash scripts/build-native.sh\n' >&2; exit 1; }
# Require a little-endian x86_64 ELF shared library, never a host Windows binary.
[[ $(od -An -tx1 -N7 "$helper" | tr -d ' \n') == 7f454c46020101 &&
   $(od -An -tx1 -j16 -N4 "$helper" | tr -d ' \n') == 03003e00 ]] || {
    printf 'The controller helper must be a Linux x86_64 ELF shared library.\n' >&2; exit 1;
}
target="$out/install-morrowind.sh"
cat > "$target" <<'HEADER'
#!/usr/bin/env bash
# Morrowind Easy Steam Deck — https://github.com/chadvictor/morrowind-easy-steamdeck
# MIT license. Source, tests, provenance and license are available in the repository.
set -euo pipefail
umask 077
MES_SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && printf '%s/%s\n' "$PWD" "$(basename -- "${BASH_SOURCE[0]}")")
if [[ $# == 0 && ! -t 0 ]]; then
    if command -v konsole >/dev/null; then
        exec konsole --hold -e bash "$MES_SOURCE" "$@"
    fi
    printf 'Open a terminal in this folder and run: bash install-morrowind.sh\n' >&2
    exit 1
fi
MES_BUNDLE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mes-bundle.XXXXXXXX")
MES_LOCK=''
cleanup() {
    if [[ -n $MES_LOCK && -f $MES_LOCK/pid ]] && [[ $(cat -- "$MES_LOCK/pid") == "$$" ]]; then
        rm -f -- "$MES_LOCK/pid"
        rmdir -- "$MES_LOCK" 2>/dev/null || true
    fi
    case $MES_BUNDLE_TMP in "${TMPDIR:-/tmp}"/mes-bundle.*) rm -rf -- "$MES_BUNDLE_TMP";; esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p -- "$MES_BUNDLE_TMP/lib" "$MES_BUNDLE_TMP/assets" "$MES_BUNDLE_TMP/src"
HEADER
printf '\n' >> "$target"
sed 's/^/# /' "$root/LICENSE" >> "$target"
for file in lib/core.sh lib/steam.sh lib/steam-vdf.awk lib/translation.sh lib/ptbr-fallbacks.awk assets/input_v3.xml assets/ptbr-masters.sha256 assets/ptbr-files.sha256 assets/keyboard-files.sha256 assets/keyboard/mes_keyboard.omwscripts assets/keyboard/scripts/mes/keyboard.lua assets/keyboard/scripts/mes/keyboard_layout.lua src/launch.sh src/main.sh; do
    # Keep the generated script's variable literal until the bundle runs.
    # shellcheck disable=SC2016
    printf '\nmkdir -p -- "$MES_BUNDLE_TMP/%s"\ncat > "$MES_BUNDLE_TMP/%s" <<\x27MES_EMBEDDED_FILE_EOF\x27\n' "$(dirname -- "$file")" "$file" >> "$target"
    if grep -qx 'MES_EMBEDDED_FILE_EOF' "$root/$file"; then printf 'Heredoc delimiter collision: %s\n' "$file" >&2; exit 1; fi
    cat -- "$root/$file" >> "$target"
    printf '\nMES_EMBEDDED_FILE_EOF\n' >> "$target"
done
{
cat <<'NATIVE_HEADER'

command -v base64 >/dev/null || { printf 'Missing base64 (included with stock SteamOS).\n' >&2; exit 1; }
base64 --decode > "$MES_BUNDLE_TMP/assets/libmes-controller-text.so" <<'MES_NATIVE_BASE64_EOF'
NATIVE_HEADER
base64 "$helper"
printf '\nMES_NATIVE_BASE64_EOF\n'
cat <<'NATIVE_SUM_HEADER'
cat > "$MES_BUNDLE_TMP/assets/libmes-controller-text.so.sha256" <<'MES_NATIVE_SHA_EOF'
NATIVE_SUM_HEADER
printf '%s  libmes-controller-text.so\n' "$(sha256sum < "$helper" | awk '{print $1}')"
printf 'MES_NATIVE_SHA_EOF\n'
cat <<'FOOTER'
MES_LIB_DIR="$MES_BUNDLE_TMP/lib"
# shellcheck source=/dev/null
source "$MES_BUNDLE_TMP/src/main.sh"
FOOTER
} >> "$target"
chmod +x "$target"
bash -n "$target"
(cd -- "$out" && sha256sum install-morrowind.sh > SHA256SUMS.txt)
printf 'Built %s\n' "$target"
