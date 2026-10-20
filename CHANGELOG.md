# Changelog

## 0.4.0-preview.1

- Add an in-game US QWERTY virtual keyboard using OpenMW's native Lua UI templates.
- Open with View + X; navigate with D-pad/left stick, select with A, erase with X, shift with Y and close with B.
- Include 60 keys covering printable US ASCII, editing, cursor movement, Caps and explicit Enter/Done actions.
- Keep the game's original text field focused; ignore text/edit requests when no field is selected.
- Capture gamepad input while the keyboard is open, neutralize previous movement and guard button releases after closing.
- Bundle verified Lua UI assets with each profile and load a menu script that also runs in modals and before a game is loaded.
- Retain 0.3.0 name suggestions, hold-to-quit, existing save directories and the connection flow that needs no typing after Steam exits.

This preview still needs testing on a physical Steam Deck. The keyboard does not require Steam's overlay.

## 0.3.0-preview.1

- Collect all connection and restore choices while Steam is still running; wait for its exit, apply guarded edits and reopen it by default, without another keypress.
- Preserve the last-reviewed Launch Options if Steam flushes a different value during shutdown.
- Add View + Y name suggestions in focused text fields, using a bundled original SDL2 helper.
- Add a three-second View + Menu shortcut to request normal engine exit from blocked modals.
- Keep OpenMW's existing controller-mode save descriptions and document how to use them.
- Use borderless fullscreen, disable minimize-on-focus-loss and avoid grabbing system keyboard shortcuts.
- Verify each profile's helper checksum at launch; retain compatibility with earlier profiles.

A player confirmed basic OpenMW/controller/PT-BR operation on a physical Steam Deck and reported the keyboard/setup problems addressed here. The new shortcuts and revised flow still require a Deck retest; Linux automated tests are not a hardware validation.

## 0.2.0-preview.1

- Add optional automatic Brazilian Portuguese installation from Morrowind PT-BR 0.1.0-beta.2.
- Verify the pinned ZIP, all 57 extracted files, supported English masters and OpenMW 0.51.0.
- Recheck translation/master integrity and engine compatibility at launch; reject unreviewed files overriding the translation.
- Activate the plugin, localization resources, UI language, subtitles and 63 translated fallbacks together.
- Keep PT-BR saves separate, preserve the original save directory, and remember the language choice on reconfiguration.
- Disable PT-BR by rerunning setup with option 9 off; no files in the original game or Flatpak application are replaced.

Physical Steam Deck validation remains pending. The community translation requires a new campaign.

## 0.1.0-preview.1

Initial Steam Deck preview.

- One standalone Bash installer with a dependency-free terminal menu on stock SteamOS.
- Native OpenMW 0.51.x from per-user Flathub, without sudo.
- Internal/SD Steam library discovery and manual path fallback.
- Balanced, Battery and Quality presets, with graphics/UI/text overrides.
- Optional controller bindings and native controller menus based on the working Windows profile.
- Existing Steam Play button connection, account selection, backup and guarded restore.
- Isolated settings generations and shared OpenMW save directory.
- English player guide, developer reference and automated Linux checks.

Known boundary: the complete SteamOS/Flatpak/Game Mode flow and performance presets have not yet been validated on physical Steam Deck hardware.
