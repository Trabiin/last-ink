class_name FeedbackView
extends Control
## "Report a bug / Send feedback" (issue #146): a short form over the title screen or any pause menu.
## The player picks bug / feedback / idea, types what happened, can leave a way to reach them and
## ticks what to attach (screenshot of the game under the menu, the logs, their save). Nothing is
## sent until they press Send; "Save to file" writes the same report as a zip instead.
##
## Opened with FeedbackView.popup(host, opts) after the host hides its own menu (so the screenshot
## shows the game, not the menu). opts: "screenshot" (bool, default true: grab the screen first),
## "previous" (Diag.previous: the report is about the last session, which crashed or hit errors).
##
## Keyboard / pad: Up / Down / Left / Right move between fields (Tab too), Confirm presses, Back
## closes (asks again if something was typed). Mouse and touch: click or tap.

signal closed

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.68, 0.66, 0.64)
const BAD := Color("ff8a7a")
const GOOD := Color("9fe07a")
const KIND_LABELS := {"bug": "Bug", "feedback": "Feedback", "idea": "Idea"}

var opts := {}
var shot: Image
var report_id := Feedback.new_id()
var kind := "bug"
var sending := false
var sent := false
var saved_path := ""
var _discard_armed := false
var _opened_frame := -1

var panel: PanelContainer
var kind_buttons := {}
var text_box: TextEdit
var contact_box: LineEdit
var shot_check: CheckBox
var log_check: CheckBox
var save_check: CheckBox
var thumb: TextureRect
var status: Label
var send_button: Button
var file_button: Button
var cancel_button: Button


## Grabs the screen (unless opts.screenshot is false), then shows the form on its own top layer.
static func popup(host: Node, p_opts := {}) -> FeedbackView:
	var layer := CanvasLayer.new()
	layer.layer = 21  # over the options screen's layer
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var view := FeedbackView.new()
	view.opts = p_opts
	view.visible = false
	layer.add_child(view)
	view.closed.connect(layer.queue_free)
	view._start()
	return view


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _start() -> void:
	if opts.get("screenshot", true) and DisplayServer.get_name() != "headless":  # headless draws nothing
		await RenderingServer.frame_post_draw  # the frame under the (already hidden) menu
		shot = get_viewport().get_texture().get_image()
		if shot != null and shot.is_empty():
			shot = null  # headless: nothing to show
	_build()
	visible = true
	_opened_frame = Engine.get_process_frames()
	text_box.grab_focus()
	var diag := get_node_or_null("/root/Diag")
	if diag:
		diag.breadcrumb("feedback form opened")


func _about_previous() -> bool:
	return not opts.get("previous", {}).is_empty()


# ---------------------------------------------------------------- layout

func _build() -> void:
	theme = _theme()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var title := Label.new()
	title.text = tr("Send a report about last time") if _about_previous() else tr("Report a bug or send feedback")
	title.add_theme_font_override("font", UiSkin.TITLE_FONT)
	title.add_theme_font_size_override("font_size", Access.fs(20))
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	if _about_previous():
		box.add_child(_note(_previous_line(), SOFT, true))

	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 4)
	kinds.add_child(_note(tr("This is a"), SOFT))
	var group := ButtonGroup.new()
	for k in Feedback.KINDS:
		var b := Button.new()
		b.text = Loc.t(KIND_LABELS[k])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == kind
		b.custom_minimum_size = Vector2(64, 0)
		b.pressed.connect(_set_kind.bind(k))
		kinds.add_child(b)
		kind_buttons[k] = b
	box.add_child(kinds)

	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 8)
	box.add_child(middle)
	text_box = TextEdit.new()
	text_box.custom_minimum_size = Vector2(0, 92)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_box.text_changed.connect(_on_text_changed)
	text_box.gui_input.connect(_tab_out.bind(text_box))
	middle.add_child(text_box)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 2)
	middle.add_child(side)
	thumb = TextureRect.new()
	thumb.custom_minimum_size = Vector2(112, 63)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if shot:
		thumb.texture = ImageTexture.create_from_image(shot)
	side.add_child(thumb)
	shot_check = _check(tr("Screenshot"), shot != null)
	shot_check.disabled = shot == null
	shot_check.toggled.connect(func(on): thumb.modulate.a = 1.0 if on else 0.25)
	side.add_child(shot_check)
	if shot == null:
		thumb.visible = false
		shot_check.visible = false

	contact_box = LineEdit.new()
	contact_box.placeholder_text = tr("How to reach you if you'd like an answer (optional)")
	contact_box.max_length = Feedback.MAX_CONTACT
	box.add_child(contact_box)

	var att := HBoxContainer.new()
	att.add_theme_constant_override("separation", 10)
	att.add_child(_note(tr("Attach:"), SOFT))
	log_check = _check(tr("Logs (errors, where you were)"), true)
	att.add_child(log_check)
	var slot := Feedback.save_slot()
	save_check = _check(tr("Your save") if slot != "" else tr("Your save (none yet)"), slot != "")
	save_check.disabled = slot == ""
	save_check.tooltip_text = tr("So the bug can be replayed in your exact game.") if slot != "" else tr("No save yet.")
	att.add_child(save_check)
	box.add_child(att)

	var privacy := HBoxContainer.new()
	privacy.add_theme_constant_override("separation", 8)
	var pnote := _note(tr("Nothing leaves your device until you press Send. A report holds what you type, the things ticked ")
		+ tr("above, the game version and your system (OS, graphics card, language). No account, name or IP address is kept."), SOFT, true)
	pnote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	privacy.add_child(pnote)
	var link := LinkButton.new()
	link.text = tr("Privacy")
	link.add_theme_color_override("font_color", GOLD)
	link.size_flags_vertical = Control.SIZE_SHRINK_END
	link.pressed.connect(func(): OS.shell_open(str(Feedback.config()["privacy_url"])))
	link.focus_mode = Control.FOCUS_NONE
	privacy.add_child(link)
	var logs_link := LinkButton.new()
	logs_link.text = tr("Download logs") if OS.has_feature("web") else tr("Log folder")
	logs_link.add_theme_color_override("font_color", GOLD)
	logs_link.size_flags_vertical = Control.SIZE_SHRINK_END
	logs_link.focus_mode = Control.FOCUS_NONE
	logs_link.pressed.connect(func():
		var diag := get_node_or_null("/root/Diag")
		if diag:
			diag.open_log_folder())
	privacy.add_child(logs_link)
	box.add_child(privacy)

	status = _note("", SOFT, true)
	box.add_child(status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 6)
	send_button = _button(tr("Send"), _on_send)
	file_button = _button(tr("Save to file"), _on_save_file)
	cancel_button = _button(tr("Cancel"), _on_cancel)
	buttons.add_child(send_button)
	if not Feedback.can_send():
		send_button.visible = false
		_say(tr("This build cannot send reports online. Save the report to a file and attach it to a comment on the game's page."), SOFT)
	buttons.add_child(file_button)
	buttons.add_child(cancel_button)
	box.add_child(buttons)
	_update_placeholder()


func _previous_line() -> String:
	var prev: Dictionary = opts["previous"]
	var n := int(prev.get("errors", 0))
	var what := tr("The game closed unexpectedly") if prev.get("crashed", false) else tr("The game ran into %d error%s") % [n, "" if n == 1 else "s"]
	if prev.get("crashed", false) and n > 0:
		what += tr(" after %d error%s") % [n, "" if n == 1 else "s"]
	return what + tr(" last time. The logs from then are attached; a line on what you were doing helps a lot.")


func _note(text: String, col: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _check(text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	return c


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(76, 20)
	b.pressed.connect(cb)
	return b


## The look: ledger panel, leather buttons, parchment text fields, a gold frame round whatever has focus.
func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = Access.fs(10)
	var pan := UiSkin.box("ledger").duplicate() as StyleBoxTexture
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		pan.set_content_margin(side, 16)
	t.set_stylebox("panel", "PanelContainer", pan)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.set_border_width_all(1)
	focus.set_expand_margin_all(1)
	var btn := UiSkin.box("button").duplicate() as StyleBoxTexture
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		btn.set_content_margin(side, 8)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		btn.set_content_margin(side, 3)
	var btn_on := btn.duplicate() as StyleBoxTexture
	btn_on.modulate_color = Color(1.25, 1.1, 0.8)
	var btn_off := btn.duplicate() as StyleBoxTexture
	btn_off.modulate_color = Color(0.6, 0.6, 0.6)
	for kind_name in ["Button"]:  # no-tr: theme type
		t.set_stylebox("normal", kind_name, btn)
		t.set_stylebox("hover", kind_name, btn_on)
		t.set_stylebox("pressed", kind_name, btn_on)
		t.set_stylebox("hover_pressed", kind_name, btn_on)
		t.set_stylebox("disabled", kind_name, btn_off)
		t.set_stylebox("focus", kind_name, focus)
		t.set_color("font_color", kind_name, TEXT)
		t.set_color("font_hover_color", kind_name, GOLD)
		t.set_color("font_pressed_color", kind_name, GOLD)
		t.set_color("font_hover_pressed_color", kind_name, GOLD)
		t.set_color("font_focus_color", kind_name, GOLD)
		t.set_color("font_disabled_color", kind_name, SOFT)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", focus)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	t.set_color("font_focus_color", "CheckBox", GOLD)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", GOLD)
	t.set_color("font_disabled_color", "CheckBox", SOFT)
	var field := StyleBoxFlat.new()
	field.bg_color = UiSkin.PAGE_PAPER
	field.border_color = Color("a07a4e")
	field.set_border_width_all(1)
	field.set_content_margin_all(4)
	for kind_name in ["TextEdit", "LineEdit"]:  # no-tr: class names
		t.set_stylebox("normal", kind_name, field)
		t.set_stylebox("read_only", kind_name, field)
		t.set_stylebox("focus", kind_name, focus)
		t.set_color("font_color", kind_name, UiSkin.PAPER_INK)
		t.set_color("font_" + "place" + "holder_color", kind_name, UiSkin.PAGE_INK_SOFT)  # split: test_data flags the word as unfinished text
		t.set_color("caret_color", kind_name, UiSkin.PAPER_INK)
		t.set_color("selection_color", kind_name, Color(0.55, 0.42, 0.2, 0.45))
	t.set_color("font_color", "Label", TEXT)
	return t


# ---------------------------------------------------------------- behaviour

func _set_kind(k: String) -> void:
	kind = k
	_update_placeholder()


func _update_placeholder() -> void:
	text_box.placeholder_text = {
		"bug": tr("What happened, and what did you expect? What were you doing just before?"),
		"feedback": tr("What did you like, what bugged you, what was confusing?"),
		"idea": tr("What would you add or change?"),
	}[kind]


func _on_text_changed() -> void:
	_discard_armed = false
	if text_box.text.length() > Feedback.MAX_TEXT:
		text_box.text = text_box.text.left(Feedback.MAX_TEXT)
		text_box.set_caret_column(text_box.get_line(text_box.get_line_count() - 1).length())
		text_box.set_caret_line(text_box.get_line_count() - 1)


## Tab leaves the text box instead of typing a tab.
func _tab_out(event: InputEvent, from: Control) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		var next := from.find_prev_valid_focus() if event.shift_pressed else from.find_next_valid_focus()
		if next:
			next.grab_focus()
		from.accept_event()


## The report as the form stands.
func current_report() -> Dictionary:
	return Feedback.build({
		"id": report_id,
		"kind": kind,
		"text": text_box.text,
		"contact": contact_box.text,
		"logs": log_check.button_pressed,
		"save": save_check.button_pressed and not save_check.disabled,
		"screenshot": shot if shot_check.button_pressed and not shot_check.disabled else null,
		"previous": opts.get("previous", {}),
	})


func _on_send() -> void:
	if sending:
		return
	if sent:
		close()
		return
	if text_box.text.strip_edges() == "" and not _about_previous():
		_say(tr("Please write a line about what happened first."), BAD)
		text_box.grab_focus()
		return
	sending = true
	_set_busy(true)
	_say(tr("Sending..."), SOFT)
	var res: Dictionary = await Feedback.send(self, current_report())
	sending = false
	_set_busy(false)
	if res["ok"]:
		sent = true
		var diag := get_node_or_null("/root/Diag")
		if diag:
			diag.breadcrumb("report sent " + str(res["id"]))
		_say(tr("Sent. Thank you! Your report number is %s.") % res["id"], GOOD)
		send_button.text = tr("Close")
		file_button.visible = false
		cancel_button.visible = false
		send_button.grab_focus()
	else:
		_say(tr("Could not send it (%s). You can save it to a file and attach it to a comment on the game's page.") % res["error"], BAD)
		file_button.grab_focus()


func _on_save_file() -> void:
	if saved_path != "" and not OS.has_feature("web"):
		OS.shell_open(ProjectSettings.globalize_path(saved_path.get_base_dir()))
		return
	saved_path = Feedback.save_zip(current_report())
	if saved_path == "":
		_say(tr("Could not write the report file."), BAD)
	elif OS.has_feature("web"):
		_say(tr("Downloaded %s.") % saved_path, GOOD)
	else:
		_say(tr("Saved to %s") % ProjectSettings.globalize_path(saved_path), GOOD)
		file_button.text = tr("Open folder")


func _on_cancel() -> void:
	if sending:
		return
	var typed := text_box.text.strip_edges() != "" or contact_box.text.strip_edges() != ""
	if typed and not sent and saved_path == "" and not _discard_armed:
		_discard_armed = true
		_say(tr("Press Back again to throw this report away."), BAD)
		return
	close()


func _set_busy(on: bool) -> void:
	for b in [send_button, file_button, cancel_button]:
		b.disabled = on


func _say(text: String, col: Color) -> void:
	status.text = text
	status.add_theme_color_override("font_color", col)


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
	var typing := get_viewport().gui_get_focus_owner() in [text_box, contact_box]
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var pad_back: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B
	if esc or pad_back or (not typing and event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		_on_cancel()
