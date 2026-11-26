extends Node
## MECHANICS-004B · 真实窗口截图：货运平台承载 16 kg 晶体的完整运输
## 01–06 全部玩家视角（第一人称）。
##
## 不作弊：只按真实按键、只把相机摆到看得清的位置。不冻结货物、不关碰撞、
## 不传送晶体、不直接设置到站状态、不直接完成剧情。
## 行驶途中**绝不 teleport 玩家**（teleport 会松开操纵杆，那不是玩家行为），
## 只调用 aim_camera_at 转视角。
##
## 第四幕正式洞穴较暗：这里在货运区临时补一盏灯（仅截图进程，不改正式场景）。

const OUT := "res://captures/mech004b"
const LEVER_LOCAL := Vector3(-1.02, 0.05, -0.50)
const CLAMP_LEVER_LOCAL := Vector3(-0.20, 0.05, -1.05)

var stage: Node
var platform: Node
var player: Node3D
var crystal: Node3D
var fill: OmniLight3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	platform = stage.get("platform")
	player = stage.get("player") as Node3D
	crystal = stage.get("crystal_a") as Node3D

	fill = OmniLight3D.new()
	fill.light_color = Color(1.0, 0.88, 0.72)
	fill.light_energy = 9.0
	fill.omni_range = 18.0
	stage.add_child(fill)

	# ---------------- 01 平台在断层一侧、尚未装货 ----------------
	fill.global_position = (platform as Node3D).global_position + Vector3(0.0, 3.2, 2.4)
	_stand((platform as Node3D).to_global(Vector3(2.35, 0.05, 1.85)),
		(platform as Node3D).to_global(Vector3(-0.20, 0.55, -0.10)))
	await _w(40)
	await _shot("01_platform_empty.png",
		"平台停在西侧装货台、货台空着（未装货）· x=%.2f dock=%s cargo=%s" % [
			float(platform.get("travel_x")), str(platform.call("current_dock")),
			str(platform.get("cargo_attached"))])

	# ---------------- 02 玩家把晶体放上货台 ----------------
	var cpos: Vector3 = crystal.global_position
	_stand(Vector3(cpos.x - 1.10, cpos.y + 0.10, cpos.z + 0.55), cpos + Vector3(0.0, 0.6, 0.0))
	await _w(45)
	await _key("pickup")
	await _w(20)
	var carried: bool = player.get("carrying") == crystal
	var bay: Vector3 = platform.call("get_bay_position") as Vector3
	_stand(Vector3(bay.x, (platform as Node3D).global_position.y + 0.05, bay.z + 1.10),
		bay + Vector3(0.0, 0.35, 0.0))
	await _w(45)
	await _shot("02_place_on_deck.png",
		"玩家把 16 kg 晶体搬到货台上方，准备放下（carried=%s）" % str(carried))
	await _key("pickup")
	await _w(80)
	_stand((platform as Node3D).to_global(Vector3(1.30, 0.05, 0.75)),
		(platform as Node3D).to_global(Vector3(0.0, 0.20, 0.0)))
	await _w(25)
	await _shot("02b_seated_on_deck.png",
		"晶体靠重力落在货台甲板上（真实刚体，cargo=%s，未冻结=%s）" % [
			str(platform.get("cargo") == crystal), str(not bool(crystal.get("freeze")))])

	# ---------------- 03 夹具正在固定晶体 ----------------
	# 站到夹具杆正前方，并确认**真的**选中了夹具控制点（否则按 E 会抓扶手）
	var targeting: bool = await _stand_at_control("clamp", CLAMP_LEVER_LOCAL)
	await _key("interact")
	await _w(26)
	await _shot("03_clamping.png",
		"E 合拢夹具：四块侧挡向内夹住晶体、压板下压（side_inner=%.2f press=%.2f target=%s）" % [
			float(platform.get("jaw_side_inner")), float(platform.get("_press_y")),
			str(targeting)])
	var locked := false
	for i in range(300):
		await get_tree().physics_frame
		if bool(platform.call("is_cargo_fixed")):
			locked = true
			break
	await _w(12)
	_stand((platform as Node3D).to_global(Vector3(1.30, 0.05, 0.55)),
		(platform as Node3D).to_global(Vector3(0.0, 0.55, 0.0)))
	await _w(18)
	await _shot("03b_clamped.png",
		"夹具已经锁定：fixed=%s press=%.2f side=%.2f clamp_t=%.2f" % [
			str(locked), float(platform.get("_press_y")),
			float(platform.get("jaw_side_inner")), float(platform.get("clamp_t"))])

	# ---------------- 04 平台承载晶体穿越断层 ----------------
	var local0: Vector3 = (platform as Node3D).to_local(crystal.global_position)
	var holding: bool = await _take_lever()
	Input.action_press("move_forward")
	for i in range(95):
		await get_tree().physics_frame
	# ---- 04 运输途中：只转视角（不松杆、不传送），平台仍在滑行 ----
	var v_moving: float = float(platform.get("speed"))
	var x_moving: float = float(platform.get("travel_x"))
	player.call("aim_camera_at", (platform as Node3D).to_global(Vector3(0.02, 0.28, 0.40)), -0.52)
	await _w(6)
	var l_now: Vector3 = (platform as Node3D).to_local(crystal.global_position)
	await _shot("04_carry_across.png",
		"平台承载晶体穿越断层（真实运输途中）· x=%.2f v=%.2f 相对货台位移=%.3f fixed=%s holding=%s" % [
			x_moving, v_moving,
			Vector2(l_now.x - local0.x, l_now.z - local0.z).length(),
			str(platform.call("is_cargo_fixed")), str(holding)])

	# ---- 05 一直按住 W 开到对岸，由端位限位/制动自然停住 ----
	var arrived := false
	for i in range(600):
		await get_tree().physics_frame
		if absf(float(platform.get("travel_x")) - float(platform.get("far_park_x"))) < 0.08 \
				and absf(float(platform.get("speed"))) < 0.08:
			arrived = true
			break
	Input.action_release("move_forward")
	await _w(20)
	await _key("interact")            # 松开操纵杆（真实玩家操作）
	await _w(15)
	# 走到货台东南角：晶体 + 夹具 + 对岸装货台都在画面里
	_stand((platform as Node3D).to_global(Vector3(1.30, 0.05, 0.55)),
		(platform as Node3D).to_global(Vector3(0.0, 0.55, 0.0)))
	await _w(16)
	await _shot("05_arrived_braked.png",
		"平台制动并到达对岸装货台 · dock=%s x=%.2f v=%.3f arrived=%s fixed=%s" % [
			str(platform.call("current_dock")), float(platform.get("travel_x")),
			float(platform.get("speed")), str(arrived), str(platform.call("is_cargo_fixed"))])

	# ---------------- 06 玩家卸下晶体、继续安装中继 ----------------
	await _key("interact")      # 松开操纵杆（玩家真实操作）
	await _w(20)
	await _stand_at_control("clamp", CLAMP_LEVER_LOCAL)
	await _key("interact")      # 打开夹具
	var opened := false
	for i in range(280):
		await get_tree().physics_frame
		if not bool(platform.call("is_cargo_fixed")):
			opened = true
			break
	await _w(20)
	var cw: Vector3 = crystal.global_position
	_stand(Vector3(cw.x - 1.05, (platform as Node3D).global_position.y + 0.05, cw.z + 0.55),
		cw + Vector3(0.0, 0.45, 0.0))
	await _w(35)
	await _key("pickup")
	await _w(25)
	var held: bool = player.get("carrying") == crystal
	await _shot("06_pickup_from_deck.png",
		"玩家从货台上取下同一块晶体（夹具已开=%s，carrying=%s）" % [str(opened), str(held)])

	print("CAP freight=" + str({
		"arrived_far": arrived,
		"dock": str(platform.call("current_dock")),
		"x": snappedf(float(platform.get("travel_x")), 0.01),
		"crystal_instance": crystal.get_instance_id(),
		"stage_crystal_instance": (stage.get("crystal_a") as Node3D).get_instance_id(),
		"carrying": held,
	}))
	get_tree().quit(0)


func _key(action: String) -> void:
	Input.action_press(action)
	await _w(3)
	Input.action_release(action)


func _stand(eye: Vector3, target: Vector3) -> void:
	player.call("teleport", eye, 0.0)
	var eye_at: Vector3 = eye + Vector3.UP * 1.55
	var drop: float = eye_at.y - target.y
	var flat: float = Vector2(target.x - eye.x, target.z - eye.z).length()
	var pitch: float = -clampf(atan2(drop, maxf(flat, 0.05)), 0.10, 1.05)
	player.call("aim_camera_at", target, pitch)


func _shot(file_name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT, file_name]))
	var w: int = img.get_width()
	var h: int = img.get_height()
	var lum := 0.0
	for k in range(20):
		var px: Color = img.get_pixel(int(w * (0.3 + 0.02 * k)), int(h * 0.5))
		lum += (px.r + px.g + px.b) / 3.0
	print("SHOT %s lum=%.3f  %s" % [file_name, lum / 20.0, note])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


## 站到某个控制点前面，直到 `current_target` 真的是它（否则按 E 会误抓扶手）。
## 返回是否选中。`control_local` 是该控制点在平台上的局部坐标。
func _stand_at_control(kind: String, control_local: Vector3) -> bool:
	var offsets: Array[Vector3] = [
		Vector3(0.30, 0.0, 0.55), Vector3(-0.30, 0.0, 0.55),
		Vector3(0.55, 0.0, 0.30), Vector3(-0.55, 0.0, 0.30),
		Vector3(0.0, 0.0, 0.62), Vector3(0.40, 0.0, 0.40),
	]
	var target_world: Vector3 = (platform as Node3D).to_global(control_local)
	for offset: Vector3 in offsets:
		var eye: Vector3 = (platform as Node3D).to_global(control_local + offset)
		_stand(eye, target_world)
		for i in range(24):
			await get_tree().physics_frame
		var hit: Node = player.get("current_target") as Node
		if hit != null and str(hit.get("kind")) == kind:
			# 再等两帧让提示稳定
			await _w(6)
			return true
	return false


## 走到行驶操纵杆前握杆（用控制点定位，确保真的选中操纵台而不是旁边的扶手）。
func _take_lever() -> bool:
	var got: bool = await _stand_at_control("drive", LEVER_LOCAL)
	await _key("interact")
	await _w(12)
	return platform.get("control_owner") == player
