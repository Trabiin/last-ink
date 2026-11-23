# AI use in Last Ink

This is the one place where we say how generative AI was used to make Last Ink. Every public text about
AI (Steam, itch.io, press kit, playtest invites, in-game credits) is copied from here, word for word or
shortened, never reworded into something softer. The provenance log at the bottom backs every claim up.

**Status:** draft. Ojon approves the wording before it goes anywhere public (issue #164). Terms of each
tool (who owns the output, commercial use) are in [LICENSES.md](LICENSES.md).

Why this exists: players punish *hiding* AI and *vague or defensive* wording far more than careful use
that is disclosed up front (research: project files `last-ink/research/ai-reception.md`). So we are
specific, plain and calm, and we never claim more human work than happened.

## 1. The public statement

> **AI use in Last Ink**
>
> Last Ink is made by one developer working with AI tools. Some players care a lot about this, and that's
> fair, so here is exactly where AI was used.
>
> - **Pixel art.** Characters, enemies, tiles, props, buildings, icons and menu frames started as AI
>   generations (PixelLab). They were then fitted to one locked style in code: snapped to a fixed palette,
>   cleaned of stray pixels, checked frame by frame, with broken animation frames rebuilt and some figures
>   resized to match the cast. Lighting, shadows, fog, weather and combat effects are drawn by the game's
>   code, not generated.
> - **Portraits and painted art.** Character portraits, the title illustration and the painted world map
>   were generated with OpenAI's image model from our own character designs and a fixed style guide, then
>   cut out, converted to pixel art and checked against each character's sprite.
> - **Writing.** The world, the cast and the direction of the story are mine. An AI assistant (Claude)
>   drafted most of the dialogue and in-game text from that direction, and I review and edit it.
> - **Code.** The game's code was written with an AI coding assistant (Claude), directed and tested by me.
>
> **Not AI:** the music and sound effects are free CC0 work by Juhani Junkala (SubspaceAudio), and the
> fonts are by Sarah Cadigan-Fried. A few combat and ambient sounds are synthesized in code. There are no
> AI voices. Nothing is generated while you play: everything in the game was made before release, and the
> game never connects to an AI service.
>
> The full list of every asset folder, where it came from and what was done to it, is here:
> https://github.com/Trabiin/last-ink/blob/main/docs/AI_USE.md#5-provenance-log

### Short version (2 sentences)

For the playtest invite, the itch.io page header, social posts and the in-game credits. Always link the
full statement next to it.

> Last Ink is made by one developer working with AI tools. The pixel art and portraits started as AI
> generations and were reworked into one locked style, and an AI assistant helped write the code and text.
> The music and sound effects are by human artists, and nothing is generated while you play.

The in-game credits read this from `data/ai_use.json` (keys `heading`, `short`, `more`). Keep the two in
step: change one, change the other, and tell the playtest survey (#168), which keeps a copy in
`data/playtest.json`.

### Keeping it true

The statement must match the build that ships. Update it (and the short version, and every place in
section 2) when any of these happen:

- the store and key art decision (#165) lands: if a human artist makes them, add "Store and key art is by
  [artist]." If the title illustration is replaced, change the portraits line;
- the soundtrack changes (#141): if any music is generated or commissioned, say so;
- a new kind of asset or a new tool is added (story CGs #117, expression portraits #107, a new
  generator): add it to the bullets and to the provenance log;
- the writing process changes (for example a full human voice pass, #167): update the Writing line to
  what actually happened, no further.

Never write "AI-assisted" for something that is mostly AI, and never "hand-drawn" or "hand-made" for art
that was generated and processed in code. OpenAI's terms also forbid presenting its output as human-made.

## 2. Where it goes

| Place | What to use | Issue |
|---|---|---|
| Steam, *AI Generated Content Disclosure*, "pre-generated content" box | The full statement, without the heading and the link line. Code is exempt on Steam's form, but the line stays so the text is the same everywhere. | #151 |
| Steam, "live-generated content" | Leave unticked: nothing is generated at runtime. | #151 |
| itch.io, *AI generation disclosure* field | Answer **Yes**. Tags: **Graphics**, **Text & Dialog**, **Code**. Not **Sound**. | #126 |
| itch.io page | Short version near the top, full statement in a section at the bottom. | #126 |
| Press kit, "AI statement" section | The full statement. | #153 |
| Playtest invite and survey | Short version plus a link to the full statement, in the invite itself, before anyone plays. | #168 |
| In-game credits (title screen > Credits) | Short version plus "Full statement and asset list: ..." from `data/ai_use.json`. | #118 |
| Devlogs, social posts that show art | Link the full statement in the profile or post when AI art is shown. | |

## 3. Marketing rule

Trailers, screenshots, GIFs, capsules and store art show only what is in the game, captured from a real
build. No AI image that does not appear in the game, no "concept art" made for marketing only, no
upscaled or retouched screenshots. Store and marketing art is where players punish AI hardest (92% of
review mentions are negative), and whether the store and key art should be made by a human artist is
decided separately in #165.

Before any public screenshot: the proportion and angle fixes (#94, #97) and the per-chapter artefact audit
(#166, `docs/AI_AUDIT.md`) are done for what is on screen. Inconsistent heads and mixed angles read as
"AI slop" even when they are not.

## 4. Answering questions about AI

Reviews, forums, Discord, comments, press.

- **Be brief, calm and specific.** Two or three sentences, then the link to section 1.
- **Agree that it's a fair thing to care about.** People are allowed to skip the game over it.
- **Point to facts, not feelings:** the provenance log says what was used where.
- **Never argue** with a negative review about AI, never reply twice in the same thread, never call anyone
  names or guess at their motives.
- **Never say** "everyone uses it", "it was too expensive to hire people", "it's just a tool", "you can't
  even tell", or "real artists use references too".
- **Say thank you** when someone points at a specific asset that looks wrong, and look at it: it goes on
  the fix list (#166).

Sample replies (adjust to the question):

> **"Is this AI?"** Yes, partly, and we say exactly where: the pixel art and portraits started as AI
> generations and were reworked to one style, and an AI assistant helped with the code and writing. The
> music and sound are by human artists. Full details: [link]

> **Negative review about AI.** Thanks for playing and for saying it plainly. We understand this matters to
> a lot of people; everything about how we used AI is listed here: [link]

> **"This looks AI-generated, you didn't disclose it."** We do disclose it, on the store page and here
> [link], including a list of every asset folder and where it came from.

> **Someone points at a broken sprite or a changed face.** Thanks, you're right that it's off. It's on our
> fix list now.

## 5. Provenance log

Every folder that ships with the game, where its contents came from, and what was done to them after.
`tests/test_ai_use.gd` fails if a folder under `assets/` is missing from this table, so a new folder has to
be logged before it can merge. Costs per call are in `docs/ART_SPEND.md` and the ledgers
`tools/art_spend*.jsonl`. Licences and tool terms: `CREDITS.md`, [LICENSES.md](LICENSES.md).

Legend: **Gen AI** = generated by a generative AI model. **Code** = drawn or synthesized by our own code,
no AI model involved. **CC0 / OFL** = made by human artists, free licence.

| Path | Source | Gen AI? | What was done after |
|---|---|---|---|
| `assets/sprites/` | PixelLab (character from text, v3 animation), Nov 2026, through the API. Ash's base came from the detail trial (PR #81, PixelLab free trial + API) and every later Ash animation builds on it. | Gen AI | Snapped to the fixed 38-colour style palette and stray specks dropped (`tools/palette_lock.py`); some figures resized to match the cast with PixelLab's pixel-art resize; idle strips rebuilt from rotation frames and head bands locked where the generator turned heads (`tools/fix_frames.py`, `tools/ai_fixes.json`); clothing colours matched to the portraits (`tools/recolor_sprite.py`); three directions mirrored in game. Every strip checked by eye (`docs/AI_AUDIT.md`). |
| `assets/sprites/_orig/` | Untouched PixelLab originals of sprites changed by the fixes above. | Gen AI | None (kept for before/after and redos). |
| `assets/tiles/` | Corner tiles (`DDDD.png` to `GGGG.png`) per biome: PixelLab tilesets. Ground fills (`grass.png`, `cobbles.png`): mostly drawn by code (`tools/make_ground.py` for the biomes, `tools/make_cobbles.py` for the town cobbles). | Gen AI + Code | Palette-snapped; grass retinted per biome inside the palette (`tools/retint_tiles.py`). Maps are laid out from text files in `maps/`, not generated images. |
| `assets/props/` | PixelLab Pro, style-locked to the target plaza (`docs/ART_STYLE.md`). | Gen AI | Picked by eye from several options, palette-snapped; variants (`_v1`, `_v2`...) made by code: eave and contact shading, side shade, recolours (`tools/depth_pass.py`, `tools/recolor_prop.py`, `tools/resize_prop.py`). |
| `assets/props/_orig/` | Untouched PixelLab originals of the props above. | Gen AI | None. |
| `assets/buildings/` | PixelLab Pro in true 3/4 view (#94); levels 1 and 2 made from level 3 with PixelLab image edit. | Gen AI | Palette-snapped, depth shading by code (`tools/depth_pass.py`). Forge and Market made the same way (`tools/make_forge_market_art.py`). |
| `assets/icons/` | PixelLab Pro at 32x32, 8 options per concept (`tools/make_item_icons.py` for the item icons). | Gen AI | Picked by eye, palette-snapped. |
| `assets/ui/` | `panel_*.png`, `button.png`: PixelLab Pro. `map_painted.jpg`: OpenAI image model (gpt-image-2 edit) from a province layout drawn for the project. `title_keyart.jpg`: OpenAI image model from the cast's portrait designs. | Gen AI | Frames palette-cleaned. The map's coast is traced by code into `assets/map/`. Known flaw in the key art (second sword hilt) waits on #165. |
| `assets/map/` | `land_mask.png`, traced from the painted map by code (`tools/trace_land.py`). | Code | Provinces are laid over it by the game. |
| `assets/portraits/` | OpenAI image model (ChatGPT image generation and the image API) from prompts in `docs/PORTRAITS.md`: our character designs plus one fixed style block. | Gen AI | Cut out of the grey background and converted to 224x336 pixel art by code (`tools/cut_portraits.py`), checked against each sprite (`tools/character_sheet.py`) and by `tests/test_portraits.gd` (size, hard edges, specks, halo). |
| `assets/icon/` | App icon drawn pixel by pixel by code (`tools/make_icon.py`). | Code | None. |
| `assets/characters/` | Puny Characters by Shade (CC0), split into paper-doll layers by `tools/import_art.py`. Only a fallback for figures without a sprite set. | CC0 | Recoloured per figure by `shaders/palette_swap.gdshader`. |
| `assets/source/` | Untouched CC0 originals: Puny Characters (Shade), Zelda-like tilesets (ArMM1998). | CC0 | None. |
| `assets/audio/` | Music: JRPG Music Packs 1 to 5; sound effects: 512 Sound Effects (8-bit style). Both by Juhani Junkala (SubspaceAudio), CC0. | CC0 | Re-encoded (Ogg Vorbis music, mono 22 kHz WAV effects). |
| `assets/fonts/` | Jersey 10 and Jacquard 12 by Sarah Cadigan-Fried (The Soft Type Project); Atkinson Hyperlegible by the Braille Institute. | OFL | None. |
| Synthesized sounds | The Blank's hum (`scripts/audio.gd`) and the charged-tech sounds (`scripts/techs.gd`). | Code | Made at runtime from fixed recipes; no AI model. |
| Effects | Lighting, cast shadows, clouds, mist, vignette, weapon trails, the Blank's edge, ink motes (`shaders/`, `scripts/ambience.gd`, `scripts/art.gd`). | Code | No AI model. |
| `maps/` | Text map layouts written for the project; biome maps produced by `tools/make_biomes.py` (rule-based, not a generative model). | Code | Hand-tuned spots and lines. |
| `data/` text | Dialogue, bond scenes, journal, item and quest text: drafted by an AI assistant (Claude) from Ojon's direction, reviewed and edited by Ojon. | Gen AI (writing) | Voice pass and LLM-prose ban list: #167. |
| `scripts/`, `shaders/`, `tools/` | Code written with an AI coding assistant (Claude), directed and tested by Ojon. | Gen AI (code) | Automated tests (`tests/`), playtests. |

Nothing in the shipped game calls an AI service; the API tools in `tools/` (`pixellab.py`,
`openai_image.py`) run only while making the game.

## 6. Awards, festivals and showcases

Rules change every year: check each one's current rules before entering. If a rule or the jury bans
generative AI in any part of the game, **don't enter**. Being disqualified, or having an award taken back,
is worse than not entering (Clair Obscur lost two Indie Game Awards in Dec 2025 this way).

| Event | Gen AI position (as of Nov 2026) | Enter? |
|---|---|---|
| Indie Game Awards | "A hard stance against gen AI in videogames"; retracted Clair Obscur's Game of the Year and Debut Game over shipped AI placeholder textures ([PC Gamer, Dec 2025](https://www.pcgamer.com/games/rpg/indie-game-awards-pulls-two-awards-from-clair-obscur-over-generative-ai-use-we-have-a-hard-stance-against-gen-ai-in-videogames)) | No |
| Independent Games Festival (IGF 2027) | No AI rule in the official rules, but 19 named jurors declined to vote for "any game that uses generative AI in any capacity", code included, and asked the IGF to adopt a ban ([Aftermath, Nov 2026](https://aftermath.site/igf-awards-2027-ai-statement-judges/), [IGF rules](https://igf.com/igf-competition-rules/)) | No (2027 entries closed in Sep 2026 anyway); recheck for 2028 |
| Games Without AI showcase (Dev Land Marketing) | Entries must not use gen AI for art, music or voice; games found to use it are removed and the studio barred ([GameBusiness.jp, Oct 2026](https://www.gamebusiness.jp/article/2026/10/31/28519.html)) | No |
| Steam Next Fest | Open to games with an AI disclosure; about a fifth of demos carry one ([AITopics](https://aitopics.org/doc/news:9EB54EAF)) | Yes (with the disclosure filled in) |
| Others to check before entering (rules not yet checked): BIG Festival, IndieCade, A MAZE, Day of the Devs, PAX Rising, Develop:Star Awards, regional showcases | Unknown | Check first, add a row |

When a call for entries opens, add or update the row with a link to the current rule.
