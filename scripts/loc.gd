class_name Loc
extends RefCounted
## Translation-ready text (issue #143). Everything a player reads goes through Godot's
## TranslationServer, gettext style: the English text itself is the message id, so code and data
## stay readable and English needs no catalogue at all. docs/LOCALIZATION.md has the rules.
##
## - Script text: "..." in instance code, "..." in static code. Translate BEFORE
##   formatting: tr("Day %d") % day, never tr("Day %d" % day). Plurals: Loc.n() / Loc.count().
## - Data text: data/*.json is read through Loc.load_json(), which translates the player-facing
##   fields named in TEXT_KEYS / LINE_KEYS / VOICE_KEYS as it loads. Ids, colours and the like are
##   left alone. A new player-facing key must be added here (tests/test_loc.gd fails otherwise).
## - Numbers and days: Loc.num() and Loc.day(), so separators follow the language.
## - Catalogues: locale/<lang>.po, listed in project.godot under internationalization/locale/
##   translations. tools/extract_strings.sh writes locale/messages.pot for translators.
##
## The language is picked once, before any data loads (the first Loc call): the saved choice in
## user://settings.cfg [options] language, else the system language when a catalogue exists for
## it, else English. Data is translated as it loads, so a new choice applies after a restart
## (Loc.restart() does that, desktop and web).

const SETTINGS := "user://settings.cfg"
const SOURCE := "en"  # the language the game is written in

## Keys whose string values (or arrays of strings, at any depth) are player text, in any data file.
const TEXT_KEYS := [
	"name", "title", "text", "desc", "blurb", "label", "summary", "flavor", "brief", "hint",
	"plural", "short", "weapon", "special", "staff_title", "envoy_title", "favors_why", "why_claim",
	"why_erased", "why_lamp", "drift_why", "wants", "done_text", "fail_text", "success", "fail",
	"effect", "rumour", "pitch", "welcome", "quips", "sites", "threat_names", "rank_names",
	"likes_text", "dislikes_text", "locked", "card", "tip", "notice", "mood", "habits", "weakness",
	"work_label", "shop_name", "shop_blurb", "intro_text", "prompt", "options", "labels",
	"welcome_title", "ai_short", "heading", "more", "outro", "body", "caption", "subtitle",
	"question", "answer", "note", "message", "say", "text_insight",
	"stakes", "if_ignored", "saved_text", "lost_text", "asker_name", "place",
]
## Keys holding spoken lines: [speaker, text] / [speaker, text, expression] (only the text is
## translated), lists of those, or plain strings (help topics speak in plain strings).
const LINE_KEYS := ["lines", "reply", "banter", "ended", "end", "done_banter"]
## Keys holding {voice id: lines} maps (help topics' "alt").
const VOICE_KEYS := ["alt"]
## Per-file exceptions: a key that is text elsewhere but ids or data in this file...
const NOT_TEXT := {}
## ...and a key that is an id elsewhere but text in this file.
const FILE_TEXT_KEYS := {
	"relationships.json": ["talk"],  # romance small talk (a talk id in story.json and personal.json)
	"survey.json": ["intro"],  # playtest survey page intro (a talk id in missions.json)
}
## Text that code also matches on (so the loader keeps it English): extracted for translators and
## translated where it is shown, e.g. tr(job["kind"]).
const KEYED_TEXT := {
	"expeditions.json": ["kind"],
}
## Keys that are never text, whatever the value looks like (ids, refs, art, conditions).
const NEVER_TEXT := ["id", "ids", "_comment", "color", "colors", "map", "maps", "path", "sprite", "portrait"]

static var _ready := false
static var _lang := SOURCE


# ---------------------------------------------------------------- language

## Picks the language (once) before anything is translated.
static func setup() -> void:
	if _ready:
		return
	_ready = true
	var want := ""
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		want = str(cfg.get_value("options", "language", ""))
	if want == "" or not want in languages():
		want = OS.get_locale_language() if OS.get_locale_language() in languages() else SOURCE
	_lang = want
	TranslationServer.set_locale(want)
	if pseudo_requested():
		pseudo(true)
	# Every string is translated explicitly (tr / Loc.t / the data loader), so Controls must not
	# translate their text a second time on their own.
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


## Test mode for longer languages: "--pseudo-loc" on the command line, or "?pseudo" on the web
## build's address. Every translated string comes out accented, bracketed and 30% longer.
static func pseudo_requested() -> bool:
	if "--pseudo-loc" in OS.get_cmdline_user_args() or "--pseudo-loc" in OS.get_cmdline_args():
		return true
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		return q is String and "pseudo" in q
	return false


## Turns pseudo-localisation on or off (German-length strings with accents, to find clipped text).
static func pseudo(on: bool) -> void:
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.3)
	ProjectSettings.set_setting("internationalization/pseudolocalization/fake_bidi", false)
	ProjectSettings.set_setting("internationalization/pseudolocalization/prefix", "[")
	ProjectSettings.set_setting("internationalization/pseudolocalization/suffix", "]")
	TranslationServer.pseudolocalization_enabled = on
	if on:
		TranslationServer.reload_pseudolocalization()


## Languages the player can pick: English plus every catalogue the project loads.
static func languages() -> Array:
	var out := [SOURCE]
	for t in ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray()):
		var res = load(t)
		if res is Translation and not res.locale in out:
			out.append(res.locale)
	return out


## The language in use, e.g. "en".
static func language() -> String:
	setup()
	return _lang


## A language's own name for itself, for the Options screen ("Deutsch", "Français").
static func language_name(code: String) -> String:
	var n := TranslationServer.get_language_name(code)
	return n if n != "" else code


## Saves a language choice; it applies on the next start (see restart()).
static func choose(code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("options", "language", code)
	cfg.save(SETTINGS)


## Restarts the game so a new language reaches every loaded table.
static func restart(tree: SceneTree) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
		return
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	tree.quit()


# ---------------------------------------------------------------- text

## Translates one message (English text as id). ctx tells apart the same English used two ways.
static func t(message: String, ctx := "") -> String:
	setup()
	if message == "":
		return message
	return TranslationServer.translate(message, ctx)


## Plural: Loc.n("%d day", "%d days", n) % n. English picks by n == 1; catalogues know their rules.
static func n(one: String, many: String, count: int, ctx := "") -> String:
	setup()
	var s := TranslationServer.translate_plural(one, many, count, ctx)
	# translate() pseudo-localises on its own; translate_plural() doesn't, so plurals would hide
	# from the longer-language test without this.
	return TranslationServer.pseudolocalize(s) if TranslationServer.pseudolocalization_enabled else s


## A counted phrase, formatted: Loc.count("%d day", "%d days", 3) -> "3 days". Use it for the count
## inside a longer sentence ("Surge in %s." % Loc.count(...)), so each count picks its own form.
static func count(one: String, many: String, amount: int, ctx := "") -> String:
	return n(one, many, amount, ctx) % amount


## "1 day" / "3 days": the most common counted phrase.
static func days(amount: int) -> String:
	return count("%d day", "%d days", amount)


## "A", "A and B", "A, B and C": a list of names or phrases joined the way the language joins them.
static func list(items: Array) -> String:
	var parts := items.map(func(x): return str(x))
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return parts[0]
	return Loc.t("%s and %s") % [Loc.t(", ", "list separator").join(parts.slice(0, parts.size() - 1)), parts[-1]]


## Translates every string in a list (labels kept in a const, translated where they are shown).
static func all(list: Array) -> Array:
	var out := []
	for s in list:
		out.append(t(s) if s is String else s)
	return out


# ---------------------------------------------------------------- numbers and dates

## Thousands separator per language.
const GROUP := {"en": ",", "de": ".", "es": ".", "pt": ".", "it": ".", "nl": ".", "pl": " ", "fr": " ", "ru": " ", "sv": " ", "cs": " "}
## Decimal mark per language.
const DECIMAL := {"de": ",", "es": ",", "pt": ",", "it": ",", "nl": ",", "pl": ",", "fr": ",", "ru": ",", "sv": ",", "cs": ","}


## A whole number with the language's grouping: 12,500 / 12.500 / 12 500. Below 10,000 no grouping
## (that reads best in every language and keeps short HUD numbers narrow).
static func num(v) -> String:
	var i := int(v)
	var neg := i < 0
	var s := str(absi(i))
	if s.length() > 4:
		var sep: String = GROUP.get(language().get_slice("_", 0), ",")
		var out := ""
		while s.length() > 3:
			out = sep + s.right(3) + out
			s = s.left(s.length() - 3)
		s = s + out
	return ("-" if neg else "") + s


## A number with `places` decimals and the language's decimal mark (1.5 / 1,5).
static func dec(v: float, places := 1) -> String:
	var s := String.num(v, places)
	if places > 0 and not "." in s:
		s += "." + "0".repeat(places)
	return s.replace(".", DECIMAL.get(language().get_slice("_", 0), "."))


## Signed whole number: +3 / -2.
static func signed(v) -> String:
	var i := int(v)
	return ("+" if i > 0 else "") + num(i)


## Percent: "35%" ("35 %" in French).
static func pct(v) -> String:
	return Loc.t("%s%%") % num(roundi(float(v)))


## The in-game date: "Day 4".
static func day(d) -> String:
	return Loc.t("Day %s") % num(d)


## Minutes and seconds: "3:07".
static func clock(secs: float) -> String:
	var s := maxi(0, int(secs))
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- data files

## Reads a data/*.json file and translates its player text. null if it is missing or broken.
static func load_json(path: String):
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return null
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return null
	return data(parsed, path.get_file())


## Translates the player text in parsed data, in place (and returns it).
static func data(v, file := ""):
	setup()
	if TranslationServer.get_locale() == SOURCE and not TranslationServer.pseudolocalization_enabled:
		return v  # English: nothing to do (the common case, and free)
	_walk(v, file, "")
	return v


## Calls visit(text, key) for every player-facing string in parsed data, or (with a translator)
## replaces it. Shared by the loader and by tools/extract_strings.gd so both see the same strings.
static func each_text(v, file: String, visit: Callable) -> void:
	_visit(v, file, "", visit)


static func _walk(v, file: String, mode: String) -> void:
	_visit(v, file, mode, Callable())


## mode: "" (look at keys), "text" (strings are text), "lines" (spoken lines), "voices" (voice -> lines).
## Returns the replacement for a string when translating (visit invalid), else the string.
static func _visit(v, file: String, mode: String, visit: Callable):
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v.keys():
				var m := key_mode(str(k), file) if mode != "voices" else "lines"
				if m == "" and mode == "text":
					m = ""  # a dictionary inside text (rare): look at its own keys
				var r = _visit(v[k], file, m, visit)
				if typeof(v[k]) == TYPE_STRING:
					v[k] = r
		TYPE_ARRAY:
			if mode == "lines" and is_line(v):
				v[1] = _text(v[1], visit, "line")
				return v
			for i in v.size():
				var r = _visit(v[i], file, mode, visit)
				if typeof(v[i]) == TYPE_STRING:
					v[i] = r
		TYPE_STRING:
			if mode == "text" or mode == "lines":
				return _text(v, visit, mode)
	return v


static func _text(s: String, visit: Callable, _why: String) -> String:
	if s.strip_edges() == "":
		return s
	if visit.is_valid():
		visit.call(s)
		return s
	return TranslationServer.translate(s)


## How a key's value is read in a given file: "text", "lines", "voices" or "" (not text).
static func key_mode(k: String, file := "") -> String:
	if k in NEVER_TEXT or k.begins_with("_") or k in NOT_TEXT.get(file, []):
		return ""
	if k in TEXT_KEYS or k in FILE_TEXT_KEYS.get(file, []):
		return "text"
	if k in LINE_KEYS:
		return "lines"
	if k in VOICE_KEYS:
		return "voices"
	return ""


## [speaker, text] or [speaker, text, expression]: speaker and expression are ids (or "").
static func is_line(a: Array) -> bool:
	if a.size() < 2 or a.size() > 3:
		return false
	for x in a:
		if typeof(x) != TYPE_STRING:
			return false
	if not is_id(a[0]) or is_id(a[1]) and a[1] != "":
		return false
	return a.size() == 2 or is_id(a[2])


## True for strings that are ids rather than words: "", "bran", "ch1_arrest", "staff:infirmary".
static func is_id(s: String) -> bool:
	for c in s:
		if not (c >= "a" and c <= "z" or c >= "0" and c <= "9" or c in "_:-./"):
			return false
	return true


## True for a string a player could read: has letters once format codes and tokens are taken out,
## and is not an id, a path or a colour. Used by the tests and the extractor.
static func looks_like_text(s: String) -> bool:
	if s.begins_with("res://") or s.begins_with("user://") or s.begins_with("http"):
		return false
	if is_id(s):
		return false
	var re := RegEx.create_from_string("%[-+ 0#]*[0-9]*(\\.[0-9]+)?[sdifxXc%]|\\{[^{}]*\\}|\\\\[nt]")
	var bare := re.sub(s, "", true)
	if is_id(bare):
		return false  # "ability_%d", "save_%s.json"
	var letters := RegEx.create_from_string("[A-Za-z\\x{00C0}-\\x{024F}]{2,}")
	if letters.search(bare) == null:
		return false
	return not RegEx.create_from_string("^#?[0-9a-fA-F]{6,8}$").search(s)
