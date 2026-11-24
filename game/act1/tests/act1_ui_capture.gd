extends SceneTree

## LIS-GAMEPLAY-001B · windowed UI check for the advance-maintenance prompts.
##
## Runs Act01 in a REAL window (never --headless) and captures the three states
## the acceptance asks about:
##   A  early service    — rotor lock / coupling operable with no power
##   B  unpowered start  — the start handle refuses and says why
##   C  powered start    — the prepared machine starts
##
## It also records the exact prompt / HUD-hint / objective strings so that text
## overlap can be judged against the pixels, not guessed from the layout code.
##
## Usage:
##   godot --path game --resolution 1920x1080 \
##     -s res://act1/tests/act1_ui_capture.gd -- <out_dir> <tag>

var stage: Node
var player: Node
var hud: Node
var vent: Node
var out_dir := ""
var tag := ""
var shots: Array[String] = []
var notes: Array[String] = []


func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0 and not str(ua[0]).begins_with("--"):
		out_dir = str(ua[0])
	if ua.size() > 1:
		tag = str(ua[1])
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _warp(pos: Vector3) -> void:
	player.call("teleport", pos, 0.0, 0.0)
	await _wait(0.25)


func _look(id: String) -> void:
	var point: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if point != null:
		player.call("look_at_point", point.get("global_position"))
	await _wait(0.5)


func _press(id: String) -> void:
	stage.call("request_interaction", id, player, "press")
	await _wait(0.35)


func _read(label: String) -> void:
	var prompt: Label = hud.get("_prompt") as Label
	var hint: Label = hud.get("_vent_hint") as Label
	var wind: Label = hud.get("_wind_value") as Label
	var obj: Label = hud.get("_objective") as Label
	var sub: Label = hud.get("_objective_sub") as Label
	var toast: Label = hud.get("_toast") as Label
	notes.append("--- %s ---" % label)
	notes.append("prompt_panel_visible=%s" % str((hud.get("_prompt_panel") as Control).visible))
	notes.append("objective=%s" % (obj.text if obj != null else ""))
	notes.append("objective_sub=%s" % (sub.text if sub != null else ""))
	notes.append("prompt=%s" % (prompt.text if prompt != null else ""))
	notes.append("wind=%s" % (wind.text if wind != null else "").replace("\n", " ⏎ "))
	notes.append("hint=%s" % (hint.text if hint != null else "").replace("\n", " ⏎ "))
	notes.append("toast=%s (alpha=%.2f)" % [
		(toast.text if toast != null else ""), float((toast as CanvasItem).modulate.a) if toast != null else 0.0])


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out_dir)
	# `root` IS the main Window (a Viewport), so read the frame from there: a
	# SceneTree script has no get_viewport() of its own.
	var img: Image = root.get_texture().get_image()
	var path := out_dir.path_join("%s_%s.png" % [tag, name])
	img.save_png(path)
	shots.append(path)
	print("SHOT %s" % path)


func _run() -> void:
	var packed := load("res://act1/act01.tscn") as PackedScene
	stage = packed.instantiate()
	root.add_child(stage)
	await _wait(2.2)
	player = stage.get("local_player")
	hud = stage.get("hud")
	vent = (stage.get("builder") as Object).get("vent")
	var vs: Vector2 = root.get_visible_rect().size
	notes.append("viewport=%dx%d window=%dx%d" % [
		int(vs.x), int(vs.y),
		int(DisplayServer.window_get_size().x), int(DisplayServer.window_get_size().y)])
	print("VIEWPORT %dx%d" % [int(vs.x), int(vs.y)])

	# Let the intro band fade so it cannot mask the HUD.
	await _wait(7.0)

	# ---- A1: unpowered rotor-lock prompt ---------------------------------
	await _warp(Vector3(7.70, 0.05, -22.30))
	await _look("rotor_lock")
	_read("A1 rotor_lock prompt, no power")
	await _shot("a1_rotor_prompt_unpowered")

	# ---- A2: refused coupling (rotor lock still fitted) ------------------
	await _warp(Vector3(8.10, 0.05, -28.15))
	await _look("coupling")
	_read("A2 coupling prompt, rotor lock fitted")
	await _shot("a2_coupling_depends_on_lock")

	# ---- A3: pulled the rotor lock while unpowered -----------------------
	await _warp(Vector3(7.70, 0.05, -22.30))
	await _look("rotor_lock")
	await _press("rotor_lock")
	_read("A3 rotor lock pulled (advance maintenance)")
	await _shot("a3_rotor_pulled_toast")

	# ---- A4: coupling engaged while unpowered ----------------------------
	await _warp(Vector3(8.10, 0.05, -28.15))
	await _look("coupling")
	await _press("coupling")
	_read("A4 coupling engaged (advance maintenance)")
	await _shot("a4_coupling_engaged_toast")

	# ---- B1: unpowered start refused, standing at the handle -------------
	await _warp(Vector3(-7.80, 0.05, -23.00))
	await _look("start_fan")
	_read("B1 start handle prompt, prepped but unpowered")
	await _shot("b1_start_prompt_unpowered")
	await _press("start_fan")
	_read("B2 start refused toast")
	await _shot("b2_start_refused_toast")

	# ---- B3: HUD + objective while serviced but unpowered ----------------
	# Step back from the handle so the prompt panel disappears and only the
	# persistent HUD (objective + ventilation panel) is visible.
	await _warp(Vector3(-6.2, 0.05, -19.5))
	await _wait(0.6)
	stage.call("_update_hud", 0.1)
	await _wait(0.4)
	_read("B3 persistent HUD, serviced but unpowered")
	await _shot("b3_hud_serviced_unpowered")

	# ---- C: powered start ------------------------------------------------
	stage.call("set_flag", "power_ready", true)
	await _wait(0.5)
	stage.call("_update_hud", 0.1)
	await _warp(Vector3(-7.80, 0.05, -23.00))
	await _look("start_fan")
	_read("C1 start handle prompt, powered")
	await _shot("c1_start_prompt_powered")
	await _press("start_fan")
	await _wait(0.8)
	_read("C2 started")
	await _shot("c2_started_toast")

	var f := FileAccess.open(out_dir.path_join("%s_ui_notes.txt" % tag), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(notes))
		f.close()
	print("UI_NOTES %s" % out_dir.path_join("%s_ui_notes.txt" % tag))
	quit(0)
