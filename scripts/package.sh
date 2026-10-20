#!/usr/bin/env bash
# Create the player download archive and checksums from the current sources.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/core.sh
source "$root/lib/core.sh"
bash "$root/scripts/build.sh"
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
folder=morrowind-easy-steamdeck
mkdir -p "$stage/$folder/assets"
cp "$root/dist/install-morrowind.sh" "$root/LICENSE" "$root/README.md" "$root/CHANGELOG.md" "$root/CONTRIBUTING.md" "$stage/$folder/"
cp -R "$root/docs" "$stage/$folder/docs"
cp "$root/assets/banner.svg" "$stage/$folder/assets/banner.svg"
chmod 755 "$stage/$folder/install-morrowind.sh"
archive="morrowind-easy-steamdeck-$MES_VERSION.tar.gz"
# Stable metadata makes the archive reproducible with GNU tar and gzip.
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' \
    -czf "$root/dist/$archive" -C "$stage" "$folder"
(cd "$root/dist" && sha256sum install-morrowind.sh "$archive" > SHA256SUMS.txt)
printf 'Packaged %s\n' "$root/dist/$archive"
