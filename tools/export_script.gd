extends SceneTree
## Writes the script export (issue #142): every player-facing string as a readable script, one
## Markdown file per chapter, into build/script/ (or the folder given). See tools/script_export.gd.
## Run tools/export_script.sh, or: godot --headless --path . -s tools/export_script.gd -- [out dir]

const OUT := "res://build/script"

var _frame := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:  # autoloads (Loc, Controls) exist from the first frame on
		var args := OS.get_cmdline_user_args()
		var out: String = args[0] if args.size() > 0 else OUT
		var counts: Dictionary = load("res://tools/script_export.gd").new().write(out)  # load, not preload: it needs the autoloads
		for f in counts:
			print("export_script: %-11s %5d strings" % [f, counts[f]])
		print("export_script: written to %s" % out)
		quit(0)
	return false
