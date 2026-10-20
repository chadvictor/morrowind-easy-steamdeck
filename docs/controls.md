# Controls that fit a controller

The profile uses OpenMW's native SDL gamepad input. Steam Input should present a **standard gamepad** to the engine. A layout that maps both sticks to keyboard/mouse will not use the native controller menus correctly.

## One Steam Input step

In Morrowind's Steam controller settings, enable Steam Input and select **Gamepad with Joystick Trackpad**, if available. A regular gamepad template also works as the starting point: assign the right trackpad to **Mouse** and its click to **Left Mouse Click** for pointer-only screens. Steam's template names can vary with language/client version.

Keep left/right sticks as gamepad joysticks, triggers as analog triggers, and ABXY/D-pad as gamepad buttons. The installer does not overwrite your Steam Input layouts.

## In the world

| Deck / Xbox-style input | Action |
| --- | --- |
| Left stick | Move |
| Right stick | Look |
| A | Activate / talk / take |
| B | Inventory / character interface |
| X | Draw / put away weapon |
| Y | Jump |
| RT | Attack or cast, depending on readied mode |
| LT | Ready magic |
| LB | Rest / wait |
| RB | Assign quick keys |
| View / Back | Journal |
| Menu / Start | Pause menu |
| Left stick click | Sneak (hold by default) |
| Right stick click | First / third person |
| D-pad up / down | Quick slot 1 / 2 |
| D-pad left / right | Previous / next weapon |

**Quicksave:** the underlying profile also maps the gamepad Guide button to quicksave, but Steam reserves the Deck's Steam button. Do not rely on that binding on Deck. Optionally assign **L4 → keyboard F5** in Steam Input for quicksave. Save normally from the pause menu as well.

OpenMW's built-in script settings can change sneak to a toggle: check **Options → Scripts → OpenMW Controls**. This installer leaves that preference alone. Morrowind still uses its own mechanics: blocking is automatic, and this does not add Skyrim's sprint, dual wielding or combat system.

## In menus

OpenMW's controller menu layout is native engine functionality, enabled by this profile. It reorganizes the inventory instead of simply moving a mouse pointer around the old desktop layout.

| Input | Typical menu behavior |
| --- | --- |
| D-pad | Move focus through entries |
| A / B | Confirm / go back |
| LT / RT | Change character-interface tab |
| LB / RB | Change available filters/categories |
| Right stick click | Toggle item tooltips where supported |
| X | Context action shown by the screen (drop, take all, offer, etc.) |
| Right trackpad | Pointer fallback for screens that need it |
| View held + X | Open / close the in-game virtual keyboard |
| View held + Y | Replace the focused name/description with a generated name |
| View + Menu held 3 seconds | Quit OpenMW, including from a modal (does not save) |
| Steam + X | Steam keyboard, when the Steam overlay supports it |

Follow the on-screen prompts; behavior depends on the active screen. Some settings and auxiliary windows still require a pointer. Menu bindings are separate from gameplay bindings in OpenMW, so changing an in-game combat key will not necessarily change its menu equivalent.

## In-game virtual keyboard

Profiles created with **0.4.0 or later** and **Controller + UI** enabled include an OpenMW UI keyboard. Focus the game's text field, hold **View / Back**, then tap **X**. The keyboard opens above the menu without taking that field's focus.

| While the keyboard is open | Action |
| --- | --- |
| D-pad / left stick | Move the highlighted key; hold to repeat |
| A | Type / activate the highlighted key |
| X | Backspace |
| Y | One-shot Shift; resets after typing a character |
| LB / RB | Move the text cursor left / right |
| B or Menu | Close without confirming the game dialog |
| View + X | Close the keyboard |
| On-screen Enter | Confirm through the game's normal Enter behavior and close |
| On-screen Done | Close, leaving the field and dialog available |

The layout includes all printable US ASCII characters, Tab, Caps Lock, cursor keys, Home, End and Delete. Shift affects punctuation; Caps affects letters, and Shift temporarily inverts it. Accented letters and IME composition are outside this initial US-layout version.

The keyboard can appear on any screen. It only sends characters or editing keys while the engine reports an active text field; otherwise the header says **Select a text field to type**. Use a trackpad to choose one if necessary. The visual keys are controlled by the gamepad, not touch or mouse clicks. Closing the overlay does not undo characters already typed. If it covers a field near the bottom, close it with B to inspect your text.

Gameplay buttons and axes are captured while the keyboard is open. Releasing a button after closing must not activate the underlying menu. Physical keyboard input remains available; Escape closes the overlay. View taps now open the Journal on release, allowing the helper to distinguish a tap from a keyboard/name/exit chord.

## Names without the Steam keyboard

With **Controller + UI** enabled in a profile created by 0.3.0 or later:

1. Focus the character-name field, or another name/description field. A trackpad click works if it is not focused already.
2. Hold **View / Back** (the two overlapping rectangles) and tap **Y**. A generated fantasy name replaces the field's entire text.
3. Release Y and tap again while holding View to try another. **A** confirms through the game's normal interface.

Suggestions are manual and never press Enter for you. They work with the engine's active text-input field, including custom class, spell and save descriptions; they do not identify the meaning of that field. Use them on names/descriptions, **not numeric quantities or the console**. Physical keyboard input remains available. Use **View + X** when you want to type your own text.

OpenMW 0.51 already suggests a calendar-based description when opening **Save** with controller menus enabled. Keep that description and confirm the normal Save action; there is no need to rename every save. Selecting an existing save still follows the game's overwrite confirmation. [Upstream save-dialog implementation](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/apps/openmw/mwgui/savegamedialog.cpp).

If a modal traps you, hold **View + Menu / Start** on the same controller for **3 seconds**. This requests the engine's normal quit path, including from the character-name screen. **Unsaved progress is lost.** Releasing either button cancels the hold. The STEAM and … buttons are not part of either shortcut.

Input behavior is tested with synthetic events in real SDL2 on Linux; the Lua UI has separate lifecycle/layout checks. The complete combination on the Deck still needs confirmation.

## Legibility

The default is **1.25× interface scale + font size 18**. Try **1.5×** if you need larger menus. Larger UI reduces the available space, so check inventory, dialogue and books before committing to a long session. If a window clips at 1.5×, rerun setup at 1.25×.

This is the OpenMW UI with its controller mode and accessibility settings. It does not replace it with Skyrim artwork or a new UI mod. A custom inventory redesign and a remapping screen are future work.

Reference: [OpenMW GUI settings](https://openmw.readthedocs.io/en/openmw-0.51.0/reference/modding/settings/GUI.html), [input settings](https://openmw.readthedocs.io/en/openmw-0.51.0/reference/modding/settings/input.html), and [Valve's gamepad emulation guidance](https://partner.steamgames.com/doc/features/steam_controller/steam_input_gamepad_emulation_bestpractices).
