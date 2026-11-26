extends SceneTree

## MECHANICS-005A-R2 · 真实窗口取证
##
##   tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path game \
##       --script res://tests/mech005a_r2_capture.gd
##
## 必须窗口模式（headless 截不到画面）。输出 game/captures/mech005a_r2/
## 规则：相机是正式第一人称玩家相机；只 teleport 玩家；机械位移全部由真实
## W/E/S 输入产生；截图脚本不写 extension / latched / load_force。

const OUT := "res://captures/mech005a_r2"
const WEST := 0
const EAST := 1

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var core: CoreRig
var hud: GameHud
var legs: Array[StabilizerRig] = []
var shots: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	shots.append(name)
	print("SHOT %s" % name)


func clean(obj: String = "") -> void:
	hud.title_layer.visible = false
	hud.clear_subtitles()
	hud.set_prompt("")
	if obj != "":
		hud.set_objective(obj)


func look_from(pos: Vector3, target: Vector3, bias: float = 0.0) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.external_hold = false
	var d: Vector3 = target - pos
	var flat: float = Vector2(d.x, d.z).length()
	player.teleport(pos, atan2(-d.x, -d.z), clampf(-atan2(target.y - (pos.y + 1.62), flat) + bias, -1.1, 1.1))
	await frames(14)


func aim(target: Vector3) -> void:
	var eye: Vector3 = player.global_position + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	var flat: Vector2 = Vector2(d.x, d.z)
	player.set_look(atan2(-d.x, -d.z), clampf(-atan2(d.y, maxf(flat.length(), 0.05)), -1.1, 1.1))
	await frames(6)


func ram_target(i: int) -> Vector3:
	var l: StabilizerRig = legs[i]
	return l.to_global(Vector3(1.45 + l.extension * StabilizerRig.STROKE, 7.05, 0.0))


func stand_at(i: int, back: float = 1.6) -> void:
	var l: StabilizerRig = legs[i]
	var pos: Vector3 = l.area.global_position + l.global_transform.basis.z * back
	pos.y = 0.06
	await look_from(pos, l.area.global_position + Vector3(0, 0.35, 0))


func hold_until(i: int, seconds: float, cond: Callable) -> void:
	Input.action_press("move_forward")
	for _i in range(int(round(seconds * 60.0))):
		await physics_frame
		if bool(cond.call()):
			break
	Input.action_release("move_forward")
	await frames(2)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(90)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	core = level.core
	hud = app.get("hud") as GameHud
	legs = level.stabilizers
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(30)

	# 走正式触发体进大厅
	clean("深入 R-05 设施，前往地心共振大厅")
	await look_from(Vector3(0, 5.9, 14.0), Vector3(0, 1.4, 0.0))
	await shot("01_hall_initial")
	await look_from(Vector3(0, 4.06, 12.2), Vector3(0, 4.06, 0.0))
	for _i in range(120):
		if level.story_stage() >= 2:
			break
		await physics_frame

	# 02 压板距离核心尚远（未配平，大摆幅）
	await stand_at(WEST)
	await frames(20)
	await shot("02_pad_far_from_core")
	print("CAP02 gap=%.4f ext=%.4f" % [legs[WEST].signed_gap, legs[WEST].extension])

	# 03 压板接近环面
	await stand_at(WEST)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(10)
	await hold_until(WEST, 1.2, func() -> bool: return legs[WEST].signed_gap < 0.35)
	await aim(ram_target(WEST))
	await shot("03_pad_approaching")
	print("CAP03 gap=%.4f ext=%.4f" % [legs[WEST].signed_gap, legs[WEST].extension])

	# 04 真实接触刚建立
	await hold_until(WEST, 2.0, func() -> bool: return legs[WEST].contact)
	await frames(6)
	await aim(ram_target(WEST))
	await shot("04_first_contact")
	print("CAP04 gap=%.4f pen=%.4f N=%.0f" % [legs[WEST].signed_gap,
		legs[WEST].penetration, legs[WEST].load_force])

	# 05 压板受载、压力上升
	await hold_until(WEST, 2.5, func() -> bool: return legs[WEST].load_force > 40000.0)
	await frames(6)
	await aim(ram_target(WEST))
	await shot("05_pad_loaded")
	print("CAP05 N=%.0f p=%.2fMPa" % [legs[WEST].load_force,
		legs[WEST].pressure * StabilizerRig.RELIEF / 1.0e6])

	# 06 西侧锁止
	await hold_until(WEST, 3.0, func() -> bool: return legs[WEST].mechanically_latched)
	if player.operating:
		Input.action_press("interact")
		await frames(3)
		Input.action_release("interact")
		await frames(4)
	await aim(ram_target(WEST))
	await shot("06_west_latched")
	print("CAP06 mech=%s ext=%.4f" % [str(legs[WEST].mechanically_latched), legs[WEST].extension])

	# 07 东侧首次接触
	await stand_at(EAST)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(10)
	await hold_until(EAST, 2.5, func() -> bool: return legs[EAST].contact)
	await aim(ram_target(EAST))
	await shot("07_east_first_contact")
	print("CAP07 E gap=%.4f N=%.0f" % [legs[EAST].signed_gap, legs[EAST].load_force])

	# 08 两侧共同承载
	await hold_until(EAST, 3.0, func() -> bool: return legs[EAST].mechanically_latched)
	if player.operating:
		Input.action_press("interact")
		await frames(3)
		Input.action_release("interact")
		await frames(4)
	clean("")
	await look_from(Vector3(0, 1.7, 9.4), Vector3(0, 3.4, -2.0), 0.02)
	await shot("08_both_legs_clamping")
	print("CAP08 W=%s E=%s limit=%.4f capturable=%s" % [
		str(legs[WEST].mechanically_latched), str(legs[EAST].mechanically_latched),
		core.capture_net_limit(), str(core.is_capturable())])

	# 09 核心超出捕获窗口（把配重推到极端，核心摆开）
	level.left_station.reset_state(0.0)
	level.right_station.reset_state(1.0)
	core.set_weights(0.0, 1.0)
	for _i in range(200):
		await physics_frame
	clean("核心失稳 · 超出捕获窗口")
	await look_from(Vector3(0, 1.7, 9.4), Vector3(0, 3.4, -2.0), 0.02)
	await shot("09_out_of_window")
	print("CAP09 net=%.3f angle=%.4f Wgap=%.3f Ngap=%.3f" % [core.get_net(),
		core.get_angle(), legs[WEST].signed_gap, legs[EAST].signed_gap])

	# 10 解锁与卸载
	await stand_at(WEST)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(8)
	Input.action_press("move_back")
	for _i in range(40):
		await physics_frame
	Input.action_release("move_back")
	await frames(4)
	if player.operating:
		Input.action_press("interact")
		await frames(3)
		Input.action_release("interact")
	await aim(ram_target(WEST))
	await shot("10_unlock")
	print("CAP10 mech=%s ext=%.4f" % [str(legs[WEST].mechanically_latched), legs[WEST].extension])

	# 11 完成稳定阶段后剧情继续
	level.left_station.reset_state(0.5725)
	level.right_station.reset_state(0.4275)
	core.set_weights(0.5725, 0.4275)
	for _i in range(240):
		await physics_frame
	clean("")
	await look_from(Vector3(0, 1.7, 10.2), Vector3(0, 1.4, 8.6), 0.0)
	await shot("11_story_continues")
	print("CAP11 net=%.3f limit=%.4f capturable=%s stage=%d" % [core.get_net(),
		core.capture_net_limit(), str(core.is_capturable()), level.story_stage()])

	print("R2_CAPTURE_DONE shots=%d" % shots.size())
	quit(0)
