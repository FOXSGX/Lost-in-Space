extends Node
## MECHANICS-004A · 真实窗口截图：第四幕晶体支架的真实落座与锁爪
## 01–05 玩家视角；06 是标注过的证据镜头（承托面/锁爪/晶体）。
## 说明：第四幕洞穴很暗，这里在支架旁临时补一盏灯（仅截图用，不改正式场景）；
## 晶体由“放到叉口上方自然落下”开始，落座、合拢、锁定全部是真实物理。

const OUT := "res://captures/mech004a"

var stage: Node
var cradles: Dictionary
var player: Node3D
var crystal: Node3D
var evidence: Camera3D
var fill: OmniLight3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	cradles = stage.get("cradles") as Dictionary
	player = stage.get("player") as Node3D
	crystal = stage.get("crystal_a") as Node3D
	var b1: Node3D = cradles["b1"] as Node3D

	# 截图补光（只加在截图进程里）
	fill = OmniLight3D.new()
	fill.light_color = Color(1.0, 0.86, 0.70)
	fill.light_energy = 9.0
	fill.omni_range = 14.0
	stage.add_child(fill)
	fill.global_position = b1.global_position + Vector3(0.6, 2.2, 1.2)

	# 1 任务初始状态：叉口张开、晶体放在旁边的地面上
	_stand(b1.global_position + Vector3(-1.4, 0.05, 1.5), b1.global_position + Vector3(0.0, 0.35, 0.0))
	await _w(30)
	await _shot("01_initial.png", "任务初始：支架叉口张开（jaw=%.2f），晶体在支架旁的甲板上" % float(b1.get("jaw_x")))

	# 2 把晶体放到叉口上方（搬运终点），开始真实落下
	crystal.set("is_carried", false)
	crystal.set("freeze", false)
	crystal.global_position = (b1.call("get_seat_position") as Vector3) + Vector3(0.0, 1.15, 0.0)
	crystal.rotation = Vector3(0.0, deg_to_rad(float(b1.get("required_yaw_deg"))), 0.0)
	crystal.set("held_yaw_deg", float(b1.get("required_yaw_deg")))
	crystal.set("linear_velocity", Vector3.ZERO)
	crystal.set("angular_velocity", Vector3.ZERO)
	await _w(12)
	_stand(b1.global_position + Vector3(-1.3, 0.05, 1.5), b1.global_position + Vector3(0.0, 0.9, 0.0))
	await _w(6)
	await _shot("02_approach.png", "晶体被放到叉口上方，正在靠重力落进叉口（未吸附、未冻结）")

	for i in range(150):
		await get_tree().physics_frame
		if bool(b1.call("is_occupied")):
			break
	await _w(20)
	_stand(b1.global_position + Vector3(-0.95, 0.05, 1.35), b1.global_position + Vector3(0.0, 0.30, 0.0))
	await _w(15)
	await _shot("03_seated.png", "晶体落座：稳稳站在承托面上（occupied=%s，仍是刚体）" % str(b1.call("is_occupied")))

	# 3 按住 E 合拢：拍行程中
	_stand(b1.global_position + Vector3(-0.85, 0.05, 1.15), b1.global_position + Vector3(0.0, 0.35, 0.0))
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(40):
		await get_tree().physics_frame
	await _shot("04_closing.png", "E 启动螺杆：两只锁爪向内合拢（jaw=%.3f）" % float(b1.get("jaw_x")))

	for i in range(240):
		await get_tree().physics_frame
		if bool(b1.get("latched")):
			break
	await _w(20)
	_stand(b1.global_position + Vector3(-0.95, 0.30, 1.55), b1.global_position + Vector3(0.0, 0.30, 0.0))
	await _w(20)
	await _shot("05_locked.png", "物理条件满足：爪压在晶体表面（%.3f）、locked=%s、中继 b1=%s" % [
		float(b1.get("jaw_x")), str(b1.call("locked")), str(stage.call("_relay_ready", "b1"))])

	# 4 证据镜头
	_evidence_at(b1.global_position + Vector3(0.95, 1.0, 1.0), b1.global_position + Vector3(0.0, 0.45, 0.0), 42.0)
	await _w(20)
	await _shot("06_jaws_evidence.png", "证据镜头｜承托面 + 两只锁爪 + 晶体（爪位 %.3f，压住=%s）" % [
		float(b1.get("jaw_x")), str(b1.get("pressing"))])
	print("CAP cradle=%s" % str({
		"jaw": snappedf(float(b1.get("jaw_x")), 0.001),
		"latched": bool(b1.get("latched")),
		"aligned": bool(b1.get("aligned")),
		"locked": bool(b1.call("locked")),
		"inside": bool(b1.call("crystal_inside")),
		"relay": bool(stage.call("_relay_ready", "b1")),
	}))
	get_tree().quit(0)


func _stand(eye: Vector3, target: Vector3) -> void:
	player.call("teleport", eye, 0.0)
	var eye_at: Vector3 = eye + Vector3.UP * 1.55
	var drop: float = eye_at.y - target.y
	var flat: float = Vector2(target.x - eye.x, target.z - eye.z).length()
	var pitch: float = -clampf(atan2(drop, maxf(flat, 0.05)), 0.10, 1.05)
	player.call("aim_camera_at", target, pitch)


func _evidence_at(eye: Vector3, target: Vector3, fov: float = 50.0) -> void:
	evidence = Camera3D.new()
	evidence.name = "EvidenceCamera"
	evidence.fov = fov
	stage.add_child(evidence)
	evidence.global_transform = Transform3D(Basis.IDENTITY, eye)
	evidence.look_at(target, Vector3.UP)
	evidence.current = true


func _shot(name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT, name]))
	var w: int = img.get_width()
	var h: int = img.get_height()
	var lum := 0.0
	for k in range(20):
		var px: Color = img.get_pixel(int(w * (0.3 + 0.02 * k)), int(h * 0.5))
		lum += (px.r + px.g + px.b) / 3.0
	print("SHOT %s lum=%.3f  %s" % [name, lum / 20.0, note])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame



