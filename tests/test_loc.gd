extends "res://tests/test_case.gd"
## Translation-ready text (issue #143, docs/LOCALIZATION.md): every player-facing string can reach a
## translator and comes back translated, and the UI copes with longer languages.

const Scan := preload("res://tools/loc_scan.gd")


## No player-facing literal in scripts/ skips tr() / Loc.t(). Fix: wrap it, move it to a const that is
## translated where shown, or end the line with "# no-tr" if players never see it.
## Data files the game never loads or shows (tools and tests read them), so nothing in them is translated.
const DEV_ONLY := ["placeholders.json"]  # the art batch's to-do list (issue #28)

func test_script_text_is_wrapped() -> void:
	var scan := Scan.new()
	var bad := 0
	for f in DirAccess.get_files_at("res://scripts/"):
		if not f.ends_with(".gd"):
			continue
		for t in scan.script_texts("res://scripts/" + f):
			if not t["wrapped"] and not t["const"]:
				bad += 1
				check(false, "scripts/%s:%d: player text not in tr(): \"%s\"" % [f, t["line"], str(t["text"]).left(70)])
	check(bad == 0, "%d untranslated literal(s); see docs/LOCALIZATION.md" % bad)


## Every string in data/ that reads like text is under a key the loader translates (Loc.TEXT_KEYS,
## LINE_KEYS, VOICE_KEYS) or is listed in Loc.KEYED_TEXT. A new text key goes into Loc.TEXT_KEYS.
func test_data_text_keys_are_known() -> void:
	var scan := Scan.new()
	for f in DirAccess.get_files_at("res://data/"):
		if not f.ends_with(".json") or f in DEV_ONLY:
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))
		for u in scan.data_unkeyed(f, parsed):
			check(false, "data/%s %s: \"%s\" reads like player text but its key is not in Loc.TEXT_KEYS (or is an id with capitals)" % [f, u[0], str(u[1]).left(60)])


## Spoken lines keep their speaker and expression ids; only the words are text.
func test_lines_split_speaker_and_text() -> void:
	check(Loc.is_line(["bran", "Huh. A person.", "surprised"]), "a line with an expression")
	check(Loc.is_line(["", "Grass. Wind."]), "narration")
	check(not Loc.is_line(["First thing to say.", "Second thing."]), "two plain help lines are not a line")
	var d := {"lines": [["bran", "Hello there.", "smug"], "A plain line."], "id": "Not Text", "name": "Bran"}
	var got := []
	Loc.each_text(d, "x.json", func(s): got.append(s))
	check_eq(got.size(), 3, "texts found in a sample")
	check(not "bran" in got and not "smug" in got and not "Not Text" in got, "ids are not text: %s" % str(got))


## The whole chain works: with pseudo-localisation on (accents, +30% length), script text and data
## text both come back changed, and ids stay as they are.
func test_pseudo_locale_reaches_scripts_and_data() -> void:
	TranslationServer.pseudolocalization_enabled = true
	var s := Loc.t("Close")
	var pl := Loc.days(3)
	var data = Loc.data({"name": "Gristle", "id": "gristle", "lines": [["bran", "Hello.", "smug"]]}, "test.json")
	TranslationServer.pseudolocalization_enabled = false
	check(s != "Close" and s.length() > 5, "script text is pseudo-localised: %s" % s)
	check(pl != "3 days" and pl.contains("3"), "plurals are pseudo-localised too: %s" % pl)
	check(data["name"] != "Gristle", "data text is pseudo-localised: %s" % data["name"])
	check_eq(data["id"], "gristle", "ids are untouched")
	check_eq(data["lines"][0][0], "bran", "speaker stays an id")
	check_eq(data["lines"][0][2], "smug", "expression stays an id")
	check(data["lines"][0][1] != "Hello.", "spoken text is pseudo-localised")


## Numbers and days go through one helper and follow the language.
func test_number_and_day_formatting() -> void:
	check_eq(Loc.num(950), "950", "small numbers")
	check_eq(Loc.num(12500), "12,500", "grouping in English")
	check_eq(Loc.num(-1234567), "-1,234,567", "negative grouping")
	check_eq(Loc.signed(3), "+3", "signed")
	check_eq(Loc.day(4), "Day 4", "day")
	check_eq(Loc.pct(35.4), "35%", "percent")
	check_eq(Loc.dec(1.5), "1.5", "decimals")
	check_eq(Loc.clock(187), "3:07", "clock")
	check_eq(Loc.languages()[0], "en", "English is always there")


## Both UI fonts draw the accented Latin of the big European languages (German, French, Spanish,
## Portuguese, Italian, Polish, Czech...), so those can be added without new fonts.
func test_fonts_cover_accented_latin() -> void:
	var chars := "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝàáâãäåæçèéêëìíîïñòóôõöøùúûüýÿßŒœ¿¡«»„“”‘’–—…ĄąĆćĘęŁłŃńŚśŹźŻżČčĎďĚěŇňŘřŠšŤťŮůŽž"
	for path in ["res://assets/fonts/Jersey10-Regular.ttf", "res://assets/fonts/Jacquard12-Regular.ttf",
			"res://assets/fonts/AtkinsonHyperlegible-Regular.ttf", "res://assets/fonts/AtkinsonHyperlegible-Bold.ttf"]:  # + the readable font (#192)
		var f: Font = load(path)
		var missing := ""
		for c in chars:
			if not f.has_char(c.unicode_at(0)):
				missing += c
		check(missing == "", "%s has no glyph for: %s" % [path.get_file(), missing])


## Issue #183: no English plural tricks. A count picks its words through Loc.n / Loc.count, which
## follow each language's plural rules, never a "s" suffix glued on in code.
func test_no_english_plural_suffixes() -> void:
	var suffix := RegEx.create_from_string("\"\" if [^\"]+ else \"(s|es)\"|\"(s|es)\" if [^\"]+ else \"\"")
	for f in DirAccess.get_files_at("res://scripts/"):
		if not f.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string("res://scripts/" + f).split("\n")
		for n in lines.size():
			if suffix.search(lines[n]) and not "no-tr" in lines[n]:
				check(false, "scripts/%s:%d: plural built with a suffix; use Loc.n(\"%%d day\", \"%%d days\", n) %% n" % [f, n + 1])


## Issue #183: no sentences glued from translated pieces. A fragment like tr("Likes ") + x or
## x + tr(" to resume.") can't be reordered by a translator; write tr("Likes %s") % x instead.
## Whole sentences may still follow each other, and key hints (Prompts.tag) may be appended.
func test_no_glued_fragments() -> void:
	var lead := RegEx.create_from_string("(\\btr|Loc\\.t)\\(\"(?:[^\"\\\\]|\\\\.)*[ :]\"\\)\\s*\\+")
	var tail := RegEx.create_from_string("\\+\\s*(\\btr|Loc\\.t)\\(\" *[a-z.,;:(]")
	var join := RegEx.create_from_string("(\\btr|Loc\\.t)\\(\" and \"\\)\\.join")
	for f in DirAccess.get_files_at("res://scripts/"):
		if not f.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string("res://scripts/" + f).split("\n")
		for n in lines.size():
			var l: String = lines[n]
			if l.strip_edges().begins_with("#") or "no-tr" in l:
				continue
			if lead.search(l) or tail.search(l) or join.search(l):
				check(false, "scripts/%s:%d: sentence glued from pieces; give it one string with %%s (or Loc.list for lists)" % [f, n + 1])


## Counted phrases and lists (issue #183).
func test_counts_and_lists() -> void:
	check_eq(Loc.days(1), "1 day", "one day")
	check_eq(Loc.days(4), "4 days", "several days")
	check_eq(Loc.count("%d pile", "%d piles", 0), "0 piles", "zero is plural in English")
	check_eq(Loc.n("%d wants a word.", "%d want a word.", 1) % 1, "1 wants a word.", "Loc.n singular")
	check_eq(Loc.list(["Bran"]), "Bran", "one name")
	check_eq(Loc.list(["Bran", "Quill"]), "Bran and Quill", "two names")
	check_eq(Loc.list(["Bran", "Quill", "Tobble"]), "Bran, Quill and Tobble", "three names")
	check_eq(MissionTypes.counted("box", 1), "1 box", "raid loot noun, singular")
	check_eq(MissionTypes.counted("box", 5), "5 boxes", "raid loot noun, plural")


## Issue #183: names go by the short form data gives them, so a translation can rename people
## without code knowing English titles ("Old", "Mother", "Brother"...).
func test_short_names_come_from_data() -> void:
	check_eq(Empire.short_name("tobble"), "Old Tobble", "title kept")
	check_eq(Empire.short_name("ninefingers"), "Daro", "rank dropped")
	check_eq(Empire.short_name("cuthbert"), "Brother Cuthbert", "Brother is a title, not a first name")
	check_eq(Empire.short_name("jessamy"), "Jessamy", "first name")


## Engine key names (English) go through the catalogue; letters stay as they are.
func test_key_names_are_translatable() -> void:
	check_eq(Prompts.key_label(KEY_ESCAPE), "Esc", "short name")
	check_eq(Prompts.key_label(KEY_K), "K", "letters as they are")
	TranslationServer.pseudolocalization_enabled = true
	var space := Prompts.key_label(KEY_SPACE)
	TranslationServer.pseudolocalization_enabled = false
	check(space != "Space", "named keys reach the catalogue: %s" % space)
