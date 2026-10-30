extends SceneTree

# Fast bench for tuning the winch loop. Unlike probe_rig.gd it teleports the
# player instead of walking, so it can be run dozens of times while tuning
# constants. It still goes through the same public API: attach_cable(),
# set_winch_input(), try_install_lock().

var app: Node3D
var rig: Node3D
var player: CharacterBody3D
var machine: Node3D
var rail: Node3D
var sheave: Node3D

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	app = (load("res://resonance_03.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(10)
	rig = app.get("rig") as Node3D
	player = app.get("player") as CharacterBody3D
	machine = app.get("machine") as Node3D
	rail = app.get("rail_body") as Node3D
	sheave = (app.get("winch_station") as Node3D).get_node("Sheave") as Node3D
	if rig == null or player == null or machine == null or rail == null or sheave == null:
		print("BENCH_FAILED missing node")
		quit(1)
		return

	print("BENCH_GEOM start_distance=%.3f" % _distance("eye_far"))
	_report_arm("eye_far")
	_report_arm("eye_mid")

	await drive("eye_far")
	await frames(90)
	await drive("eye_mid")

	current_scene = null
	app.queue_free()
	await frames(3)
	quit(0)

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func _anchor(id: String) -> Node3D:
	return rig.call("find_anchor", id) as Node3D

func _distance(id: String) -> float:
	var anchor: Node3D = _anchor(id)
	return (anchor.call("attach_point") as Vector3).distance_to(sheave.global_position)

func _report_arm(id: String) -> void:
	var anchor: Node3D = _anchor(id)
	var local: Vector3 = rail.to_local(anchor.call("attach_point") as Vector3)
	var arm: float = float(rail.call("cable_moment_arm", local, sheave.global_position))
	var max_force: float = float(machine.get("max_force"))
	var torque: float = arm * max_force * 1.05
	print("BENCH_ARM %s arm=%.3f max_torque=%.0f dist=%.3f" % [id, arm, torque, _distance(id)])

func drive(id: String) -> void:
	rig.call("reset_mission")
	await frames(5)
	var anchor: Node3D = _anchor(id)
	var at: Vector3 = anchor.call("attach_point") as Vector3
	player.global_position = at + Vector3(0.0, 0.0, 1.4)
	await frames(2)
	var attached: Dictionary = rig.call("attach_cable", id) as Dictionary
	await frames(2)
	var w: Dictionary = rig.call("tension_state") as Dictionary
	print("BENCH_ATTACH %s ok=%s length=%.2f dist=%.2f tension=%.0f" % [id, str(attached.get("ok")), float(w.get("free_length", 0.0)), _distance(id), float(w.get("tension", 0.0))])

	var console: Vector3 = (app.get("winch_station") as Node3D).global_position
	player.global_position = console + Vector3(0.0, 0.0, 1.6)
	app.set("at_console", true)
	await frames(2)

	Input.action_press("winch_haul")
	var broke: bool = false
	var min_angle: float = 15.0
	for i: int in range(600):
		await physics_frame
		var info: Dictionary = rig.call("alignment_state") as Dictionary
		min_angle = minf(min_angle, float(info.get("angle_deg", 15.0)))
		if not bool(info.get("jammed", true)):
			broke = true
		if i % 30 == 0:
			_show("%s haul t=%.2f" % [id, float(i) / 60.0], info)
		if broke and float(info.get("angle_deg", 15.0)) <= 2.0:
			break
	Input.action_release("winch_haul")
	await frames(120)
	var held: Dictionary = rig.call("alignment_state") as Dictionary
	_show("%s released_near_zero" % id, held)
	print("BENCH_HOLD %s angle=%.2f settled=%s lockable=%s" % [id, float(held.get("angle_deg", 0.0)), str(held.get("settled")), str(held.get("lockable"))])

	# Keep hauling past the bracket to reproduce the overshoot.
	Input.action_press("winch_haul")
	for i: int in range(300):
		await physics_frame
		var info: Dictionary = rig.call("alignment_state") as Dictionary
		if i % 30 == 0:
			_show("%s overshoot t=%.2f" % [id, float(i) / 60.0], info)
		if float(info.get("angle_deg", 0.0)) <= -1.5:
			break
	Input.action_release("winch_haul")
	await frames(2)
	var after: Dictionary = rig.call("alignment_state") as Dictionary
	print("BENCH_RESULT %s broke=%s min_angle=%.2f after=%.2f" % [id, str(broke), min_angle, float(after.get("angle_deg", 0.0))])

	# Recover: pay out until the cable goes slack, let the sag swing the rail
	# back, then catch it with a short haul before it reaches the start angle.
	Input.action_press("winch_payout")
	for _i: int in range(30):
		await physics_frame
		if float((rig.call("tension_state") as Dictionary).get("tension", 0.0)) <= 5.0:
			break
	Input.action_release("winch_payout")
	var caught: bool = false
	for _i: int in range(240):
		await physics_frame
		var angle: float = float((rig.call("alignment_state") as Dictionary).get("angle_deg", 0.0))
		if angle >= -0.4:
			caught = true
			break
	if caught:
		Input.action_press("winch_haul")
		await frames(8)
		Input.action_release("winch_haul")
	await frames(180)
	var settled: Dictionary = rig.call("alignment_state") as Dictionary
	print("BENCH_RECOVER %s angle=%.2f settled=%s lockable=%s caught=%s" % [id, float(settled.get("angle_deg", 0.0)), str(settled.get("settled")), str(settled.get("lockable")), str(caught)])
	var lock: Dictionary = rig.call("try_install_lock") as Dictionary
	print("BENCH_LOCK %s ok=%s reason=%s" % [id, str(lock.get("ok")), str(lock.get("reason"))])

func _show(tag: String, info: Dictionary) -> void:
	var w: Dictionary = rig.call("tension_state") as Dictionary
	print("BENCH_TRACE %s angle=%.2f jam=%s tension=%.0f length=%.2f mode=%s stalled=%s" % [
		tag,
		float(info.get("angle_deg", 0.0)),
		str(info.get("jammed")),
		float(w.get("tension", 0.0)),
		float(w.get("free_length", 0.0)),
		str(w.get("mode")),
		str(w.get("stalled")),
	])
