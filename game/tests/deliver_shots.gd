extends SceneTree

## 交付截图工具：用真实渲染跑一遍五幕关键节点并落盘 PNG。
## 只在 --script 显式运行时执行，不进入导出包（tests/ 已在导出预设中排除）。

func _initialize() -> void:
	run.call_deferred()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("SHOT_FAIL ", path)
		return
	img.save_png(path)
	print("SHOT_OK ", path, " ", img.get_width(), "x", img.get_height())

func run() -> void:
	var out_dir := ""
	for arg_value in OS.get_cmdline_user_args():
		var s := str(arg_value)
		if s.begins_with("--out="):
			out_dir = s.split("=", true, 1)[1]
	if out_dir.is_empty():
		out_dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var hub: Node = root.get_node_or_null("/root/SessionHub")
	print("SHOTS hub=", hub)

	var launcher: Node = null
	for node in root.get_children():
		if node.name == "Launcher":
			launcher = node
	var deadline := 0
	while launcher == null and deadline < 400:
		await process_frame
		for node in root.get_children():
			if node.name == "Launcher":
				launcher = node
		deadline += 1
	if launcher == null:
		print("SHOTS no launcher")
		quit(1)
		return
	await create_timer(1.2).timeout
	await _shot(out_dir.path_join("01_launcher.png"))

	# 进入第一幕（真实同名按钮）
	var pressed := false
	for btn_value in launcher.find_children("*", "Button", true, false):
		var btn := btn_value as Button
		if btn != null and btn.text == "开始单人剧情":
			btn.pressed.emit()
			pressed = true
			break
	print("SHOTS pressed_solo=", pressed)
	var waited := 0.0
	while waited < 30.0:
		await create_timer(0.5).timeout
		waited += 0.5
		if current_scene != null and str(current_scene.name) == "Act01":
			break
	print("SHOTS scene=", str(current_scene.name) if current_scene != null else "null")
	await create_timer(3.0).timeout
	await _shot(out_dir.path_join("02_act01_entry.png"))
	print("SHOTS_DONE")
	quit(0)
