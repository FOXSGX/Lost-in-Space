extends SceneTree

# Toggle-based isolation. Each capture hides exactly one candidate node, so a
# black region can be attributed by disappearance instead of by shape guessing.

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
	var route: Vector3 = CART.route_pose(0.0).origin + Vector3(0, 0, 2.2)
	camera.look_at_from_position(route + Vector3(-2.0, 1.05, -3.4), route + Vector3(9.0, 0.15, 0.6), Vector3.UP)
	await _frames(6)

	var candidates: Array[String] = ["CaveFloor", "CaveShell", "DockLanding", "MovingCart"]
	await _shot("00_baseline")
	for name: String in candidates:
		var node: Node3D = scene.find_child(name, true, false) as Node3D
		if node == null:
			print("MISSING ", name)
			continue
		node.visible = false
		await _frames(3)
		await _shot("hide_" + name)
		node.visible = true
		await _frames(2)
	# Also try hiding every direct child of the environment to catch unnamed boxes.
	var env: Node3D = scene.find_child("StationaryCave", true, false) as Node3D
	if env != null:
		for child: Node in env.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false
		await _frames(3)
		await _shot("hide_all_env_meshes")
	print("ISOLATE_DONE")
	quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
