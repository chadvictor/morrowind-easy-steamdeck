# Help, updates and undo

## The file opens as text

In Dolphin, enable **Properties → Permissions → Is executable**, then choose Execute when opening the file. If the file association still opens an editor, open Konsole, type `bash ` (including the space), drag `install-morrowind.sh` into the terminal, and press Enter. Or, if it is in Downloads:

```sh
bash "$HOME/Downloads/install-morrowind.sh"
```

The installer opens Konsole itself when started outside a terminal. It does not need sudo. Never run this installer with sudo or as root.

## It cannot find Morrowind

Finish the Steam installation first. In Desktop Mode, use Steam's Morrowind **Properties → Installed Files → Browse** to open its folder. Copy the full path from Dolphin's address bar and paste it into the installer. The `Morrowind` folder and its `Data Files` folder are both accepted.

Make sure the SD card is mounted in Dolphin. The installer reads Steam's libraries, including SD-card libraries; it does not scan every disk. It checks for Morrowind, Tribunal and Bloodmoon ESM/BSA files plus Morrowind.ini. If files are missing, use Steam's **Verify integrity** action. Modified or incomplete installations are outside the initial target.

## Steam is running / automatic connection is refused

Keep Steam open while choosing **Connect the Steam Play button**, the account, confirmation and reopening option. After the installer says it has collected every choice, use **Steam → Exit Steam** in Desktop Mode; closing its window may leave it running. The installer detects the exit, applies the connection and reopens Steam by default. It never stops Steam for you and never asks for Enter after the exit.

If three minutes pass without detecting an exit, the installer finishes without editing Steam. Reopen it and retry. If Steam saved different Launch Options while exiting, the installer also stops rather than overwriting a value you did not review.

If you prefer a manual connection, use **Show manual Steam Launch Options**. Paste the displayed line into Morrowind **Properties → General → Launch Options**. It is also saved in `~/.local/share/morrowind-easy-steamdeck/steam-launch-options.txt`. Save your old Launch Options yourself before replacing them manually; the automatic restore only tracks edits made by the automatic connector.

If you have multiple Steam accounts, choose the numeric account folder you use for Morrowind. Steam stores these under `~/.local/share/Steam/userdata/`. If you are unsure, use the manual method from the correct signed-in account.

## Pressing Play does not start OpenMW

1. Confirm the Launch Options line still ends in `%command%`.
2. Confirm the SD card is mounted and the game has not moved. If it moved, run setup and select the new folder.
3. Use stock SteamOS's **native Steam**. Steam installed through Flatpak has another sandbox and is not supported by this preview's launch bridge.
4. Check `~/.local/share/morrowind-easy-steamdeck/last-launch-error.txt` if present, and `launch.log`. For an engine failure, find the active profile from the `active` text file and inspect its `openmw.log`.

The default Flatpak package can access host game folders. If you previously restricted OpenMW's filesystem permissions in Flatseal or elsewhere, allow access to the game directory and the installer's directory. We do not reset your Flatpak permissions automatically. [Package permissions](https://github.com/flathub/org.openmw.OpenMW/blob/master/org.openmw.OpenMW.yaml).

## Controls behave like a mouse, or buttons do nothing

Select a **gamepad** Steam Input template. Left stick should not send WASD; right stick should not send mouse movement. Enable the controller option in this installer's setup. Keep a trackpad assigned to mouse for menus with limited controller support. If you see doubled input, remove additional keyboard/mouse mappings from gamepad buttons. See [Controls](controls.md).

The Steam button opens Steam; it is not available as the profile's Guide/quicksave button. Optionally map L4 to F5 instead.

## Steam + X does not open a keyboard / stuck naming a character

Update with the new installer and **run setup with Controller + UI enabled**; just selecting Connect Steam does not install the helper. Focus the name field, hold **View** (two overlapping rectangles), and tap **X** to open the in-game keyboard. Navigate with the D-pad/left stick and press A to type. X erases, Y toggles Shift, B closes, and the on-screen Enter key confirms. See [the full keyboard controls](controls.md).

For a quick suggested name instead, hold View and tap Y while the keyboard is closed. Press A to confirm; repeat the shortcut to roll another. The save dialog already supplies a description in controller-menu mode.

To leave a blocked modal, hold **View + Menu** for **3 seconds**. This exits OpenMW and loses unsaved progress. Both buttons must come from the same controller.

If the shortcuts do nothing, confirm the Steam Input buttons still send gamepad input. Open **Diagnostics** in the installer and check the controller-helper and keyboard-file checksums. After launching, `launch.log` should contain `[MES controller text] ready`. No such line can mean the helper failed to load or the engine no longer uses the expected SDL2 entry point; include that log with a report. For a panel that fails to appear, also include the active profile's `openmw.log`.

If the panel says to select a text field, close it with B, select the desired field with the controller or trackpad, and reopen it. The keyboard preserves the game's focus; opening it does not choose a field. Its keys are operated by gamepad rather than mouse/touch, and this first version uses US ASCII characters. If it covers a field, close it to inspect what you entered. Done/B close without confirming; Enter uses that dialog's normal confirmation behavior.

Desktop Mode, desktop Big Picture and SteamOS Game Mode have different overlay paths. A Flatpak game working does not prove its Steam keyboard works. The in-game keyboard and suggested names work independently of that overlay. [Valve's Flatpak overlay issue](https://github.com/ValveSoftware/steam-for-linux/issues/8952).

New profiles use borderless fullscreen, do not minimize on focus loss, and disable SDL's keyboard grab so desktop system shortcuts remain available where the compositor supports them.

## Text is too large / a window is cut off

Try scale 1.25 instead of 1.5, or 1.0 if necessary. Font size and interface scale are independent. Restart the game after changing the profile. Long PT-BR text can require more space than English.

## PT-BR installation stops or my saves seem missing

The optional translation requires the hash-checked **English Steam GOTY** masters and **OpenMW 0.51.0 exactly**. If the files do not match, select English in Steam properties and verify the game files, or leave PT-BR off. Download/checksum failures do not activate the new profile. See [translation recovery](translation.md#disable-or-recover) for a damaged cache.

Original-language and PT-BR saves are deliberately separated. Switch the option back to the language of your campaign to see its saves again. No saves are deleted or converted. Start a new game the first time you enable PT-BR.

## Download interrupted or version not supported

Run setup again. Flatpak manages its downloads; an incomplete INI import never replaces your active profile. Failed staging folders may remain under `profiles/` for inspection.

This preview supports OpenMW **0.51.x**. If Flathub has moved to a later engine version, download an updated installer. We stop before applying an unreviewed controller format. Flatpak/Discover can update an already-installed engine separately, so check release compatibility before updating it. Updating the engine may affect other users of the same per-user OpenMW package; the profile isolation does not install a separate copy of the engine for each profile.

## Update this project or change settings

Download the newer release and run it. Setup updates the per-user OpenMW package from stable Flathub and creates a fresh profile. The installer also saves itself as `manage.sh` so you can reopen the menu without finding the original download. It does not silently download or execute a newer installer script.

## Restore Steam's original Play behavior

Keep Steam open, run the installer and choose **Restore previous Steam Launch Options**. Confirm restoration and the reopening option first; then exit Steam when instructed. The installer waits, restores the original value (or removes its added value if none existed), and reopens Steam by default. No Enter is needed after closing Steam.

If you edited Launch Options after connecting, automatic restore stops to avoid losing your change. Read `steam-backup/before-options` and `steam-backup/before-present` to recover the old value manually through Steam Properties. Keep `steam-backup/localconfig.before` as evidence; do not replace your whole current Steam configuration with that backup unless you deliberately want to undo other changes too.

## Go back to an earlier graphics profile

Close OpenMW. Inside `profiles/`, find the earlier timestamped folder and inspect its `choices.txt`. The `active` file contains one folder name, without a path. Replace that line with the chosen earlier folder name and save. Original-language profiles use `userdata/saves/`; PT-BR profiles use `userdata-ptbr/saves/`. Do not use this procedure while the game is running.

## Remove this setup

First restore Steam's Launch Options. Then, in Dolphin, **back up `userdata/saves/` and `userdata-ptbr/saves/` if present**, and move the entire `morrowind-easy-steamdeck` directory to a backup location or Trash. Do not delete that directory while Steam still points to its launcher. The Morrowind installation remains in Steam.

OpenMW itself remains installed because you may use it for another setup. You can remove it separately using Discover if you no longer need it. There is no background service or scheduled task to remove.

## A stale installer lock remains

The lock prevents two installer windows from changing the same setup. Close all installer windows first. If no installer is running after an interruption/reboot, remove only the `installer.lock` folder inside this installer's directory with Dolphin. A Steam edit interrupted mid-write may also leave a `localconfig.vdf.morrowind-easy-steamdeck.lock` directory next to the selected account's `localconfig.vdf`; remove only that lock directory after confirming no installer is active, then try **Restore** before reconnecting. Keep all backup files.

## Report a problem

Choose **Diagnostics**, review the output for personal folder names, and include it with an [issue](https://github.com/chadvictor/morrowind-easy-steamdeck/issues). Include Deck model, SteamOS version, release version, internal/SD installation, and what you expected versus what happened. Never upload your full Steam userdata folder, account credentials, saves containing personal data, or Morrowind game assets.
