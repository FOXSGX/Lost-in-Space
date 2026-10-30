extends SceneTree

# Locate the dark rectangles by name. Casts rays through the same audit views and
# prints the collider/visual hit at sample points, so a black region can be
# attributed to a specific node instead of guessed from its silhouette.

const CART := preload("res://scripts/moving_cart.gd")

var app: Node
var scene: Node3D
var cart: AnimatableBody3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	app = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	cart = scene.get("cart") as AnimatableBody3D
	await _frames(45)
	player_pause()
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 160.0
	scene.add_child(camera)
	camera.current = true
	(scene.get("hud") as CanvasLayer).visible = false
	await _frames(6)

	print("=== ALL MESHES NEAR THE START (world AABB, x in -12..14, z in -14..14) ===")
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null: continue
		var world: AABB = mesh.global_transform * mesh.get_aabb()
		if world.position.x > 14.0 or world.end.x < -12.0: continue
		if world.position.z > 14.0 or world.end.z < -14.0: continue
		var mat: Material = mesh.material_override
		var tint: String = "?"
		if mat is StandardMaterial3D:
			tint = str((mat as StandardMaterial3D).albedo_color)
		elif mat is ShaderMaterial:
			tint = "shader:" + str((mat as ShaderMaterial).shader.resource_path.get_file())
		print("  %-34s pos=%s size=%s mat=%s" % [str(mesh.name), _v(world.position), _v(world.size), tint])

	print("=== RAY IDENTIFICATION (screen points that render black) ===")
	var route: Vector3 = CART.route_pose(0.0).origin + Vector3(0, 0, 2.2)
	camera.look_at_from_position(route + Vector3(-2.0, 1.05, -3.4), route + Vector3(9.0, 0.15, 0.6), Vector3.UP)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var reported: Dictionary = {}
	for py: int in range(0, image.get_height(), 24):
		for px: int in range(0, image.get_width(), 24):
			var c: Color = image.get_pixel(px, py)
			if c.get_luminance() > 0.055: continue
			var ndc: Vector2 = Vector2((float(px) + 0.5) / float(image.get_width()), (float(py) + 0.5) / float(image.get_height()))
			var origin: Vector3 = camera.project_ray_origin(ndc)
			var dir: Vector3 = camera.project_ray_normal(ndc)
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0, 6 | 32 | 2)
			var hit: Dictionary = space.intersect_ray(query)
			var label: String = "<no hit>"
			if not hit.is_empty():
				var collider: Object = hit["collider"]
				label = str((collider as Node).name) + " <" + str((collider as Node).get_class()) + "> parent=" + str((collider as Node).get_parent().name)
			if not reported.has(label):
				reported[label] = 0
			reported[label] = int(reported[label]) + 1
	var keys: Array = reported.keys()
	keys.sort_custom(func(a, b) -> bool: return int(reported[a]) > int(reported[b]))
	for k: String in keys:
		print("  dark px hits %-4d  %s" % [int(reported[k]), k])
	quit(0)

func player_pause() -> void:
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	player.set("paused", true)
	scene.set("input_blocked", true)
	(player.get("camera") as Camera3D).current = false

func _v(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]
