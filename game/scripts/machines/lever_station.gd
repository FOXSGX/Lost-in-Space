class_name LeverStation
extends Node3D

## Hydraulic counterweight control station. The player physically grabs the
## lever; W/S tilt it, the linked cart accelerates with inertia, and releasing it
## lets the cart coast to a stop. Nothing here writes a "balanced" flag.
##
## Proportions are set for a standing operator: the lever grip sits at chest
## height, the dial is a small instrument on the left, and the cart runs on the
## track 5 m ahead, so the console never hides the machine it controls.

signal cart_moved(p: float)
signal lever_engaged()
signal lever_released()

var core: CoreRig
var cart: WeightCart
var player: PlayerController
var side_name: String = "左"
var side_sign: float = -1.0
var station_yaw: float = 0.0
var anchor: Transform3D
var lever_angle: float = 0.0
var active: bool = false
var gauge: BalanceGauge
var lever_node: Node3D
var marker: Node3D
var area: Area3D
var pos_readout: Label3D
var kit: WorldKit
var _built: bool = false
var _time: float = 0.0
# --- V2 co-op -------------------------------------------------------------
var session: CoopSession
var machine_id: String = "cart_left"
var active_pid: int = 0
var pending_player: PlayerController = null
var _net_baseline: float = 9.0
var _credited_effect: bool = false


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	var steel: Material = MatLib.dark_steel()
	var paint: Material = MatLib.flat(Color(0.045, 0.075, 0.085), 0.80, 0.05)
	# pedestal / hydraulic base
	kit.box("Pedestal", Vector3(1.40, 0.72, 1.00), Vector3(0, 0.36, 0), MatLib.metal(Color(0.19, 0.22, 0.24), 0.4, 0.75, 0.55), Vector3.ZERO, true)
	kit.box("PedestalTop", Vector3(1.54, 0.08, 1.12), Vector3(0, 0.76, 0), steel, Vector3.ZERO, false)
	kit.box("HazardTrim", Vector3(1.56, 0.10, 0.07), Vector3(0, 0.70, 0.54), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.box("ToePlate", Vector3(1.62, 0.10, 1.20), Vector3(0, 0.07, 0), MatLib.dark_steel(), Vector3.ZERO, true)
	# angled operator panel with the instrument and the cart-position slot
	kit.box("PanelFace", Vector3(1.20, 0.34, 0.07), Vector3(0, 0.82, 0.30), paint, Vector3(deg_to_rad(-24), 0, 0), false)
	# pivot yoke and lever (pivot 0.74 m above the deck)
	kit.box("YokeL", Vector3(0.10, 0.24, 0.26), Vector3(-0.15, 0.74, 0.02), steel, Vector3.ZERO, false)
	kit.box("YokeR", Vector3(0.10, 0.24, 0.26), Vector3(0.15, 0.74, 0.02), steel, Vector3.ZERO, false)
	kit.cylinder("Pivot", 0.075, 0.36, Vector3(0, 0.74, 0.02), MatLib.bronze(), Vector3(0, 0, deg_to_rad(90)), false, 12)
	kit.box("LeverSlot", Vector3(0.14, 0.02, 0.46), Vector3(0, 0.795, 0.02), MatLib.emissive(Color(0.2, 0.65, 0.7), 0.35), Vector3.ZERO, false)
	lever_node = Node3D.new()
	lever_node.name = "Lever"
	lever_node.position = Vector3(0, 0.74, 0.02)
	add_child(lever_node)
	var lk: WorldKit = WorldKit.new(lever_node)
	lk.beam("LeverShaft", Vector3.ZERO, Vector3(0, 0.52, 0), 0.038, steel, false, 8)
	lk.cylinder("LeverGrip", 0.052, 0.30, Vector3(0, 0.54, 0), MatLib.grip(), Vector3(0, 0, deg_to_rad(90)), false, 12)
	for side in [-1.0, 1.0]:
		lk.cylinder("GripCap", 0.060, 0.035, Vector3(side * 0.155, 0.54, 0), MatLib.bronze(), Vector3(0, 0, deg_to_rad(90)), false, 10)
	lk.box("LeverCollar", Vector3(0.11, 0.08, 0.11), Vector3(0, 0.08, 0), MatLib.bronze(), Vector3.ZERO, false)
	# cart position indicator: a short horizontal slot on the panel top
	kit.box("IndicatorSlot", Vector3(0.58, 0.02, 0.08), Vector3(0, 0.80, 0.40), MatLib.dark_steel(), Vector3.ZERO, false)
	kit.label3d("内", Vector3(-0.34, 0.86, 0.40), 0.0018, Color(0.75, 0.85, 0.9), 20)
	kit.label3d("外", Vector3(0.34, 0.86, 0.40), 0.0018, Color(0.75, 0.85, 0.9), 20)
	marker = Node3D.new()
	marker.name = "PositionPointer"
	marker.position = Vector3(0, 0.815, 0.40)
	add_child(marker)
	var mk: WorldKit = WorldKit.new(marker)
	mk.box("Pointer", Vector3(0.055, 0.03, 0.10), Vector3.ZERO, MatLib.emissive(Color(0.95, 0.7, 0.2), 1.4), Vector3.ZERO, false)
	# small balance gauge, angled toward the operator on the left of the panel
	kit.box("GaugeHousing", Vector3(0.32, 0.34, 0.10), Vector3(-0.46, 0.98, 0.26), steel, Vector3(deg_to_rad(-18), 0, 0), false)
	gauge = BalanceGauge.new()
	gauge.name = "StationGauge"
	gauge.position = Vector3(-0.46, 0.98, 0.325)
	add_child(gauge)
	gauge.build(0.135)
	# hydraulic hose down the back of the pedestal, clear of the operator's view
	kit.pipe("HydraulicLine", [Vector3(-0.56, 0.62, -0.36), Vector3(-0.68, 0.36, -0.48), Vector3(-0.78, 0.04, -0.52)], 0.045, MatLib.copper(), false)
	for i in range(3):
		kit.cylinder("HoseClamp", 0.075, 0.05, Vector3(-0.56 - float(i) * 0.09, 0.62 - float(i) * 0.20, -0.36 - float(i) * 0.06), MatLib.dark_steel(), Vector3(PI * 0.5, 0, 0), false, 8)
	# a small emergency-stop button and a tool tray for industrial readability
	kit.box("EstopHousing", Vector3(0.16, 0.16, 0.10), Vector3(0.52, 0.86, 0.30), MatLib.dark_steel(), Vector3(deg_to_rad(-24), 0, 0), false)
	kit.cylinder("EstopButton", 0.055, 0.04, Vector3(0.52, 0.875, 0.36), MatLib.emissive(Color(0.9, 0.22, 0.12), 1.2), Vector3(deg_to_rad(66), 0, 0), false, 12)
	kit.box("ToolTray", Vector3(0.30, 0.04, 0.18), Vector3(-0.52, 0.72, 0.38), MatLib.dark_steel(), Vector3.ZERO, false)
	# interaction area just in front of the lever
	area = Area3D.new()
	area.name = "StationArea"
	area.position = Vector3(0, 1.2, 0.75)
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitorable = true
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.9
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	area.add_child(col)
	add_child(area)
	add_to_group("interactable")
	# small plate + label on the front of the pedestal, not a floating billboard
	kit.box("NamePlate", Vector3(0.52, 0.14, 0.02), Vector3(0, 0.56, 0.505), MatLib.dark_steel(), Vector3.ZERO, false)
	pos_readout = kit.label3d(side_name + "侧配重", Vector3(0, 0.56, 0.522), 0.0016, Color(0.82, 0.93, 0.98), 20)
	anchor = Transform3D(Basis(Vector3.UP, station_yaw), to_global(Vector3(0, 0, 1.00)))


func setup(p_core: CoreRig, p_cart: WeightCart, p_player: PlayerController, p_side_sign: float, p_station_yaw: float) -> void:
	core = p_core
	cart = p_cart
	side_sign = p_side_sign
	station_yaw = p_station_yaw
	side_name = "左" if side_sign < 0.0 else "右"
	if not _built:
		build()
	rotation.y = station_yaw
	anchor = Transform3D(Basis(Vector3.UP, station_yaw), to_global(Vector3(0, 0, 1.00)))
	if p_player != null:
		bind_player(p_player)


func bind_player(p: PlayerController) -> void:
	player = p
	if player == null:
		return
	if not player.operate_stopped.is_connected(_on_player_stopped):
		player.operate_stopped.connect(_on_player_stopped)


func setup_coop(p_session: CoopSession, p_machine_id: String) -> void:
	session = p_session
	machine_id = p_machine_id
	if session != null:
		if not session.local_claim_granted.is_connected(_on_grant):
			session.local_claim_granted.connect(_on_grant)
		if not session.local_claim_denied.is_connected(_on_deny):
			session.local_claim_denied.connect(_on_deny)


func get_prompt() -> String:
	if core != null and core.is_locked():
		return "核心已锁定 · 配重机构已锁定"
	if active:
		return ""
	if session != null and session.is_claimed_by_other(machine_id, session.local_pid):
		return "%s 正在操作%s侧配重" % [session.ledger.display_name(session.claim_owner(machine_id)), side_name]
	return "E 握住" + side_name + "侧配重手柄"


func interact(p: PlayerController) -> void:
	if core == null or cart == null:
		return
	if core.is_locked() or core.is_locking():
		return
	if p.operating:
		return
	pending_player = p
	if session != null and not session.is_authority():
		if session.is_pending_claim(machine_id):
			return
		session.note_pending_claim(machine_id)
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_claim(machine_id)
		return
	if session != null:
		var result: Dictionary = session.try_claim(machine_id, session.local_pid)
		if not bool(result.get("ok", false)):
			var hud: GameHud = _find_hud()
			if hud != null:
				hud.toast(str(result.get("reason", "")), 2.0)
			return
	_enter(p)


func _enter(p: PlayerController) -> void:
	pending_player = null
	active = true
	active_pid = session.local_pid if session != null else 1
	_net_baseline = absf(core.get_net())
	_credited_effect = false
	bind_player(p)
	p.enter_operate(anchor, self, station_yaw, 1.18)
	p.hands.set_state("lever")
	if session != null:
		session.local_operating_machine = machine_id
	lever_engaged.emit()


func _on_grant(granted: String) -> void:
	if granted != machine_id:
		return
	if pending_player == null or not is_instance_valid(pending_player):
		return
	_enter(pending_player)


func _on_deny(denied: String, reason: String) -> void:
	if denied != machine_id:
		return
	pending_player = null
	var hud: GameHud = _find_hud()
	if hud != null:
		hud.toast(reason, 2.0)


func _find_net() -> CoopNet:
	var hub_net: CoopNet = NetLookup.get_net()
	if hub_net != null:
		return hub_net
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("CoopNet") as CoopNet


func _find_hud() -> GameHud:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("Hud") as GameHud


func _on_player_stopped(target: Node) -> void:
	if target != self:
		return
	active = false
	active_pid = 0
	lever_released.emit()
	if session == null:
		return
	if session.is_authority():
		session.release_claim(machine_id, session.local_pid)
	else:
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_release(machine_id)


func _physics_process(delta: float) -> void:
	if not _built or core == null or cart == null:
		return
	_time += delta
	if session != null and not session.is_authority():
		# Client: the cart position arrives in the snapshot; only drive the lever
		# visual towards the snapshot position.
		var target: float = lerpf(-0.22, 0.22, cart.get_p())
		if marker != null:
			marker.position.x = target
		return
	var owner: int = session.claim_owner(machine_id) if session != null else (active_pid if active else 0)
	var driving: bool = owner != 0 and not core.is_locked() and not core.is_locking()
	var local_axis: float = 0.0
	if active and owner == session.local_pid:
		local_axis = Input.get_axis("move_back", "move_forward")
	var axis: float = 0.0
	if driving:
		axis = session.axis_for(machine_id, local_axis) if session != null else local_axis
	var target_angle: float = -axis * 0.62
	lever_angle = move_toward(lever_angle, target_angle, delta * (3.0 if absf(axis) > 0.05 else 4.5))
	if lever_node != null:
		lever_node.rotation.x = lever_angle
	var drive_velocity: float = 0.0
	if driving:
		drive_velocity = -lever_angle / 0.62 * 0.255
	cart.set_drive(drive_velocity, delta)
	if gauge != null:
		gauge.update_net(core.get_net(), core.is_capturable())
	if marker != null:
		marker.position.x = lerpf(-0.22, 0.22, cart.get_p())
	if pos_readout != null:
		pos_readout.text = "%s侧配重 · %s" % [side_name, _position_word(cart.get_p())]
	# report this cart through the core / preserve the other side
	if side_sign < 0.0:
		core.set_weights(cart.get_p(), core.right_p)
	else:
		core.set_weights(core.left_p, cart.get_p())
	# Credit only a real reduction of the core moment achieved by this operator.
	if session != null and owner != 0 and absf(axis) > 0.05:
		var net_now: float = absf(core.get_net())
		if net_now < _net_baseline - 0.03 and not _credited_effect:
			_credited_effect = true
			session.credit(owner, "counterweight_effect", _net_baseline - net_now, "%s侧配重减小核心力矩" % side_name)
	cart_moved.emit(cart.get_p())


func _position_word(p: float) -> String:
	if p < 0.2:
		return "最内"
	if p < 0.42:
		return "偏内"
	if p < 0.62:
		return "中位"
	if p < 0.82:
		return "偏外"
	return "最外"


func reset_state(new_p: float) -> void:
	active = false
	lever_angle = 0.0
	if lever_node != null:
		lever_node.rotation.x = 0.0
	if cart != null:
		cart.reset_state(new_p)
	if marker != null:
		marker.position.x = lerpf(-0.22, 0.22, new_p)





