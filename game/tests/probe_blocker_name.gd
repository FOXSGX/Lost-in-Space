extends SceneTree

## Name the solid thing standing between the left ramp foot and the left
## counterweight console: cast down and report the nearest visible meshes.

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	var space: PhysicsDirectSpaceState3D = app.get_world_3d().direct_space_state
	var meshes: Array[MeshInstance3D] = []
	_collect(app, meshes)
	for p in [Vector3(-5.4, 0.0, 2.2), Vector3(-5.4, 0.0, 3.0), Vector3(-5.4, 0.0, 4.0)]:
		var from: Vector3 = p + Vector3(0, 3.0, 0)
		var to: Vector3 = p + Vector3(0, -0.2, 0)
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit: Dictionary = space.intersect_ray(q)
		print("RAY ", p, " -> ", hit.get("position", "none"), " normal=", hit.get("normal", ""))
		if hit.is_empty():
			continue
		var at: Vector3 = hit["position"]
		var near: Array[Dictionary] = []
		for m in meshes:
			if not m.is_visible_in_tree():
				continue
			var d: float = m.global_position.distance_to(at)
			if d < 1.6:
				near.append({"d": d, "name": str(m.name), "parent": str(m.get_parent().name), "pos": m.global_position})
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
		for i in range(mini(5, near.size())):
			print("   NEAR ", JSON.stringify(near[i]))
	quit(0)


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, out)
