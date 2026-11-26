extends SceneTree

## R4：复现 test_solo_coop 的东→西顺序，诊断西侧为何够不到

var app: Node3D
var level: LevelBuilder
var core: CoreRig
var player: PlayerController
var legs: Array[StabilizerRig] = []


func _initialize() -> void:
	_run.call_deferred()


func _f(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _wait(s: float) -> void:
	await _f(maxi(1, int(round(s * 60.0))))


func _stand(pos: Vector3, look: Vector3) -> void:
	var d: Vector3 = look - pos
	player.force_exit_operate()
	player.teleport(pos, atan2(-d.x, -d.z), -0.12)
	await _f(10)


func _interact() -> void:
	Input.action_press("interact")
	await _f(3)
	Input.action_release("interact")
	await _f(4)


func _run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await _f(90)
	level = app.get("level") as LevelBuilder
	core = level.core
	player = app.get("player") as PlayerController
	legs = level.stabilizers

	print("=== R4 SOLO-ORDER DIAG (east -> west) ===")
	print("initial net=%.3f angle=%+.4f" % [core.get_net(), core.angle])

	# 先配平（模拟 solo_coop 的配重阶段）
	level.left_station.reset_state(0.0)
	level.right_station.reset_state(0.0)
	core.set_weights(0.0, 0.0)
	await _wait(1.0)
	# 拉到 solo_coop 的实际配平值
	level.left_station.reset_state(0.25)
	level.right_station.reset_state(0.0)
	core.set_weights(0.25, 0.0)
	await _wait(6.0)
	print("BALANCED: net=%.3f angle=%+.4f omega=%+.4f lat=%.3f" % [
		core.get_net(), core.angle, core.omega, _lat()])
	var amin := 9.0
	var amax := -9.0
	for _i in range(240):
		await physics_frame
		amin = minf(amin, core.angle)
		amax = maxf(amax, core.angle)
	print("  角度波动 %.4f .. %.4f" % [amin, amax])

	# 西侧：逐帧观察
	var wa: Vector3 = legs[0].anchor.origin
	await _stand(wa + Vector3(0, 0, -0.6), legs[0].global_position + Vector3(0, 1.2, 0))
	await _interact()
	print("WEST start: ext=%.4f net=%.3f angle=%+.4f lat=%.3f" % [
		legs[0].extension, core.get_net(), core.angle, _lat()])
	Input.action_press("move_forward")
	for i in range(400):
		await physics_frame
		if i % 40 == 0:
			print("  f%3d ext=%.4f gap=%+8.4f N=%7.1f ang=%+.4f v=%+.3f mech=%s" % [
				i, legs[0].extension, legs[0].signed_gap, legs[0].load_force,
				core.angle, legs[0].ram_velocity, str(legs[0].mechanically_latched)])
		if legs[0].mechanically_latched:
			break
	Input.action_release("move_forward")
	await _f(3)
	print("WEST end: ext=%.4f mech=%s N=%.1f angle=%+.4f" % [
		legs[0].extension, str(legs[0].mechanically_latched), legs[0].load_force, core.angle])
	print("SOLO_DIAG_DONE")
	quit(0)


func _lat() -> float:
	var rc: Vector3 = core.outer_ring.global_transform.origin
	var cc: Vector3 = core.global_transform.origin
	return Vector2(rc.x - cc.x, rc.z - cc.z).length()
