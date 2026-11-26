extends SceneTree

## LIS-GAMEPLAY-003 · Act 01 "worst case HUD" states, captured in a real window.
##
## The region sweep shows the calm state. These are the moments when the most
## HUD channels speak at once, i.e. where text could genuinely pile up:
##
##   s1  gust warning      toast + hint + objective together
##   s2  gust active       alarm copy on screen
##   s3  player downed     damage copy + rescue prompt
##   s4  fan running       live pressure numbers + test countdown
##   s5  platform refused  refusal toast while standing at a locked machine
##
## Usage:
##   godot --path game --resolution 1920x1080 \
##     -s res://act1/tests/act1_hud_stress.gd -- <abs_out_dir> <tag>

var stage: Node
var player: Node
var hud: Node
var vent: Node
var out_dir := ""
var tag := ""
var rows: Array[String] = []


func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0 and not str(ua[0]).begins_with("--"):
		out_dir = str(ua[0])
	if ua.size() > 1:
		tag = str(ua[1])
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _warp(p: Vector3) -> void:
	player.call("teleport", p, 0.0, 0.0)
	await _wait(0.3)


func _look(id: String) -> void:
	var p: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if p != null:
		player.call("look_at_point", p.get("global_position"))
	await _wait(0.45)


func _txt(n: String, prop := "text") -> String:
	var v: Variant = hud.get(n)
	return str(v.get(prop)) if v != null else ""


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out_dir)
	var img: Image = root.get_texture().get_image()
	var path := out_dir.path_join("%s_%s.png" % [tag, name])
	img.save_png(path)
	print("SHOT %s" % path)


func _snap(label: String) -> void:
	rows.append("--- %s ---" % label)
	rows.append("objective: %s / %s" % [_txt("_objective"), _txt("_objective_sub")])
	rows.append("toast    : '%s' alpha=%.2f" % [
		_txt("_toast"), float((hud.get("_toast") as CanvasItem).modulate.a)])
	rows.append("hint     : %s" % _txt("_vent_hint").replace("\n", " / "))
	rows.append("prompt   : %s" % _txt("_prompt"))
	rows.append("status   : %s" % _txt("_status"))


func _run() -> void:
	stage = (load("res://act1/act01.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	await _wait(2.2)
	player = stage.get("local_player")
	hud = stage.get("hud")
	vent = (stage.get("builder") as Object).get("vent")
	print("VIEWPORT %dx%d" % [int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y)])
	await _wait(7.5)

	# ---- s1/s2: bring the machine up the authored way, then let the gust fire
	# The pneumatic chain itself is covered by act1_solo_full_run.gd; here we only
	# need the machine running so the HUD shows its live channels.
	stage.call("set_flag", "power_ready", true)
	stage.call("set_flag", "rotor_lock_released", true)
	stage.call("set_flag", "coupling_engaged", true)
	await _warp(Vector3(-7.80, 0.05, -23.00))
	await _look("start_fan")
	stage.call("request_interaction", "start_fan", player, "press")
	await _wait(1.2)
	await _warp(Vector3(8.00, 0.05, -29.60))
	await _look("damper")
	stage.call("request_interaction", "damper", player, "press")
	await _wait(2.0)

	# Stand on the catwalk so the gust copy and the grab prompt share the frame.
	await _warp(Vector3(3.70, 3.50, -26.00))
	await _wait(0.5)
	# Wait for the scripted gust warning (damper open + speed > 0.58).
	var waited := 0.0
	while waited < 20.0:
		var t := _txt("_toast")
		if t.find("泄压") >= 0 or t.find("压力失衡") >= 0:
			break
		await _wait(0.25)
		waited += 0.25
	_snap("s1 gust warning / active")
	await _shot("s1_gust_warning")

	await _wait(1.5)
	_snap("s2 gust active")
	await _shot("s2_gust_active")

	# ---- s4: live pressure test numbers
	await _warp(Vector3(8.00, 0.05, -34.00))
	var t2 := 0.0
	while t2 < 14.0:
		if bool(stage.get("flags").get("vent_complete", false)):
			break
		await _wait(0.5)
		t2 += 0.5
	_snap("s4 pressure test")
	await _shot("s4_pressure_test")

	# ---- s5: platform refusal with a live objective
	await _warp(Vector3(5.35, 1.58, -47.05))
	await _look("cargo")
	stage.call("request_interaction", "cargo", player, "press")
	await _wait(0.3)
	_snap("s5 platform refusal")
	await _shot("s5_platform_refusal")

	# ---- s3: downed state (self-rescue copy + prompt)
	await _warp(Vector3(2.30, 3.55, -29.00))
	await _wait(0.4)
	player.call("report_fall") if player.has_method("report_fall") else null
	await _wait(2.5)
	_snap("s3 after a fall")
	await _shot("s3_after_fall")

	var f := FileAccess.open(out_dir.path_join("%s_stress_notes.txt" % tag), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(rows))
		f.close()
	print("NOTES ok")
	quit(0)
