#!/usr/bin/env bash
# Build on Linux. SDL2 is a build/test dependency, never linked into the helper.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
out="$root/dist"
compiler=${CC:-cc}
command -v "$compiler" >/dev/null || { printf 'A C compiler is required to build the native helper.\n' >&2; exit 1; }
command -v pkg-config >/dev/null || { printf 'pkg-config and SDL2 development headers are required.\n' >&2; exit 1; }
pkg-config --exists sdl2
if [[ $(uname -s) != Linux ]]; then
    printf 'Build this helper on Linux for the Steam Deck Flatpak runtime.\n' >&2
    exit 1
fi
mkdir -p -- "$out"
read -r -a sdl_cflags <<< "$(pkg-config --cflags sdl2)"
read -r -a sdl_libs <<< "$(pkg-config --libs sdl2)"
flags=(-std=c11 -O2 -Wall -Wextra -Werror "-ffile-prefix-map=$root=.")
shared=(-fPIC -shared '-Wl,-z,relro,-z,now' '-Wl,--no-undefined')
"$compiler" "${flags[@]}" "${sdl_cflags[@]}" "${shared[@]}" -fvisibility=hidden \
    "$root/native/controller-text.c" -o "$out/libmes-controller-text.so" -ldl
"$compiler" "${flags[@]}" "${sdl_cflags[@]}" "${shared[@]}" -DMES_TEST_CLOCK \
    "$root/tests/test-native.c" -o "$out/test-native-clock.so" -ldl
"$compiler" "${flags[@]}" "${sdl_cflags[@]}" "$root/tests/test-native.c" \
    -o "$out/test-native" "${sdl_libs[@]}"
"$compiler" "${flags[@]}" "${sdl_cflags[@]}" "$root/tests/test-keyboard.c" \
    -o "$out/test-keyboard" "${sdl_libs[@]}"
"$compiler" "${flags[@]}" "${sdl_cflags[@]}" "$root/tests/test-getters.c" \
    -o "$out/test-getters" "${sdl_libs[@]}"
# Relative preload paths also exercise the loader contract for paths with spaces.
(
    cd -- "$out"
    MES_VIRTUAL_KEYBOARD=0 SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        LD_PRELOAD='./libmes-controller-text.so:./test-native-clock.so' ./test-native
    MES_VIRTUAL_KEYBOARD=1 SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        LD_PRELOAD='./libmes-controller-text.so:./test-native-clock.so' ./test-keyboard
    MES_VIRTUAL_KEYBOARD=0 SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        LD_PRELOAD='./libmes-controller-text.so:./test-native-clock.so' ./test-getters
    MES_VIRTUAL_KEYBOARD=1 SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        LD_PRELOAD='./libmes-controller-text.so:./test-native-clock.so' ./test-getters
)
if command -v readelf >/dev/null; then
    if readelf -d "$out/libmes-controller-text.so" | grep -q 'NEEDED.*libSDL'; then
        printf 'The helper must not link against libSDL.\n' >&2
        exit 1
    fi
fi
(cd -- "$out" && sha256sum libmes-controller-text.so > libmes-controller-text.so.sha256)
printf 'Built and tested %s\n' "$out/libmes-controller-text.so"
