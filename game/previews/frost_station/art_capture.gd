extends SceneTree

## 霜烬星美术验收机位（ART-PLANET-VISUAL-STANDARD v1 的四类机位 + 近景特写）。
##
## 用法：
##   Godot_v4.7.2-stable_win64.exe --path game --script previews/frost_station/art_capture.gd -- <输出目录>
##
## 本脚本只读场景、只写 PNG，不改动任何玩法状态；相机位姿与 FOV 写死在 SHOTS 中，
## 便于改造前后同机位对照。条目第二项为 "camera" 时使用自由相机，为 "player" 时
## 使用玩家第一人称眼高（1.5 m + 身高）机位。HUD 在拍摄时统一隐藏，避免遮挡画面。

const SHOTS: Array = [
	# A. Wide —— 读构图与尺度
	["A-wide-yard", "camera", Vector3(26, 14, -18), Vector3(-6, 4, -96), 52.0],
	["A2-wide-station", "camera", Vector3(-40, 16, -152), Vector3(18, 5, -58), 52.0],
	# B. Player Eye —— 眼高，站在玩家会站的位置
	["B-player-main-entry", "player", Vector3(0, 0.3, -78), Vector3(0, 4.6, -94)],
	["B2-player-yard", "player", Vector3(26, 0.3, -40), Vector3(-26, 3.4, -72)],
	["B3-player-garage", "player", Vector3(46, 0.3, -8), Vector3(45, 1.2, -24)],
	["B4-player-warehouse", "player", Vector3(-43, 0.3, -14), Vector3(-52, 1.8, -26)],
	# C. Interaction —— 1–2 m 近景，读工艺与材质
	["C-interaction-suction", "player", Vector3(15, 0.3, -103), Vector3(15, 1.2, -106.6)],
	["C2-interaction-fuse", "player", Vector3(50, 0.3, -105), Vector3(50, 1.3, -108)],
	["C3-interaction-core", "player", Vector3(0, 0.3, 11), Vector3(0, 1.9, 16)],
	# D. Three-quarter —— 主体与自然环境的关系
	["D-threequarter-bone", "camera", Vector3(46, 26, -60), Vector3(0, 18, -186), 54.0],
	["D2-threequarter-museum", "player", Vector3(-34, 0.3, -47), Vector3(-49, 3.4, -74)],
	# 近景特写：边角 / 紧固 / 接触 / 表面
	["E1-eave", "camera", Vector3(7.5, 4.4, -84.5), Vector3(9.8, 9.5, -94.3), 46.0],
	["E2-wall-panel", "camera", Vector3(-13.6, 1.9, -91.0), Vector3(-13.6, 2.2, -94.4), 42.0],
	["E3-ice-lock", "camera", Vector3(-54.4, 1.6, -18.2), Vector3(-57.4, 1.8, -21.6), 44.0],
	["E4-ground-snow", "camera", Vector3(2.2, 1.15, -58), Vector3(6.5, 0.15, -64.5), 42.0],
	["E5-bone", "camera", Vector3(-45.4, 2.6, -67.6), Vector3(-49.0, 3.4, -74.4), 44.0],
	["E6-door-frame", "camera", Vector3(0.8, 2.1, -90.4), Vector3(0.0, 2.6, -94.2), 46.0],
]

var world_root: Node3D
var actor: Node3D
var folder: String
var camera: Camera3D

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	folder = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://").path_join("../work/art-iterations/20261124-frost-station-art/evidence/after").simplify_path()
	call_deferred("run")

func frames(n: int = 12) -> void:
	for i: int in n:
		await physics_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	world_root = load("res://previews/frost_station/adventure.tscn").instantiate()
	root.add_child(world_root)
	world_root.start_session(false)
	world_root.test_mode = true
	await frames(24)
	actor = world_root.players[1]
	_hide_hud()
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 1400.0
	camera.near = 0.05
	root.add_child(camera)
	for entry: Array in SHOTS:
		await shoot(entry)
	print("FROST_ART_CAPTURE_OK %d shots -> %s" % [SHOTS.size(), folder])
	quit()

func _hide_hud() -> void:
	for layer: Node in world_root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false

func shoot(entry: Array) -> void:
	var shot_name: String = entry[0]
	if String(entry[1]) == "player":
		var player_camera: Camera3D = actor.get("_camera") as Camera3D
		if player_camera != null:
			player_camera.make_current()
		actor.position = entry[2]
		actor.velocity = Vector3.ZERO
		world_root.notice_time = 0.0
		var target: Vector3 = entry[3]
		var offset: Vector3 = target - (actor.position + Vector3.UP * 1.5)
		world_root.accept_controls(1, {"yaw": atan2(-offset.x, -offset.z), "pitch": atan2(-offset.y, Vector2(offset.x, offset.z).length())})
		await frames(26)
	else:
		camera.fov = float(entry[4])
		camera.position = entry[2]
		camera.look_at(entry[3], Vector3.UP)
		camera.make_current()
		await frames(14)
	var player_cam: Camera3D = actor.get("_camera") as Camera3D
	if player_cam != null and String(entry[1]) == "player":
		player_cam.make_current()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(folder + "/" + shot_name + ".png")
	print("shot ", shot_name)
