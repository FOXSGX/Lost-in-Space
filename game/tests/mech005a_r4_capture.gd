extends SceneTree

## MECHANICS-005A-R4 · 真实窗口取证
##   godot --path game --script res://tests/mech005a_r4_capture.gd
## 窗口模式运行；headless 截不到画面。

const OUT := "res://captures/mech005a_r4"
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


func wait(s: float) -> void:
	await frames(maxi(1, int(round(s * 60.0))))


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


func look(pos: Vector3, target: Vector3, bias: float = 0.0) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.external_hold = false
	var d: Vector3 = target - pos
	var flat: float = Vector2(d.x, d.z).length()
	player.teleport(pos, atan2(-d.x, -d.z),
		clampf(-atan2(target.y - (pos.y + 1.62), flat) + bias, -1.1, 1.1))
	await frames(14)


func aim(target: Vector3) -> void:
	var eye: Vector3 = player.global_position + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	player.set_look(atan2(-d.x, -d.z),
		clampf(-atan2(d.y, maxf(Vector2(d.x, d.z).length(), 0.05)), -1.1, 1.1))
	await frames(6)


func ram_target(i: int) -> Vector3:
	var l: StabilizerRig = legs[i]
	return l.to_global(Vector3(StabilizerRig.PAD_FACE_LOCAL_X + l.extension * StabilizerRig.STROKE,
		7.05, 0.0))


func stand_at(i: int, back: float = 1.6) -> void:
	var l: StabilizerRig = legs[i]
	var pos: Vector3 = l.area.global_position + l.global_transform.basis.z * back
	pos.y = 0.06
	await look(pos, l.area.global_position + Vector3(0, 0.35, 0))


func settle() -> void:
	for _i in range(900):
		if core.angle >= -0.02 and core.angle <= 0.09 and absf(core.omega) < 0.25:
			return
		await physics_frame


func latch(i: int) -> int:
	var l: StabilizerRig = legs[i]
	var t: int = 0
	while not l.mechanically_latched and t < 4:
		t += 1
		await stand_at(i)
		Input.action_press("interact")
		await frames(4)
		Input.action_release("interact")
		await frames(10)
		await settle()
		Input.action_press("move_forward")
		for _k in range(600):
			await physics_frame
			if l.mechanically_latched:
				break
		Input.action_release("move_forward")
		await frames(4)
		if l.mechanically_latched:
			break
		Input.action_press("move_back")
		await wait(4.8)
		Input.action_release("move_back")
		await frames(4)
	if player.operating:
		Input.action_press("interact")
		await frames(4)
		Input.action_release("interact")
		await frames(6)
	return t


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

	# 01 初始大摆幅
	clean("深入 R-05 设施，前往地心共振大厅")
	await look(Vector3(0, 5.9, 14.0), Vector3(0, 1.4, 0.0))
	await frames(60)
	await look(Vector3(0, 6.2, 13.0), Vector3(0, 3.4, -2.0))
	await shot("01_initial_large_swing")
	print("CAP01 net=%.3f angle=%+.4f lat=%.3f" % [core.get_net(), core.angle, _lat()])

	# 02 完全收回的压板与核心的空间关系（俯视远景）
	await look(Vector3(0, 11.0, 15.5), Vector3(0, 4.5, -3.0))
	await frames(20)
	await shot("02_retracted_pad_clearance")
	print("CAP02 W ext=%.3f gap=%.3f | E ext=%.3f gap=%.3f" % [
		legs[0].extension, legs[0].signed_gap, legs[1].extension, legs[1].signed_gap])

	# 03 未配平时压板够不到（站到西侧看）
	await stand_at(WEST)
	Input.action_press("interact")
	await frames(4)
	Input.action_release("interact")
	await frames(10)
	Input.action_press("move_forward")
	await wait(5.0)
	Input.action_release("move_forward")
	await frames(6)
	await aim(ram_target(WEST))
	await shot("03_unbalanced_cannot_reach")
	print("CAP03 net=%.3f angle=%+.4f W ext=%.3f gap=%.3f contact=%s" % [
		core.get_net(), core.angle, legs[0].extension, legs[0].signed_gap,
		str(legs[0].contact)])
	if player.operating:
		Input.action_press("interact")
		await frames(4)
		Input.action_release("interact")
	Input.action_press("move_back")
	await wait(4.8)
	Input.action_release("move_back")
	await frames(6)

	# 04 玩家调整配重
	clean("用配重把手柄把核心压进捕获范围")
	await look(Vector3(-8.5, 1.70, 7.47), level.left_station.area.global_position)
	await frames(10)
	await shot("04_player_trimming_weights")

	level.left_station.reset_state(0.5725)
	level.right_station.reset_state(0.4275)
	core.set_weights(0.5725, 0.4275)
	await settle()

	# 05 配重后进入捕获区
	clean("")
	await look(Vector3(0, 6.2, 13.0), Vector3(0, 3.4, -2.0))
	await frames(20)
	await shot("05_in_capture_window")
	print("CAP05 net=%.3f angle=%+.4f lat=%.3f" % [core.get_net(), core.angle, _lat()])

	# 06 西侧真实接触
	await stand_at(WEST)
	Input.action_press("interact")
	await frames(4)
	Input.action_release("interact")
	await frames(10)
	# Hold the pump until the pad is actually loaded, then keep it pressed for the
	# frame the screenshot is taken on - releasing first lets the ring push back.
	var reached := false
	Input.action_press("move_forward")
	for _i in range(700):
		await physics_frame
		if legs[WEST].contact and legs[WEST].load_force > 30000.0:
			reached = true
			break
	if not reached:
		for _i in range(240):
			await physics_frame
			if legs[WEST].contact and legs[WEST].load_force > 30000.0:
				reached = true
				break
	await aim(ram_target(WEST))
	await shot("06_west_real_contact")
	Input.action_release("move_forward")
	await frames(3)
	print("CAP06 W gap=%.4f pen=%.4f N=%.0f p=%.2fMPa" % [
		legs[WEST].signed_gap, legs[WEST].penetration, legs[WEST].load_force,
		legs[WEST].pressure * StabilizerRig.RELIEF / 1.0e6])

	# 07 接触衬垫受压状态（近距离）
	await aim(ram_target(WEST))
	await frames(6)
	await shot("07_pad_compressed")

	# 08 西侧锁止
	await latch(WEST)
	await stand_at(WEST)
	await aim(ram_target(WEST))
	await shot("08_west_latched")
	print("CAP08 W mech=%s ext=%.4f" % [str(legs[WEST].mechanically_latched), legs[WEST].extension])

	# 09 东侧真实接触与双侧锁止
	await latch(EAST)
	clean("")
	await look(Vector3(0, 1.7, 9.4), Vector3(0, 3.4, -2.0), 0.02)
	await frames(16)
	await shot("09_both_legs_latched")
	print("CAP09 W=%s E=%s limit=%.4f capturable=%s" % [
		str(legs[0].mechanically_latched), str(legs[1].mechanically_latched),
		core.capture_net_limit(), str(core.is_capturable())])

	# 10 解锁与回缩
	await stand_at(WEST)
	Input.action_press("interact")
	await frames(4)
	Input.action_release("interact")
	await frames(8)
	Input.action_press("move_back")
	await wait(3.0)
	Input.action_release("move_back")
	await frames(6)
	if player.operating:
		Input.action_press("interact")
		await frames(4)
		Input.action_release("interact")
	await aim(ram_target(WEST))
	await shot("10_unlock_and_retract")
	print("CAP10 W mech=%s ext=%.4f" % [str(legs[WEST].mechanically_latched), legs[WEST].extension])

	# 11 故事继续
	await latch(WEST)
	clean("")
	await look(Vector3(0, 1.7, 10.2), Vector3(0, 1.4, 8.6), 0.0)
	await frames(10)
	await shot("11_story_continues")
	print("CAP11 net=%.3f limit=%.4f stage=%d" % [core.get_net(),
		core.capture_net_limit(), level.story_stage()])

	print("R4_CAPTURE_DONE shots=%d" % shots.size())
	quit(0)


func _lat() -> float:
	var rc: Vector3 = core.outer_ring.global_transform.origin
	var cc: Vector3 = core.global_transform.origin
	return Vector2(rc.x - cc.x, rc.z - cc.z).length()
