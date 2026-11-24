class_name IsolationRig
extends Node3D

const Log := preload("res://scripts/core/log.gd")

## Emergency physical isolation of the extraction feedback loop.
## The extraction drive arrives from the wall side (+X), the core link is on the
## hall side (-X). Two interlocking dog flanges are held by a radial shear pin;
## the player pulls the pin, then pushes the sliding carriage towards the hall so
## the flanges separate into open space instead of backing into the rock wall.

signal pin_pulled()
signal separated()
signal interlock_denied()
signal message(text: String)

var core: CoreRig
var player: PlayerController
var kit: WorldKit
var carriage: Node3D
var pin_node: Node3D
var pin_handle: Node3D
var lever_node: Node3D
var area: Area3D
var status_lamp: MeshInstance3D
var status_light: OmniLight3D
var pin_out: bool = false
var separated_flag: bool = false
var active: bool = false
var progress: float = 0.0
var lever_angle: float = 0.0
var pin_anim: float = 0.0
var anchor: Transform3D
var _built: bool = false
var _time: float = 0.0
var _audio: AudioDirector
# --- V2 co-op -------------------------------------------------------------
var session: CoopSession
var damper: DamperRig
var machine_id: String = "isolation_carriage"
var active_pid: int = 0
var pending_player: PlayerController = null


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	var steel: Material = MatLib.painted_steel(Color(0.24, 0.31, 0.34))
	var dark: Material = MatLib.dark_steel()
	var bronze: Material = MatLib.bronze()
	# bed frame
	kit.box("Bed", Vector3(5.2, 0.40, 2.20), Vector3(0, 0.20, 0), dark, Vector3.ZERO, true)
	kit.box("BedTrim", Vector3(5.3, 0.10, 2.30), Vector3(0, 0.43, 0), steel, Vector3.ZERO, false)
	for sz in [-0.80, 0.80]:
		kit.box("BedRail", Vector3(5.3, 0.16, 0.10), Vector3(0, 0.55, sz), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.box("CarriageEndStop", Vector3(0.10, 0.26, 1.5), Vector3(-2.55, 0.58, 0), MatLib.dark_steel(), Vector3.ZERO, false)
	# bearing housings: extraction side (+X, wall) and sliding guide (-X, hall)
	for sx in [2.00]:
		kit.box("BearingHousing", Vector3(0.90, 1.80, 1.60), Vector3(sx, 1.15, 0), MatLib.painted_steel(Color(0.16, 0.21, 0.23)), Vector3.ZERO, true)
		kit.box("HousingCap", Vector3(1.05, 0.24, 1.75), Vector3(sx, 2.14, 0), bronze, Vector3.ZERO, false)
		kit.cylinder("Bearing", 0.62, 0.40, Vector3(sx, 1.25, 0), bronze, Vector3(0, 0, PI * 0.5), false, 24)
		for i in range(6):
			kit.box("HousingBolt", Vector3(0.08, 0.08, 0.08), Vector3(sx - 0.38 + float(i) * 0.15, 2.28, 0.68), MatLib.steel(), Vector3.ZERO, false)
	# fixed drive shaft (wall side, +X)
	kit.cylinder("FixedShaft", 0.26, 1.35, Vector3(1.02, 1.25, 0), MatLib.metal(Color(0.40, 0.42, 0.44), 0.28, 0.9, 0.4), Vector3(0, 0, PI * 0.5), false, 18)
	kit.cylinder("FixedFlange", 0.60, 0.22, Vector3(0.18, 1.25, 0), bronze, Vector3(0, 0, PI * 0.5), false, 28)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0 + PI / 8.0
		kit.box("FixedDog", Vector3(0.14, 0.18, 0.10), Vector3(0.05, 1.25 + cos(a) * 0.44, sin(a) * 0.44), bronze, Vector3(a, 0, 0), false)
	# sliding carriage (hall side, -X); slides towards the open hall
	carriage = Node3D.new()
	carriage.name = "SlidingCarriage"
	add_child(carriage)
	var ck: WorldKit = WorldKit.new(carriage)
	ck.cylinder("CarriageShaft", 0.26, 1.35, Vector3(-1.02, 1.25, 0), MatLib.metal(Color(0.40, 0.42, 0.44), 0.28, 0.9, 0.4), Vector3(0, 0, PI * 0.5), false, 18)
	ck.cylinder("CarriageFlange", 0.60, 0.22, Vector3(-0.18, 1.25, 0), bronze, Vector3(0, 0, PI * 0.5), false, 28)
	for i in range(8):
		var a2: float = TAU * float(i) / 8.0
		ck.box("CarriageDog", Vector3(0.14, 0.18, 0.10), Vector3(-0.05, 1.25 + cos(a2) * 0.44, sin(a2) * 0.44), bronze, Vector3(a2, 0, 0), false)
	ck.box("CarriageBlock", Vector3(0.90, 0.50, 0.78), Vector3(-1.20, 0.80, 0), steel, Vector3.ZERO, false)
	ck.box("BlockRib", Vector3(0.30, 0.12, 0.82), Vector3(-1.20, 1.06, 0), bronze, Vector3.ZERO, false)
	# fixed guide rails under the carriage block (on the bed, not on the carriage)
	for sz in [-0.68, 0.68]:
		kit.box("SlideRail", Vector3(2.45, 0.10, 0.14), Vector3(-1.35, 0.50, sz), dark, Vector3.ZERO, false)
		kit.box("SlideStop", Vector3(0.12, 0.18, 0.18), Vector3(-2.55, 0.56, sz), bronze, Vector3.ZERO, false)
	# safety pin: a radial shear pin through both flange lugs, pulled towards the hall
	for sx2 in [0.18, -0.18]:
		kit.box("PinLug", Vector3(0.20, 0.22, 0.24), Vector3(sx2, 1.92, 0), bronze, Vector3.ZERO, false)
	pin_node = Node3D.new()
	pin_node.name = "SafetyPin"
	pin_node.position = Vector3(0, 1.92, 0)
	add_child(pin_node)
	var pk: WorldKit = WorldKit.new(pin_node)
	pk.cylinder("PinBody", 0.055, 0.80, Vector3.ZERO, MatLib.metal(Color(0.70, 0.16, 0.10), 0.35, 0.6, 0.4), Vector3(0, 0, PI * 0.5), false, 12)
	pin_handle = Node3D.new()
	pin_handle.name = "PinHandle"
	pin_handle.position = Vector3(-0.48, 0, 0)
	pin_node.add_child(pin_handle)
	var hk: WorldKit = WorldKit.new(pin_handle)
	hk.box("PinGrip", Vector3(0.08, 0.34, 0.08), Vector3.ZERO, MatLib.emissive(Color(0.9, 0.25, 0.12), 1.0), Vector3.ZERO, false)
	hk.box("PinGripBar", Vector3(0.08, 0.08, 0.34), Vector3.ZERO, MatLib.emissive(Color(0.9, 0.25, 0.12), 1.0), Vector3.ZERO, false)
	# breaker lever on a pedestal in front of the coupling, at chest height
	kit.box("LeverBase", Vector3(0.52, 0.86, 0.52), Vector3(-0.90, 0.43, 2.05), dark, Vector3.ZERO, true)
	kit.box("LeverGuard", Vector3(0.58, 0.10, 0.58), Vector3(-0.90, 0.88, 2.05), MatLib.hazard_material(), Vector3.ZERO, false)
	lever_node = Node3D.new()
	lever_node.name = "BreakerLever"
	lever_node.position = Vector3(-0.90, 0.92, 2.05)
	add_child(lever_node)
	var lk: WorldKit = WorldKit.new(lever_node)
	lk.beam("LeverShaft", Vector3.ZERO, Vector3(0, 0.54, 0.16), 0.040, steel, false, 8)
	lk.cylinder("LeverGrip", 0.055, 0.28, Vector3(0, 0.56, 0.17), MatLib.grip(), Vector3(0, 0, PI * 0.5), false, 12)
	lk.cylinder("GripCap", 0.062, 0.03, Vector3(-0.15, 0.56, 0.17), bronze, Vector3(0, 0, PI * 0.5), false, 10)
	lk.cylinder("GripCap", 0.062, 0.03, Vector3(0.15, 0.56, 0.17), bronze, Vector3(0, 0, PI * 0.5), false, 10)
	lk.box("LeverHousing", Vector3(0.34, 0.22, 0.34), Vector3(0, -0.18, 0), MatLib.bronze(), Vector3.ZERO, false)
	lever_node.rotation.x = -0.22
	# hydraulic link from the lever base to the carriage block
	kit.pipe("LeverLink", [Vector3(-0.90, 0.62, 1.80), Vector3(-1.05, 0.62, 1.30), Vector3(-1.20, 0.72, 0.60)], 0.040, MatLib.copper(), false)
	# status column with a red/green lamp, mounted on the bed
	kit.box("StatusPost", Vector3(0.10, 1.30, 0.10), Vector3(1.90, 0.95, 1.20), dark, Vector3.ZERO, false)
	kit.box("StatusHousing", Vector3(0.30, 0.40, 0.22), Vector3(1.90, 1.66, 1.20), steel, Vector3.ZERO, false)
	status_lamp = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	sm.radial_segments = 12
	status_lamp.mesh = sm
	status_lamp.material_override = MatLib.emissive(Color(0.95, 0.2, 0.1), 2.2)
	status_lamp.position = Vector3(1.90, 1.68, 1.32)
	add_child(status_lamp)
	status_light = OmniLight3D.new()
	status_light.position = Vector3(1.90, 1.75, 1.42)
	status_light.light_color = Color(1.0, 0.25, 0.12)
	status_light.light_energy = 0.8
	status_light.omni_range = 3.0
	status_light.shadow_enabled = false
	add_child(status_light)
	# labels and a sign mounted on a bracket, not floating
	kit.label3d("采掘回路联轴器", Vector3(0, 2.62, 0.85), 0.0028, Color(0.85, 0.94, 1.0), 34)
	# interaction area in front of the rig
	area = Area3D.new()
	area.name = "IsolationArea"
	area.position = Vector3(0.2, 1.4, 2.6)
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitorable = true
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 1.05
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sph
	area.add_child(col)
	add_child(area)
	add_to_group("interactable")
	anchor = Transform3D(Basis(), to_global(Vector3(0.2, 0, 3.60)))


func setup(p_core: CoreRig, p_player: PlayerController, p_audio: AudioDirector) -> void:
	core = p_core
	_audio = p_audio
	anchor = Transform3D(Basis(), to_global(Vector3(0.2, 0, 3.60)))
	if p_player != null:
		bind_player(p_player)


## V2: the carriage is an independently claimed machine and it is interlocked
## with the extraction-loop damper. Without damping the residual vibration
## pushes the carriage back faster than one player can shove it.
func setup_coop(p_session: CoopSession, p_damper: DamperRig) -> void:
	session = p_session
	damper = p_damper
	machine_id = "isolation_carriage"
	anchor = Transform3D(Basis(), to_global(Vector3(0.2, 0, 3.60)))
	if session != null:
		if not session.local_claim_granted.is_connected(_on_grant):
			session.local_claim_granted.connect(_on_grant)
		if not session.local_claim_denied.is_connected(_on_deny):
			session.local_claim_denied.connect(_on_deny)


func bind_player(p: PlayerController) -> void:
	player = p
	if player == null:
		return
	if not player.operate_stopped.is_connected(_on_stopped):
		player.operate_stopped.connect(_on_stopped)


func get_prompt() -> String:
	if separated_flag:
		return "采掘回路已隔离"
	if core != null and not core.is_locked():
		return "安全联锁 · 先稳定并锁定核心"
	if not pin_out:
		return "E 拔出安全销"
	if active:
		return ""
	if session != null and session.is_claimed_by_other(machine_id, session.local_pid):
		return "%s 正在推滑架" % session.ledger.display_name(session.claim_owner(machine_id))
	var damped: bool = damper != null and damper.damper_effect() >= 0.35
	if not damped:
		return "E 握住隔离手柄 · 残余振动过大（先去加载回路阻尼器）"
	return "E 握住隔离手柄  ·  W 推动滑架"


func interact(p: PlayerController) -> void:
	if separated_flag or p.operating:
		return
	if core == null or not core.is_locked():
		interlock_denied.emit()
		message.emit("安全联锁：核心尚未锁定，隔离装置被机械闭锁。")
		return
	if not pin_out:
		if session != null and not session.is_authority():
			var net_c: CoopNet = _find_net()
			if net_c != null:
				net_c.submit_action("isolation_pin")
			return
		pin_out = true
		pin_anim = 0.0
		pin_pulled.emit()
		message.emit("安全销已拔出。液压滑架解锁。")
		if _audio != null:
			_audio.play_sfx("pin_pull", global_position, -4.0)
		if session != null and session.is_authority():
			session.credit(session.local_pid, "isolation_pin", 1.0, "拔出联轴器安全销")
		return
	if damper != null and damper.damper_effect() < 0.35:
		message.emit("滑架被残余振动顶住：先加载回路阻尼器，再推。")
		if _audio != null:
			_audio.play_sfx("lock_fail", global_position, -3.0)
		return
	pending_player = p
	Log.d("ISO", "client request carriage pid=%d operating=%s pending=%s" % [session.local_pid if session != null else -1, str(p.operating), str(session.is_pending_claim(machine_id) if session != null else false)])
	if session != null and not session.is_authority():
		if session.is_pending_claim(machine_id):
			return
		session.note_pending_claim(machine_id)
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_claim(machine_id)
		return
	if session != null and session.is_authority():
		var result: Dictionary = session.try_claim(machine_id, session.local_pid)
		if not bool(result.get("ok", false)):
			message.emit(str(result.get("reason", "")))
			return
	_enter_operate(p)


func _enter_operate(p: PlayerController) -> void:
	pending_player = null
	active = true
	active_pid = session.local_pid if session != null else 1
	p.enter_operate(anchor, self, 0.0, 0.8)
	p.hands.set_state("lever")
	if session != null:
		session.local_operating_machine = machine_id
	lever_engage()


func _on_grant(granted: String) -> void:
	Log.d("ISO", "grant received=%s want=%s" % [granted, machine_id])
	if granted != machine_id:
		return
	if pending_player == null or not is_instance_valid(pending_player):
		return
	_enter_operate(pending_player)


func _on_deny(denied: String, reason: String) -> void:
	Log.d("ISO", "deny received=%s reason=%s" % [denied, reason])
	if denied != machine_id:
		return
	pending_player = null
	message.emit(reason)


func _find_net() -> CoopNet:
	var hub_net: CoopNet = NetLookup.get_net()
	if hub_net != null:
		return hub_net
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("CoopNet") as CoopNet


func lever_engage() -> void:
	pass


func _on_stopped(target: Node) -> void:
	if target == self:
		active = false
		active_pid = 0
		if session != null and not separated_flag:
			if session.is_authority():
				session.release_claim(machine_id, session.local_pid)
			else:
				var net: CoopNet = _find_net()
				if net != null:
					net.submit_release(machine_id)


func _physics_process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	if pin_out and pin_anim < 1.0:
		pin_anim = minf(1.0, pin_anim + delta * 2.2)
		if pin_node != null:
			pin_node.position.x = -pin_anim * 0.46
			pin_handle.rotation.x = pin_anim * 0.9
	if session != null and not session.is_authority():
		# client: everything is a snapshot, only the lamp animation runs here
		if carriage != null:
			carriage.position.x = -progress * 1.05
		return
	var owner: int = session.claim_owner(machine_id) if session != null else 0
	var driving: bool = (active or owner != 0) and not separated_flag
	var local_axis: float = 0.0
	if active:
		local_axis = Input.get_axis("move_back", "move_forward")
	var axis: float = session.axis_for(machine_id, local_axis) if session != null else local_axis
	var damped: bool = damper != null and damper.damper_effect() >= 0.35
	if driving:
		lever_angle = move_toward(lever_angle, -axis * 0.62, delta * 3.0)
		if lever_node != null:
			lever_node.rotation.x = -0.22 + lever_angle
		if axis > 0.05:
			var rate: float = 0.34 * (0.45 + 0.55 * (1.0 if damped else 0.0))
			progress = clampf(progress + delta * rate * axis, 0.0, 1.0)
			if _audio != null:
				_audio.tick_servo(delta)
			if session != null and owner != 0 and progress > 0.25:
				session.credit(owner, "carriage_push", progress, "推动滑架分离联轴器")
		else:
			if _audio != null:
				_audio.stop_servo()
		if not damped:
			# residual vibration pushes the carriage back
			progress = maxf(0.0, progress - delta * 0.16)
		if progress >= 0.78:
			_complete_separation()
	else:
		if _audio != null:
			_audio.stop_servo()
		lever_angle = move_toward(lever_angle, 0.0, delta * 2.0)
		if lever_node != null:
			lever_node.rotation.x = -0.22 + lever_angle
	if carriage != null:
		carriage.position.x = -progress * 1.05
	if status_lamp != null:
		var blink: bool = fmod(_time * 2.2, 1.0) < 0.5
		if separated_flag:
			status_lamp.material_override = MatLib.emissive(Color(0.2, 1.0, 0.55), 2.0)
			status_light.light_color = Color(0.25, 1.0, 0.55)
			status_light.light_energy = 0.55
		else:
			status_lamp.material_override = MatLib.emissive(Color(0.95, 0.18, 0.08), 2.4 if blink else 1.1)
			status_light.light_color = Color(1.0, 0.22, 0.1)
			status_light.light_energy = 1.0 if blink else 0.4


func _complete_separation() -> void:
	if separated_flag:
		return
	separated_flag = true
	active = false
	progress = 1.0
	if player != null and player.operating:
		player.stop_operating()
	if _audio != null:
		_audio.play_sfx("separation", global_position, -2.0)
		_audio.stop_servo()
	separated.emit()


func snapshot() -> Dictionary:
	return {
		"pin": pin_out,
		"progress": progress,
		"separated": separated_flag,
		"active": active_pid,
	}


func apply_snapshot(data: Dictionary) -> void:
	pin_out = bool(data.get("pin", pin_out))
	progress = float(data.get("progress", progress))
	active_pid = int(data.get("active", active_pid))
	var was_sep: bool = separated_flag
	separated_flag = bool(data.get("separated", separated_flag))
	if carriage != null:
		carriage.position.x = -progress * 1.05
	if pin_node != null:
		pin_node.position.x = -0.46 if pin_out else 0.0
	if status_lamp != null:
		status_lamp.material_override = MatLib.emissive(Color(0.2, 1.0, 0.55) if separated_flag else Color(0.95, 0.2, 0.1), 2.0)
	if separated_flag and not was_sep:
		separated.emit()


func reset_state() -> void:
	pin_out = false
	separated_flag = false
	active = false
	progress = 0.0
	lever_angle = 0.0
	pin_anim = 0.0
	if carriage != null:
		carriage.position.x = 0.0
	if pin_node != null:
		pin_node.position.x = 0.0
	if pin_handle != null:
		pin_handle.rotation = Vector3.ZERO
	if lever_node != null:
		lever_node.rotation.x = -0.22
	if status_lamp != null:
		status_lamp.material_override = MatLib.emissive(Color(0.95, 0.2, 0.1), 2.2)
	if _audio != null:
		_audio.stop_servo()


func force_separated_state() -> void:
	pin_out = true
	pin_anim = 1.0
	separated_flag = true
	active = false
	progress = 1.0
	if carriage != null:
		carriage.position.x = -1.05
	if pin_node != null:
		pin_node.position.x = -0.46
	if pin_handle != null:
		pin_handle.rotation.x = 0.9
	if status_lamp != null:
		status_lamp.material_override = MatLib.emissive(Color(0.2, 1.0, 0.55), 2.0)
	if status_light != null:
		status_light.light_color = Color(0.25, 1.0, 0.55)
		status_light.light_energy = 0.55
	if _audio != null:
		_audio.stop_servo()









