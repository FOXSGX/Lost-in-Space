class_name DamperRig
extends Node3D

## Extraction-loop damper ("回路阻尼器"). The extraction coupling keeps feeding
## residual vibration back into the core; this flywheel damper has to be loaded
## before the sliding carriage can be pushed apart. Two players can split the job
## (one holds the damper, one pushes the carriage); a solo player loads it and
## drops the pawl first, which costs time but leaves the carriage free.

signal latched(pid: int)
signal pressure_changed(value: float)

const BUILD_RATE := 0.30
const BLEED_RATE := 0.10
const LATCH_AT := 0.95

var session: CoopSession
var machine_id: String = "damper"
var pressure: float = 0.0
var latched_flag: bool = false
var active: bool = false
var active_pid: int = 0
var pending_player: PlayerController = null
var pending_mode: bool = false
var anchor: Transform3D
var area: Area3D
var wheel: Node3D
var flywheel: Node3D
var needle: Node3D
var status_lamp: MeshInstance3D
var kit: WorldKit
var audio: AudioDirector
var _wheel_angle: float = 0.0
var _hold_time: float = 0.0
var _time: float = 0.0
var _built: bool = false


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	var dark: Material = MatLib.dark_steel()
	var steel: Material = MatLib.painted_steel(Color(0.23, 0.30, 0.32))
	var bronze: Material = MatLib.bronze()
	kit.box("Base", Vector3(2.6, 0.28, 1.8), Vector3(0, 0.14, 0), dark, Vector3.ZERO, true)
	kit.box("BaseTrim", Vector3(2.7, 0.06, 1.9), Vector3(0, 0.31, 0), MatLib.hazard_material(), Vector3.ZERO, false)
	for sx in [-0.95, 0.95]:
		kit.box("Cheek", Vector3(0.24, 1.55, 1.30), Vector3(sx, 1.05, 0), steel, Vector3.ZERO, true)
		kit.box("CheekCap", Vector3(0.34, 0.16, 1.4), Vector3(sx, 1.86, 0), bronze, Vector3.ZERO, false)
		kit.cylinder("Bearing", 0.16, 0.20, Vector3(sx, 1.30, 0), bronze, Vector3(0, 0, PI * 0.5), false, 16)
	flywheel = Node3D.new()
	flywheel.name = "Flywheel"
	flywheel.position = Vector3(0, 1.30, 0)
	add_child(flywheel)
	var fk: WorldKit = WorldKit.new(flywheel)
	fk.cylinder("WheelDisc", 0.72, 0.34, Vector3.ZERO, MatLib.metal(Color(0.34, 0.36, 0.38), 0.28, 0.9, 0.35), Vector3(0, 0, PI * 0.5), false, 28)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		fk.box("WheelSpoke", Vector3(0.10, 0.06, 1.24), Vector3.ZERO, MatLib.painted_steel(Color(0.46, 0.30, 0.12)), Vector3(a, 0, 0), false)
	fk.ring_box("WheelRim", 0.74, 0.08, 0.36, Vector3.ZERO, bronze, Basis(Vector3.UP, PI * 0.5), 32, false)
	fk.cylinder("WheelHub", 0.14, 0.42, Vector3.ZERO, MatLib.steel(), Vector3(0, 0, PI * 0.5), false, 14)
	# The flywheel is a large moving part, so it needs a solid guard volume: the
	# player must not be able to walk through the spinning disc. Collision only,
	# the visible disc/rim is built above.
	var wheel_body: StaticBody3D = StaticBody3D.new()
	wheel_body.name = "FlywheelGuard"
	wheel_body.collision_layer = 1
	wheel_body.collision_mask = 0
	add_child(wheel_body)
	var wheel_shape: CylinderShape3D = CylinderShape3D.new()
	wheel_shape.radius = 0.76
	wheel_shape.height = 0.40
	var wheel_col: CollisionShape3D = CollisionShape3D.new()
	wheel_col.name = "FlywheelShape"
	wheel_col.shape = wheel_shape
	wheel_col.position = Vector3(0, 1.30, 0)
	wheel_col.rotation.z = PI * 0.5
	wheel_body.add_child(wheel_col)
	# crank on the +Z side
	wheel = Node3D.new()
	wheel.name = "Crank"
	wheel.position = Vector3(0, 1.30, 0.62)
	add_child(wheel)
	var wk: WorldKit = WorldKit.new(wheel)
	wk.beam("CrankArm", Vector3.ZERO, Vector3(0, 0.42, 0.16), 0.038, MatLib.steel(), false, 8)
	wk.cylinder("CrankGrip", 0.05, 0.28, Vector3(0, 0.44, 0.20), MatLib.grip(), Vector3(0, 0, PI * 0.5), false, 10)
	# pressure gauge and pawl
	kit.cylinder("GaugeBack", 0.18, 0.08, Vector3(0.85, 2.10, 0.20), dark, Vector3(PI * 0.5, 0, 0), false, 20)
	kit.ring_box("GaugeBezel", 0.185, 0.04, 0.05, Vector3(0.85, 2.10, 0.26), bronze, Basis(Vector3.RIGHT, PI * 0.5), 24, false)
	needle = Node3D.new()
	needle.position = Vector3(0.85, 2.10, 0.31)
	add_child(needle)
	var nk: WorldKit = WorldKit.new(needle)
	nk.box("NeedleBar", Vector3(0.02, 0.14, 0.012), Vector3(0, 0.06, 0), MatLib.emissive(Color(1.0, 0.72, 0.2), 1.8), Vector3.ZERO, false)
	kit.label3d("回路阻尼", Vector3(0.85, 2.36, 0.10), 0.0018, Color(0.86, 0.95, 1.0), 22)
	kit.box("PawlHousing", Vector3(0.30, 0.36, 0.30), Vector3(-0.98, 1.62, 0.20), dark, Vector3.ZERO, false)
	kit.beam("Pawl", Vector3(-0.98, 1.62, 0.20), Vector3(-0.72, 1.50, 0.20), 0.045, bronze, false, 6)
	kit.pipe("DamperLine", [Vector3(-1.25, 0.55, 0.30), Vector3(-1.9, 0.55, 0.10), Vector3(-2.6, 0.40, -0.6)], 0.055, MatLib.copper(), false)
	status_lamp = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	sm.radial_segments = 12
	status_lamp.mesh = sm
	status_lamp.material_override = MatLib.emissive(Color(1.0, 0.45, 0.10), 1.4)
	status_lamp.position = Vector3(0.95, 2.50, -0.10)
	add_child(status_lamp)
	kit.omni(Vector3(0, 1.9, 1.2), Color(1.0, 0.66, 0.32), 1.1, 4.2, false, "DamperLamp")
	kit.label3d("回注振动抑制 · W 加载", Vector3(0, 0.42, 1.18), 0.0018, Color(0.88, 0.92, 0.85), 24)
	area = Area3D.new()
	area.name = "DamperArea"
	area.position = Vector3(0, 1.30, 1.55)
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitorable = true
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 0.95
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sph
	area.add_child(col)
	add_child(area)
	add_to_group("interactable")
	anchor = Transform3D(Basis(Vector3.UP, 0.0), to_global(Vector3(0, 0, 1.75)))


func setup(p_session: CoopSession, p_audio: AudioDirector) -> void:
	session = p_session
	audio = p_audio
	anchor = Transform3D(Basis(Vector3.UP, 0.0), to_global(Vector3(0, 0, 1.75)))
	if session != null:
		if not session.local_claim_granted.is_connected(_on_grant):
			session.local_claim_granted.connect(_on_grant)
		if not session.local_claim_denied.is_connected(_on_deny):
			session.local_claim_denied.connect(_on_deny)


func bind_player(p: PlayerController) -> void:
	if p == null:
		return
	if not p.operate_stopped.is_connected(_on_stopped):
		p.operate_stopped.connect(_on_stopped)


func get_prompt() -> String:
	if latched_flag:
		return "回路阻尼器已加载锁止 · 可以推动隔离滑架"
	if active:
		return ""
	if session != null and session.is_claimed_by_other(machine_id, session.local_pid):
		return "%s 正在加载阻尼器" % session.ledger.display_name(session.claim_owner(machine_id))
	return "E 加载回路阻尼器 · W 提高阻尼（另一人可同时推滑架）"


func interact(p: PlayerController) -> void:
	if p.operating or session == null or latched_flag:
		return
	pending_player = p
	if session.is_authority():
		var result: Dictionary = session.try_claim(machine_id, session.local_pid)
		if bool(result.get("ok", false)):
			_enter(p)
		else:
			_toast(str(result.get("reason", "")))
	else:
		if session.is_pending_claim(machine_id):
			return
		session.note_pending_claim(machine_id)
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_claim(machine_id)
		else:
			session.deny_local_claim(machine_id, "未连接主机")


func _enter(p: PlayerController) -> void:
	active = true
	active_pid = session.local_pid
	pending_player = null
	bind_player(p)
	p.enter_operate(anchor, self, 0.0, 0.95)
	p.hands.set_state("lever")
	if session != null:
		session.local_operating_machine = machine_id
	if audio != null:
		audio.play_sfx("lever_click", global_position, -6.0)


func _on_grant(machine_id_granted: String) -> void:
	if machine_id_granted != machine_id:
		return
	if pending_player == null or not is_instance_valid(pending_player):
		return
	_enter(pending_player)


func _on_deny(machine_id_denied: String, reason: String) -> void:
	if machine_id_denied != machine_id:
		return
	pending_player = null
	_toast(reason)


func _toast(text: String, seconds: float = 2.0) -> void:
	if text == "":
		return
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var hud: GameHud = root.get_node_or_null("Hud") as GameHud
	if hud != null:
		hud.toast(text, seconds)


func _find_net() -> CoopNet:
	var hub_net: CoopNet = NetLookup.get_net()
	if hub_net != null:
		return hub_net
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("CoopNet") as CoopNet


func _on_stopped(target: Node) -> void:
	if target != self or not active:
		return
	active = false
	active_pid = 0
	if session == null:
		return
	if session.is_authority():
		session.release_claim(machine_id, session.local_pid)
	else:
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_release(machine_id)


func _physics_process(delta: float) -> void:
	if not _built or session == null:
		return
	_time += delta
	if not session.is_authority():
		_apply_visuals()
		return
	var local_axis: float = 0.0
	if active and active_pid == session.local_pid:
		local_axis = Input.get_axis("move_back", "move_forward")
	var axis: float = maxf(0.0, session.axis_for(machine_id, local_axis))
	var owner: int = session.claim_owner(machine_id)
	if not latched_flag:
		if axis > 0.05 and owner != 0:
			pressure = clampf(pressure + axis * BUILD_RATE * delta * 2.6, 0.0, 1.0)
			_wheel_angle += axis * delta * 6.0
			_hold_time = 0.0 if pressure < 0.3 else _hold_time + delta
			if _hold_time > 1.4:
				session.credit(owner, "damper_hold", _hold_time, "持续压住回路阻尼器")
			if audio != null:
				audio.tick_servo(delta)
		else:
			pressure = maxf(0.0, pressure - BLEED_RATE * delta)
			_hold_time = 0.0
			if audio != null:
				audio.stop_servo()
		if pressure >= LATCH_AT and not latched_flag:
			latched_flag = true
			session.credit(owner, "damper_latch", 1.0, "锁定采掘回路阻尼器")
			latched.emit(owner)
			if audio != null:
				audio.play_sfx("latch", global_position, -3.0)
				audio.stop_servo()
			_toast("阻尼器已加载并锁止", 2.0)
			if active and is_instance_valid(pending_player):
				pass
	_apply_pose()
	_apply_visuals()
	pressure_changed.emit(pressure)


func damper_effect() -> float:
	if latched_flag:
		return 1.0
	return pressure


func _apply_pose() -> void:
	if flywheel != null:
		flywheel.rotation.z = _wheel_angle
	if wheel != null:
		wheel.rotation.z = _wheel_angle * 1.8
	if needle != null:
		needle.rotation.z = lerpf(0.95, -0.95, pressure)


func _apply_visuals() -> void:
	if status_lamp == null:
		return
	var col: Color = Color(1.0, 0.45, 0.10)
	if latched_flag:
		col = Color(0.18, 1.0, 0.55)
	status_lamp.material_override = MatLib.emissive(col, 2.2 if latched_flag else 1.2 + pressure)


func reset_state() -> void:
	pressure = 0.0
	latched_flag = false
	active = false
	active_pid = 0
	_wheel_angle = 0.0
	_hold_time = 0.0
	_apply_pose()


func snapshot() -> Dictionary:
	return {"press": pressure, "latched": latched_flag, "active": active_pid}


func apply_snapshot(data: Dictionary) -> void:
	pressure = float(data.get("press", pressure))
	latched_flag = bool(data.get("latched", latched_flag))
	active_pid = int(data.get("active", active_pid))
	_apply_pose()
	_apply_visuals()
