extends SceneTree

## What is actually in front of the exit-corridor camera? Ray-casts straight
## ahead at eye height and reports the collider plus the visible mesh behind it.

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for i in range(30):
		await physics_frame
	var level: LevelBuilder = app.get("level") as LevelBuilder
	level.exit_door.open_door()
	for i in range(200):
		await physics_frame
	var space: PhysicsDirectSpaceState3D = app.get_world_3d().direct_space_state
	var origin: Vector3 = Vector3(-13.2, 1.68, -2.0)
	for dz in [-1.8, -1.2, -0.6, -0.1, 0.0, 0.1, 0.6, 1.2, 1.8]:
		var from: Vector3 = origin + Vector3(0, 0, dz)
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + Vector3(-8, 0, 0), 0xFFFFFFFF, [])
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			print("ray z=%+.1f  MISS" % dz)
			continue
		var col: Node = hit["collider"] as Node
		var p: Vector3 = hit["position"]
		var nearest: String = "none"
		var best: float = 1.0e12
		for n in level.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.mesh == null:
				continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			if not box.grow(0.05).has_point(p):
				continue
			var d: float = box.get_center().distance_to(p)
			if d < best:
				best = d
				nearest = str(mi.get_path())
		print("ray z=%+.1f  dist=%.2f  collider=%s  pos=(%.2f, %.2f, %.2f)  mesh=%s" % [dz, from.distance_to(p), col.get_path() if col != null else "?", p.x, p.y, p.z, nearest])
	quit()
