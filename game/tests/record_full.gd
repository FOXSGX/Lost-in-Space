extends SceneTree

## Record the complete real-input playthrough as a 15 fps JPEG sequence.
## Encode with:
## ffmpeg -y -framerate 15 -i frames/frame_%05d.jpg -c:v libx264 -crf 20 -pix_fmt yuv420p full_run.mp4

var bot: RefCounted
var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-05-quality-polish/evidence/video-full"
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	for file in DirAccess.get_files_at(out_dir + "/frames"):
		DirAccess.remove_absolute(out_dir + "/frames/" + file)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	bot = (load("res://tests/playthrough_bot.gd") as Script).new()
	bot.set("capture_dir", out_dir + "/frames")
	bot.set("capture_every", 4)
	bot.call("setup", app)
	var report: Dictionary = await bot.call("run_tour") as Dictionary
	# hold the completion card for a few seconds of footage
	await bot.call("frames", 150)
	report["route"] = bot.get("route_log")
	report["captured_frames"] = bot.get("captured")
	var f: FileAccess = FileAccess.open(out_dir + "/record_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("RECORD_DONE ", JSON.stringify({"ok": report.get("ok"), "frames": bot.get("captured"), "failures": report.get("failures")}))
	quit(0)
