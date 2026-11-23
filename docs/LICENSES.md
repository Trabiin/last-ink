# Licences, AI terms and the name check

Issue #157. Checked on 2026-11-21. **Not legal advice:** this records what the public terms say and what we
found; anything marked **Ojon** needs a decision or a check only Ojon can make (or a professional).

- Who made each asset: [CREDITS.md](../CREDITS.md) (also shown in-game under Title > Credits).
- Licence texts that ship with the game: [THIRD_PARTY_LICENSES.md](../THIRD_PARTY_LICENSES.md).
- Which files are AI-made and how we disclose it: `docs/AI_USE.md` (issue #164).
- Privacy note for bug reports and feedback: [PRIVACY.md](PRIVACY.md) (issue #146).

## Summary

| Area | Result | Action |
|---|---|---|
| CC0 art and audio | All 4 sources confirmed CC0 on their OpenGameArt pages | None |
| Fonts (OFL 1.1) | Fine for commercial games; licence text must travel with the font | Done: texts in THIRD_PARTY_LICENSES.md, shipped with every build |
| Godot Engine (MIT) | Notice must be included in the game or its docs | Done: credits row + full notices in THIRD_PARTY_LICENSES.md, shipped next to desktop and web builds. In-game full text: see "Open items" |
| PixelLab | Terms (updated 2026-10-30): we own the output, commercial use allowed, **no difference between free trial, subscription and API** | Ash's base character came from free-trial gens; terms cover it. **Ojon:** screenshot the pricing page's free-trial card for the records (see below) |
| OpenAI images | Output is assigned to us; commercial use allowed; we must not claim AI output is human-made | Disclosure is #164's job; nothing to replace |
| Code-made audio and FX | Ours | None |
| Name "Last Ink" | No game or game trademark with this exact name found in web searches | **Ojon:** run the free official searches below (Steam, EUIPO/TMview, USPTO, domains) before the store page |

Nothing in `assets/` has unclear terms, so nothing has to be replaced or regenerated.

## 1. Asset sources

Every folder under `assets/` traced to its source (2026-11-21, after PR #174):

| Folder | Source | Licence |
|---|---|---|
| `assets/source/zeldalike/`, `assets/tiles/overworld.png` | ArMM1998, Zelda-like tilesets and sprites | CC0 (OpenGameArt licence field checked) |
| `assets/source/puny/`, `assets/characters/` | Shade, Puny Characters (fallback paper doll) | CC0 (checked) |
| `assets/audio/music/` | Juhani Junkala, JRPG Music Packs #1 to #5 | CC0 (all 5 pack pages checked) |
| `assets/audio/sfx/` | Juhani Junkala, 512 Sound Effects (8-bit style) | CC0 (checked) |
| `assets/fonts/` | Jersey 10, Jacquard 12 (The Soft Type Project, via Google Fonts); Atkinson Hyperlegible (Braille Institute, via Google Fonts, the readable font option #192) | SIL OFL 1.1 |
| `assets/sprites/`, `assets/tiles/` (art pass), `assets/props/`, `assets/buildings/`, `assets/icons/`, `assets/ui/button.png`, `assets/ui/panel_*.png` | PixelLab, generated for this project (logged in `tools/art_spend*.jsonl`) | Ours under PixelLab's terms (section 2) |
| `assets/portraits/` | OpenAI image generation (ChatGPT and API), pixelated by `tools/cut_portraits.py` | Ours under OpenAI's terms (section 3) |
| `assets/ui/title_keyart.jpg`, `assets/ui/map_painted.jpg`, `assets/map/land_mask.png` | OpenAI image API (`tools/openai_image.py`); mask traced from the map in code | Ours under OpenAI's terms |
| `assets/icon/` | Made for this project from the game's own art | Ours |
| Sounds made in code (`scripts/audio.gd`, `scripts/techs.gd`), shaders, code-drawn FX and UI | Written for this project | Ours |

Not in the project yet: **GodotSteam** (#150) is MIT; when it is added, append its licence to
THIRD_PARTY_LICENSES.md and a row to CREDITS.md. Steamworks SDK redistributables are covered by Valve's
Steamworks SDK licence that Ojon accepts in Steamworks.

## 2. PixelLab

Sources: [Terms of Service](https://www.pixellab.ai/termsofservice) (Last Updated 2026-10-30, Pixel Heart AB,
Swedish law) and the [FAQ](https://www.pixellab.ai/docs/faq).

- s.1.3: "You own the copyrights to your creations, permitting usage for both commercial and non-commercial
  purposes with no need for permission."
- s.3.3: "You retain ownership of any content you create using PixelLab", "free to use, modify, and distribute
  the outputs from our tools for any purpose", except training other models.
- FAQ: "Can I use the generated images commercially?" "Yes, we only ask that you do not train new models with
  the images." FAQ on Steam: "Yes, you are allowed to use AI assets in your games."
- No attribution required. No clause makes free-tier or trial output non-commercial, watermarked or public.
- Conditions we follow: don't train models on the output (s.1.2); the terms incorporate the Open RAIL-M
  use restrictions (s.4.1: no harmful uses such as harassment or disinformation; a game is fine); we are
  responsible for not infringing anyone else's rights with what we generate (s.3.3), so no prompts naming
  other games, artists or characters (docs/ART_PROMPTS.md already follows this).
- Programmatic use must go through the official API (s.2.2), which is what `tools/pixellab.py` does.

### The free-trial art

Ojon's free-tier test (2026-11-17) art was removed in Phase 0/1 (commit 74befb4). One thing remains:
the **detail trial** (PR #81, 2026-11-19) used Ojon's last 16 free-trial generations plus about $0.20 of API
credit, and Ash's PixelLab character **"Ash trial 32"** comes from it. Every later Ash animation was generated
on that base through the paid API (docs/ART_PROMPTS.md, "Character descriptions used").

Because the terms give ownership and commercial rights for all output with no tier distinction, this is covered
and **does not need regenerating**. Redoing it would cost about $0.30 but would change Ash's approved look and
every animation, so we recommend keeping it.

**Ojon (2 minutes, free):** open pixellab.ai's pricing section in a browser and screenshot the free-trial card.
A third-party summary (respawnstack.com, 2026-10-22) reports the card says "Use generated images commercially"
with a "***" footnote; we could not load the card (it renders in the browser only), so the footnote is unread.
Save the screenshot in project files `last-ink/legal/` so we have proof of the terms on the day.

## 3. OpenAI image generation

Sources: [Terms of Use (rest of world, effective 2026-01-01)](https://openai.com/policies/row-terms-of-use/)
for ChatGPT, [Business Terms](https://openai.com/policies/business-terms/) for the API. Users in the EU/UK fall
under OpenAI's EU terms for ChatGPT, which (like the others) assign output to the user; we did not fetch that
page, so **Ojon** can glance at it if wanted.

- Terms of Use: "you (a) retain your ownership rights in Input and (b) own the Output. We hereby assign to you
  all our right, title, and interest, if any, in and to Output." Commercial use is allowed ("for any purpose,
  including commercial purposes such as sale or publication").
- Business Terms 3.1 (API): the same assignment of all Output.
- Conditions we follow: never "represent that Output was human-generated when it was not" (our AI statement,
  #164, covers this); output may not be unique, so other users can get similar images; no OpenAI name or logo
  in the game or marketing.

## 4. A note on AI output and copyright

In the US (and likely the EU) purely AI-generated images may not be protected by copyright, whatever the tool's
terms say. That doesn't stop us selling the game. It means someone could reuse a sprite with weaker recourse.
The parts with clear human authorship are protected as normal: the code, writing, level design, our edits,
pixel clean-up, palette locking, animation assembly and the game as a whole. Nothing to do now.

## 5. Name check: "Last Ink"

Searched on 2026-11-21 with web search (the stores, trademark registers and domain lookups themselves are
blocked from this environment, so these need a quick manual pass, see below).

| Where | What we found |
|---|---|
| Steam | No game called "Last Ink" in search results |
| itch.io | No game called "Last Ink". Nearest: **"Last Inkwarden"** by JoyerH (a small itch.io game; page could not be opened to see details). Different name, but close enough that the store search should be checked |
| Other games | Nothing with this exact title. Similar but distinct: *Inked* (2018), *INK* (indie platformer) and *Ink* (board game), *The Last Tinker*, *The Last Night* |
| US trademarks (Justia index of USPTO) | No "LAST INK" mark found. Nearest marks are unrelated ink/printing names (LIVING INK, LIVE INK, ETERNAL INK, THE LAST INCH) |
| EU trademarks | Not checked (EUIPO/TMview blocked here) |
| Domains and handles | Not checked (lookups blocked here). Fallbacks if `lastink.com` is taken: `lastinkgame.com`, `playlastink.com`; handle `@lastinkgame` |

So far the name looks free for a game. A web search can miss a registered mark or a small store page, so:

**Ojon, before the Steam store page (#151), about 10 minutes, all free:**
1. Steam: search "Last Ink" on store.steampowered.com and on SteamDB (catches unreleased apps).
2. itch.io: search "Last Ink", and open joyerh.itch.io/last-inkwarden to see what it is.
3. EU + national marks: search the word "last ink" on TMview (tmdn.org/tmview), classes 9 (game software) and
   41 (entertainment). Also the Benelux register (boip.int) if you are in the Netherlands.
4. US marks: search "last ink" on tmsearch.uspto.gov, same classes.
5. Domain and handles: check lastink.com / lastinkgame.com at any registrar, and @lastinkgame on X, Bluesky,
   TikTok, YouTube. Buying a domain (~$10 a year) is optional and Ojon's call.

If any of those turns up a game or a class 9/41 mark called "Last Ink", tell Claude and we'll pick a fallback
following docs/NAMING.md. Filing our own trademark is optional (~$250 to $350 per class in the US, EUR 850 for
one class at the EUIPO) and not needed to sell on Steam.

## 6. Open items

- **In-game licence text (web build):** the Credits screen lists Godot (MIT) and the asset licences; the full
  texts ship as `THIRD_PARTY_LICENSES.md` next to desktop builds and the web build, and inside the game pack.
  Showing the full text in-game (Godot's `Engine.get_license_text()` plus this file) belongs in the Credits
  screen, which #164 is editing now; follow-up after that merges.
- macOS: the Godot-exported .app zip has no room for loose files; the licences are inside the pack and listed
  in Credits. Revisit when the macOS build gets a proper installer or Steam depot (#150).
- EULA: Steam's default Subscriber Agreement is enough; no custom EULA needed for now. itch.io has no EULA
  requirement either.
- Business side (tax info in Steamworks, sole trader or company): **Ojon's** call, outside the repo.
- Steam's content survey (Mature content, AI disclosure) must match `docs/AI_USE.md` (#151, #164).
