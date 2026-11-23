extends "res://tests/test_case.gd"
## InkMenu text and signpost plates stay inside their panel and on screen (the playtest welcome ran
## off both edges of a 1920-wide browser window; the meadow signpost smeared): every title-screen notice
## and every map sign is laid out at each text size, with and without the readable font, on the narrowest
## and some wider and taller screens, and each line drawn must sit inside its panel, inside the screen.

const SIZES := [Vector2(640, 360), Vector2(671, 360), Vector2(853, 360), Vector2(640, 480), Vector2(1138, 360)]


func after_each() -> void:
	Access.text_size = 0
	Access.readable_font = false
	Access.apply_font()


## The title screen's notices, as title.gd sets them up (the longest real text of each).
func _notices() -> Array:
	var s := Survey.settings()
	var long_error := "Error: " + "res://scripts/some_very_long_script_name_that_never_ends.gd:123 - ".repeat(3)
	return [
		["welcome", str(s["welcome_title"]), [{"id": "ok", "label": "Let's play"}],
			str(s["welcome"]) + "\n\n" + Survey.ai_short(), 0.22],
		["survey offer", "How was it?", [
			{"id": "survey", "label": "Take the playtest survey", "detail": "about 5 minutes"},
			{"id": "later", "label": "Later", "detail": "it's in the menu any time"},
			{"id": "mute", "label": "Don't ask again"}],
			"You've played for a while. A few answers about how it went help more than anything else.", 0.22],
		["crash offer", "Sorry about that", [
			{"id": "send", "label": "Send report", "detail": "you see everything before it goes"},
			{"id": "later", "label": "Not now"}],
			"Last Ink closed unexpectedly last time. A report with the log from then helps fix it. " + long_error, 0.28],
		["save notice", "About your saves", [{"id": "ok", "label": "OK"}],
			"A save from an older version was updated to this one. Your old file was kept next to it, just in case something looks wrong.\n\nAnother very long notice line that keeps going and going so it has to wrap at least once on every screen.", 0.25],
		["long detail", "", [{"id": "x", "label": "Continue", "detail": "Day 14, Hollowmark, 6 heroes, 3 provinces lost to the Blank, a very long save description that runs on"},
			{"id": "load", "label": "Load Game", "enabled": false, "note": "(no saves yet)"}], "", 0.42],
	]


func test_notices_fit_inside_their_panel_and_the_screen() -> void:
	Access.load_settings()
	for font in [false, true]:
		for ts in Access.TEXT_SIZES.size():
			Access.text_size = ts
			Access.readable_font = font
			Access.apply_font()
			for n in _notices():
				for vs in SIZES:
					var m := InkMenu.new()
					m.view_override = vs
					m.top = n[4]
					tree.root.add_child(m)
					m.setup(n[1], n[2], n[3])
					await frames(2)
					var where := "%s, text size %d%s, %dx%d" % [n[0], ts, " readable" if font else "", vs.x, vs.y]
					var p: Rect2 = m.panel_rect
					check(p.position.x >= 0.0 and p.end.x <= vs.x and p.position.y >= 0.0 and p.end.y <= vs.y,
						"%s: panel %s is off screen" % [where, p])
					check(not m.drawn_text.is_empty(), "%s: nothing was drawn" % where)
					for r in m.drawn_text:
						var t: Rect2 = r
						if not check(t.position.x >= p.position.x + 4.0 and t.end.x <= p.end.x - 4.0,
								"%s: a line %s runs past the panel's sides %s" % [where, t, p]):
							break
						if not check(t.position.y >= p.position.y - 2.0 and t.end.y <= p.end.y + 2.0,
								"%s: a line %s runs past the panel's top or bottom %s" % [where, t, p]):
							break
					m.queue_free()


func test_wrap_px_keeps_every_line_inside_the_width() -> void:
	var font := ThemeDB.fallback_font
	var lines := InkMenu.wrap_px(font, "short\n\n" + "word ".repeat(80) + "x".repeat(200), 9, 200.0)
	check_eq(lines[0], "short", "first paragraph")
	check_eq(lines[1], "", "blank line kept")
	check(lines.size() > 4, "long text wrapped onto several lines")
	for l in lines:
		check(font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x <= 200.0, "line fits: " + l)


## Text taller than the screen (the credits) starts at the top, scrolls under the title with up and
## down, and the choices under it come into view at the end.
func test_long_text_scrolls_and_reaches_the_choices() -> void:
	Access.load_settings()
	for ts in Access.TEXT_SIZES.size():
		Access.text_size = ts
		var m := InkMenu.new()
		m.view_override = Vector2(640, 360)
		m.title_size = 16
		tree.root.add_child(m)
		var lines := []
		for i in 60:
			lines.append("Credit line number %d - someone who made something for this game" % i)
		m.setup("Credits", [{"id": "back", "label": "Back"}], "\n".join(lines))
		await frames(2)
		check(m._text_mode, "text size %d: long text scrolls" % ts)
		var p: Rect2 = m.panel_rect
		for r in m.drawn_text:
			check((r as Rect2).end.y <= p.end.y + 2.0, "text size %d: text stays inside the panel" % ts)
		check(m._rects.size() == 1 and (m._rects[0] as Rect2).position.y < 0.0, "text size %d: Back is below, out of view, at first" % ts)
		var down := InputEventAction.new()
		down.action = "ui_down"
		down.pressed = true
		for i in 80:
			m._input(down)
		await frames(2)
		check(m._scroll >= m._max_scroll - 0.5, "text size %d: down reaches the end" % ts)
		var back: Rect2 = m._rects[0]
		check(back.position.y > 0.0 and back.end.y <= 360.0, "text size %d: Back is on screen at the end (%s)" % [ts, back])
		m.queue_free()


## Every signpost's text (the @sign lines of the maps) fits its paper plate and the screen at every
## text size, and the plate's lines sit on whole pixels so the ink stays crisp.
func test_sign_plates_fit() -> void:
	Access.load_settings()
	var signs := []
	for f in DirAccess.get_files_at("res://maps/"):
		if not f.ends_with(".txt"):
			continue
		for line in FileAccess.get_file_as_string("res://maps/" + f).split("\n"):
			if line.begins_with("@sign"):
				signs.append(line.substr(line.find(" ") + 1).replace("|", "\n"))
	check(signs.size() > 3, "found the maps' signs")
	var font := ThemeDB.fallback_font
	for font_on in [false, true]:
		for ts in Access.TEXT_SIZES.size():
			Access.text_size = ts
			Access.readable_font = font_on
			Access.apply_font()
			for vs in SIZES:
				for text in signs:
					var lay := UiSkin.sign_layout(font, vs, vs.y * 0.62, text)
					var p: Rect2 = lay["panel"]
					var where := "sign '%s', text size %d%s, %dx%d" % [text.get_slice("\n", 0), ts, " readable" if font_on else "", vs.x, vs.y]
					check(p.position.x >= 0.0 and p.end.x <= vs.x and p.end.y <= vs.y, "%s: plate %s off screen" % [where, p])
					for l in lay["lines"]:
						var pos: Vector2 = l[1]
						check(pos.x >= p.position.x + 8.0 and pos.x + float(l[2]) <= p.end.x - 8.0, "%s: '%s' runs past the plate" % [where, l[0]])
						check(pos.y - Access.fs(10) >= p.position.y and pos.y <= p.end.y - 4.0, "%s: '%s' runs past the plate's top or bottom" % [where, l[0]])
						check(pos == pos.round(), "%s: '%s' is not on whole pixels" % [where, l[0]])
