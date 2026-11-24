# Translation-ready text (issue #143)

**Decision (Ojon, 2026-11-21):** Last Ink launches in English. The game is fully translation-ready,
so languages can be added after launch without touching code. Only the store page (Steam, itch.io)
gets translated for launch.

## How it works

Gettext style: **the English text is the message id.** Code and data stay readable, English needs no
catalogue, and a translation is one `locale/<lang>.po` file.

| Where the text is | What to do |
|---|---|
| A literal in a script (instance code) | `tr("Close")` |
| A literal in a static function | `Loc.t("Close")` |
| Text with numbers or names | translate first, then format: `tr("Day %d begins.") % day`, never `tr("Day %d begins." % day)` |
| Plurals | the whole sentence: `Loc.n("Surge in %d day.", "Surge in %d days.", n) % n`; a count inside a longer line: `Loc.count("%d pile", "%d piles", n)` ("5 piles"), `Loc.days(n)`. Never glue an `"s"` on in code |
| Lists of names or things | `Loc.list(names)`: "Bran", "Bran and Quill", "Bran, Quill and Tobble" |
| A key or button name | `Prompts.key("pause")`, or `Prompts.key_label(keycode)` for a raw key: named keys ("Space", "Enter", "Esc") go through the catalogue |
| Same English, two meanings | context: `Loc.t("Back", "menu button")` |
| Labels in a `const` (can't call functions there) | keep the literal, translate where it is shown: `Loc.t(STAT_NAMES[k])` |
| Prose players never see (logs, node names, HTTP headers, the bug report sent to us) | leave it plain and end the line with `# no-tr: why` |
| Text in `data/*.json` | write plain English. Files are read with `Loc.load_json()` / `Loc.data()`, which translates the keys listed in `Loc.TEXT_KEYS` (and spoken lines under `LINE_KEYS`). A **new key that holds player text goes into `Loc.TEXT_KEYS`** |
| Data text that code also matches on (expedition `kind`) | list it in `Loc.KEYED_TEXT`, show it with `tr(value)` |
| Numbers, percentages, days | `Loc.num(12500)` (12,500 / 12.500), `Loc.pct(35)`, `Loc.day(4)`, `Loc.signed(3)`, `Loc.clock(secs)` |

Don't build sentences from pieces (`tr("Likes ") + x`, `x + tr(" to resume.")`, `"%s%s" % [a, tr(" and packed")]`);
give each whole sentence its own string with `%s` where the pieces go (`tr("Likes %s") % x`), and
when a part is optional write both sentences out. Whole sentences may follow each other
(`a + " " + tr("Next sentence.")`), and a key hint from `Prompts.tag()` may be appended. Keep `%s`, `%d`, `{tag:action}`, `{a}`, `{lead}` and other
tokens exactly as they are in translations.

## Tests

`tests/test_loc.gd` (part of `tools/run_tests.sh` and CI):

- **No untranslated literals:** any string literal in `scripts/` that reads like text must be in
  `tr()` / `Loc.t()`, in a const, or on a `# no-tr` line. The rules for "reads like text" are in
  `tools/loc_scan.gd` (ids, paths, colours and log lines are skipped).
- **No unknown data text keys:** a string in `data/` that reads like text under a key the loader
  does not translate fails, naming the file and key path.
- Spoken lines keep speaker and expression ids; ids are never translated.
- Pseudo-localisation reaches both script and data text.
- Number/day formatting, counted phrases and lists.
- **No plural suffixes** (`"" if n == 1 else "s"`) and **no glued fragments** (`tr("Likes ") + x`,
  `x + tr(" to resume.")`, `tr(" and ").join(...)`) in `scripts/` (issue #183).
- The UI fonts (Jersey 10, Jacquard 12, and Atkinson Hyperlegible for the readable font option) have glyphs for accented Latin (German, French, Spanish,
  Portuguese, Italian, Polish, Czech). Chinese, Japanese, Korean or Cyrillic would need a fallback
  font (not planned for launch).

## Finding clipped text (longer languages)

German runs about 30% longer than English. Start the game with pseudo-localisation, which accents
every translated string, brackets it and makes it 30% longer:

- desktop: `godot --path . -- --pseudo-loc`
- web build: add `?pseudo` to the address, e.g. `https://trabiin.github.io/last-ink/?pseudo`

Text that loses its closing `]` is clipped; text without accents was missed by the translation pass.

## Making a translation

1. `tools/extract_strings.sh` writes `locale/messages.pot` (CI also builds it for every change:
   the `messages-pot` artifact on the workflow run). It is generated, so it is not kept in git.
2. A translator makes `locale/de.po` from it (Poedit, Weblate, Crowdin...).
3. Add the file to `project.godot`:
   ```
   [internationalization]
   locale/translations=PackedStringArray("res://locale/de.po")
   ```
4. The game picks it up: the system language is used when a catalogue exists for it, and an
   Options row appears to choose the language once there is more than one (a change restarts the
   game, since data is translated as it loads).

Not translated on purpose: character names that are names (a catalogue may still give them a
local form, and a recruit with a title or nickname spells its short form out in
`data/recruits.json` under `"short"`, so no code knows English titles), the Godot licence notice
(a legal text), and the developer log / bug report text.

Resource names after numbers ("12 Gilt", "4 Supplies", "+3 Fray", "2 Insight") are unit labels and
stay one form; a translation picks a form that reads after any number.

Raid and Salvage briefs in `data/mission_types.json` take the loot count as a counted phrase
("at least %d of the %s" + `"noun": "box"`); `MissionTypes.counted()` turns it into "5 boxes".

The credits box wraps by pixel width (`InkMenu.wrap_px`), so the AI statement and licence text
reflow for any language with spaces between words.
