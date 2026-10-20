# Brazilian Portuguese, one optional switch

Enable **`9 — Brazilian Portuguese (PT-BR)`** in the setup screen, then choose **I** to install. The option is off for a new setup and remembers your choice when you rerun setup. The installer's own menu and documentation remain in English.

## What gets installed

The installer downloads [Morrowind PT-BR 0.1.0-beta.2](https://github.com/chadvictor/morrowind-traducao-ptbr/releases/tag/v0.1.0-beta.2), the ready-to-play mod ZIP. It does not run the upstream Windows installers or Python reconstruction tools.

It automatically:

- Verifies the download's SHA-256 and all 57 extracted files.
- Rejects extra files and links, and rechecks the package, original masters and OpenMW version when launching.
- Keeps the complete mod in its own versioned folder, including maps, interface resources, licenses and notices.
- Loads the mod's `Data Files` after the game's original data directory.
- Loads `Morrowind_PTBR.esp` after Morrowind → Tribunal → Bloodmoon.
- Sets game-data encoding to `win1252` and the modern UI language to `pt_BR, en`.
- Enables subtitles and merges the 63 translated engine messages, replacing matching fallback keys without leaving duplicates.
- Uses a separate save directory for PT-BR campaigns.

The game-data encoding does not change UTF-8 configuration or YAML text. The 63 fallback entries cover character-class questions, level-up messages and blood-type labels; calendar names come from the mod's localization resources.

The downloaded `.qm` files are optional translations for the separate Qt launcher. They are retained with the package but **not applied inside Flatpak**: Steam launches the game directly, and the in-game translation does not need them. No OpenMW application/resource files are replaced.

## Compatibility

This integration requires **OpenMW 0.51.0 exactly**, plus these original **English Steam GOTY** masters:

| File | SHA-256 |
| --- | --- |
| Morrowind.esm | `5c3c8c2cbd20e25901b59b3ece33d36b7ef0e3d60ad8d11828bcc61a5ead1647` |
| Tribunal.esm | `2ace511f23cc2a9ddd5f3aa59c7919789b9378cf4b17c8ae3375dd6b782f3f2b` |
| Bloodmoon.esm | `bd27090d0e6ad4c1bf1abc83f1a2dac56fcc82cae7bfe8263c413fb301801357` |

If a hash differs, setup stops without activating a new profile. In Steam's game properties, select English and verify the game files, or leave the PT-BR option off. Do not install over previously translated masters or combine this plugin with the older translation format.

If Discover later updates OpenMW to a different version, a PT-BR launch stops with an explanation. Use a newer installer with a translation reviewed for that engine; turning PT-BR off lets you return to the original-language campaign, subject to the installer's normal engine compatibility check. The installer does not downgrade Flatpak automatically.

The upstream translation was validated on Windows. File/configuration integration is checked automatically for this installer; **actual Steam Deck gameplay remains untested**. Other mods, engine versions and language editions are not covered by this translation release. [Upstream compatibility notes](https://github.com/chadvictor/morrowind-traducao-ptbr/blob/v0.1.0-beta.2/docs/COMPATIBILIDADE.md).

## Start a new campaign

The translation coordinates dialogue topic names and scripts. There is no validated conversion of an English campaign to PT-BR or back again. Choose **New Game** when you first enable PT-BR.

Your directories are separate:

```text
~/.local/share/morrowind-easy-steamdeck/userdata/saves/       original-language campaigns
~/.local/share/morrowind-easy-steamdeck/userdata-ptbr/saves/  PT-BR campaigns
```

Switching PT-BR off does not delete, move or convert either set. Enabling it again reuses the PT-BR save directory. Existing original-language saves may appear again when you turn the option off. Back up both folders separately; this project does not configure Steam Cloud for them. `XDG_DATA_HOME`, if set, changes the base directory as described in the README.

## Disable or recover

Close the game, reopen the installer, choose setup, turn **9** off, and apply. A new original-language profile is generated without the plugin, mod directory, translated fallbacks or forced Portuguese locale. Old profiles and the downloaded package remain available. The Steam launch connection stays the same.

If download, verification or translation setup fails, the previous active profile is retained. For a damaged or modified cache, close the game and move `mods/ptbr-0.1.0-beta.2` to a backup location, then rerun setup to download a verified copy. Do not edit that managed cache in place; custom mods are outside this setup's initial scope.

Keep `userdata-ptbr/data` empty: local data can override the verified mod. If the launcher finds files or links there, move that content to a backup location and retry. Leave the separate `userdata-ptbr/saves` folder in place.

The integration pins a reviewed release and checksum; it does not silently choose an unreviewed future translation. Updates arrive through a newer version of this installer.

## Coverage and credit

The upstream project covers game text, dialogue, books, item/world labels and several interface resources. It does not supply Portuguese voice acting or translated videos. It is a community beta produced with AI assistance and automated checks, with incomplete human review and no full campaign playthrough. [Upstream coverage](https://github.com/chadvictor/morrowind-traducao-ptbr/blob/v0.1.0-beta.2/docs/COBERTURA.md) · [Installation contract](https://github.com/chadvictor/morrowind-traducao-ptbr/blob/v0.1.0-beta.2/docs/INSTALACAO.md).

The mod is downloaded directly from its upstream release. This installer bundles only verification metadata, not its translated assets. The original archive is pinned to SHA-256 `ea76ae106c2f347fc4c7e0d776df7fedadf90debe1396010c44b2123b2bf7b62` (4,525,354 bytes; about 18.1 MB extracted). Its license, Qt sources and third-party notices are retained in the extracted package.
