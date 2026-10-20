# Architecture and evidence

This is an original Bash/awk installer, configuration profile and optional SDL2 input helper. It uses OpenMW's documented configuration and public SDL events for controller text suggestions. Game executables remain unchanged; OpenMW is fetched from Flathub and Morrowind data comes from the player's Steam installation.

## Installation flow

1. Read native/Flatpak Steam roots and modern or legacy `libraryfolders.vdf` files.
2. Read `appmanifest_22320.acf` and validate the installed game folder, including TES3/BSA signatures. This detects obvious wrong files, not full archive integrity.
3. Add Flathub for the current user and install/update `org.openmw.OpenMW//stable` with `flatpak --user`.
4. Check `openmw --version` against 0.51.x before applying engine-specific bindings.
5. If PT-BR is selected, require OpenMW 0.51.0 and matching English Steam GOTY master hashes. Download the pinned translation ZIP, verify it before extraction, then verify the exact 57-file payload. Reject extra files and links. Keep it in a separate versioned mod directory.
6. Run the package's `openmw-iniimporter` on the user's own INI. Retain its fallback values; specify the three official masters and archives explicitly. PT-BR adds its plugin last and replaces 63 fallback values by key, keeping UTF-8 intact.
7. Generate a settings profile, optionally copy the controller mapping, then atomically replace a small `active` pointer file. Failed profile generation leaves the previous pointer intact. Previous profiles remain on disk. PT-BR selects `userdata-ptbr`; the original language uses `userdata`. Lua storage is copied only between consecutive profiles in the same save group.
8. Optionally change one Steam account's app-22320 `LaunchOptions` with a lexical VDF parser, a full backup, concurrency checks and a guarded restore.

All user values are data: there is no `eval`, and saved preferences/paths are not sourced as shell code. The VDF editor retains bytes outside the affected value or inserted structure. It refuses ambiguous duplicate keys and unsupported syntax instead of guessing. Automatic Steam edits require a successful process check with Steam closed. No Steam processes are killed.

## Native launch

`launch.sh` resolves its own directory, reads the selected profile and verifies the original game files still exist. It then executes:

```text
flatpak run --user --branch=stable --command=openmw org.openmw.OpenMW
  --replace=config --config=<profile>
  --user-data=<installer>/userdata
  --data-local=<installer>/userdata/data
  --data=<original game data directory>
```

Actual code uses separate quoted arguments, not the illustrative text above. `--replace=config` skips unrelated user configuration chains while preserving the engine's global configuration, resources and built-in VFS data. Passing paths on the command line avoids writing user paths into the engine's configuration grammar. The original Proton `%command%` arguments are ignored. Loader overrides `LD_PRELOAD` and `LD_LIBRARY_PATH` are removed before invoking Flatpak; display, Steam Input and Gamescope variables remain.

For PT-BR, the launcher adds the mod's `Data Files` as a second `--data` argument and selects `userdata-ptbr` for both user-data paths. Each launch rechecks the exact engine version, original master hashes and complete translation payload, using hash manifests saved in the profile. It also refuses files or links in `userdata-ptbr/data`, because local data could override the verified masters or mod. It never deletes that content.

Controller-enabled profiles additionally contain a checksum-verified `libmes-controller-text.so`. Their Flatpak command is `sh -c` with a fixed script and separate positional arguments: change to the profile directory, set `LD_PRELOAD=./libmes-controller-text.so`, then `exec openmw` with the arguments above. The relative basename is intentional: the dynamic loader splits absolute preload paths containing spaces. The helper is only loaded inside the OpenMW sandbox, not into host Steam or Flatpak. Profiles from earlier releases without the helper manifest continue to use the direct launch command.

The launcher sets `SDL_GRAB_KEYBOARD=0`. New profiles use window mode 1 (borderless fullscreen) and disable minimize-on-focus-loss. These choices permit desktop switching where supported; they do not guarantee Steam's overlay or keyboard.

The profile stores real-case paths because Linux filesystems are case-sensitive. Steam library discovery accepts spaces and quoted VDF paths. Paths containing line breaks/tabs are rejected by discovery instead of being split into unintended records.

## Controller contract

The XML profile uses OpenMW input format v3 and its 51 action channels. SDL controller axes 0–5 map to movement, camera, ready magic and attack/cast. Each native binding uses `deviceId="1"`, OpenMW's fixed game-controller device identifier. The profile preserves keyboard/mouse fallback bindings. Native menu handling is separate C++ behavior, enabled with `[GUI] controller menus = true` and `controller tooltips = true`.

This configuration was first tested with the installed Windows engine, revision **f4bec41444214a7903bebd178389ca22ca13f646**, and the user confirmed successful controller gameplay. On 2026-10-20 the user also reported successful OpenMW/controller/PT-BR operation on a Deck, alongside the keyboard and connection problems addressed in 0.3.0. Exact hardware/OS versions and full Game Mode coverage remain unrecorded.

### Optional SDL2 helper

`native/controller-text.c` is original MIT-licensed code. It interposes the public `SDL_PollEvent` function and resolves SDL2 functions with `dlsym(RTLD_NEXT)`. It does not use engine addresses, C++ ABI hooks, modified game records or a custom OpenMW build.

When SDL reports active text input, View held + a new Y press from the same controller produces a private ordered queue: Ctrl+A to select the field, followed by a bounded ASCII/UTF-8 name. The matching Y release is consumed, unrelated inputs pass through, and Enter is never injected. SDL's physical modifier state is not changed. This is an explicit, generic suggestion command; the helper cannot infer whether the focused field is a name, quantity or console.

A same-controller View + Menu hold produces one `SDL_QUIT` after three seconds, including on idle frames. Release, device removal/remap and focus/background transitions clear the relevant holds. OpenMW routes SDL_QUIT through its normal window-close handler; this does not save the campaign. `SDL_PollEvent(NULL)` retains its non-consuming peek behavior. Native SDL integration tests cover event ordering, paired releases, multiple controllers, text inactivity, modifier preservation, focus loss and clock wraparound.

The helper is compiled on Linux against SDL2 headers but dynamically links only the system C/dynamic-loading runtime. Its binary and checksum are embedded in the single installer; no player compiler or extra package is required. Each profile gets its own copy, so rollback retains the matching helper. Disabling Controller + UI creates a profile without it.

## Runtime dependencies

Player side: Bash 4+, awk, GNU coreutils/findutils, grep, procps utilities, Flatpak, and Konsole when opening the shell file graphically. Optional PT-BR downloads use curl and either bsdtar or unzip. These are part of the stock SteamOS desktop environment; no extra terminal UI framework is downloaded. `kdialog` is optional for launcher error popups.

Development tests additionally use Python's standard library, ShellCheck, a C compiler, pkg-config and SDL2 development headers/libraries. GitHub Actions runs the native tests against real SDL2 with a dummy video driver, simulated Steam libraries and a fake Flatpak command. Translation tests download the real upstream mod ZIP but use synthetic game masters; no original game installation is downloaded or required. Building bundles source files and hash metadata into heredocs, plus the native helper encoded as base64, in one executable shell script. Stock SteamOS supplies the base64 decoder. The release requires no checkout and downloads no project helper scripts at runtime.

## Sources

- [OpenMW 0.51.0 release](https://openmw.org/2026/openmw-0-51-0-released/) — engine release, controller/UI improvements.
- [OpenMW settings defaults, exact supported revision](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/files/settings-default.cfg) — setting sections, names, types and defaults.
- [Input action IDs](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwinput/actions.hpp), [binding manager](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwinput/bindingsmanager.cpp), [controller manager](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwinput/controllermanager.cpp) — controller mapping and native menu routing.
- [Configuration manager](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/components/files/configurationmanager.cpp) — `config`, `replace`, user data and resource behavior.
- [INI importer CLI](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/mwiniimporter/main.cpp) — importer arguments and its success-code limitation, handled by output validation.
- [SDL event wrapper](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/components/sdlutil/sdlinputwrapper.cpp), [keyboard routing](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwinput/keyboardmanager.cpp), [text-input dialog](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwgui/textinput.cpp) and [save dialog](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwgui/savegamedialog.cpp) — source-backed input, confirmation, save-description and quit behavior.
- [SDL keyboard grab](https://wiki.libsdl.org/SDL2/SDL_HINT_GRAB_KEYBOARD) and [Valve's Flatpak overlay issue](https://github.com/ValveSoftware/steam-for-linux/issues/8952) — desktop shortcut and overlay limitations; the helper bypasses keyboard dependence for name suggestions.
- [Flathub package manifest](https://github.com/flathub/org.openmw.OpenMW/blob/master/org.openmw.OpenMW.yaml) — stable 0.51.0 source, bundled launcher and host filesystem access, inspected 2026-10-19.
- [Flatpak usage](https://docs.flatpak.org/en/latest/using-flatpak.html) — per-user remote/install/run commands.
- [OpenMW GUI](https://openmw.readthedocs.io/en/openmw-0.51.0/reference/modding/settings/GUI.html) and [input settings](https://openmw.readthedocs.io/en/openmw-0.51.0/reference/modding/settings/input.html) — accessibility and controller options.
- [Modding-OpenMW distant terrain guidance](https://modding-openmw.com/mods/distant-land-and-objects/) — community-authored configuration reference, not a Deck benchmark.

Steam's local VDF layout is an integration assumption checked against fixtures and common client paths, not a stable official API. The manual Launch Options path remains available if a future client changes that format.

## Licensing boundaries

Installer scripts, the original native helper, tests, configuration mappings and original SVG artwork are MIT licensed. OpenMW and the Flathub distribution retain their own licenses and are fetched directly from their distributors. No OpenMW source file or Morrowind asset is bundled. DadsMmoLab's scripts were consulted as UX inspiration, not copied; that separate project's AGPL license does not describe this original implementation.

The optional [PT-BR mod](translation.md) is fetched from its own release. Its assets are not included in this installer's release bundle; the full downloaded package retains its license, source translations and third-party notices.
