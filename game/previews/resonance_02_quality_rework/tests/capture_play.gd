extends SceneTree

# Player-perspective capture for the visual acceptance pass.
#
# visual_sweep.gd uses free audit cameras and hides the HUD so geometry can be
# judged. This script does the opposite: it keeps the real third-person rig and
# the real HUD, because the two complaints from the player report were "the deck
# is a black slab" and "the UI covers the scene". Only the player camera can
# prove those two are fixed.

var app: Node
var stage: Node3D
var player: CharacterBody3D
var output: String
var shot_index: int = 0

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = output.path_join("%02d_%s.png" % [shot_index, name])
	root.get_texture().get_image().save_png(path)
	shot_index += 1

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	stage = app.get("stage") as Node3D
	player = stage.get("player") as CharacterBody3D
	await _frames(60)
	# Let the spawn settle so the landing and the boarding steps are in frame.
	await _shot("spawn_view")
	# Put the player on the deck facing the departure controller.
	player.call("restore_at", stage.get("cart").call("to_global", Vector3(1.0, 1.91, 1.6)) as Vector3)
	player.set("_camera_yaw_target", -PI * 0.5)
	await _frames(50)
	await _shot("deck_view")
	(stage.get("cart") as Node3D).call("start")
	await _frames(150)
	await _shot("moving_view")
	(stage.get("hud") as CanvasLayer).call("toggle_help")
	await _frames(10)
	await _shot("debug_hud")
	print("PLAY_CAPTURE_DONE")
	current_scene = null
	app.queue_free()
	await _frames(4)
	quit(0)
