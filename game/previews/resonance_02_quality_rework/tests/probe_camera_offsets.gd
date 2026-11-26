extends SceneTree

# Camera-offset probe for the cart deck. Pauses the player rig, then renders the
# same moment from four candidate third-person offsets so the one that does not
# sit inside the cart's gantry can be chosen from pixels instead of guessed.

var app: Node
var scene: Node3D
var player: CharacterBody3D
var camera: Camera3D
var output: String

const OFFSETS: Array = [
	{"name": "a_d500_h250", "back": 5.0, "up": 2.5, "side": 0.4},
	{"name": "b_d440_h270", "back": 4.4, "up": 2.7, "side": 0.4},
	{"name": "c_d380_h300", "back": 3.8, "up": 3.0, "side": 0.4},
	{"name": "d_d520_h320", "back": 5.2, "up": 3.2, "side": 0.4},
]

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
	scene = app.get("stage") as Node3D
	player = scene.get("player") as CharacterBody3D
	var cart: AnimatableBody3D = scene.get("cart") as AnimatableBody3D
	player.call("restore_at", cart.call("to_global", Vector3(1.0, 1.91, 1.6)) as Vector3)
	cart.call("start")
	await _frames(200)
	player.set("paused", true)
	camera = player.get("camera") as Camera3D
	camera.current = true
	var forward: Vector3 = -cart.global_basis.x.normalized()
	var side: Vector3 = cart.global_basis.z.normalized()
	for entry: Dictionary in OFFSETS:
		var focus: Vector3 = player.global_position + Vector3.UP * 1.2
		var at: Vector3 = focus - forward * float(entry["back"]) + side * float(entry["side"]) + Vector3.UP * float(entry["up"])
		camera.look_at_from_position(at, focus, Vector3.UP)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(str(entry["name"]) + ".png"))
	print("CAMERA_OFFSETS_DONE")
	current_scene = null
	app.queue_free()
	await _frames(4)
	quit(0)
