extends SceneTree

## LIS-GAMEPLAY-003 · authored accident states, captured in a real window.
##
## The region/stress sweeps only show calm and mid-task states. The two authored
## ACCIDENTS are what a player actually stumbles into, and they are the states
## where the HUD has the least to say. This probe triggers them through the
## game's own callbacks (`report_player_fall` / `report_out_of_bounds`) instead
## of poking at flags, then records what the player would see.
##
## Usage:
##   godot --path game --resolution 1920x1080 \
##     -s res://act1/tests/act1_accident_view.gd -- <abs_out_dir> <tag>

var stage: Node
var player: Node
var hud: Node
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


func _txt(n: String) -> String:
	var v: Variant = hud.get(n)
	return str(v.text) if v != null else ""


func _panel_visible(n: String) -> bool:
	var c: Variant = hud.get(n)
	return (c as Control).is_visible_in_tree() if c is Control else false


func _nearby() -> String:
	var out: Array[String] = []
	var its: Dictionary = stage.get("interactables") as Dictionary
	for id in its.keys():
		var it = its[id]
		var d: float = (player.get("global_position") as Vector3).distance_to(
			(it.get("global_position") as Vector3))
		if d < 4.25:      # the authored interaction reach
			out.append("%s(%.1fm)" % [str(id), d])
	return ",".join(out) if not out.is_empty() else "<none in reach>"


func _snap(label: String) -> void:
	rows.append("--- %s ---" % label)
	rows.append("player y=%.2f downed=%s" % [
		float((player.get("global_position") as Vector3).y), str(player.get("downed"))])
	rows.append("prompt    : '%s' (panel visible=%s)" % [
		_txt("_prompt"), str(_panel_visible("_prompt_panel"))])
	rows.append("toast     : '%s'" % _txt("_toast"))
	rows.append("objective : %s / %s" % [_txt("_objective"), _txt("_objective_sub")])
	rows.append("in reach  : %s" % _nearby())


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out_dir)
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join("%s_%s.png" % [tag, name]))
	print("SHOT %s" % out_dir.path_join("%s_%s.png" % [tag, name]))


func _run() -> void:
	stage = (load("res://act1/act01.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	await _wait(2.2)
	player = stage.get("local_player")
	hud = stage.get("hud")
	await _wait(7.5)

	# ---- A: fall off the catwalk, handled by the game's own fall reporter -----
	# Put the body on the catwalk edge, then let normal gravity drop it: that is
	# the sequence the real fall detector observes.
	player.call("teleport", Vector3(3.70, 3.55, -29.00), 0.0, 0.0)
	await _wait(0.5)
	# trigger the authored handler exactly as the fall detector does
	stage.call("report_player_fall", player)
	await _wait(1.5)
	_snap("A after fall (authored report_player_fall)")
	await _shot("a_after_fall")

	# Player looks down at their own body: what is in front of them?
	var cam: Variant = player.get("camera")
	if cam is Camera3D:
		(cam as Camera3D).look_at(player.get("global_position") + Vector3(0, 0.2, 0), Vector3.UP)
	await _wait(0.4)
	_snap("A2 looking down while downed")
	await _shot("a2_downed_look_down")

	# ---- B: out-of-bounds safety net -----------------------------------------
	stage.call("report_out_of_bounds", player)
	await _wait(1.5)
	_snap("B safety-net placement")
	await _shot("b_safety_net")

	# ---- C: can the player find the ladder from the pit? ---------------------
	# Turn toward the authored ladder anchor and see whether the prompt appears.
	var ladder: Object = (stage.get("interactables") as Dictionary).get("self_rescue") as Object
	if ladder != null:
		var lp: Vector3 = ladder.get("global_position")
		player.call("look_at_point", lp)
		await _wait(0.6)
		_snap("C aimed at the self-rescue ladder")
		await _shot("c_aim_ladder")
		rows.append("ladder distance = %.2f m" % (
			(player.get("global_position") as Vector3).distance_to(lp)))

	var f := FileAccess.open(out_dir.path_join("%s_accident_notes.txt" % tag), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(rows))
		f.close()
	print("NOTES ok")
	quit(0)
