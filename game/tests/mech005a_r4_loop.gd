extends SceneTree

## R4 第二阶段：最小动力学闭环
## 配平 → 等核心稳定 → 真实 W 泵压 → 接触 → 锁止

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


func _stand(i: int) -> void:
	var leg: StabilizerRig = legs[i]
	var pos: Vector3 = leg.area.global_position + leg.global_transform.basis.z * 1.5
	pos.y = 0.06
	var d: Vector3 = leg.area.global_position - pos
	player.force_exit_operate()
	player.teleport(pos, atan2(-d.x, -d.z), -0.12)
	await _f(10)


func _run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(90):
		await physics_frame
	level = app.get("level") as LevelBuilder
	core = level.core
	player = app.get("player") as PlayerController
	legs = level.stabilizers

	print("=== R4 MINIMAL LOOP ===")
	level.left_station.reset_state(0.5725)
	level.right_station.reset_state(0.4275)
	core.set_weights(0.5725, 0.4275)
	core.angle = 0.0
	core.omega = 0.0

	# 等核心稳定进窗口
	var settled := false
	for i in range(1200):
		await physics_frame
		if i > 300 and core.angle >= -0.02 and core.angle <= 0.09 and absf(core.omega) < 0.25:
			settled = true
			break
	print("settled=%s net=%.3f angle=%+.4f omega=%+.4f lat=%.3f" % [
		str(settled), core.get_net(), core.angle, core.omega, _lat()])

	for i in range(2):
		await _stand(i)
		Input.action_press("interact")
		await _f(4)
		Input.action_release("interact")
		await _f(10)
		var leg: StabilizerRig = legs[i]
		print("\n-- leg%d (%s) operating=%s --" % [i, leg.side_name, str(player.operating)])
		Input.action_press("move_forward")
		for k in range(700):
			await physics_frame
			if k % 60 == 0:
				print("   f%3d ext=%.4f gap=%+8.4f N=%7.1f p=%5.2fMPa ang=%+.4f v=%+.3f mech=%s" % [
					k, leg.extension, leg.signed_gap, leg.load_force,
					leg.pressure * StabilizerRig.RELIEF / 1.0e6, core.angle,
					leg.ram_velocity, str(leg.mechanically_latched)])
			if leg.mechanically_latched:
				break
		Input.action_release("move_forward")
		await _f(4)
		if player.operating:
			Input.action_press("interact")
			await _f(4)
			Input.action_release("interact")
			await _f(6)
		print("   END ext=%.4f mech=%s N=%.1f" % [leg.extension,
			str(leg.mechanically_latched), leg.load_force])

	print("\nFINAL W mech=%s ext=%.4f | E mech=%s ext=%.4f | limit=%.4f capturable=%s" % [
		str(legs[0].mechanically_latched), legs[0].extension,
		str(legs[1].mechanically_latched), legs[1].extension,
		core.capture_net_limit(), str(core.is_capturable())])
	quit(0)


func _lat() -> float:
	var rc: Vector3 = core.outer_ring.global_transform.origin
	var cc: Vector3 = core.global_transform.origin
	return Vector2(rc.x - cc.x, rc.z - cc.z).length()
