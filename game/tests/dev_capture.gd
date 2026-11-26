extends SceneTree

## Development screenshot harness. Boots the real scene and captures the real
## player camera at a handful of navigation checkpoints.

var app: Node3D
var out_dir: String = ""


func _initialize() -> void:
	run.call_deferred()


func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	var image: Image = root.get_texture().get_image()
	image.save_png(out_dir + "/" + name + ".png")
	print("SHOT ", name, " ", image.get_width(), "x", image.get_height())


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "res://evidence/dev"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(150)
	var player: PlayerController = app.get("player") as PlayerController
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var hud: GameHud = app.get("hud") as GameHud
	var story: StoryDirector = app.get("story") as StoryDirector
	hud.title_layer.visible = false
	hud.clear_subtitles()
	story.set_process(false)
	await shot("01_spawn")
	player.teleport(Vector3(0, 4.06, 12.6), 0.0, -0.12)
	await frames(20)
	await shot("02_balcony_reveal")
	player.teleport(Vector3(0, 0.06, 8.6), 0.0, -0.02)
	await frames(20)
	await shot("03_core_from_console")
	player.teleport(Vector3(-8.6, 1.66, 9.8), -0.55, -0.1)
	await frames(20)
	await shot("04_left_station")
	player.teleport(Vector3(9.0, 1.66, 9.8), 0.55, -0.1)
	await frames(20)
	await shot("05_right_station")
	player.teleport(Vector3(8.8, 0.06, -5.6), 0.0, -0.06)
	await frames(20)
	await shot("06_isolation")
	player.teleport(Vector3(-13.0, 0.06, -2.0), PI * 0.5, -0.02)
	await frames(20)
	await shot("07_exit")
	print("DEV_CAPTURE_DONE")
	quit()
