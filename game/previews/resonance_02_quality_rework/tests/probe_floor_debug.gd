extends SceneTree

# Split the generated floor into its two inputs. debug_channel 1 shows the raw
# albedo, 2 shows the decoded irradiance. If the floor renders black while both
# inputs look sane, the problem is in the encode/decode, not in the data.

const CART := preload("res://scripts/moving_cart.gd")

var app: Node
var scene: Node3D
var camera: Camera3D
var output: String

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	await _frames(45)
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	player.set("paused", true)
	scene.set("input_blocked", true)
	(player.get("camera") as Camera3D).current = false
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 160.0
	scene.add_child(camera)
	camera.current = true
	(scene.get("hud") as CanvasLayer).visible = false
	await _frames(6)

	# Find the generated floor and report its real vertex colour range.
	var floor_mesh: MeshInstance3D = scene.find_child("CaveFloor", true, false) as MeshInstance3D
	print("FLOOR_FOUND ", floor_mesh != null)
	if floor_mesh == null:
		quit(1)
		return
	var arrays: Array = (floor_mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var lo: float = 1e9
	var hi: float = -1e9
	for c: Color in colors:
		lo = minf(lo, minf(c.r, minf(c.g, c.b)))
		hi = maxf(hi, maxf(c.r, maxf(c.g, c.b)))
	print("FLOOR_VERTEX_COLOR min=%.5f max=%.5f  count=%d" % [lo, hi, colors.size()])
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	print("FLOOR_UV sample=%s" % [uv[0] if uv.size() > 0 else Vector2.ZERO])
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	print("FLOOR_UV2 sample=%s" % [uv2[0] if uv2.size() > 0 else Vector2.ZERO])
	var material: ShaderMaterial = floor_mesh.material_override as ShaderMaterial
	print("FLOOR_MATERIAL ", material != null, " log_irradiance=", material.get_shader_parameter("log_irradiance"), " scale=", material.get_shader_parameter("irradiance_scale"))

	var route: Vector3 = CART.route_pose(0.0).origin + Vector3(0, 0, 2.2)
	camera.look_at_from_position(route + Vector3(-2.0, 1.05, -3.4), route + Vector3(9.0, 0.15, 0.6), Vector3.UP)
	await _frames(2)
	for channel: int in [0, 1, 2]:
		material.set_shader_parameter("debug_channel", channel)
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("floor_ch%d.png" % channel))
	print("FLOOR_DEBUG_DONE")
	quit(0)
