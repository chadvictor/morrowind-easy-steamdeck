# Architecture and evidence

This is an original Bash/awk installer and configuration profile. It does not patch a game executable, inject input, modify DRM, or redistribute OpenMW/Morrowind binaries. The implementation uses the installed engine's configuration contracts and the corresponding open-source code.

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

The profile stores real-case paths because Linux filesystems are case-sensitive. Steam library discovery accepts spaces and quoted VDF paths. Paths containing line breaks/tabs are rejected by discovery instead of being split into unintended records.

## Controller contract

The XML profile uses OpenMW input format v3 and its 51 action channels. SDL controller axes 0–5 map to movement, camera, ready magic and attack/cast. Each native binding uses `deviceId="1"`, OpenMW's fixed game-controller device identifier. The profile preserves keyboard/mouse fallback bindings. Native menu handling is separate C++ behavior, enabled with `[GUI] controller menus = true` and `controller tooltips = true`.

This configuration was first tested with the installed Windows engine, revision **f4bec41444214a7903bebd178389ca22ca13f646**, and the user confirmed successful controller gameplay. Porting the same SDL binding schema is source-backed; Steam Deck hardware behavior still requires validation.

## Runtime dependencies

Player side: Bash 4+, awk, GNU coreutils/findutils, grep, procps utilities, Flatpak, and Konsole when opening the shell file graphically. Optional PT-BR downloads use curl and either bsdtar or unzip. These are part of the stock SteamOS desktop environment; no extra terminal UI framework is downloaded. `kdialog` is optional for launcher error popups.

Development tests additionally use Python's standard library and ShellCheck. GitHub Actions runs simulated Steam libraries and a fake Flatpak command. Translation tests download the real upstream mod ZIP but use synthetic game masters; no original game installation is downloaded or required. Building bundles the source files and hash metadata into heredocs in one executable shell script. The release requires no checkout and downloads no project helper scripts at runtime.

## Sources

- [OpenMW 0.51.0 release](https://openmw.org/2026/openmw-0-51-0-released/) — engine release, controller/UI improvements.
- [OpenMW settings defaults, exact supported revision](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/files/settings-default.cfg) — setting sections, names, types and defaults.
- [Input action IDs](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwinput/actions.hpp), [binding manager](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwinput/bindingsmanager.cpp), [controller manager](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwinput/controllermanager.cpp) — controller mapping and native menu routing.
- [Configuration manager](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/components/files/configurationmanager.cpp) — `config`, `replace`, user data and resource behavior.
- [INI importer CLI](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/mwiniimporter/main.cpp) — importer arguments and its success-code limitation, handled by output validation.
- [Flathub package manifest](https://github.com/flathub/org.openmw.OpenMW/blob/master/org.openmw.OpenMW.yaml) — stable 0.51.0 source, bundled launcher and host filesystem access, inspected 2026-10-19.
- [Flatpak usage](https://docs.flatpak.org/en/latest/using-flatpak.html) — per-user remote/install/run commands.
- [OpenMW GUI](https://openmw.readthedocs.io/en/openmw-0.51.0/reference/modding/settings/GUI.html) and [input settings](https://openmw.readthedocs.io/en/openmw-0.51.0/reference/modding/settings/input.html) — accessibility and controller options.
- [Modding-OpenMW distant terrain guidance](https://modding-openmw.com/mods/distant-land-and-objects/) — community-authored configuration reference, not a Deck benchmark.

Steam's local VDF layout is an integration assumption checked against fixtures and common client paths, not a stable official API. The manual Launch Options path remains available if a future client changes that format.

## Licensing boundaries

Installer scripts, tests, configuration mappings and original SVG artwork are MIT licensed. OpenMW and the Flathub distribution retain their own licenses and are fetched directly from their distributors. No OpenMW source file or Morrowind asset is bundled. DadsMmoLab's scripts were consulted as UX inspiration, not copied; that separate project's AGPL license does not describe this original implementation.

The optional [PT-BR mod](translation.md) is fetched from its own release. Its assets are not included in this installer's release bundle; the full downloaded package retains its license, source translations and third-party notices.
