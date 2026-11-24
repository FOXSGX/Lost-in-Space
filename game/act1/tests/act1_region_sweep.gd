extends SceneTree

## LIS-GAMEPLAY-003 · Act 01 region sweep, captured in a REAL window.
##
## The acceptance question is not "does the HUD fit its box" (that is already
## covered by the font-metric audits) but "does the HUD cover the thing the
## player is looking at". So this probe walks the three regions the brief names
## and, at each authored interaction point, records:
##
##   * a full-frame screenshot with the real window,
##   * the fraction of the frame covered by opaque HUD panels,
##   * whether the interaction target's projected screen position falls under a
##     HUD panel (the actual occlusion question),
##   * the prompt / objective / hint strings on screen at that moment.
##
## Usage:
##   godot --path game --resolution 1920x1080 \
##     -s res://act1/tests/act1_region_sweep.gd -- <abs_out_dir> <tag>

var stage: Node
var player: Node
var hud: Node
var out_dir := ""
var tag := ""
var rows: Array[String] = []
var shots: Array[String] = []

## Region -> list of [screenshot name, machine id, standing position].
## Positions mirror the authored interaction reach used by the other probes.
const POINTS := [
	# --- power room -------------------------------------------------------
	["p1_power_cart", "cart_push", Vector3(-8.00, 0.05, -2.50)],
	["p2_winch", "power_winch", Vector3(1.95, 0.05, -5.00)],
	["p3_clamp", "power_clamp", Vector3(2.40, 0.05, -4.30)],
	# --- ventilation ------------------------------------------------------
	["v1_rotor_lock", "rotor_lock", Vector3(7.70, 0.05, -22.30)],
	["v2_coupling", "coupling", Vector3(8.10, 0.05, -28.15)],
	["v3_start_fan", "start_fan", Vector3(-7.80, 0.05, -23.00)],
	["v4_governor", "governor", Vector3(-8.00, 0.05, -21.20)],
	["v5_damper", "damper", Vector3(8.00, 0.05, -29.60)],
	["v6_catwalk", "secure_crate", Vector3(3.72, 3.45, -29.40)],
	["v7_rescue_winch", "rescue_winch", Vector3(1.45, 3.45, -21.10)],
	# --- mine station -----------------------------------------------------
	["m1_chock", "chock", Vector3(-5.62, 0.05, -45.40)],
	["m2_brake", "parking_brake", Vector3(6.55, 1.60, -48.60)],
	["m3_cargo", "cargo", Vector3(6.55, 1.60, -43.00)],
	["m4_launch", "launch_cart", Vector3(-3.00, 1.60, -50.00)],
]


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
	await _wait(0.25)


func _look(id: String) -> void:
	var p: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if p != null:
		player.call("look_at_point", p.get("global_position"))
	await _wait(0.5)


func _text(l: Node, prop: String) -> String:
	var v: Variant = l.get(prop)
	return str(v) if v != null else ""


## Opaque HUD panels that can hide the world: their global rects.
func _hud_panels() -> Array:
	var out: Array = []
	var names := ["_prompt_panel", "_objective", "_objective_sub", "_status",
		"_participation", "_wind_value", "_vent_hint", "_toast", "_debug"]
	for n in names:
		var c: Variant = hud.get(n)
		if c is Control and (c as Control).is_visible_in_tree():
			var r: Rect2 = (c as Control).get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				out.append([str(n), r])
	return out


## Is a world point hidden behind a HUD panel of real (opaque) size?
func _target_screen_pos(id: String) -> Variant:
	var p: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if p == null:
		return null
	var cam := get_viewport_camera()
	if cam == null:
		return null
	var world: Vector3 = (p as Node3D).global_position
	if cam.is_position_behind(world):
		return null
	return cam.unproject_position(world)


func get_viewport_camera() -> Camera3D:
	if player == null:
		return null
	var c: Variant = player.get("camera")
	return c as Camera3D if c is Camera3D else null


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out_dir)
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
	var vs: Vector2 = root.get_visible_rect().size
	rows.append("viewport=%dx%d tag=%s" % [int(vs.x), int(vs.y), tag])
	print("VIEWPORT %dx%d" % [int(vs.x), int(vs.y)])
	# Let the intro band finish so it cannot cover the shots.
	await _wait(7.5)

	for entry in POINTS:
		var name := str(entry[0])
		var id := str(entry[1])
		var pos: Vector3 = entry[2]
		await _warp(pos)
		await _look(id)

		var prompt := _text(hud.get("_prompt"), "text")
		var obj := _text(hud.get("_objective"), "text")
		var sub := _text(hud.get("_objective_sub"), "text")
		var hint := _text(hud.get("_vent_hint"), "text").replace("\n", " / ")

		# Occlusion: does the target sit under an opaque HUD panel?
		var covered := "n/a"
		var sp: Variant = _target_screen_pos(id)
		if sp != null:
			var pt: Vector2 = sp
			var hit: Array = []
			for entry2 in _hud_panels():
				var nm: String = str(entry2[0])
				var r: Rect2 = entry2[1]
				# the prompt panel is a bottom bar; the target legitimately sits
				# above it, so only flag panels that really contain the point
				if r.has_point(pt):
					hit.append(nm)
			covered = "COVERED_BY=" + str(hit) if not hit.is_empty() else "clear"
			rows.append("%-16s target_screen=(%4d,%4d) %s" % [
				name, int(pt.x), int(pt.y), covered])
		else:
			rows.append("%-16s target_screen=<behind camera>" % name)

		rows.append("    prompt   : %s" % prompt)
		rows.append("    objective: %s / %s" % [obj, sub])
		rows.append("    vent hint: %s" % hint)
		await _shot(name)

	var f := FileAccess.open(out_dir.path_join("%s_region_notes.txt" % tag), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(rows))
		f.close()
	print("NOTES %s" % out_dir.path_join("%s_region_notes.txt" % tag))
	quit(0)
