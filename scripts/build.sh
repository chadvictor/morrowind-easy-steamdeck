#!/usr/bin/env bash
# Reproducible, self-contained shell release. Run from any directory.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
out="$root/dist"
mkdir -p -- "$out"
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
for file in lib/core.sh lib/steam.sh lib/steam-vdf.awk assets/input_v3.xml src/launch.sh src/main.sh; do
    # Keep the generated script's variable literal until the bundle runs.
    # shellcheck disable=SC2016
    printf '\ncat > "$MES_BUNDLE_TMP/%s" <<\x27MES_EMBEDDED_FILE_EOF\x27\n' "$file" >> "$target"
    if grep -qx 'MES_EMBEDDED_FILE_EOF' "$root/$file"; then printf 'Heredoc delimiter collision: %s\n' "$file" >&2; exit 1; fi
    cat -- "$root/$file" >> "$target"
    printf '\nMES_EMBEDDED_FILE_EOF\n' >> "$target"
done
cat >> "$target" <<'FOOTER'
MES_LIB_DIR="$MES_BUNDLE_TMP/lib"
# shellcheck source=/dev/null
source "$MES_BUNDLE_TMP/src/main.sh"
FOOTER
chmod +x "$target"
bash -n "$target"
(cd -- "$out" && sha256sum install-morrowind.sh > SHA256SUMS.txt)
printf 'Built %s\n' "$target"
