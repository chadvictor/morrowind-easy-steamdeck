# What has — and has not — been tested

## Confirmed evidence

- OpenMW **0.51.0**, revision **f4bec41444**, was present on the development Windows system.
- The initial controller profile was accepted by that engine, retained all 51 action channels after serialization, and loaded with the native controller UI enabled in a 1280 × 800 engine probe.
- The player subsequently confirmed that the controller setup worked on Windows on the first attempt.
- On **2026-10-20**, the player reported testing the previous installer on a physical Steam Deck: OpenMW launched, controller support worked and Portuguese text appeared. They used manual Launch Options because the automatic workflow required typing after closing Steam. At the character-name screen, the virtual keyboard failed; the Steam menu appeared only in desktop Big Picture, and even there Steam + X did not produce usable text entry. Exact Deck model, SteamOS version and full Game Mode behavior were not recorded.
- The Flathub manifest inspected for this preview points to the same 0.51.0 source revision and grants host filesystem access.
- The real Windows `openmw --version` output was checked against the installer gate. The installed `openmw-iniimporter` accepted this installer's arguments and produced 560 fallback entries from the local owned game's INI into a separate temporary file; no game/configuration files were changed by that check.
- The checked-in automated suites exercise Steam library discovery, VDF editing/restoration, configuration failure paths, native-launch arguments and the exact controller XML contract. Consult the [CI history](https://github.com/chadvictor/morrowind-easy-steamdeck/actions/workflows/ci.yml) for the result at a particular commit.

- The 0.4 keyboard UI was rendered in the actual Windows OpenMW 0.51.0 engine over its native character-name modal at 1280 × 800, UI scale 1.25. The 60-key panel remained visible while physical text input filled the native field. This verifies rendering and focus preservation, not the Linux native helper's end-to-end controller operation.

These are different kinds of evidence. The Deck report confirms basic launch, input and translation, but not the new 0.3/0.4 helpers or every acceptance item below. A passing mock test does not prove a real Flatpak installation succeeds on every SteamOS image.

## Automated coverage

The Steam suite uses fake native and Flatpak Steam roots, an SD library with spaces/quotes, synthetic TES3/BSA headers, multiple accounts and VDF fixtures. It exercises missing files, invalid manifests, legacy libraries, BOM/CRLF/no-final-newline handling, ambiguous keys, running Steam, concurrent changes, failed rename/state writes, repeat install, restore and preservation of unrelated settings.

The profile suite substitutes a fake Flatpak command. It checks engine-version compatibility, importer failure despite a zero exit status, exclusion of unwanted imported content/config, profile activation, old-profile retention, Lua storage/save preservation, controller-off mode, missing SD-card files, pointer traversal rejection and ignoring appended Proton arguments. Python checks every controller channel, neutral value, axis/button assignment and essential keyboard/mouse fallbacks. ShellCheck analyzes the shell code, and the bundle is built and syntax-checked on Linux CI.

No CI test boots a licensed copy of Morrowind or measures GPU performance.

The controller helper is compiled and exercised with **real SDL2**, a dummy video driver and a test-only clock shim on Linux. Tests cover View + Y event ordering, generated UTF-8 text without Enter, same-controller requirements, held-button debouncing, physical modifier preservation, ordinary event passthrough, three-second quit timing, cancellation, focus/device changes and SDL tick wraparound. The launcher suite verifies helper integrity, legacy profiles and literal paths containing spaces/dollar signs. The connection suite checks that every prompt precedes Steam shutdown, both setup and restore finish without Enter, conflicting exit-time settings are preserved, and Steam reopening is requested only after exit.

The keyboard suite checks its toggle chord, gamepad capture, navigation/repeat timing, Shift/Caps, editing, Enter versus Done, multiple controllers, focus/device changes, state heartbeats and trailing releases. LuaJIT tests check the same 60-key layout, non-interactive layers, asynchronous layer creation, selection, case display, watchdog and bounds at four logical viewport sizes. The launcher rejects modified keyboard files before starting OpenMW. These component tests do not replace real Deck testing of each native text dialog.

The translation suite verifies the actual pinned upstream ZIP and all 57 files. It exercises network/extraction/checksum failures, cache reuse and modification, all 63 UTF-8 fallback replacements, exact engine compatibility, master mismatches, plugin/data order, isolated save groups, disabling/re-enabling, and changes after setup. Synthetic masters are used for the profile tests; production hashes remain unchanged. No translated campaign is played by CI.

## Pending physical Steam Deck acceptance

Before calling the Steam Deck release stable, perform and record:

- [ ] Fresh SteamOS Desktop Mode: download and execute the release shell file through Dolphin.
- [ ] Per-user OpenMW install from Flathub without an administrator password.
- [ ] Discover and launch a game installed on the internal SSD.
- [ ] Discover and launch a game installed on a mounted SD card, including a path with spaces.
- [ ] Automatic Steam connection with no previous Launch Options, and restoration afterward.
- [ ] Game Mode Play button launches native OpenMW and retains Steam overlay/input.
- [ ] Both sticks, both triggers, ABXY, D-pad, shoulders and stick-clicks respond correctly.
- [ ] Character creation using View + Y, repeat to reroll, A to accept; ordinary Y still jumps outside text fields.
- [ ] View + X keyboard: type a custom character name using D-pad/stick + A, edit with X/LB/RB, toggle Shift/Caps, then confirm with its Enter key.
- [ ] Custom save, class, spell and enchanted-item names; inventory quantity fields; console. Confirm each field is focused and respects its own input restrictions.
- [ ] Keyboard open outside a text field: no characters or gameplay actions leak; B closes it. Test held sticks/triggers while opening/closing, controller disconnect and suspend/resume.
- [ ] View + Menu held for 3 seconds exits the name modal; shorter holds, focus loss and disconnect cancel it.
- [ ] Automatic suggested save description; custom spell/class/save names using the manual shortcut.
- [ ] Steam + X where supported; record Desktop/Big Picture/Game Mode separately.
- [ ] New connect/restore flow: all choices while Steam is open, automatic continuation and reopening after exit, no typing afterward.
- [ ] Inventory tabs, equipment, quantities, looting, trading, dialogue, journal and book navigation.
- [ ] Trackpad fallback, mode switching and prompts; no duplicate actions from mixed Steam mappings.
- [ ] UI/text at scale 1.0, 1.25 and 1.5 on 1280 × 800, including long text.
- [ ] Save, quit, relaunch and load from the same save directory.
- [ ] Enable PT-BR, start a new game, and inspect accented text, character-class questions, dialogue links, books and level-up messages.
- [ ] Disable/re-enable PT-BR and confirm that each language shows only its own campaign saves.
- [ ] Suspend/resume and SD-card removal/remount behavior.
- [ ] Measure exterior/interior performance and power for all presets; report model, SteamOS and frame limit.
- [ ] Re-run setup, restore Steam, and confirm original launch behavior remains recoverable.

Record LCD/OLED model, SteamOS version, Steam client version, OpenMW/Flatpak version, controller template and installer release with each report. Evidence from one model should not be presented as measured performance for another.
