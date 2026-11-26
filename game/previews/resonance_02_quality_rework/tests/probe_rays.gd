extends SceneTree

# Cast the exact audit-camera frustum against the generated corridor and report
# every pixel whose ray escapes to the background. Produces a mask image so the
# hole can be located in screen space and traced back to world space.

const CART := preload("res://scripts/moving_cart.gd")

var output: String
var host: Node3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	host = Node3D.new()
	root.add_child(host)
	current_scene = host
	var tunnel: Node3D = preload("res://scripts/cave_tunnel.gd").new() as Node3D
	host.add_child(tunnel)
	tunnel.call("build", host)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 200.0
	camera.current = true
	host.add_child(camera)
	await _frames(6)
	var space: PhysicsDirectSpaceState3D = host.get_world_3d().direct_space_state
	var views: Dictionary = {
		"090_deck": [Vector3(90, 3.5, 0), Vector3(104, 1.9, 0)],
		"040_overview": [Vector3(34, 7.4, -4.0), Vector3(48, 1.2, 0.4)],
		"000_reverse": [Vector3(3.2, 3.3, 0.0), Vector3(-16.0, 1.6, 0.0)],
	}
	for name: String in views:
		var spec: Array = views[name]
		var offset_a: Vector3 = spec[0] as Vector3
		var offset_b: Vector3 = spec[1] as Vector3
		var at: Vector3 = CART.route_pose(offset_a.x) * Vector3(0.0, offset_a.y, offset_a.z)
		var look: Vector3 = CART.route_pose(clampf(offset_b.x, 0.0, 90.0)) * Vector3(0.0, offset_b.y, offset_b.z)
		if offset_b.x > 90.0:
			look = at + CART.route_pose(90.0).basis * Vector3(offset_b.x - 90.0, 0.0, 0.0) + Vector3(0, offset_b.y - 3.5, 0)
		camera.look_at_from_position(at, look, Vector3.UP)
		var width: int = 160
		var height: int = 100
		var mask: Image = Image.create(width, height, false, Image.FORMAT_RGB8)
		var escapes: Array[Vector3] = []
		for py: int in range(height):
			for px: int in range(width):
				var ndc: Vector2 = Vector2((float(px) + 0.5) / float(width), (float(py) + 0.5) / float(height))
				var origin: Vector3 = camera.project_ray_origin(ndc)
				var dir: Vector3 = camera.project_ray_normal(ndc)
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0, 6)
				if space.intersect_ray(query).is_empty():
					mask.set_pixel(px, py, Color(1, 0, 1))
					escapes.append(origin + dir * 6.0)
				else:
					mask.set_pixel(px, py, Color(0, 0, 0))
		mask.resize(width * 4, height * 4, Image.INTERPOLATE_NEAREST)
		mask.save_png(output.path_join(name + "_mask.png"))
		print("VIEW %-14s escapes=%d / %d" % [name, escapes.size(), width * height])
		if not escapes.is_empty():
			var sample: Vector3 = escapes[escapes.size() / 2]
			var s: float = float(tunnel.call("nearest_s", sample))
			var local: Vector3 = CART.route_pose(s).affine_inverse() * sample
			print("   mid escape world=%s -> s=%.1f lateral=%.2f up=%.2f" % [sample, s, local.z - 2.2, local.y])
	quit(0)
