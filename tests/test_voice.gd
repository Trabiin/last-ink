extends "res://tests/test_case.gd"
## Script voice (issue #167, docs/VOICES.md): prose that reads as machine-written.
##
## - test_no_banned_phrases: the hard ban list (docs/VOICES.md 2.1) in data/ values and script strings. Fails.
## - test_one_punctuation_style: no em/en dashes, curly quotes or the single-character ellipsis (VOICES.md 3). Fails.
## - test_voice_report: the softer tells (VOICES.md 2.2), counted and printed. Advisory until the rewrite in
##   #167 step two sets WATCH_STRICT; VOICE_REPORT=1 lists every hit:
##     VOICE_REPORT=1 godot --headless --audio-driver Dummy --path . -s tests/run.gd -- voice

## Hard bans: model-prose fingerprints. Case-insensitive.
const BANNED := [
	"\\ba testament to\\b", "\\btapestr(y|ies)\\b", "\\bwhispers of\\b", "\\bpalpabl[ey]\\b", "\\bdelv(e|es|ed|ing)\\b",
	"\\bin the heart of\\b", "\\bthe weight of\\b", "\\ba dance of\\b", "\\blittle did \\w+ know\\b",
	"\\bshivers? (down|up) (my|your|his|her|their|our) spine", "\\bbreath (I|you|he|she|they|we) didn'?t know\\b",
	"\\b(symphony|cacophony|kaleidoscope) of\\b", "\\bmyriad\\b", "\\bebb and flow\\b", "\\bbeacon of\\b",
	"\\bindelibl[ey]\\b", "\\bunwavering\\b", "\\bresolve (hardened|hardening|hardens)\\b",
	"\\bsteel(ed|s|ing)? (him|her|them|my|your|our)sel(f|ves)\\b", "\\bethereal\\b", "\\bgossamer\\b", "\\bliminal\\b",
	"\\bpalimpsests?\\b", "\\bnestled\\b", "\\bbustling\\b", "\\bvibrant\\b", "\\bintricate(ly)?\\b",
	"\\bever-(changing|shifting|present|evolving)\\b", "\\bsentinels?\\b", "\\bechoes of\\b", "\\bfabric of\\b",
	"\\bbarely above a whisper\\b", "\\bhung in the air\\b", "\\bhangs in the air\\b", "\\bair (was |is )?thick with\\b",
	"\\bdeafening silence\\b", "\\bsilence (stretched|stretches)\\b", "\\bcan'?t help but\\b", "\\blets? out a breath\\b",
	"\\bonly time will tell\\b", "\\bin a world where\\b", "\\bserves? as a reminder\\b", "\\ba reminder that\\b",
	"\\bat the end of the day\\b", "\\band that'?s okay\\b", "\\bmaybe that'?s enough\\b",
	"\\b(it|this|that)('s| is| was) not about\\b[^.!?]{1,50}\\babout\\b", "\\bnot just\\b[^.!?;]{1,40}\\bbut\\b",
	"\\bmore than just\\b", "\\beyes (glint|sparkl|gleam)\\w*\\b", "\\bsomething shifted\\b",
]

## Deliberate uses of a banned phrase: [where (substring of the location, "" for anywhere), text (substring of
## the string), why]. Keep this short; every entry needs a reason a reader would accept.
const ALLOW := []

## One punctuation style (VOICES.md 3): em dash, en dash, the single-character ellipsis, curly quotes.
const PUNCT := "[—–…‘’“”]| -- "
## In data text a spaced hyphen is a dash too (script strings use it for keys: "+ / - to zoom").
const DATA_DASH := " - "

## Softer tells (VOICES.md 2.2), counted. "owners" are speakers for whom the move is a tic on their sheet;
## their lines don't count. "limit" applies once WATCH_STRICT is on (#167 step two sets the numbers).
const WATCH := [
	{"id": "people think", "re": "\\bpeople (think|say|assume)\\b", "limit": 1},
	{"id": "correction", "re": "(^|[.!?] )Not (a |an |the )?\\w+[.,] (\\w+ )?\\w+\\.|\\b(it|that|this) (isn't|wasn't|is not)\\b[^.!?]{0,30}[.!?]+ (it|that|this)('s| is| was)\\b", "limit": 4},
	{"id": "either/or verdict", "re": "\\beither\\b[^.!?]{1,50}\\bor\\b|[.!?] Or (terrifying|tragic|stupid|smart|brilliant|the most \\w+)\\b", "owners": ["bran"], "limit": 0},
	{"id": "'Or X.' afterthought", "re": "[.!?] Or [^.!?]{1,30}[.!?]", "owners": ["jessamy", "bran"], "limit": 2},
	{"id": "fragment triplet", "re": "(^|[.!?] )\\w+\\. \\w+\\. \\w+\\.( |$)", "limit": 10},
	{"id": "stated feeling", "re": "\\bI (feel|felt)\\b|\\bI'?m (so )?(sad|angry|grateful|scared|hurt|lonely|happy|heartbroken|devastated)\\b|\\bI'?m not crying\\b", "limit": 0},
	{"id": "moral tag", "re": "\\bnow you know\\b|\\bthat'?s the whole (art|point|trick)\\b|\\bthat isn'?t nothing\\b|\\bthat'?s how it works\\b", "limit": 1},
	{"id": "soft-fantasy word", "re": "\\b(journey|realm|embark\\w*|unravel\\w*|whisper\\w*|truly|deeply)\\b", "limit": 3},
	{"id": "therapy-speak", "re": "\\b(closure|boundaries|healing journey|process (this|it|that)|trauma|toxic|validate|valid feelings)\\b", "limit": 0},
]

## Words a character owns (VOICES.md 5) and dialect markers (VOICES.md 4): anyone else saying them is counted under "somebody else's word".
const OWNED := {
	"dearie": ["gristle"],
	"darling": ["velvette", "sallow"],
	"clause": ["bran"],
	"invoice": ["bran"],
	"smudge": ["bran"],
	"handsome": ["jessamy"],
	# dialect markers (VOICES.md 4.2): a marker in the wrong mouth is as wrong as a catchphrase
	"cully": ["jessamy"],
	"nowt": ["tobble", "ottoline"],
	"summat": ["tobble", "ottoline"],
	"civvies": ["ninefingers"],
	"dreckly": ["merrow"],
	"herewith": ["quill", "clerk", "marrow", "auditor", "warden", "captain"],
	"chérie": ["velvette", "sallow"],
}

## Step two of #167 flips this: watched tells over their limit fail the run.
const WATCH_STRICT := false

var _texts: Array = []  # [where, text, speaker id or ""]


func before_each() -> void:
	_texts = []
	for f in DirAccess.get_files_at("res://data/"):
		if f.ends_with(".json"):
			_walk(f, JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f)), "")
	var lit := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	for f in DirAccess.get_files_at("res://scripts/"):
		if not f.ends_with(".gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string("res://scripts/" + f).split("\n"):
			n += 1
			if line.strip_edges().begins_with("#") or line.contains("# no-tr"):
				continue
			for m in lit.search_all(line):
				var s := m.get_string()
				_texts.append(["scripts/%s:%d" % [f, n], s.substr(1, s.length() - 2), "", true])


## Every string value in data (not _comment keys), with its speaker when it is a spoken line.
func _walk(where: String, v, who: String) -> void:
	match typeof(v):
		TYPE_STRING:
			_texts.append([where, v, who, false])
		TYPE_ARRAY:
			if _is_line(v):
				_texts.append([where, v[1], str(v[0]), false])
				return
			for x in v:
				_walk(where, x, who)
		TYPE_DICTIONARY:
			if v.has("who") and typeof(v.get("text")) == TYPE_STRING:
				_texts.append([where, v["text"], str(v["who"]), false])
				return
			for k in v:
				if not str(k).begins_with("_"):
					_walk("%s.%s" % [where, k] if where.count(".") < 2 else where, v[k], who)


## [speaker id, text] or [speaker id, text, expression]: a short id with no spaces first.
func _is_line(a: Array) -> bool:
	if a.size() < 2 or a.size() > 3 or typeof(a[0]) != TYPE_STRING or typeof(a[1]) != TYPE_STRING:
		return false
	var id: String = a[0]
	return id.length() < 24 and not id.contains(" ") and id == id.to_lower() and a[1].contains(" ")


func _allowed(where: String, text: String) -> bool:
	for a in ALLOW:
		if (a[0] == "" or where.contains(a[0])) and text.contains(a[1]):
			return true
	return false


## No banned phrase anywhere a player can read (docs/VOICES.md 2.1).
func test_no_banned_phrases() -> void:
	var res := []
	for p in BANNED:
		var re := RegEx.create_from_string("(?i)" + p)
		check(re.is_valid(), "banned phrase pattern does not compile: %s" % p)
		res.append(re)
	for t in _texts:
		for re in res:
			var m: RegExMatch = re.search(t[1])
			if m and not _allowed(t[0], t[1]):
				check(false, "%s: banned phrase '%s' (docs/VOICES.md 2.1) in \"%s\"" % [t[0], m.get_string(), t[1].left(90)])


## One punctuation style (docs/VOICES.md 3).
func test_one_punctuation_style() -> void:
	var re := RegEx.create_from_string(PUNCT)
	for t in _texts:
		var m := re.search(t[1])
		check(m == null, "%s: use plain punctuation (docs/VOICES.md 3), found '%s' in \"%s\"" % [t[0], m.get_string() if m else "", t[1].left(90)])
		if not t[3]:
			check(not t[1].contains(DATA_DASH), "%s: a spaced hyphen used as a dash (docs/VOICES.md 3) in \"%s\"" % [t[0], t[1].left(90)])


## The softer tells, counted (docs/VOICES.md 2.2). Prints one line per tell; fails only with WATCH_STRICT.
func test_voice_report() -> void:
	var list := OS.get_environment("VOICE_REPORT") != ""
	var lines := 0
	for t in _texts:
		if not t[3]:
			lines += 1
	var total := 0
	var out := []
	for w in WATCH:
		var re := RegEx.create_from_string("(?i)" + w["re"])
		check(re.is_valid(), "watch pattern %s does not compile" % w["id"])
		var hits := []
		for t in _texts:
			if t[3] or (t[2] in w.get("owners", [])):  # script strings are UI, not prose
				continue
			for m in re.search_all(t[1]):
				hits.append("%s [%s] \"%s\"" % [t[0], t[2] if t[2] != "" else "-", t[1].left(100)])
		total += hits.size()
		out.append([w["id"], hits, int(w.get("limit", 0))])
	var owned := []
	for t in _texts:
		if t[2] == "":
			continue
		for word in OWNED:
			if not (t[2] in OWNED[word]) and RegEx.create_from_string("(?i)\\b%s\\b" % word).search(t[1]):
				owned.append("%s [%s] says '%s' (%s's word) \"%s\"" % [t[0], t[2], word, "/".join(OWNED[word]), t[1].left(80)])
	total += owned.size()
	out.append(["somebody else's word", owned, 0])
	print("VOICE REPORT (docs/VOICES.md 2.2, %s): %d watched tells in %d data strings" % ["enforced" if WATCH_STRICT else "advisory", total, lines])
	for o in out:
		print("  %-22s %3d  (limit %d)" % [o[0], o[1].size(), o[2]])
		if list:
			for h in o[1]:
				print("      " + h)
		if WATCH_STRICT:
			check(o[1].size() <= o[2], "voice: %d '%s' tells, limit %d (VOICE_REPORT=1 lists them)" % [o[1].size(), o[0], o[2]])
