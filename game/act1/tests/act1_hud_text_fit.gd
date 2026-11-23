extends SceneTree

## LIS-GAMEPLAY-001B · HUD text-fit audit using Godot's REAL font metrics.
##
## `--headless` cannot produce pixels on this machine (the Intel OpenGL driver
## access-violates as soon as a shadow-casting DirectionalLight3D renders), so
## text clipping is measured the way the renderer would measure it: the actual
## theme font, the actual wrap width, the actual line count. No pixel guessing.
##
## For every HUD line the probe records
##   * measured width of each wrapped line vs the box width,
##   * how many lines the text needs vs how many the box shows,
## and asserts nothing is clipped. It prints the numbers so an A/B against the
## previous build is possible without touching the working tree.
##
## Usage:
##   godot --headless --path game -s res://act1/tests/act1_hud_text_fit.gd -- <out_dir> <tag>

const PROMPT_BOX_W := 680.0
const PROMPT_FONT := 20
const HINT_BOX_W := 244.0
const HINT_FONT := 12
const HINT_BOX_H := 50.0
const OBJ_SUB_W := 524.0
const OBJ_SUB_FONT := 15

var out_dir := ""
var tag := ""
var failures: Array[String] = []
var checks := 0
var lines: Array[String] = []


func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0 and not str(ua[0]).begins_with("--"):
		out_dir = str(ua[0])
	if ua.size() > 1:
		tag = str(ua[1])
	_run.call_deferred()


func log_line(t: String) -> void:
	print("FIT " + t)
	lines.append(t)


func check(ok: bool, t: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + t)
	if not ok:
		failures.append(t)
	return ok


## Wrap `text` at `box_w` with the real font and return the wrapped lines.
func _wrap(font: Font, text: String, box_w: float, font_size: int) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in text.split("\n"):
		var cur := ""
		for ch in str(raw):
			var probe := cur + str(ch)
			if font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > box_w and cur != "":
				out.append(cur)
				cur = str(ch)
			else:
				cur = probe
		out.append(cur)
	return out


func _measure(label: String, font: Font, text: String, box_w: float, font_size: int,
		box_h: float, check_clip: bool) -> void:
	if text == "":
		log_line("%s: <empty>" % label)
		return
	var wrapped := _wrap(font, text, box_w, font_size)
	var widest := 0.0
	for l in wrapped:
		widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var line_h := font.get_height(font_size)
	var need_h := float(wrapped.size()) * line_h + float(wrapped.size() - 1) * 1.0
	log_line("%s: lines=%d widest=%.1f/%.0f height=%.1f/%.0f" % [
		label, wrapped.size(), widest, box_w, need_h, box_h])
	for i in range(wrapped.size()):
		log_line("    | %s" % str(wrapped[i]))
	if check_clip:
		check(need_h <= box_h + 1.0, "%s: text fits its box height (%.1f <= %.0f)" % [label, need_h, box_h])
		check(widest <= box_w + 1.0, "%s: no line exceeds its box width" % label)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _warp(p: Vector3) -> void:
	player.call("teleport", p, 0.0, 0.0)
	await _wait(0.2)


func _look(id: String) -> void:
	var p: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if p != null:
		player.call("look_at_point", p.get("global_position"))
	await _wait(0.45)


func _press(id: String) -> void:
	stage.call("request_interaction", id, player, "press")
	await _wait(0.3)


var stage: Node
var player: Node
var hud: Node
var vent: Node


func _run() -> void:
	stage = (load("res://act1/act01.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	await _wait(1.8)
	player = stage.get("local_player")
	hud = stage.get("hud")
	vent = (stage.get("builder") as Object).get("vent")
	await _wait(6.5)

	var font: Font = (hud.get("_font") as Font)
	check(font != null, "HUD exposes its real theme font")

	# ---- A: early service, unpowered -------------------------------------
	await _warp(Vector3(7.70, 0.05, -22.30))
	await _look("rotor_lock")
	_measure("A prompt(rotor_lock, no power)", font,
		(hud.get("_prompt") as Label).text, PROMPT_BOX_W, PROMPT_FONT, 36.0, true)
	_measure("A objective_sub", font,
		(hud.get("_objective_sub") as Label).text, OBJ_SUB_W, OBJ_SUB_FONT, 28.0, true)

	await _press("rotor_lock")
	await _warp(Vector3(8.10, 0.05, -28.15))
	await _look("coupling")
	_measure("A2 prompt(coupling, no power)", font,
		(hud.get("_prompt") as Label).text, PROMPT_BOX_W, PROMPT_FONT, 36.0, true)
	await _press("coupling")
	await _warp(Vector3(-6.2, 0.05, -19.5))
	stage.call("_update_hud", 0.1)
	await _wait(0.3)
	_measure("A3 hint(serviced, unpowered)", font,
		(hud.get("_vent_hint") as Label).text, HINT_BOX_W, HINT_FONT, HINT_BOX_H, true)
	_measure("A3 objective_sub(serviced)", font,
		(hud.get("_objective_sub") as Label).text, OBJ_SUB_W, OBJ_SUB_FONT, 28.0, true)

	# ---- B: unpowered start refused --------------------------------------
	await _warp(Vector3(-7.80, 0.05, -23.00))
	await _look("start_fan")
	_measure("B prompt(start_fan, unpowered)", font,
		(hud.get("_prompt") as Label).text, PROMPT_BOX_W, PROMPT_FONT, 36.0, true)
	await _press("start_fan")
	_measure("B toast(start refused)", font,
		(hud.get("_toast") as Label).text, 760.0, 18, 40.0, true)
	await _warp(Vector3(-6.2, 0.05, -19.5))
	stage.call("_update_hud", 0.1)
	await _wait(0.3)
	_measure("B2 hint(unpowered, serviced)", font,
		(hud.get("_vent_hint") as Label).text, HINT_BOX_W, HINT_FONT, HINT_BOX_H, true)

	# ---- C: powered start ------------------------------------------------
	stage.call("set_flag", "power_ready", true)
	await _wait(0.4)
	stage.call("_update_hud", 0.1)
	_measure("C hint(powered, not started)", font,
		(hud.get("_vent_hint") as Label).text, HINT_BOX_W, HINT_FONT, HINT_BOX_H, true)
	_measure("C objective_sub(powered)", font,
		(hud.get("_objective_sub") as Label).text, OBJ_SUB_W, OBJ_SUB_FONT, 28.0, true)
	await _warp(Vector3(-7.80, 0.05, -23.00))
	await _look("start_fan")
	_measure("C prompt(start_fan, powered)", font,
		(hud.get("_prompt") as Label).text, PROMPT_BOX_W, PROMPT_FONT, 36.0, true)
	await _press("start_fan")
	await _wait(0.8)
	await _warp(Vector3(-6.2, 0.05, -19.5))
	stage.call("_update_hud", 0.1)
	await _wait(0.3)
	_measure("C2 hint(running)", font,
		(hud.get("_vent_hint") as Label).text, HINT_BOX_W, HINT_FONT, HINT_BOX_H, true)

	_finish()


func _finish() -> void:
	var ok := failures.is_empty()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var rep := {"probe": "act1_hud_text_fit.gd", "tag": tag, "passed": ok,
			"checks": checks, "failures": failures, "log": lines}
		var f := FileAccess.open(out_dir.path_join("text_fit_%s.json" % tag), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rep, "  "))
			f.close()
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(ok)])
	print("FIT_%s %s checks=%d" % [tag, "OK" if ok else "FAIL", checks])
	quit(0 if ok else 1)
