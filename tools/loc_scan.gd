extends RefCounted
## Finds the player text in scripts/*.gd and data/*.json (issue #143). Used by tests/test_loc.gd (no
## unwrapped literals, no unknown text keys) and tools/extract_strings.gd (writes the .pot file), so
## both agree on what counts as text. Rules: docs/LOCALIZATION.md.
##
## A string literal in a script is player text when Loc.looks_like_text() says so and it is not:
## on a "# no-tr" line (or in a const block whose first line says "# no-tr"); on a log line
## (print, push_error, Diag breadcrumbs...); an argument of a call that takes names, not text
## (get_node, load, Color, is_action_pressed...); a dictionary key, match pattern or comparison.
## Text must sit directly in tr(...), Loc.t(...), tr_n / Loc.n(...) or in a const / static var
## (translated where it is shown, e.g. Loc.t(STAT_NAMES[k])).

const WRAPS := ["tr(", "Loc.t(", "tr_n(", "Loc.n(", "Loc.count(", "TranslationServer.translate("]
const LOG_CALLS := ["print", "printerr", "print_rich", "push_error", "push_warning", "assert", "breadcrumb",
	"_print", "_log", "allow_log", "print_debug"]
const NAME_CALLS := [
	"get_node", "get_node_or_null", "find_child", "has_node", "get_bus_index", "set_bus_name", "set_bus_send",
	"has_method", "call", "callv", "call_deferred", "emit_signal", "connect", "is_class", "get_meta", "set_meta",
	"has_meta", "get_singleton", "has_singleton", "load", "preload", "exists", "file_exists", "open", "Color",
	"html", "StringName", "NodePath", "is_action_pressed", "is_action_just_pressed", "is_action_just_released",
	"is_action", "has_action", "action_get_events", "get_setting", "set_setting", "has_setting", "eval",
	"get_value", "set_value", "has_section_key", "add_theme_color_override", "add_theme_font_size_override",
	"add_theme_constant_override", "add_theme_stylebox_override", "add_theme_font_override", "get_theme_color",
	"get_theme_font", "get_theme_stylebox", "get_stylebox", "get_color", "get_font", "set_stylebox", "set_color", "set_font", "set_font_size",
	"set_constant", "tween_property", "tween_method", "set_shader_parameter", "has_feature",
	"begins_with", "ends_with", "find", "contains", "split", "replace", "get_slice", "count",
	"is_valid_identifier", "play", "add_user_signal", "icon", "draw_icon", "box", "panel", "highlight",
	"create_from_string", "compile", "add_to_group", "is_in_group", "get_nodes_in_group",
	"remove_from_group", "get_first_node_in_group", "has_flag", "flag", "seen", "mark", "mark_seen", "heard",
	"key", "tag", "any_key", "action_add_event", "add_action", "erase_action", "request", "parse_string",
	"get_environment", "strip_edges", "trim_prefix", "trim_suffix", "path_join", "recruit", "job",
	"building", "faction", "node", "talk", "play_talk", "launch", "unlock", "meets", "is_seen",
	"get_shader_parameter", "sprite", "frames", "sfx", "tone", "music", "get_string_size",
]

var _lit := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")


## Every player-text literal in one script: [{line, text, wrapped, const}] (wrapped: inside tr() and
## friends; const: inside a const / static var block).
func script_texts(path: String) -> Array:
	var out := []
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var in_const := false
	var const_skip := false
	var depth := 0
	for n in lines.size():
		var line: String = lines[n]
		var s := line.strip_edges()
		if s == "" or s.begins_with("#"):
			continue
		var code := _code(line)
		var starts_const := RegEx.create_from_string("^\\s*(const|static var|enum)\\b").search(line) != null
		if not in_const and starts_const:
			in_const = true
			depth = 0
			const_skip = "no-tr" in line
		if in_const:
			depth += _opens(code)
			if not const_skip and not "no-tr" in line:
				for m in _lit.search_all(code):
					var v := _unquote(m.get_string())
					if Loc.looks_like_text(v):
						out.append({"line": n + 1, "text": v, "wrapped": false, "const": true})
			if depth <= 0:
				in_const = false
			continue
		if "no-tr" in line or s.begins_with("@export") or s.begins_with("signal ") or _is_log(code):
			continue
		var is_func := RegEx.create_from_string("^\\s*(static )?func ").search(line) != null
		for m in _lit.search_all(code):
			var v := _unquote(m.get_string())
			if not Loc.looks_like_text(v):
				continue
			var a := m.get_start()
			var before := code.substr(0, a)
			var after := code.substr(m.get_end()).strip_edges(true, false)
			if after.begins_with(":") and not after.begins_with(":="):
				continue  # dictionary key or match pattern
			if RegEx.create_from_string("(==|!=|\\bin|match)\\s*$").search(before) or after.begins_with("==") or after.begins_with("!=") or after.begins_with("in "):
				continue
			if RegEx.create_from_string("(\\btr|Loc\\.t)\\(\"(?:[^\"\\\\]|\\\\.)*\",\\s*$").search(before):
				continue  # the context argument: tr("Back", "menu button")
			var cn := _call_name(code, a)
			if cn in NAME_CALLS:
				continue
			var wrapped := false
			for w in WRAPS:
				if before.ends_with(w):
					wrapped = true
			# tr_n / Loc.n / Loc.count: the plural form is the second argument
			if not wrapped and RegEx.create_from_string("(tr_n|Loc\\.n|Loc\\.count)\\(\"(?:[^\"\\\\]|\\\\.)*\",\\s*$").search(before):
				wrapped = true
			out.append({"line": n + 1, "text": v, "wrapped": wrapped, "const": is_func})
	return out


## Every player-text string in a parsed data file, via the same walk the loader uses.
func data_texts(file: String, parsed) -> Array:
	var out := []
	Loc.each_text(parsed, file, func(s): out.append(s))
	return out


## Strings in a data file that read like text but sit under a key the loader does not translate:
## [[key path, text]]. Each one is either a new text key for Loc.TEXT_KEYS or an id-like value.
func data_unkeyed(file: String, v, path := "", mode := "") -> Array:
	var out := []
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				var m: String = Loc.key_mode(str(k), file) if mode != "voices" else "lines"
				if str(k).begins_with("_") or str(k) in Loc.NEVER_TEXT:
					continue
				out.append_array(data_unkeyed(file, v[k], path + "." + str(k), m))
		TYPE_ARRAY:
			for x in v:
				out.append_array(data_unkeyed(file, x, path, mode))
		TYPE_STRING:
			if mode == "" and Loc.looks_like_text(v) and not path.get_slice(".", path.get_slice_count(".") - 1) in Loc.KEYED_TEXT.get(file, []):
				out.append([path, v])
	return out


func _code(line: String) -> String:
	var q := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "\\" and q:
			i += 2
			continue
		if c == "\"":
			q = not q
		elif c == "#" and not q:
			return line.substr(0, i)
		i += 1
	return line


func _opens(code: String) -> int:
	var stripped := _lit.sub(code, "\"\"", true)
	var d := 0
	for c in stripped:
		if c in "([{":
			d += 1
		elif c in ")]}":
			d -= 1
	return d


func _is_log(code: String) -> bool:
	for c in LOG_CALLS:
		if RegEx.create_from_string("\\b" + c + "\\s*\\(").search(code):
			return true
	return false


func _call_name(code: String, pos: int) -> String:
	var depth := 0
	var i := pos - 1
	while i >= 0:
		var c := code[i]
		if c in ")]}":
			depth += 1
		elif c in "([{":
			if depth == 0:
				if c != "(":
					return ""
				var j := i - 1
				while j >= 0 and code[j] == " ":
					j -= 1
				var k := j
				while k >= 0 and (code[k] == "_" or code.unicode_at(k) < 128 and (code[k] >= "a" and code[k] <= "z" or code[k] >= "A" and code[k] <= "Z" or code[k] >= "0" and code[k] <= "9")):
					k -= 1
				return code.substr(k + 1, j - k)
			depth -= 1
		i -= 1
	return ""


func _unquote(lit: String) -> String:
	return lit.substr(1, lit.length() - 2).c_unescape()
