extends Node
## ART-SAMPLE-002 · 标准机位模板（四机位 + 近景特写，自动取景）
##
## 用途：任何星球只要把 `TARGET` 指向英雄区根节点，就能一键出**同规格**的验收图：
##   A Wide / B PlayerEye / C Interaction / D ThreeQuarter + 4 张近景特写
##
## 用法（在任意 Godot 工程里）：
##   godot --path <工程> --resolution 1920x1080 res://<你的路径>/standard_shots.tscn -- --out=C:/out
##
## 取景规则（与本样例完全一致，保证星球之间可横向比较）：
##   * Wide          : 距目标 6.5×半径、眼高 +0.7 m、FOV 50
##   * PlayerEye     : 站在目标正面 1.6 倍半径处、眼高 1.60 m、FOV 66
##   * Interaction   : 目标正面 1.2–1.8 m（按目标尺寸自适应）、FOV 40–46
##   * ThreeQuarter  : 左前 45°、距 4.5×半径、眼高 +0.3、FOV 52
##   * Closeups      : 包围盒的 4 个角/面各拍一张 1–2 m 特写

const TARGET_NAME := "Hero"          # 英雄区根节点名（找不到就用场景根）
const OUT_PREFIX := "shot"


func _ready() -> void:
	var out_dir := "user://shots"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6)
		elif s.begins_with("--target="):
			pass
	DirAccess.make_dir_recursive_absolute(out_dir)
	var target := _find_target()
	if target == null:
		push_warning("standard_shots: target not found")
		get_tree().quit(1)
		return
	var box := _world_aabb(target)
	var c := box.get_center()
	var r := maxf(0.6, box.size.length() * 0.5)
	var cam := Camera3D.new()
	cam.near = 0.03
	cam.far = 200.0
	add_child(cam)
	cam.make_current()

	var shots := [
		{"id": "A_wide", "pos": c + Vector3(0.55, 0.35, 1.0).normalized() * r * 6.5,
			"look": c + Vector3(0, 0.15 * r, 0), "fov": 50.0},
		{"id": "B_player_eye", "pos": c + Vector3(0.15, 0.0, 1.0).normalized() * r * 1.9
			+ Vector3(0, 1.60 - c.y, 0), "look": c + Vector3(0, 1.55 - c.y, 0), "fov": 66.0},
		{"id": "C_interaction", "pos": c + Vector3(0.30, 0.15, 1.0).normalized() * maxf(1.2, r * 0.9)
			+ Vector3(0, 0.1 * r, 0), "look": c, "fov": 44.0},
		{"id": "D_threequarter", "pos": c + Vector3(-1.0, 0.30, 0.85).normalized() * r * 4.5,
			"look": c + Vector3(0, 0.1 * r, 0), "fov": 52.0},
	]
	# 近景特写：包围盒的四个对角各一张
	var hs := box.size * 0.5
	for i in range(4):
		var sx := 1.0 if i % 2 == 0 else -1.0
		var sz := 1.0 if i < 2 else -1.0
		var p := c + Vector3(sx * hs.x * 1.6, hs.y * 0.55, sz * hs.z * 1.6)
		shots.append({"id": "E_closeup_%d" % (i + 1), "pos": p, "look": c, "fov": 42.0})

	for shot in shots:
		cam.fov = float(shot["fov"])
		cam.global_position = shot["pos"] as Vector3
		cam.look_at(shot["look"] as Vector3, Vector3.UP)
		for k in range(4):
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out_dir, OUT_PREFIX, str(shot["id"])])
		print("STDSHOT %s" % str(shot["id"]))
	print("STDSHOT_DONE %s" % out_dir)
	get_tree().quit(0)


func _find_target() -> Node3D:
	var t := get_tree().current_scene.find_child(TARGET_NAME, true, false) as Node3D
	if t != null:
		return t
	return get_tree().current_scene as Node3D


func _world_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(root.global_position, Vector3.ONE * 2.0)
	return box
