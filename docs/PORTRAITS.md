# Character portraits

Large visual-novel portraits shown in dialogue and bond scenes (issue #12).

## Where they live

| File | What |
|---|---|
| `assets/portraits/<id>.png` | Game portrait: hi-res pixel art, 224x336, hard-edged transparent background (style picked by Ojon on 2026-11-21, issue #169). `<id>` is the recruit id (`ash`, `bran`, `gristle`) or a speaker id from `data/dialogue.json` / `data/story.json` (`verity`, `auditor`, `clerk`, `governor`, `warden`, `captain`). |
| `assets/portraits/<id>_<expr>.png` | Optional expression: `happy`, `angry`, `sad`, `surprised`, `smug`. Code falls back to `<id>.png` when one is missing. |
| `tools/cut_portraits.py` | Turns raw generator output into game portraits: cuts out the flat grey background (also pockets between hair strands, the pale glow the generator paints round strands, and stray specks), cleans the grey out of the edge colours, then pixelates to 224x336 with `tools/portrait_style.py` (32 colours per portrait, pulled toward the game palette, 1px ink outline). `--painted DIR` also saves the painted 512x768 cut-out. |
| `tests/test_portraits.gd` | Fails on a portrait with the wrong size, soft alpha, stray specks or leftover background on the silhouette edge. |

Raw 1024x1536 originals are kept in the project's shared files (`last-ink/portraits/`), not in the repo, to keep the web build small.

To add one: save the raw image as `<id>-v2.png` (or `<id>_<expr>-v2.png`) in a folder, run
`python3 tools/cut_portraits.py <folder> --only <id> --painted <folder>/painted`, look at the result on a dark
background and in the dialogue box (`tools/shot.gd scene=town talk=<talk>`), run `tools/run_tests.sh portraits`,
open the project in Godot once so it imports, commit `assets/portraits/`. Put the raw image and the painted cut-out
in project files `last-ink/portraits/`.

Why pixel art: the painted portraits looked pasted on top of the pixel world. Shown at 1 canvas pixel per art pixel
(2 screen pixels, half the world's pixel size) they read as part of the game and faces still hold up. Comparison:
project files `last-ink/art-pass/portrait-style/`. Code draws them at whole-number scales only
(`Dialogue.portrait_size` / `Dialogue.fitted`; the journal thumbnail is shrunk smoothly).

## How the game uses them

- Bond scenes (`scripts/scene_view.gd`): the character stands on the left, flipped to face Ash on the right. Whoever has the floor is lit; the other is dimmed and pushed back. A soft glow in the character's accent colour sits behind each. A line in `data/bonds.json` can carry a third entry, an expression: `["bran", "Read it again.", "smug"]`.
- Every speaker has a portrait: `tests/test_data.gd` fails the build when one is missing, so the code-drawn safety-net bust never ships. The one exception is a letter read aloud (`"stage": "letter"` on the speaker), which stands on stage as a sealed sheet of paper.
- The dialogue system (#11) loads the same files by the same naming.

## Tool and terms

Generated with **ChatGPT image generation** (OpenAI). OpenAI's Terms of Use assign rights in output to the user and allow commercial use, so the portraits can ship in the game. Keep a note in `CREDITS.md` if the tool changes (for example PixelLab for sprites, whose output the project also owns).

## The style prompt

Every prompt starts with this block, then one paragraph describing the character and ending with their expression. Run each in a new chat, ask for 2:3 portrait.

```
Visual novel character portrait for a dark surreal fantasy game, made to be converted into pixel art. Half-body, neutral pose, plain flat light-grey background, no text, no glow or rim light against the background. Anime-influenced illustration with bold clean dark ink outlines and flat cel shading in two or three tones per material, light coming from the top left. Big readable shapes: hair drawn as a few large locks, no thin flyaway strands; no fine fabric texture, grunge, scratches or speckled weathering; no tiny repeated details. Muted palette of charcoal, bone white and rust, with one saturated accent color per character. Erased-paper edges on clothing drawn as a few clean torn shapes, not specks. Portrait 2:3 aspect ratio. Straight-on camera at the character's own eye level, never looking up from below or down from above. Body angled three-quarters toward the viewer's left, framed from the waist up, with empty space above the head and nothing (hair, weapons) cut off by the frame edges. Stylized anime faces with simple cel-shaded skin and clearly drawn eyes, even for older or rugged characters, no realistic skin texture. Same line weight and face style as a cohesive anime character roster.
```

What changed (2026-11-21, pixel style): portraits are now shrunk to 224x336 pixel art, so the prompt asks for what
survives that: bold outlines, flat cel shading, large hair locks, top-left light like the world, and no fine texture,
flyaway strands or background glow (those turned into noise and white specks). The old block, for matching the
existing portraits when an expression is added for one of them:

```
Visual novel character portrait for a dark surreal fantasy game. Half-body, neutral pose, plain flat light-grey background, no text. Painterly anime-influenced illustration with clean dark ink linework and soft cel shading. Muted palette of charcoal, bone white and rust, with one saturated accent color per character. Subtle ink-splatter and erased-paper edges on clothing. Portrait 2:3 aspect ratio. Straight-on camera at the character's own eye level, never looking up from below or down from above. Body angled three-quarters toward the viewer's left, framed from the waist up, with empty space above the head and nothing (hair, weapons) cut off by the frame edges. Stylized anime faces with simple cel-shaded skin, even for older or rugged characters, no realistic skin texture. Same line weight and face style as a cohesive anime character roster.
```

Keep the background plain light grey: the cut-out tool depends on it.

**Accent colours** (one per character): Ash ink-blue, Bran rust-orange, Fauvette crimson, Verity violet, Mother Gristle poison green, Ilse icy cyan. Pick a new, distinct one for each new character.

### Character paragraphs used so far

- **Ash:** a quiet young swordsman around 20. Messy black hair, pale skin, faint black ink stains creeping up his hands and neck. Tattered charcoal cloak whose frayed edges fade to blank white, with a deep ink-blue lining as his accent. Dark leather vest, steel shortsword at his hip. Calm, unreadable, determined expression.
- **Bran:** a broad-shouldered mercenary in his 40s. Shaved head, scarred jaw, grey stubble, one clouded eye. Dented grey plate pauldron over a stained brown gambeson, with a rust-orange sash as his accent. A contract written in tiny black script is tattooed down his bare forearm. Heavy axe on his back. Wry, tired half-smirk, a man who'd sell you out for the right price but apologise first.
- **Fauvette:** an elegant woman around 30, a duelist and courtesan-spy. Sleek wine-red bob, sharp eyeliner, beauty mark. Fitted black high-collared coat with gold buttons and a deep crimson inner lining as her accent, long gloves, thin rapier. Playful, knowing smile with one raised eyebrow.
- **Verity Hale:** a former chief archivist in her early 50s, now a quiet villain. Tall and thin, silver-streaked dark hair pinned up neatly, a few loose strands, faint lines around tired grey eyes, small round reading spectacles. Long bone-white archivist's robe with a high collar, ink-stained cuffs, and a deep violet stole as her accent. Her right hand and the hem of her robe are fading into blank white paper, as if erased. Holds a closed ledger against her chest. Polite, weary, gently sad smile, someone who believes she is doing the merciful thing.
- **Mother Gristle:** a hunched, sturdy old woman around 70, a swamp herbalist who heals for money. Wild grey hair tied back with twine, sharp hooked nose, deep wrinkles, gold-capped front tooth, shrewd narrow eyes. Patched brown shawl over a dark apron hung with rows of small glass bottles, the liquid inside a glowing poison green as her accent. Gnarled wooden staff wrapped in dried herbs, a coin purse on her belt. Grandmotherly grin that doesn't reach her eyes, like she's already adding up your bill.
- **Ilse:** an ageless knight who is a living reflection that stepped out of a mirror after her original was erased. Strikingly beautiful, long straight pale hair, porcelain skin with thin hairline cracks like broken glass along her cheek and collarbone, her side part and beauty mark on the "wrong" side. Silvered mirror-plate armour over a dark gown, with icy cyan light glinting in the cracks and on her spear tip as her accent. Holds a slender spear upright. Faint mirrored double outline around her silhouette. Cool, vain, faintly amused expression, admiring herself more than the viewer.

### Canon looks (issue #166)

The portrait is the canon reference for each character. Every expression, CG and field sprite must keep the
items below. `python3 tools/character_sheet.py out_dir` puts portrait, expressions, CGs and the five sprite
rotations side by side for checking; see docs/AI_AUDIT.md for the audit.

| Character | Must match everywhere | Known gaps (audit 2026-11-21) |
|---|---|---|
| Ash | messy black hair, pale skin, charcoal cloak with ink-blue lining, one sword | field sprite always has the hood up, portrait and key art have it down |
| Bran | shaved head, grey stubble (not a full beard), rust-orange sash, grey pauldron, heavy axe | sprite has a full grey beard and red marks on the face |
| Mother Gristle | wild grey hair tied up, hooked nose, rust shawl, poison-green vials, gnarled staff | none |
| Ninefingers | short dark hair, mustard scarf, worn grey-brown coat, spear; one finger missing | the only hand in the portrait has all five fingers (show the missing one in expressions) |
| Jessamy | dark hood up, long dark hair, violet scarf, lantern in her right hand | none |
| Odile | black hair in a bun, round spectacles, navy uniform with gold trim, satchel and book | none |
| Ottoline | long black hair, magenta waistcoat over black shirt, rolled sleeves, arms crossed | none |
| Fauvette | crimson-red bob, black high-collared coat with crimson lining, gold buttons, rapier | none since the sprite hair recolour |
| Sister Hild | bone-white hood and robe, brown hair, glowing writ held to her chest, satchel of quills | none since the sprite hood recolour |
| Quill | grey hair, quill behind the ear, green coat, book | none |
| Tobble | bald with a white beard, cream shirt, brown apron, copper mug | none |
| Verity | silver-streaked dark hair pinned up, bone robe with violet stole, ledger | none |
| The Auditor | top hat, white mask with a red mark, black coat with red lining, quill-blade spear | sprite mask is grey with no red mark |
| Clerk Pettigrew / Ozias Crane | both balding, spectacles and a quill behind the ear | the two old clerks read as the same face; Crane should get his own look |

### Expressions

In the same chat as the locked neutral image, paste the same full prompt, replace only the last sentence with one of these, and add "Same character, same outfit, same framing, change only the facial expression."

- happy: genuine smile, eyes softened
- angry: brows drawn down, jaw tight, glaring
- sad: eyes lowered, mouth pressed thin
- surprised: eyes wide, mouth slightly open
- smug: half-lidded eyes, crooked smile

### Status

Every recruit and story speaker has a neutral portrait (Phase 8, plus Clerk Pettigrew, Governor Thale, the Concord Warden and Tithe-Captain Morrow for issue #111, and Ozias Crane, Hester Vane, Notary Fennick, Marguerite Penhallow and Augustin Sallow for the personal missions of issue #113). Expressions (`<id>_<expr>.png`) are issue #107.

## API pipeline (Phase 8)

`tools/openai_image.py OUT.png "prompt" --ref a.png --ref b.png --quality medium` calls gpt-image-2 directly (no
ChatGPT chat needed). Give it the style block above + "Match the art style, line weight, face style and rendering of
the two reference portraits exactly, but draw a new character:" + the character paragraph, with the raw Ash and Bran
portraits (downscaled to 512x768) as references. That keeps new faces on-model with the cast. A 1024x1536 medium
portrait costs about $0.054; every call is logged in `tools/art_spend.jsonl` with its token usage. The paragraphs used
are in project files `last-ink/portraits/` next to the raw images.

**The sprite is canon (Ojon, 2026-11-23).** When a portrait and the field sprite disagree, redraw the portrait to
match the sprite: pass the sprite's south and south-east rotations (scaled up 8x, nearest neighbour, on light
grey) as a third reference and add "The third reference is this character's in-game pixel sprite: the portrait
must match the sprite's design, body build, hair, colours, clothing and props exactly". Quill, Odile, Hesper and
Verity were redrawn this way ($0.059 each); briefs in project files `last-ink/portraits/phase8-prompts.json`.
Colour-only gaps can go the other way with `tools/recolor_sprite.py` (Daro, Ottoline, Velvette, Auditor).

Corporal Daro is non-binary (they/them).

## Style trial (2026-11-21)

`tools/portrait_style.py OUT_DIR quill velvette bran` makes code-only treatments of existing portraits
(grade, ink, pix336, pix168), and `tools/shot.gd ... scene=town talk=quill_first portraits=OUT_DIR/pix336`
shows one in the real dialogue box without touching `assets/portraits/` (`skip=N` starts N lines in).
Comparison images: project files `last-ink/art-pass/portrait-style/`.
