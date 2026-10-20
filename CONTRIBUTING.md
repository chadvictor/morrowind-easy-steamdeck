# Contributing

Keep the player workflow small: own the game, run one shell file, choose options, play. Changes should run on stock SteamOS without sudo or extra CLI frameworks. Keep proprietary game data, personal configuration and credentials out of the repository.

## Development checks

On Linux, with Bash, ShellCheck, Python 3, a C compiler, pkg-config and SDL2 development headers installed for development (Ubuntu packages `build-essential libsdl2-dev`):

```sh
shellcheck -x -e SC1091 lib/*.sh src/*.sh scripts/*.sh tests/*.sh
bash scripts/build-native.sh
export MES_NATIVE_LIBRARY="$PWD/dist/libmes-controller-text.so"
bash tests/test-steam.sh
bash tests/test-core.sh
bash tests/test-menu.sh
bash tests/test-connect.sh
bash tests/test-translation.sh
python3 tests/test-profile.py
bash scripts/package.sh
bash dist/install-morrowind.sh --help
```

The result is `dist/install-morrowind.sh`, a player tarball and `dist/SHA256SUMS.txt`. The native build also leaves a `.so` helper and two test-only binaries in `dist/`; do not attach the test binaries to releases. GitHub Actions runs the suites on Ubuntu 22.04 and 24.04. Native tests use real SDL2; Steam/Flatpak integration uses fixtures. See the [hardware checklist](docs/validation.md).

## Layout

| Location | Purpose |
| --- | --- |
| `src/main.sh` | Terminal menu and player workflow |
| `src/launch.sh` | Native launch bridge used by Steam |
| `lib/core.sh` | Flatpak install, presets and isolated profile activation |
| `lib/steam.sh` | Discovery, signature checks and reversible Steam integration |
| `lib/steam-vdf.awk` | VDF lexer/parser and surgical edits |
| `lib/translation.sh`, `lib/ptbr-fallbacks.awk` | Pinned PT-BR download, verification and fallback merging |
| `assets/ptbr-*.sha256` | Reviewed upstream payload and original-master checksums |
| `assets/input_v3.xml` | Approved OpenMW 0.51 controller contract |
| `native/controller-text.c` | Original SDL2 name suggestions and hold-to-quit helper |
| `scripts/build-native.sh`, `tests/test-native.c` | Linux helper build and SDL integration tests |
| `scripts/build.sh` | Standalone release bundle generation |
| `tests/` | Synthetic fixtures; no commercial assets |

Please include tests for changes to discovery, escaping, Steam edits, profile activation or save handling. Test real hardware before making performance claims. Do not expand support to a new OpenMW action format by only relaxing the version check; verify the mapping against source and runtime behavior first.

The translation suite downloads the pinned 4.5 MB mod ZIP once. Pass a local copy as its only argument to reuse an existing download; its SHA-256 is still checked. It never needs commercial game files. Updating the translation requires a new archive review, hashes, compatibility contract and tests, not just changing its URL.

## Releases

Update the version in `lib/core.sh`, the README example and changelog. Run all checks, build from the exact tagged commit on Ubuntu 22.04 for the older glibc baseline, and attach `install-morrowind.sh`, an executable-preserving tarball and SHA-256 checksums to a GitHub release. Mark releases as prereleases until the physical Steam Deck acceptance checklist has been completed. A prerelease is linked through the Releases page, because GitHub's `/releases/latest` excludes prereleases.

Future priorities: finish real Deck validation, refine presets from measurements, add controller remapping, and assess whether a custom inventory UI improves on the native controller mode. A new UI should be a separately tested feature, not implied by the installer.
