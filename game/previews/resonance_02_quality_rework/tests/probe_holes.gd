extends SceneTree

# Background-hole detector. Two independent signals:
#   1. magenta clear colour: any magenta pixel is a hole through the geometry;
#   2. a ray grid from the player camera: any ray that hits nothing tells us the
#      world-space region of the hole, so the responsible surface can be found.
# Nothing in the scene uses magenta, so 1 has no false positives.

var app: Node
var output: String

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	var scene: Node3D = app.get("stage") as Node3D
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	await _frames(60)
	for child: Node in scene.get_children():
		if child is WorldEnvironment:
			(child as WorldEnvironment).environment.background_color = Color(1, 0, 1)
	var camera: Camera3D = player.get("camera") as Camera3D
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("spawn_magenta.png"))
	# Ray grid: 64 x 40 samples of the 1280 x 800 frame.
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var misses: Array[Vector3] = []
	var magenta: int = 0
	var total: int = 0
	var image: Image = root.get_texture().get_image()
	var cave: Node3D = null
	for node: Node in scene.find_children("*", "Node3D", true, false):
		if node.has_method("nearest_s"):
			cave = node as Node3D
			break
	var printed: int = 0
	for py: int in range(20, 780, 20):
		for px: int in range(20, 1260, 20):
			var c: Color = image.get_pixel(px, py)
			total += 1
			var is_magenta: bool = c.r > 0.45 and c.g < 0.25 and c.b > 0.45
			if is_magenta:
				magenta += 1
			var from: Vector3 = camera.project_ray_origin(Vector2(px, py))
			var to: Vector3 = from + camera.project_ray_normal(Vector2(px, py)) * 220.0
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = true
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				misses.append(from + camera.project_ray_normal(Vector2(px, py)) * 60.0)
			elif is_magenta and printed < 8:
				printed += 1
				var at: Vector3 = hit["position"] as Vector3
				var s_at: float = float(cave.call("nearest_s", at)) if cave != null else -999.0
				print("MAGENTA_AT px=", px, ",", py, " hit=", at, " s=", s_at, " collider=", hit["collider"])
	print("MAGENTA_PIXELS ", magenta, " / ", total)
	print("RAY_MISSES ", misses.size())
	if not misses.is_empty():
		var bounds: AABB = AABB(misses[0], Vector3.ZERO)
		for point: Vector3 in misses:
			bounds = bounds.expand(point)
		print("MISS_BOUNDS ", bounds)
		print("MISS_SAMPLE ", misses[0], " ", misses[misses.size() / 2], " ", misses[misses.size() - 1])
	print("PROBE_HOLES_DONE")
	current_scene = null
	app.queue_free()
	await _frames(4)
	quit(0)
