extends SceneTree

## Developer probe: identify what the camera actually sees and list every mesh /
## collider near a point. Used to attribute visual defects to a specific node.

var app: Node3D
var level: LevelBuilder
var cam: Camera3D


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(80)
	level = app.get("level") as LevelBuilder
	var player: PlayerController = app.get("player") as PlayerController
	player.camera.current = false
	cam = Camera3D.new()
	cam.fov = 66.0
	cam.near = 0.03
	cam.far = 260.0
	cam.current = true
	level.add_child(cam)

	probe("CORE_FRONT", Vector3(0, 6.2, 9.0), Vector3(0, 7.2, -2.0))
	probe("CORE_SIDE", Vector3(9.0, 7.2, 5.4), Vector3(0, 7.0, -2.0))
	probe("A15", Vector3(-9.6, 3.3, 8.4), Vector3(-6.2, 2.9, 3.6))
	probe("A16", Vector3(-6.4, 3.1, 6.6), Vector3(-6.4, 2.2, 3.6))
	probe("A19", Vector3(-8.0, 2.7, 5.1), Vector3(-8.0, 3.4, 6.9))
	probe("A23", Vector3(10.5, 2.2, -5.2), Vector3(10.5, 1.2, -9.0))
	probe("A13", Vector3(2.4, 4.4, 5.2), Vector3(0, 4.3, 0.0))
	probe("A01", Vector3(0, 5.4, 34.0), Vector3(0, 5.8, 12.0))
	quit()


func probe(label: String, pos: Vector3, target: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	print("\n=== PROBE ", label, " from ", pos, " -> ", target, " ===")
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	for uv in [Vector2(0.5, 0.5), Vector2(0.3, 0.5), Vector2(0.7, 0.5), Vector2(0.5, 0.35), Vector2(0.5, 0.7), Vector2(0.2, 0.6), Vector2(0.8, 0.6)]:
		var origin: Vector3 = cam.project_ray_origin(uv * Vector2(1280, 720))
		var dir: Vector3 = cam.project_ray_normal(uv * Vector2(1280, 720))
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
		q.from = origin
		q.to = origin + dir * 40.0
		q.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			print("  uv ", uv, " -> no static hit")
			continue
		var collider: Node = hit.get("collider") as Node
		var owner_name: String = str(collider.get_path()) if collider != null else "?"
		var parent: Node = collider
		var chain: String = ""
		while parent != null and parent != level:
			chain = parent.name + "/" + chain
			parent = parent.get_parent()
		print("  uv ", uv, " dist %.2f" % (origin.distance_to(hit.get("position") as Vector3)), " hit ", owner_name, " chain ", chain, " at ", hit.get("position"))
	# nearby meshes
	var near: Array = []
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		var center: Vector3 = box.get_center()
		var d: float = center.distance_to(cam.global_position)
		if d < 4.5:
			var chain2: String = ""
			var p: Node = mi
			while p != null and p != level:
				chain2 = p.name + "/" + chain2
				p = p.get_parent()
			near.append({"d": d, "name": chain2, "center": center, "size": box.size, "dist_surface": d - box.size.length() * 0.5})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for item in near.slice(0, 26):
		print("  near %-58s d=%.2f c=%s s=%s" % [item["name"], item["d"], str(item["center"]), str(item["size"])])

