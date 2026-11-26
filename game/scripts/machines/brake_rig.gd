class_name BrakeRig
extends Node3D

## Emergency resonance brake ("应急制动"). Two floor pumps feed a pressure
## accumulator; once the pressure passes the pawl threshold the crank latches and
## the brake band stays applied without anyone standing there. Pressure bleeds
## when nobody pumps, and a latched brake cuts the severity of the next resonance
## recoil. Two pumps sit side by side so two players can charge it in half the
## time - but either pump also works alone.

signal pressure_changed(value: float, latched: bool)
signal brake_latched(pid: int)

const BUILD_RATE := 0.22
const BLEED_RATE := 0.075
const LATCH_PRESSURE := 0.96

var session: CoopSession
var core: CoreRig
var machine_id: String = "brake"
var assist_machine_id: String = "brake_assist"
var pressure: float = 0.0
var latched: bool = false
var local_machine_id: String = ""
var active_pid: int = 0
var assist_pid: int = 0
var active: bool = false
var pending_player: PlayerController = null
var player: PlayerController
var anchor: Transform3D
var assist_anchor: Transform3D
var area: Area3D
var assist_area: Area3D
var kit: WorldKit
var wheel_left: Node3D
var wheel_right: Node3D
var band_node: Node3D
var needle: Node3D
var status_lamp: MeshInstance3D
var label: Label3D
var audio: AudioDirector
var _built: bool = false
var _time: float = 0.0
var _wheel_angle: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	var dark: Material = MatLib.dark_steel()
	var steel: Material = MatLib.painted_steel(Color(0.25, 0.31, 0.33))
	var bronze: Material = MatLib.bronze()
	# frame
	kit.box("Bed", Vector3(3.4, 0.30, 2.0), Vector3(0, 0.15, 0), dark, Vector3.ZERO, true)
	kit.box("BedTrim", Vector3(3.5, 0.07, 2.1), Vector3(0, 0.32, 0), MatLib.hazard_material(), Vector3.ZERO, false)
	# brake drum on the core-facing (-Z) half of the bed
	kit.cylinder("DrumHousing", 0.95, 1.10, Vector3(0, 1.15, -0.35), steel, Vector3(PI * 0.5, 0, 0), true, 28)
	kit.cylinder("DrumFace", 0.72, 1.16, Vector3(0, 1.15, -0.35), MatLib.metal(Color(0.36, 0.38, 0.40), 0.30, 0.9, 0.35), Vector3(PI * 0.5, 0, 0), false, 24)
	kit.ring_box("DrumRim", 0.96, 0.10, 0.16, Vector3(0, 1.15, -0.86), bronze, Basis(Vector3.RIGHT, PI * 0.5), 40, false)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		kit.box("DrumBolt", Vector3(0.09, 0.09, 0.05), Vector3(cos(a) * 0.60, 1.15 + sin(a) * 0.60, -0.95), MatLib.steel(), Vector3.ZERO, false)
	# brake band that tightens when the brake is applied
	band_node = Node3D.new()
	band_node.name = "BrakeBand"
	band_node.position = Vector3(0, 1.15, -0.35)
	add_child(band_node)
	var bk: WorldKit = WorldKit.new(band_node)
	bk.ring_box("Band", 1.02, 0.16, 0.22, Vector3.ZERO, MatLib.painted_steel(Color(0.45, 0.20, 0.10)), Basis(Vector3.RIGHT, PI * 0.5), 40, false)
	bk.box("BandLug", Vector3(0.30, 0.24, 0.30), Vector3(0, 1.02, 0), bronze, Vector3.ZERO, false)
	bk.beam("BandArm", Vector3(0, 1.02, 0), Vector3(0, 1.55, 0.55), 0.055, MatLib.steel(), false, 8)
	# accumulator bottles behind the drum
	for sx in [-0.95, 0.95]:
		kit.cylinder("Accumulator", 0.28, 1.55, Vector3(sx, 0.95, 0.55), MatLib.painted_steel(Color(0.20, 0.34, 0.30)), Vector3.ZERO, true, 18)
		kit.cylinder("AccumulatorCap", 0.16, 0.20, Vector3(sx, 1.80, 0.55), bronze, Vector3.ZERO, false, 12)
		kit.pipe("AccumulatorHose", [Vector3(sx, 1.68, 0.55), Vector3(sx * 0.7, 1.30, 0.30), Vector3(sx * 0.4, 1.15, -0.10)], 0.045, MatLib.copper(), false)
	# gauge + status
	kit.cylinder("GaugeBack", 0.20, 0.08, Vector3(0, 1.98, 0.30), dark, Vector3(PI * 0.5, 0, 0), false, 20)
	kit.ring_box("GaugeBezel", 0.205, 0.045, 0.055, Vector3(0, 1.98, 0.36), bronze, Basis(Vector3.RIGHT, PI * 0.5), 24, false)
	needle = Node3D.new()
	needle.name = "Needle"
	needle.position = Vector3(0, 1.98, 0.41)
	add_child(needle)
	var nk: WorldKit = WorldKit.new(needle)
	nk.box("NeedleBar", Vector3(0.022, 0.16, 0.012), Vector3(0, 0.07, 0), MatLib.emissive(Color(1.0, 0.72, 0.2), 1.8), Vector3.ZERO, false)
	kit.label3d("制动蓄压", Vector3(0, 2.26, 0.32), 0.0018, Color(0.85, 0.95, 1.0), 24)
	# pump stations left and right
	for side in [-1.0, 1.0]:
		var px: float = side * 1.32
		kit.box("PumpPedestal", Vector3(0.62, 0.92, 0.62), Vector3(px, 0.46, 1.20), MatLib.metal(Color(0.19, 0.23, 0.24), 0.42, 0.72, 0.55), Vector3.ZERO, true)
		kit.box("PumpTop", Vector3(0.68, 0.07, 0.68), Vector3(px, 0.95, 1.20), steel, Vector3.ZERO, false)
		var wheel: Node3D = Node3D.new()
		wheel.name = "Crank"
		wheel.position = Vector3(px, 1.10, 1.28)
		add_child(wheel)
		var wk: WorldKit = WorldKit.new(wheel)
		wk.torus("WheelRim", 0.28, 0.035, Vector3.ZERO, MatLib.steel(), Basis(Vector3.RIGHT, PI * 0.5), 24, 6)
		for i in range(4):
			var a2: float = TAU * float(i) / 4.0
			wk.beam("Spoke", Vector3.ZERO, Vector3(cos(a2) * 0.27, sin(a2) * 0.27, 0), 0.022, MatLib.steel(), false, 6)
		wk.cylinder("WheelHub", 0.075, 0.16, Vector3.ZERO, bronze, Vector3(PI * 0.5, 0, 0), false, 12)
		wk.cylinder("CrankHandle", 0.045, 0.26, Vector3(0, 0.24, 0.14), MatLib.grip(), Vector3(0, 0, PI * 0.5), false, 10)
		kit.pipe("PumpLine", [Vector3(px, 0.98, 1.20), Vector3(px * 0.8, 0.80, 0.80), Vector3(px * 0.5, 0.60, 0.30)], 0.05, MatLib.copper(), false)
		if side < 0.0:
			wheel_left = wheel
		else:
			wheel_right = wheel
	# status lamp on a post
	kit.box("LampPost", Vector3(0.09, 1.9, 0.09), Vector3(1.55, 0.95, -0.75), dark, Vector3.ZERO, false)
	status_lamp = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	sm.radial_segments = 12
	status_lamp.mesh = sm
	status_lamp.material_override = MatLib.emissive(Color(1.0, 0.42, 0.10), 1.6)
	status_lamp.position = Vector3(1.55, 1.95, -0.75)
	add_child(status_lamp)
	kit.omni(Vector3(0, 1.9, 1.9), Color(1.0, 0.62, 0.30), 1.0, 4.2, false, "BrakeLamp")
	label = kit.label3d("应急制动 · 共振抑制", Vector3(0, 0.42, 1.58), 0.0020, Color(0.95, 0.85, 0.75), 26)
	# interaction areas: left pump (main), right pump (assist)
	area = _make_area(Vector3(-1.32, 1.30, 2.15), 0.92)
	assist_area = _make_area(Vector3(1.32, 1.30, 2.15), 0.92)
	assist_area.name = "BrakeAssistArea"
	add_to_group("interactable")
	anchor = Transform3D(Basis(Vector3.UP, rig_yaw()), to_global(Vector3(-1.32, 0, 2.30)))
	assist_anchor = Transform3D(Basis(Vector3.UP, rig_yaw()), to_global(Vector3(1.32, 0, 2.30)))


func _make_area(pos: Vector3, radius: float) -> Area3D:
	var a: Area3D = Area3D.new()
	a.name = "BrakeArea"
	a.position = pos
	a.collision_layer = 8
	a.collision_mask = 0
	a.monitorable = true
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = radius
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sph
	a.add_child(col)
	add_child(a)
	return a


func rig_yaw() -> float:
	return rotation.y


func setup(p_core: CoreRig, p_session: CoopSession, p_audio: AudioDirector) -> void:
	core = p_core
	session = p_session
	audio = p_audio
	anchor = Transform3D(Basis(Vector3.UP, rig_yaw()), to_global(Vector3(-1.32, 0, 2.30)))
	assist_anchor = Transform3D(Basis(Vector3.UP, rig_yaw()), to_global(Vector3(1.32, 0, 2.30)))
	if session != null:
		if not session.local_claim_granted.is_connected(_on_local_grant):
			session.local_claim_granted.connect(_on_local_grant)
		if not session.local_claim_denied.is_connected(_on_local_deny):
			session.local_claim_denied.connect(_on_local_deny)


func bind_player(p: PlayerController) -> void:
	player = p
	if player == null:
		return
	if not player.operate_stopped.is_connected(_on_player_stopped):
		player.operate_stopped.connect(_on_player_stopped)


func get_prompt() -> String:
	if latched:
		return "应急制动已蓄压锁止 · 下一次反冲将被削弱"
	if active:
		return ""
	if session != null and session.claim_owner(machine_id) not in [0, session.local_pid]:
		return "%s 正在给制动蓄压" % session.ledger.display_name(session.claim_owner(machine_id))
	if session != null and session.claim_owner(assist_machine_id) not in [0, session.local_pid]:
		return "另一台泵已占用 · 按 E 使用空闲泵"
	return "E 操作应急制动 · W 蓄压（可双人同时泵压）"


func interact(p: PlayerController) -> void:
	if p.operating or session == null or latched:
		return
	var local_free: bool = not session.is_claimed_by_other(machine_id, session.local_pid)
	var assist_free: bool = not session.is_claimed_by_other(assist_machine_id, session.local_pid)
	if not local_free and not assist_free:
		_toast("两台制动泵都被占用")
		return
	var target_id: String = machine_id if local_free else assist_machine_id
	var target_anchor: Transform3D = anchor if local_free else assist_anchor
	pending_player = p
	pending_machine = target_id
	if session.is_authority():
		var result: Dictionary = session.try_claim(target_id, session.local_pid)
		if bool(result.get("ok", false)):
			_enter(p, session.local_pid, target_id, target_anchor)
		else:
			_toast(str(result.get("reason", "")))
	else:
		if session.is_pending_claim(target_id):
			return
		session.note_pending_claim(target_id)
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_claim(target_id)
		else:
			session.deny_local_claim(target_id, "未连接主机")


var pending_machine: String = ""


func _enter(p: PlayerController, pid: int, target_id: String, target_anchor: Transform3D) -> void:
	active = true
	active_pid = pid
	local_machine_id = target_id
	pending_player = null
	bind_player(p)
	p.enter_operate(target_anchor, self, rig_yaw(), 0.95)
	p.hands.set_state("lever")
	if session != null:
		session.local_operating_machine = target_id
	if audio != null:
		audio.play_sfx("lever_click", global_position + Vector3(0, 1, 0), -6.0)


func _on_local_grant(granted_id: String) -> void:
	if granted_id != machine_id and granted_id != assist_machine_id:
		return
	if pending_player == null or not is_instance_valid(pending_player):
		return
	var anchor_use: Transform3D = anchor if granted_id == machine_id else assist_anchor
	_enter(pending_player, session.local_pid, granted_id, anchor_use)


func _on_local_deny(denied_id: String, reason: String) -> void:
	if denied_id != machine_id and denied_id != assist_machine_id:
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


func _on_player_stopped(target: Node) -> void:
	if target != self or not active:
		return
	active = false
	if session != null and local_machine_id != "":
		var held: String = local_machine_id
		if session.is_authority():
			session.release_claim(held, session.local_pid)
		else:
			var net: CoopNet = _find_net()
			if net != null:
				net.submit_release(held)
	local_machine_id = ""
	active_pid = 0


func _physics_process(delta: float) -> void:
	if not _built or session == null:
		return
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	if not session.is_authority():
		_apply_visuals(delta)
		return
	var local_axis: float = 0.0
	if active and active_pid == session.local_pid:
		local_axis = Input.get_axis("move_back", "move_forward")
	var axis_main: float = session.axis_for(machine_id, local_axis)
	var axis_assist: float = session.axis_for(assist_machine_id, local_axis)
	var pumping: float = maxf(0.0, axis_main) + maxf(0.0, axis_assist)
	if pumping > 0.05 and not latched:
		pressure = clampf(pressure + pumping * BUILD_RATE * delta * 3.2, 0.0, 1.0)
		_wheel_angle += pumping * delta * 5.5
	else:
		pressure = maxf(0.0, pressure - BLEED_RATE * delta)
	if pressure >= LATCH_PRESSURE and not latched:
		_latch()
	_apply_pose()
	_apply_visuals(delta)
	pressure_changed.emit(pressure, latched)


func _latch() -> void:
	latched = true
	pressure = 1.0
	var pid: int = session.claim_owner(machine_id)
	if pid == 0:
		pid = session.claim_owner(assist_machine_id)
	if pid == 0:
		pid = active_pid if active_pid != 0 else session.local_pid
	session.credit(pid, "brake_charge", 1.0, "应急制动蓄压锁止")
	brake_latched.emit(pid)
	if audio != null:
		audio.play_sfx("latch", global_position + Vector3(0, 1.5, 0), -3.0)


## Called by the surge director when the warning starts or a pump is used during
## the warning: only a real pressure delta counts.
func credit_response(pid: int, delta_pressure: float) -> void:
	if delta_pressure > 0.02:
		session.credit(pid, "surge_response", 1.0, "反冲预兆中给制动蓄压")


func on_surge(strength: float) -> void:
	_flash = strength


func _apply_pose() -> void:
	if needle != null:
		needle.rotation.z = lerpf(0.95, -0.95, pressure)
	if band_node != null:
		band_node.scale = Vector3(1.0, 1.0, 1.0)
	if wheel_left != null:
		wheel_left.rotation.z = _wheel_angle
	if wheel_right != null:
		wheel_right.rotation.z = _wheel_angle * 0.92


func _apply_visuals(delta: float) -> void:
	if status_lamp == null:
		return
	var col: Color = Color(1.0, 0.42, 0.10)
	if latched:
		col = Color(0.18, 1.0, 0.55)
	elif _flash > 0.0:
		col = Color(1.0, 0.12, 0.06)
	status_lamp.material_override = MatLib.emissive(col, 2.4 if latched else 1.2 + pressure)
	if band_node != null:
		band_node.rotation.z = lerpf(0.0, 0.03, pressure)


func reset_state() -> void:
	pressure = 0.0
	latched = false
	active = false
	active_pid = 0
	assist_pid = 0
	_wheel_angle = 0.0
	_apply_pose()
	if core != null:
		core.set_brake_state(0.0)


func brake_effect() -> float:
	# 0..1 mitigation strength used by the surge director
	return 1.0 if latched else clampf(pressure, 0.0, 1.0)


func snapshot() -> Dictionary:
	return {"press": pressure, "latched": latched, "active": active_pid, "assist": assist_pid}


func apply_snapshot(data: Dictionary) -> void:
	pressure = float(data.get("press", pressure))
	latched = bool(data.get("latched", latched))
	active_pid = int(data.get("active", active_pid))
	assist_pid = int(data.get("assist", assist_pid))
	_apply_pose()
