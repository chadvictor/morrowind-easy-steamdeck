# Choose the view you want

These are **curated starting points**, not measured performance promises or a universal community consensus. We have not benchmarked them on a Steam Deck. Start with Balanced and adjust after visiting a busy exterior such as Balmora.

| Setting | Balanced (default) | Battery | Quality |
| --- | --- | --- | --- |
| Resolution | 1280 × 800 | 1280 × 800 | 1280 × 800 |
| Horizontal field of view | 75° | 75° | 75° |
| View distance | 16,384 units (~2 cells) | 8,192 (~1 cell) | 24,576 (~3 cells) |
| Distant terrain / object paging | On | On | On |
| Lighting method | Modern shaders | Modern shaders | Modern shaders |
| Anisotropic filtering | 8× | 8× | 16× |
| Shader water + refraction | On, 512-pixel texture | Off | On, 512-pixel texture |
| Shadows | Off | Off | Nearby objects, actors and player |
| Shadow distance / resolution | — | — | 4,096 units / 1,024 pixels |
| Terrain shadows | Off | Off | Off |
| Multisample antialiasing | Off | Off | Off |

Distance, shadows and shader water can each be overridden in the menu. Choosing another preset resets those three options to its defaults. All other engine settings retain OpenMW's defaults.

**Why these choices:** OpenMW documents distant terrain and modern shader lighting as supported engine features. Object paging helps render objects beyond active cells. Long view distances, water reflections and shadows all add work, so the default limits distance and leaves shadows off. Battery further reduces visual load; its name does not imply a measured battery-life improvement. [OpenMW defaults at the supported revision](https://github.com/OpenMW/openmw/blob/f4bec41444214a7903bebd178389ca22ca13f646/files/settings-default.cfg) · [Modding-OpenMW distant terrain guide](https://modding-openmw.com/mods/distant-land-and-objects/).

## Frame pacing

The installer leaves OpenMW's frame limiter unlimited and VSync off. Use the Deck's **Quick Access (…) → Performance** menu to select your preferred frame limit and refresh rate. Start with a comfortable limit and lower it if frame delivery is uneven. Available rate combinations differ between LCD/OLED displays and SteamOS versions; this project does not claim a fixed 30/40/60 FPS result.

## Interface and text are separate

- **Interface scale:** 1.0×, 1.25× (default), or 1.5×. This changes the whole UI.
- **Text size:** 16 or 18 (default). OpenMW 0.51 clamps this setting to 12–18; setting it to 24 does not provide a larger native font. Increase UI scale for larger text.
- **Controller + UI:** enables the gamepad, native controller menus/tooltips, dead zone 0.15 and cursor speed 0.65. Turning it off leaves keyboard/mouse play and the selected graphics/UI sizes.
- **Encoding:** win1252 for English/Western European editions, win1250 for Central/Eastern European, or win1251 for Cyrillic. This option alone does not translate the game. With PT-BR enabled it is fixed to win1252.
- **Brazilian Portuguese (PT-BR):** optional automatic installation of the verified community translation. Requires the supported English masters and OpenMW 0.51.0. It selects Portuguese UI/text and a separate PT-BR save directory. Start a new campaign; see [translation details](translation.md).

## Changing settings later

Open the downloaded installer again, or open `~/.local/share/morrowind-easy-steamdeck/manage.sh`. Setup creates a new settings/bindings profile and retains earlier profiles. It preserves both language groups' save directories and copies existing global/player Lua storage files when the previous and new profiles use the same language group. It does not merge custom graphics overrides or mods into a freshly generated preset.

For a small adjustment, use OpenMW's in-game options. For advanced manual editing, the `active` file names the folder inside `profiles/` that contains `settings.cfg`, `input_v3.xml` and `openmw.cfg`. Close the game before editing. [OpenMW settings reference](https://openmw.readthedocs.io/en/openmw-0.51.0/reference/modding/settings/).
