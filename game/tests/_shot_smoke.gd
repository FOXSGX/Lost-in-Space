extends SceneTree
## Diagnostic only: prove that a real (non-headless) Godot window can render this
## project and that Viewport.get_texture().get_image() yields a real PNG.
## Not part of the acceptance evidence; used once to validate the capture path.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = ""
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			out = s.split("=", true, 1)[1]
	var guard := 0
	while current_scene == null and guard < 600:
		await physics_frame
		guard += 1
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	print("SMOKE scene=%s display=%s img=%s" % [
		str(current_scene.name) if current_scene != null else "null",
		DisplayServer.get_name(), str(img.get_size()) if img != null else "null"])
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var e: int = img.save_png(out)
		print("SMOKE_SAVE %s err=%d" % [out, e])
	quit(0)
