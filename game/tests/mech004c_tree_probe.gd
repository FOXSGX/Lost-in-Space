extends Node
## MECHANICS-004C · 诊断：场景树在第四幕完成前后的真实变化

var stage: Node
var gate: Node3D
var player: Node3D
var _t: float = 0.0
var _log_armed: bool = false


func _ready() -> void:
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	gate = stage.get("gate") as Node3D
	player = stage.get("player") as Node3D
	print("TREE current_scene=", _name_of(get_tree().current_scene),
		" root_children=", _child_names(get_tree().root))
	stage.set_meta("suppress_act5", false)
	var seen: Dictionary = stage.get("seen_memories") as Dictionary
	for index: int in [1, 2, 3]:
		seen[index] = true
		stage.call("_on_memory_finished", index)
		await _w(50)
	var guard := 0
	while not bool(gate.get("exit_allowed")) and guard < 1800:
		await get_tree().physics_frame
		guard += 1
	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	player.call("teleport", Vector3(door_world.x + 1.0, 0.05, door_world.z), 0.0)
	await _w(20)
	Input.action_press("move_forward")
	for _i in range(180):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await _w(60)
	print("TREE after_exit completed=", str(stage.get("completed")),
		" current_scene=", _name_of(get_tree().current_scene),
		" root_children=", _child_names(get_tree().root))
	_log_armed = true
	_t = 0.0


func _process(delta: float) -> void:
	if not _log_armed:
		return
	_t += delta
	if _t > 8.0:
		print("TREE final current_scene=", _name_of(get_tree().current_scene),
			" root_children=", _child_names(get_tree().root))
		var hub: Node = get_node_or_null("/root/SessionHub")
		if hub != null:
			print("TREE hub scene_path=", str(hub.get("scene_path")),
				" chapter=", str(hub.get("current_chapter")))
		get_tree().quit(0)
		_log_armed = false
		return
	if int(_t * 2.0) != int((_t - delta) * 2.0):
		print("TREE t=%.1f current_scene=%s root_children=%s" % [
			_t, _name_of(get_tree().current_scene), _child_names(get_tree().root)])


func _name_of(n: Node) -> String:
	return n.name if n != null and is_instance_valid(n) else "<null>"


func _child_names(n: Node) -> String:
	if n == null:
		return "<null>"
	var out: Array[String] = []
	for c: Node in n.get_children():
		out.append(c.name)
	return str(out)


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
