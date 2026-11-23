class_name SurveyView
extends Control
## The playtest survey form (issues #148, #168), over the title screen or any pause menu. One page of
## questions at a time (data/survey.json, scripts/survey.gd); Back / Next between pages, every answer
## optional. The page that mentions AI comes last and locks the pages before it ("Your earlier
## answers are kept exactly as you gave them"), so neutral answers can't be revised after the
## tester learns about AI. The last page sends the answers, or saves them as a file when this build
## has no report inbox.
##
## Opened with SurveyView.popup(host) after the host hides its own menu.
## Keyboard / pad: arrows or Tab move, Confirm picks, Back closes (asks first if something was
## answered). Mouse and touch: click or tap.

signal closed

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.68, 0.66, 0.64)
const BAD := Color("ff8a7a")
const GOOD := Color("9fe07a")

var answers := {}
var page := 0
var locked_before := -1  # pages below this index can't be reopened (set when the AI page opens)
var ai_page_seen := false
var sending := false
var sent := false
var saved_path := ""
var report_id := Feedback.new_id()
var cast: Array = []  # characters the "character" questions offer
var _opened_at := 0.0
var _discard_armed := false
var _opened_frame := -1
var _focus_first: Control

var panel: PanelContainer
var title_label: Label
var step_label: Label
var body: VBoxContainer
var scroll: ScrollContainer
var status: Label
var back_button: Button
var next_button: Button
var file_button: Button
var cancel_button: Button


static func popup(host: Node) -> SurveyView:
	var layer := CanvasLayer.new()
	layer.layer = 21
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var view := SurveyView.new()
	layer.add_child(view)
	view.closed.connect(layer.queue_free)
	return view


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	cast = Survey.characters()
	_opened_at = Time.get_unix_time_from_system()
	_opened_frame = Engine.get_process_frames()
	_build()
	show_page(0)
	var diag := get_node_or_null("/root/Diag")
	if diag:
		diag.breadcrumb("playtest survey opened")


func pages() -> Array:
	return Survey.pages()


func ai_page_index() -> int:
	var ps := pages()
	for i in ps.size():
		if ps[i].get("ai", false):
			return i
	return ps.size()


# ---------------------------------------------------------------- layout

func _build() -> void:
	var look := FeedbackView.new()  # same ledger look as the report form
	theme = look._theme()
	look.free()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	title_label = Label.new()
	title_label.add_theme_font_override("font", UiSkin.TITLE_FONT)
	title_label.add_theme_font_size_override("font_size", Access.fs(20))
	title_label.add_theme_color_override("font_color", GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	step_label = _note("", SOFT)
	head.add_child(step_label)

	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 232)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 7)
	scroll.add_child(body)

	status = _note("", SOFT, true)
	box.add_child(status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	cancel_button = _button(tr("Close"), _on_cancel)
	buttons.add_child(cancel_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	back_button = _button(tr("Back"), _on_back)
	buttons.add_child(back_button)
	file_button = _button(tr("Save to file"), _on_save_file)
	buttons.add_child(file_button)
	next_button = _button(tr("Next"), _on_next)
	buttons.add_child(next_button)


func show_page(i: int) -> void:
	var ps := pages()
	page = clampi(i, 0, ps.size() - 1)
	if page >= ai_page_index() and not ai_page_seen:
		ai_page_seen = true
		locked_before = ai_page_index()
	var p: Dictionary = ps[page]
	title_label.text = tr(str(p.get("title", "")))
	step_label.text = tr("Page %d of %d") % [page + 1, ps.size()]
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_focus_first = null
	if str(p.get("intro", "")) != "":
		body.add_child(_note(tr(str(p["intro"])), SOFT, true))
	if p.get("ai", false):
		body.add_child(_ai_block())
	for q in p.get("questions", []):
		body.add_child(_question(q))
	var last := page == ps.size() - 1
	if last:
		body.add_child(_privacy_block())
	back_button.disabled = page == 0 or page - 1 < locked_before
	next_button.text = (tr("Send") if Feedback.can_send() else tr("Save to file")) if last else tr("Next")
	file_button.visible = false  # only after a failed send
	if last and not Feedback.can_send() and not sent:
		_say(tr("This build can't send the survey online. Save it to a file and send it the way the invite says."), SOFT)
	else:
		_say("", SOFT)
	scroll.scroll_vertical = 0
	(_focus_first if _focus_first else next_button).grab_focus()


## The AI statement shown above the AI page's questions, with a link to the full text.
func _ai_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var lead := _note(tr("We use AI tools for parts of the art and writing. In our own words:"), TEXT, true)
	box.add_child(lead)
	var quote := _note(tr(Survey.ai_short()), UiSkin.PAGE_PAPER, true)
	box.add_child(quote)
	if Survey.ai_url() != "":
		var link := LinkButton.new()
		link.text = tr("Read exactly where AI was used")
		link.add_theme_color_override("font_color", GOLD)
		link.focus_mode = Control.FOCUS_NONE
		link.pressed.connect(func(): OS.shell_open(Survey.ai_url()))
		box.add_child(link)
	return box


## What sending means, on the last page (docs/PRIVACY.md).
func _privacy_block() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var note := _note(tr("Nothing leaves your device until you press Send. The survey holds your answers, the game version, your system and where you were in the game. No logs, screenshots or saves."), SOFT, true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	var link := LinkButton.new()
	link.text = tr("Privacy")
	link.add_theme_color_override("font_color", GOLD)
	link.focus_mode = Control.FOCUS_NONE
	link.size_flags_vertical = Control.SIZE_SHRINK_END
	link.pressed.connect(func(): OS.shell_open(str(Feedback.config()["privacy_url"])))
	row.add_child(link)
	return row


func _question(q: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.set_meta("qid", q["id"])
	box.add_child(_note(tr(str(q["prompt"])), TEXT, true))
	var qid: String = q["id"]
	match str(q["type"]):
		"scale":
			var labels: Array = q.get("labels", [])
			var opts := []
			for n in labels.size():
				opts.append({"value": n + 1, "label": tr(str(labels[n]))})
			box.add_child(_pick_row(qid, opts, false))
		"choice":
			var opts := []
			for o in q.get("options", []):
				opts.append({"value": str(o), "label": tr(str(o))})
			box.add_child(_pick_row(qid, opts, false))
		"multi":
			var opts := []
			for o in q.get("options", []):
				opts.append({"value": str(o), "label": tr(str(o))})
			box.add_child(_pick_row(qid, opts, true))
		"character":
			box.add_child(_character_row(qid))
		"text":
			var t := TextEdit.new()
			t.custom_minimum_size = Vector2(0, 46)
			t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			t.text = str(answers.get(qid, ""))
			t.text_changed.connect(func():
				if t.text.length() > Survey.MAX_ANSWER:
					t.text = t.text.left(Survey.MAX_ANSWER)
				_set_answer(qid, t.text))
			t.gui_input.connect(_tab_out.bind(t))
			box.add_child(t)
			_first(t)
		"line":
			var l := LineEdit.new()
			l.max_length = 120 if qid == "contact" else Survey.MAX_ANSWER
			l.text = str(answers.get(qid, ""))
			l.text_changed.connect(func(s): _set_answer(qid, s))
			box.add_child(l)
			_first(l)
	return box


## A row of buttons; one pick (pressing it again clears it) or, with multi, any number.
func _pick_row(qid: String, opts: Array, multi: bool) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 3)
	var buttons := []
	for o in opts:
		var b := Button.new()
		b.text = o["label"]
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", Access.fs(9))
		_pick_look(b)
		var cur = answers.get(qid)
		b.button_pressed = (o["value"] in cur) if multi and cur is Array else cur == o["value"]
		row.add_child(b)
		buttons.append(b)
		_first(b)
	for n in buttons.size():
		var b: Button = buttons[n]
		var value = opts[n]["value"]
		b.toggled.connect(func(on: bool):
			if multi:
				var list: Array = answers.get(qid, []).duplicate()
				if on and value not in list:
					list.append(value)
				elif not on:
					list.erase(value)
				_set_answer(qid, list)
				return
			if on:
				for other in buttons:
					if other != b:
						other.set_pressed_no_signal(false)
				_set_answer(qid, value)
			elif answers.get(qid) == value:
				_set_answer(qid, null))
	return row


## Characters from the tester's roster, "Someone else" with a line to name them, or "Not sure".
func _character_row(qid: String) -> Control:
	var box := VBoxContainer.new()
	var opts := []
	for c in cast:
		opts.append({"value": c["id"], "label": c["name"]})
	opts.append({"value": Survey.OTHER, "label": tr("Someone else")})
	var cur = answers.get(qid, {})
	var picked: String = str(cur.get("id", "")) if cur is Dictionary else ""
	var shadow := qid + "__pick"  # the row's own pick; the answer itself is stored as {id, name, other}
	answers.erase(shadow)
	if picked != "":
		answers[shadow] = picked
	var row := _pick_row(shadow, opts, false)
	box.add_child(row)
	var other := LineEdit.new()
	other.placeholder_text = tr("Who? (a name or a description)")
	other.max_length = 120
	other.text = str(cur.get("other", "")) if cur is Dictionary else ""
	other.visible = picked == Survey.OTHER
	box.add_child(other)
	var sync := func():
		var id := str(answers.get(shadow, ""))
		other.visible = id == Survey.OTHER
		if id == "":
			_set_answer(qid, null)
			return
		var name := ""
		for c in cast:
			if c["id"] == id:
				name = c["name"]
		_set_answer(qid, {"id": id, "name": name, "other": other.text if id == Survey.OTHER else ""})
	for b in row.get_children():
		(b as Button).toggled.connect(func(_on): sync.call())
	other.text_changed.connect(func(_s): sync.call())
	return box


## Picked answers must not look like the focused one: the focus frame alone shows focus, and a
## picked answer gets a lit button and gold text.
func _pick_look(b: Button) -> void:
	var lit := (theme.get_stylebox("normal", "Button") as StyleBoxTexture).duplicate() as StyleBoxTexture
	lit.modulate_color = Color(1.7, 1.35, 0.6)
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, lit)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_pressed_color", GOLD)


func _first(c: Control) -> void:
	if _focus_first == null:
		_focus_first = c


func _set_answer(qid: String, value) -> void:
	_discard_armed = false
	if value == null:
		answers.erase(qid)
	else:
		answers[qid] = value


func _note(text: String, col: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1, 0)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(64, 20)
	b.pressed.connect(cb)
	return b


## Tab leaves a text box instead of typing a tab.
func _tab_out(event: InputEvent, from: Control) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		var next := from.find_prev_valid_focus() if event.shift_pressed else from.find_next_valid_focus()
		if next:
			next.grab_focus()
		from.accept_event()


# ---------------------------------------------------------------- behaviour

## Only the real answers (not the character rows' own picks).
func clean_answers() -> Dictionary:
	var out := {}
	for k in answers:
		if not str(k).ends_with("__pick"):
			out[k] = answers[k]
	return out


func current_report() -> Dictionary:
	return Survey.build_report(clean_answers(), {
		"ai_page_seen": ai_page_seen,
		"minutes": snappedf((Time.get_unix_time_from_system() - _opened_at) / 60.0, 0.1),
		"characters": cast.map(func(c): return c["name"]),
	}, report_id)


func _on_back() -> void:
	if page > 0 and page - 1 >= locked_before:
		show_page(page - 1)


func _on_next() -> void:
	if sending:
		return
	if sent:
		close()
		return
	if page < pages().size() - 1:
		show_page(page + 1)
		return
	if not Feedback.can_send():
		if saved_path == "":
			_on_save_file()
		if saved_path != "":
			_finish(report_id)
		return
	sending = true
	_set_busy(true)
	_say(tr("Sending..."), SOFT)
	var res: Dictionary = await Feedback.send(self, current_report())
	sending = false
	_set_busy(false)
	if res["ok"]:
		_finish(str(res["id"]))
		_say(tr("Sent. Thank you, that helps a lot!"), GOOD)
	else:
		_say(tr("Could not send it (%s). Save it to a file instead and send it the way the invite says.") % res["error"], BAD)
		file_button.visible = true
		file_button.grab_focus()


func _finish(id: String) -> void:
	sent = true
	Survey.mark_submitted(id)
	var diag := get_node_or_null("/root/Diag")
	if diag:
		diag.breadcrumb("playtest survey sent " + id)
	next_button.text = tr("Close")
	back_button.visible = false
	cancel_button.visible = false
	next_button.grab_focus()


func _on_save_file() -> void:
	if saved_path != "" and not OS.has_feature("web"):
		OS.shell_open(ProjectSettings.globalize_path(saved_path.get_base_dir()))
		return
	saved_path = Feedback.save_zip(current_report())
	if saved_path == "":
		_say(tr("Could not write the file."), BAD)
	elif OS.has_feature("web"):
		_say(tr("Downloaded %s. Thank you!") % saved_path, GOOD)
	else:
		_say(tr("Saved to %s. Thank you!") % ProjectSettings.globalize_path(saved_path), GOOD)
		file_button.text = tr("Open folder")


func _on_cancel() -> void:
	if sending:
		return
	if not clean_answers().is_empty() and not sent and saved_path == "" and not _discard_armed:
		_discard_armed = true
		_say(tr("Press Close again to throw your answers away."), BAD)
		return
	close()


func _set_busy(on: bool) -> void:
	for b in [back_button, next_button, file_button, cancel_button]:
		b.disabled = on


func _say(text: String, col: Color) -> void:
	status.text = text
	status.add_theme_color_override("font_color", col)
	status.visible = text != ""


func close() -> void:
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Prompts.touch_to_mouse(self, event):  # taps reach the buttons and text boxes too
		return
	if Engine.get_process_frames() == _opened_frame:
		return
	var typing := get_viewport().gui_get_focus_owner() is TextEdit or get_viewport().gui_get_focus_owner() is LineEdit
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var pad_back: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B
	if esc or pad_back or (not typing and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		_on_cancel()
