class_name HostWord
extends InkGlob
## One word of the Host's speech (issue #29): flies like a Spitter's glob (InkGlob) and hurts the same way, but
## it is drawn as the word it shouted, in wet wine-red letters, so a volley reads as a sentence coming at you.

## Translated where drawn (tr in _draw); keep each short enough to read on a sprite-sized glob.
const WORDS := ["MORE", "EAT", "SIT", "STAY", "GUEST", "TASTE", "MINE", "YUM", "SUP", "DINE"]
const WINE := Color("8a2a4a")
const CREAM := Color("f3ead2")

var word := ""  # an entry of WORDS; empty picks one at random


func _ready() -> void:
	super._ready()
	if word == "":
		word = WORDS[randi() % WORDS.size()]


func _pop() -> void:
	Fx.burst(get_parent(), global_position, [WINE, CREAM], 6, 45.0)
	queue_free()


func _draw() -> void:
	draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	var shown := tr(word)
	var w := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
	var at := Vector2(-w / 2.0, 3.0 + sin(t * 14.0) * 0.8)
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_string(font, at + o, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), Color(0.08, 0.04, 0.06, 0.95))
	draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), CREAM)
	draw_string(font, at + Vector2(0, 1), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), Color(WINE, 0.35))
