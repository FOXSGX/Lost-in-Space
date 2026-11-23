extends SceneTree

## Record a short error-and-recovery clip: drive the right counterweight into the
## end stop, show the resonance surge, then reverse the input and recover.

var bot: RefCounted
var app: Node3D
var player: PlayerController
var level: LevelBuilder
var hud: GameHud


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-core-finale/evidence/video-error"
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	for file in DirAccess.get_files_at(out_dir + "/frames"):
		DirAccess.remove_absolute(out_dir + "/frames/" + file)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(30):
		await physics_frame
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	hud = app.get("hud") as GameHud
	bot = (load("res://tests/playthrough_bot.gd") as Script).new()
	bot.set("capture_dir", out_dir + "/frames")
	bot.set("capture_every", 4)
	bot.call("setup", app)
	hud.set_objective("配重过冲与反向修正")
	# stage the right station and a mid-rail cart
	level.left_cart.set_p(0.58)
	level.right_cart.set_p(0.48)
	level.core.set_weights(0.58, 0.48)
	player.teleport(Vector3(9.025, 1.66, 7.625), PI * 0.25, 0.15)
	await bot.call("frames", 40)
	level.right_station.interact(player)
	await bot.call("frames", 20)
	hud.subtitle("推动手柄，把右侧配重继续向外送。", "七号", 3.6)
	# drive it into the end stop
	Input.action_press("move_forward")
	await bot.call("seconds", 3.4)
	Input.action_release("move_forward")
	await bot.call("seconds", 1.2)
	var p_over: float = level.right_cart.get_p()
	hud.subtitle("配重撞到止挡——共振冲击！机械设备在响。", "七号", 4.0)
	await bot.call("seconds", 2.2)
	# reverse
	hud.subtitle("反向推动手柄，把配重拉回内侧。", "七号", 3.6)
	Input.action_press("move_back")
	await bot.call("seconds", 2.8)
	Input.action_release("move_back")
	await bot.call("seconds", 2.4)
	var p_recover: float = level.right_cart.get_p()
	hud.subtitle("过冲已修正。松开手柄后仍要留意小车的惯性。", "七号", 4.0)
	await bot.call("seconds", 4.0)
	player.stop_operating()
	await bot.call("seconds", 2.0)
	var report: Dictionary = {
		"surges": level.core.surge_strength,
		"end_p": p_over,
		"recovered_p": p_recover,
		"net": level.core.get_net(),
		"captured_frames": bot.get("captured"),
	}
	var f: FileAccess = FileAccess.open(out_dir + "/error_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("ERROR_CLIP_DONE ", JSON.stringify(report))
	quit(0)
