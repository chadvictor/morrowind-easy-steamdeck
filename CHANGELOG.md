# Changelog

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
