extends SceneTree

## MECHANICS-005A-R2 · 接触闭环实测
##
##   godot --headless --path game --script res://tests/mech005a_r2_probe.gd

var app: Node3D
var level: LevelBuilder
var core: CoreRig
var player: PlayerController
var legs: Array[StabilizerRig] = []


func _initialize() -> void:
	_run.call_deferred()


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
	var hud: GameHud = app.get("hud") as GameHud
	if hud != null:
		hud.title_layer.visible = false

	print("=== R2 CONTACT PROBE ===")
	print("RIG_RADIUS=%.3f ring_outer=%.3f" % [StabilizerRig.RIG_RADIUS, CoreRig.RING_OUTER_RADIUS])
	for i in range(2):
		var l: StabilizerRig = legs[i]
		print("  leg%d(%s) origin=%s pad_r(e0)=%.4f pad_r(e1)=%.4f" % [
			i, l.side_name, str(l.global_transform.origin.snapped(Vector3(0.01,0.01,0.01))),
			_radius(l, 0.0), _radius(l, 1.0)])

	print("\n-- A) 未操作：必须无接触、法向力为零 --")
	print("  gap=%.4f contact=%s N=%.1f carrying=%s" % [
		legs[0].signed_gap, str(legs[0].contact), legs[0].load_force, str(legs[0].carrying_load)])

	print("\n-- 配平到捕获窗口 --")
	level.left_station.reset_state(0.5725)
	level.right_station.reset_state(0.4275)
	core.set_weights(0.5725, 0.4275)
	for _i in range(180):
		await physics_frame
	print("  net=%.3f angle=%.4f omega=%.4f" % [core.get_net(), core.get_angle(), core.get_omega()])

	print("\n-- B) 西侧真实 W 泵压 --")
	await _stand_at_leg(0)
	Input.action_press("interact")
	await _frames(4)
	Input.action_release("interact")
	await _frames(10)
	var leg: StabilizerRig = legs[0]
	Input.action_press("move_forward")
	var first := false
	for i in range(280):
		await physics_frame
		if not first and leg.contact:
			first = true
			print("  FIRST CONTACT f%d: gap=%.4f pen=%.4f N=%.1f ext=%.4f" % [
				i, leg.signed_gap, leg.penetration, leg.load_force, leg.extension])
		if i % 25 == 0:
			print("   f%3d ext=%.4f gap=%+8.4f N=%7.1f p=%5.2fMPa v=%+.3f mech=%s carry=%s" % [
				i, leg.extension, leg.signed_gap, leg.load_force,
				leg.pressure * StabilizerRig.RELIEF / 1.0e6, leg.ram_velocity,
				str(leg.mechanically_latched), str(leg.carrying_load)])
		if leg.mechanically_latched:
			print("  LATCHED f%d ext=%.4f N=%.1f core_angle=%.4f" % [
				i, leg.extension, leg.load_force, core.angle])
			break
	Input.action_release("move_forward")
	await _frames(4)
	print("  final: ext=%.4f gap=%+.4f N=%.1f mech=%s carry=%s angle=%.4f" % [
		leg.extension, leg.signed_gap, leg.load_force, str(leg.mechanically_latched),
		str(leg.carrying_load), core.angle])

	print("\n-- C) 松手 60 帧 --")
	if player.operating:
		Input.action_press("interact")
		await _frames(3)
		Input.action_release("interact")
	for i in range(60):
		await physics_frame
		if i % 12 == 0:
			print("   f%2d ext=%.4f gap=%+8.4f N=%7.1f mech=%s carry=%s angle=%.4f" % [
				i, leg.extension, leg.signed_gap, leg.load_force,
				str(leg.mechanically_latched), str(leg.carrying_load), core.angle])

	print("\n-- D) 东侧真实 W 泵压 --")
	await _stand_at_leg(1)
	Input.action_press("interact")
	await _frames(4)
	Input.action_release("interact")
	await _frames(10)
	var le: StabilizerRig = legs[1]
	Input.action_press("move_forward")
	for i in range(280):
		await physics_frame
		if le.mechanically_latched:
			print("  EAST LATCHED f%d ext=%.4f N=%.1f" % [i, le.extension, le.load_force])
			break
	Input.action_release("move_forward")
	await _frames(4)
	print("  both: W mech=%s N=%.1f | E mech=%s N=%.1f | limit=%.4f capturable=%s" % [
		str(legs[0].mechanically_latched), legs[0].load_force,
		str(legs[1].mechanically_latched), legs[1].load_force,
		core.capture_net_limit(), str(core.is_capturable())])

	print("\nR2_PROBE_DONE")
	quit(0)


func _radius(leg: StabilizerRig, e: float) -> float:
	var w: Vector3 = leg.to_global(Vector3(StabilizerRig.PAD_FACE_LOCAL_X + e * StabilizerRig.STROKE, 7.30, 0.0))
	var ax: Vector3 = Vector3(core.global_transform.origin.x, 0.0, core.global_transform.origin.z)
	return Vector2(w.x - ax.x, w.z - ax.z).length()


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _stand_at_leg(index: int) -> void:
	var leg: StabilizerRig = legs[index]
	var pos: Vector3 = leg.area.global_position + leg.global_transform.basis.z * 1.5
	pos.y = 0.06
	var d: Vector3 = leg.area.global_position - pos
	player.force_exit_operate()
	player.teleport(pos, atan2(-d.x, -d.z), -0.12)
	await _frames(10)
