extends SceneTree

## Evidence capture: boot the packaged launcher and drive it into Act 4,
## then capture both the launcher and the Act 4 scene. Run windowed so
## rendering actually produces frames:
##   godot --main-pack <pck> --resolution 1280x720 --script res://tests/capture_packaged.gd -- <out>

var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice/evidence/packaged"


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute(out_dir)
		img.save_png("%s/%s.png" % [out_dir, name])
		print("SHOT ", name)


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await frames(30)
	await shot("launcher")
	# Drive the launcher into Act 4 solo through its real button path.
	var launcher: Node = Engine.get_main_loop().root.get_node_or_null("Launcher")
	if launcher == null:
		launcher = current_scene
	if launcher != null and launcher.has_method("_start_solo"):
		launcher.call("_start_solo")
		await frames(60)
		await shot("act4_entered")
	else:
		print("LAUNCHER_NOT_FOUND scene=", current_scene)
	print("PACKAGED_EVIDENCE_DONE")
	quit()