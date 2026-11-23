# Credits and asset licenses

Every third-party asset in the project is listed here with its source and license.
Third-party art and audio are CC0 (public domain); fonts are under the SIL Open Font License; the engine is
MIT. Everything else was made for this project, by hand, in code, or with AI tools whose terms give the output
to us for commercial use. Untouched CC0 originals live in `assets/source/`; `tools/import_art.py` builds the
runtime files from them. Full licence texts that builds must carry: [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
The licence audit, AI service terms and the name check: [docs/LICENSES.md](docs/LICENSES.md).

| Asset | Author | Source | License | Used for |
|---|---|---|---|---|
| Zelda-like tilesets and sprites (`Overworld.png`) | ArMM1998 | https://opengameart.org/content/zelda-like-tilesets-and-sprites | CC0 | `assets/tiles/overworld.png`: fallback ground and props where no art-pass tile exists |
| Puny Characters (`Character-Base`, `Archer`, `Warrior`, `Soldier`, `Mage`, `Slime`) | Shade | https://opengameart.org/content/puny-characters | CC0 | `assets/characters/`: fallback paper-doll body and outfits for any character without an art-pass sprite set |
| Character, enemy, tile and prop art (`assets/sprites/`, `assets/tiles/meadow/`, `assets/tiles/town/`, `assets/props/`, `assets/buildings/`, art pass) | Generated with PixelLab AI for this project (API, pay per call) | https://www.pixellab.ai | Owned by the project (PixelLab output) | Heroes in missions, town and the party picker |
| Character portraits (`assets/portraits/`) | Made with OpenAI image generation for this project | https://openai.com/policies/row-terms-of-use/ | Owned by the project (OpenAI's terms assign output to the user, commercial use allowed) | Dialogue and bond scenes; painted, then turned into pixel art by `tools/cut_portraits.py` (`docs/PORTRAITS.md`) |
| Title key art and painted map (`assets/ui/title_keyart.jpg`, `assets/ui/map_painted.jpg`) | Made with the OpenAI image API for this project | https://openai.com/policies/business-terms/ | Owned by the project (OpenAI's terms assign output to the user) | Title screen; Command Table map (coast traced into `assets/map/land_mask.png`) |
| Music (`assets/audio/music/`): title = "Whispers From Beyond", town = "Where Time Stands Still", command = "Peaceful Days", meadow = "Grasslands", woods = "Prairie Nights", breakout = "Sneaking Around", blank = "Witch's Lair", boss = "Encounter With The Witches" | Juhani Junkala (SubspaceAudio) | JRPG Music Packs #1 to #5: https://opengameart.org/content/jrpg-pack-1-exploration (and packs 2-towns, 3-evil, 4-calm, 5-action) | CC0 | Background music; re-encoded to smaller Ogg Vorbis |
| Sound effects (`assets/audio/sfx/`) | Juhani Junkala (SubspaceAudio) | The Essential Retro Video Game Sound Effects Collection [512 sounds]: https://opengameart.org/content/512-sound-effects-8-bit-style | CC0 | Menus, swings, hits, deaths, level-ups, loot, alerts; converted to mono 22 kHz WAV |
| Fonts: Jersey 10 (body text) and Jacquard 12 (titles) (`assets/fonts/`) | Sarah Cadigan-Fried (The Soft Type Project) | https://github.com/scfried/soft-type-jersey and https://github.com/scfried/soft-type-jacquard (via Google Fonts) | SIL Open Font License 1.1 (`assets/fonts/OFL-*.txt`) | All game text |
| Font: Atkinson Hyperlegible (the readable font option) (`assets/fonts/`) | Braille Institute of America (Elliott Scott, Megan Eiswerth, Linus Boman, Theodore Petrosky) | https://www.brailleinstitute.org/freefont (via Google Fonts) | SIL Open Font License 1.1 (`assets/fonts/OFL-AtkinsonHyperlegible.txt`) | All game text with Options > Accessibility > Font: Readable |
| UI frames and icons (`assets/ui/`, `assets/icons/`) | Generated with PixelLab AI for this project (API, pay per call), palette-locked | https://www.pixellab.ai | Owned by the project (PixelLab output) | Panels, buttons, item/gear/ability/research/building icons |
| The Blank's hum and charged-tech sounds | Made in code for this project (`scripts/audio.gd`, `scripts/techs.gd`) | | Owned by the project | Drone near the Blank's edge and Blots; tech wind-up and release |
| Godot Engine 4.3 | Juan Linietsky, Ariel Manzur and Godot Engine contributors | https://godotengine.org/license | MIT (notice and third-party notices in `THIRD_PARTY_LICENSES.md`) | The engine the game runs on |

CC0 does not require credit, but we give it anyway. Thank you!

