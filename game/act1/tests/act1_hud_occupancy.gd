extends SceneTree

## LIS-GAMEPLAY-001B · real HUD occupancy audit (A/B capable).
##
## The first layout probe compared raw Control rects, which reports two false
## positives by construction:
##   * `_participation` is a 540x130 bottom-left label whose box is far taller
##     than the 2-3 lines it actually draws, and the centre prompt panel sits
##     inside that empty box;
##   * `vent_value` (100..137) and `vent_hint` (136..186) share exactly one row
##     of pixels — a boundary artefact that exists in the shipped layout.
##
## So this probe measures the ACTUAL occupied band of every label: the wrapped
## line count from the real theme font times the real line height. Two blocks
## only count as overlapping when their drawn text really intersects.
##
## It is A/B capable: run it against the current tree and against the pristine
## HUD to show which findings (if any) this iteration introduced.
##
## Usage:
##   godot --headless --path game -s res://act1/tests/act1_hud_occupancy.gd -- <out_dir> <tag>

var out_dir := ""
var tag := ""
var failures: Array[String] = []
var checks := 0
var lines: Array[String] = []
var stage: Node
var player: Node
var hud: Node
var vent: Node


func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0 and not str(ua[0]).begins_with("--"):
		out_dir = str(ua[0])
	if ua.size() > 1:
		tag = str(ua[1])
	_run.call_deferred()


func log_line(t: String) -> void:
	print("OCC " + t)
	lines.append(t)


func check(ok: bool, t: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + t)
	if not ok:
		failures.append(t)
	return ok


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


## The band of pixels a label actually paints: its box, offset by the horizontal
## alignment of the drawn text, and sized by the real wrapped text height.
## Empty when hidden, fully transparent (a faded toast), or blank.
func _occupied(l: Label, font: Font, box_w: float) -> Rect2:
	if l == null or not l.is_visible_in_tree():
		return Rect2()
	if l.modulate.a <= 0.02:
		return Rect2()
	var txt := l.text
	if txt.strip_edges() == "":
		return Rect2()
	var fs: int = l.get_theme_font_size("font_size")
	var wrapped := _wrap(font, txt, box_w, fs)
	var lh := font.get_height(fs)
	var h := float(wrapped.size()) * lh
	var widest := 0.0
	for w in wrapped:
		widest = maxf(widest, font.get_string_size(str(w), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var gr := l.get_global_rect()
	var draw_w := minf(widest, gr.size.x)
	# Centre / right aligned labels do not paint from the box origin; shift the
	# band so an overlap test compares glyphs, not the (much wider) box.
	var x := gr.position.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x = gr.position.x + (gr.size.x - draw_w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = gr.position.x + gr.size.x - draw_w
	return Rect2(Vector2(x, gr.position.y), Vector2(draw_w, h))


func _audit(label: String, font: Font) -> void:
	var bands := {
		"objective": _occupied(hud.get("_objective") as Label, font, 524.0),
		"objective_sub": _occupied(hud.get("_objective_sub") as Label, font, 524.0),
		"participation": _occupied(hud.get("_participation") as Label, font, 540.0),
		"vent_value": _occupied(hud.get("_wind_value") as Label, font, 244.0),
		"vent_hint": _occupied(hud.get("_vent_hint") as Label, font, 244.0),
		"toast": _occupied(hud.get("_toast") as Label, font, 760.0),
	}
	var prompt_panel := hud.get("_prompt_panel") as Control
	if prompt_panel != null and prompt_panel.is_visible_in_tree():
		bands["prompt_panel"] = prompt_panel.get_global_rect()

	log_line("STATE " + label)
	for k in bands:
		var r: Rect2 = bands[k]
		log_line("  drawn %-14s x=%4d..%4d y=%4d..%4d" % [
			k, int(r.position.x), int(r.position.x + r.size.x),
			int(r.position.y), int(r.position.y + r.size.y)])

	var names := bands.keys()
	var real: Array[String] = []
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a: Rect2 = bands[names[i]]
			var b: Rect2 = bands[names[j]]
			if a.size.x <= 0.0 or b.size.x <= 0.0 or a.size.y <= 0.0 or b.size.y <= 0.0:
				continue
			# require a real pixel intersection, not a shared boundary row
			var inter := a.intersection(b)
			if inter.size.x > 1.0 and inter.size.y > 1.0:
				real.append("%s×%s(%.0fx%.0f)" % [names[i], names[j], inter.size.x, inter.size.y])
	check(real.is_empty(), "%s: no drawn HUD text overlaps (%s)" % [label, str(real)])

	# nothing may be pushed outside the viewport
	var vp: Vector2 = root.get_visible_rect().size
	var outside: Array[String] = []
	for k in bands:
		var r2: Rect2 = bands[k]
		if r2.size.x <= 0.0 or r2.size.y <= 0.0:
			continue
		if r2.position.x < -1.0 or r2.position.y < -1.0 \
				or r2.position.x + r2.size.x > vp.x + 1.0 \
				or r2.position.y + r2.size.y > vp.y + 1.0:
			outside.append(str(k))
	check(outside.is_empty(), "%s: every drawn block stays inside the viewport (%s)" % [label, str(outside)])


func _run() -> void:
	stage = (load("res://act1/act01.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	await _wait(1.8)
	player = stage.get("local_player")
	hud = stage.get("hud")
	vent = (stage.get("builder") as Object).get("vent")
	var font: Font = hud.get("_font") as Font
	log_line("viewport=%dx%d tag=%s" % [
		int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y), tag])
	await _wait(6.5)

	await _warp(Vector3(7.70, 0.05, -22.30))
	await _look("rotor_lock")
	_audit("A_prompt_rotor_unpowered", font)

	await _press("rotor_lock")
	await _warp(Vector3(8.10, 0.05, -28.15))
	await _look("coupling")
	await _press("coupling")
	await _warp(Vector3(-6.2, 0.05, -19.5))
	stage.call("_update_hud", 0.1)
	await _wait(0.3)
	_audit("B_hud_serviced_unpowered", font)

	await _warp(Vector3(-7.80, 0.05, -23.00))
	await _look("start_fan")
	await _press("start_fan")
	_audit("C_prompt_start_refused", font)

	stage.call("set_flag", "power_ready", true)
	await _wait(0.4)
	await _press("start_fan")
	await _wait(0.8)
	await _warp(Vector3(-6.2, 0.05, -19.5))
	stage.call("_update_hud", 0.1)
	await _wait(0.3)
	_audit("D_hud_running", font)

	_finish()


func _finish() -> void:
	var ok := failures.is_empty()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var rep := {"probe": "act1_hud_occupancy.gd", "tag": tag, "passed": ok,
			"checks": checks, "failures": failures, "log": lines}
		var f := FileAccess.open(out_dir.path_join("occupancy_%s.json" % tag), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rep, "  "))
			f.close()
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(ok)])
	print("OCCUPANCY_%s %s checks=%d" % [tag, "OK" if ok else "FAIL", checks])
	quit(0 if ok else 1)
