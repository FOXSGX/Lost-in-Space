extends SceneTree

## Full playthrough driven only by game input actions (WASD / E / W-S).

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-core-finale/tests-out"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var app: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	var bot: RefCounted = (load("res://tests/playthrough_bot.gd") as Script).new() as RefCounted
	bot.call("setup", app)
	var report: Dictionary = await bot.call("run_tour") as Dictionary
	report["route"] = bot.get("route_log")
	var f: FileAccess = FileAccess.open(out_dir + "/full_walk_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("FULL_WALK ", JSON.stringify({"ok": report["ok"], "failures": report["failures"], "stage": report["stage"], "elapsed": report["elapsed"]}))
	quit(0 if bool(report["ok"]) else 1)
