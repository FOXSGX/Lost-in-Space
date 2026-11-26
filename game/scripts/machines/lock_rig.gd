class_name LockRig
extends Node3D

## Three hydraulic capture rams around the core base plus the operator console.
## The rams only close when the core is inside the mechanical capture range; a
## failed attempt produces a visible twitch and a clear mechanical reason.

signal lock_attempt_failed(reason: String)
signal lock_succeeded()
signal prompt_updated()

var core: CoreRig
var kit: WorldKit
var gauge: BalanceGauge
var rams: Array[Node3D] = []
var pins: Array[Node3D] = []
var jaw_tops: Array[Node3D] = []
var jaw_bottoms: Array[Node3D] = []
var lamp: MeshInstance3D
var lamp_material: StandardMaterial3D
var status_lights: Array[MeshInstance3D] = []
var console_area: Area3D
var target_extension: float = 0.0
var extension: float = 0.0
var fail_flash: float = 0.0
var locked_latch: bool = false
var time: float = 0.0
var _built: bool = false
var session: CoopSession


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	_build_pedestal()
	_build_rams()
	_build_console()


func _build_pedestal() -> void:
	var steel: Material = MatLib.dark_steel()
	var bronze: Material = MatLib.bronze()
	kit.cylinder("Pedestal", 5.2, 0.8, Vector3(0, 0.4, 0), MatLib.metal(Color(0.22, 0.25, 0.27), 0.45, 0.7, 0.55), Vector3.ZERO, true, 40)
	kit.ring_box("PedestalTrim", 5.05, 0.5, 0.16, Vector3(0, 0.82, 0), bronze, Basis(), 64, false)
	kit.ring_box("HazardBand", 5.18, 0.65, 0.22, Vector3(0, 0.25, 0), MatLib.hazard_material(), Basis(), 64, false)
	kit.rivet_ring(Vector3(0, 0.83, 0), 5.0, 36, Vector3.UP, MatLib.steel())
	# A machined turntable top instead of one black disc: lighter deck plate,
	# radial ribs and an inner bearing ring around the capture column.
	kit.cylinder("PedestalDeck", 4.98, 0.07, Vector3(0, 0.865, 0), MatLib.metal(Color(0.29, 0.31, 0.32), 0.52, 0.55, 0.6), Vector3.ZERO, false, 48)
	for i in range(12):
		var a3: float = TAU * float(i) / 12.0
		kit.box("DeckRib", Vector3(0.16, 0.05, 3.4), Vector3(cos(a3) * 3.1, 0.91, sin(a3) * 3.1), MatLib.dark_steel(), Vector3(0, -a3, 0), false)
	kit.ring_box("DeckInnerRing", 2.35, 0.34, 0.10, Vector3(0, 0.92, 0), MatLib.painted_steel(Color(0.34, 0.24, 0.16)), Basis(), 40, false)
	kit.rivet_ring(Vector3(0, 0.95, 0), 2.40, 24, Vector3.UP, MatLib.steel())
	for i in range(12):
		var a: float = TAU * float(i) / 12.0
		kit.box("FloorClamp", Vector3(0.7, 0.16, 0.7), Vector3(cos(a) * 6.3, 0.08, sin(a) * 6.3), steel, Vector3(0, -a, 0), false)
	# radial cable trays run out from under the deck, not through the walkway
	for i in range(4):
		var a2: float = TAU * float(i) / 4.0 + 0.4
		kit.box("CableTray", Vector3(0.5, 0.08, 3.4), Vector3(cos(a2) * 6.8, 0.10, sin(a2) * 6.8), MatLib.copper(), Vector3(0, -a2, 0), false)
		kit.box("TrayCover", Vector3(0.56, 0.05, 3.4), Vector3(cos(a2) * 6.8, 0.15, sin(a2) * 6.8), MatLib.dark_steel(), Vector3(0, -a2, 0), false)


func _build_rams() -> void:
	# The three rams are clocked 30 degrees off the axes so the console sight line
	# down +Z stays open: no tower ever sits between the operator and the core.
	for i in range(3):
		var a: float = TAU * float(i) / 3.0 + PI / 6.0
		var root: Node3D = Node3D.new()
		root.name = "Ram_%d" % i
		root.position = Vector3(cos(a) * 5.35, 0.8, sin(a) * 5.35)
		root.rotation.y = PI * 0.5 - a
		add_child(root)
		rams.append(root)
		var rk: WorldKit = WorldKit.new(root)
		var steel: Material = MatLib.painted_steel(Color(0.24, 0.31, 0.35))
		var dark: Material = MatLib.dark_steel()
		# compact tower and saddle
		rk.box("TowerBase", Vector3(1.15, 0.9, 1.25), Vector3(0, 0.45, 0.10), dark, Vector3.ZERO, false)
		rk.box("Tower", Vector3(0.82, 2.4, 0.92), Vector3(0, 1.75, 0.12), steel, Vector3.ZERO, false)
		rk.box("TowerCap", Vector3(1.05, 0.24, 1.15), Vector3(0, 3.07, 0.12), MatLib.bronze(), Vector3.ZERO, false)
		rk.box("GuideSaddle", Vector3(0.9, 0.46, 0.8), Vector3(0, 3.38, 0.18), steel, Vector3.ZERO, false)
		for side in [-1.0, 1.0]:
			rk.beam("Brace", Vector3(side * 0.42, 0.5, 0.7), Vector3(side * 0.38, 2.9, 0.35), 0.07, MatLib.bronze(), false, 8)
		# horizontal guide tube reaching toward the collar, supported by the saddle
		rk.cylinder("GuideTube", 0.30, 3.0, Vector3(0, 3.45, -1.30), steel, Vector3(PI * 0.5, 0, 0), false, 16)
		for zpos in [-0.02, -2.62]:
			rk.cylinder("GuideClamp", 0.38, 0.16, Vector3(0, 3.45, zpos), MatLib.bronze(), Vector3(PI * 0.5, 0, 0), false, 16)
		# diagonal support from the tower to the guide tube
		rk.beam("GuideStay", Vector3(0, 3.05, 0.55), Vector3(0, 3.12, -1.55), 0.065, MatLib.bronze(), false, 6)
		rk.cylinder("Hydraulic", 0.20, 1.3, Vector3(0, 3.45, 0.90), MatLib.copper(), Vector3(PI * 0.5, 0, 0), false, 12)
		rk.pipe("Hose", [Vector3(0.44, 2.7, 0.55), Vector3(0.82, 1.7, 0.55), Vector3(0.95, 0.55, 0.2)], 0.045, MatLib.rubber(), false)
		# moving capture head: retracted inside the guide, jaws close on the collar
		var pin: Node3D = Node3D.new()
		pin.name = "CapturePin"
		pin.position = Vector3(0, 3.45, -2.40)
		root.add_child(pin)
		pins.append(pin)
		var pin_mesh: CylinderMesh = CylinderMesh.new()
		pin_mesh.top_radius = 0.17
		pin_mesh.bottom_radius = 0.17
		pin_mesh.height = 1.8
		pin_mesh.radial_segments = 14
		var pin_body: MeshInstance3D = MeshInstance3D.new()
		pin_body.mesh = pin_mesh
		pin_body.material_override = MatLib.metal(Color(0.55, 0.42, 0.24), 0.28, 0.9, 0.3)
		pin_body.rotation_degrees = Vector3(90, 0, 0)
		pin_body.position = Vector3(0, 0, 0.92)
		pin.add_child(pin_body)
		var head: MeshInstance3D = MeshInstance3D.new()
		var head_mesh: BoxMesh = BoxMesh.new()
		head_mesh.size = Vector3(0.46, 0.40, 0.34)
		head.mesh = head_mesh
		head.material_override = MatLib.dark_steel()
		head.position = Vector3(0, 0, 0.14)
		pin.add_child(head)
		# vertical web and two tangential jaw plates form a C-clamp around the collar
		var web: MeshInstance3D = MeshInstance3D.new()
		var web_mesh: BoxMesh = BoxMesh.new()
		web_mesh.size = Vector3(0.20, 0.72, 0.20)
		web.mesh = web_mesh
		web.material_override = MatLib.painted_steel(Color(0.30, 0.26, 0.20))
		web.position = Vector3(0, 0, -0.02)
		pin.add_child(web)
		var jaw_top: Node3D = Node3D.new()
		jaw_top.name = "JawTop"
		jaw_top.position = Vector3(0, 0.34, 0)
		pin.add_child(jaw_top)
		var jaw_mesh: BoxMesh = BoxMesh.new()
		jaw_mesh.size = Vector3(0.66, 0.14, 0.46)
		var top_plate: MeshInstance3D = MeshInstance3D.new()
		top_plate.mesh = jaw_mesh
		top_plate.material_override = MatLib.bronze()
		top_plate.position = Vector3(0, 0.08, -0.12)
		jaw_top.add_child(top_plate)
		var top_pad: MeshInstance3D = MeshInstance3D.new()
		var pad_mesh: BoxMesh = BoxMesh.new()
		pad_mesh.size = Vector3(0.54, 0.05, 0.34)
		top_pad.mesh = pad_mesh
		top_pad.material_override = MatLib.grip()
		top_pad.position = Vector3(0, -0.01, -0.12)
		jaw_top.add_child(top_pad)
		var jaw_bottom: Node3D = Node3D.new()
		jaw_bottom.name = "JawBottom"
		jaw_bottom.position = Vector3(0, -0.34, 0)
		pin.add_child(jaw_bottom)
		var bottom_plate: MeshInstance3D = MeshInstance3D.new()
		bottom_plate.mesh = jaw_mesh
		bottom_plate.material_override = MatLib.bronze()
		bottom_plate.position = Vector3(0, -0.08, -0.12)
		jaw_bottom.add_child(bottom_plate)
		var bottom_pad: MeshInstance3D = MeshInstance3D.new()
		bottom_pad.mesh = pad_mesh
		bottom_pad.material_override = MatLib.grip()
		bottom_pad.position = Vector3(0, 0.01, -0.12)
		jaw_bottom.add_child(bottom_pad)
		jaw_tops.append(jaw_top)
		jaw_bottoms.append(jaw_bottom)
		# warning lamp on top
		if i == 0:
			lamp = MeshInstance3D.new()
			var sphere_mesh: SphereMesh = SphereMesh.new()
			sphere_mesh.radius = 0.18
			sphere_mesh.height = 0.36
			sphere_mesh.radial_segments = 12
			lamp.mesh = sphere_mesh
			lamp_material = MatLib.emissive(Color(1.0, 0.25, 0.1), 2.4)
			lamp.material_override = lamp_material
			lamp.position = Vector3(0, 3.62, 0.55)
			root.add_child(lamp)
			root.add_child(_make_lamp_light(i))


func _make_lamp_light(_i: int) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.position = Vector3(0, 3.75, 0.55)
	light.light_color = Color(1.0, 0.3, 0.15)
	light.light_energy = 0.8
	light.omni_range = 4.5
	light.shadow_enabled = false
	return light


func _build_console() -> void:
	var steel: Material = MatLib.painted_steel(Color(0.22, 0.30, 0.32))
	var dark: Material = MatLib.dark_steel()
	kit.box("ConsoleBase", Vector3(1.9, 0.92, 0.85), Vector3(0, 0.46, 8.60), MatLib.metal(Color(0.20, 0.24, 0.25), 0.42, 0.72, 0.55), Vector3.ZERO, true)
	kit.box("ConsoleTop", Vector3(1.78, 0.09, 0.92), Vector3(0, 0.95, 8.56), steel, Vector3(deg_to_rad(-10), 0, 0), false)
	kit.box("ConsoleLip", Vector3(1.84, 0.07, 0.10), Vector3(0, 0.905, 8.16), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.box("ConsoleStep", Vector3(2.3, 0.14, 1.2), Vector3(0, 0.07, 8.30), MatLib.dark_steel(), Vector3.ZERO, true)
	# angled instrument binnacle: a real bezel, a smaller dial, no floating disc
	kit.box("GaugeHousing", Vector3(0.86, 0.62, 0.16), Vector3(0, 1.24, 8.86), steel, Vector3(deg_to_rad(-12), 0, 0), false)
	kit.cylinder("GaugeBack", 0.34, 0.10, Vector3(0, 1.24, 8.94), dark, Vector3(deg_to_rad(90), 0, 0), false, 32)
	kit.ring_box("GaugeBezel", 0.335, 0.055, 0.06, Vector3(0, 1.24, 8.995), MatLib.bronze(), Basis(Vector3.RIGHT, PI * 0.5), 40, false)
	gauge = BalanceGauge.new()
	gauge.name = "DeviationGauge"
	gauge.position = Vector3(0, 1.24, 9.00)
	add_child(gauge)
	gauge.build(0.28)
	# status lamps: red / amber / green in a small binnacle above the dial
	status_lights.clear()
	for i in range(3):
		var status: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = 0.055
		sm.height = 0.11
		sm.radial_segments = 12
		status.mesh = sm
		var col: Color = [Color(1.0, 0.18, 0.08), Color(1.0, 0.68, 0.15), Color(0.2, 1.0, 0.5)][i]
		status.material_override = MatLib.emissive(col, 0.5 if i > 0 else 2.0)
		status.position = Vector3(-0.62 + float(i) * 0.13, 1.55, 8.97)
		add_child(status)
		status_lights.append(status)
	kit.box("StatusHousing", Vector3(0.48, 0.13, 0.10), Vector3(-0.49, 1.55, 8.91), dark, Vector3.ZERO, false)
	# small lock-state screen left of the dial
	kit.box("ScreenFrame", Vector3(0.48, 0.32, 0.06), Vector3(-0.58, 1.18, 8.90), dark, Vector3.ZERO, false)
	kit.box("ConsoleScreen", Vector3(0.42, 0.25, 0.02), Vector3(-0.58, 1.18, 8.94), MatLib.energy(Color(0.18, 0.7, 0.8), 0.5, 0.4, 4.0), Vector3.ZERO, false)
	# mechanical capture lever on the right, guarded and at chest height
	kit.box("LeverPedestal", Vector3(0.46, 0.72, 0.46), Vector3(1.38, 0.36, 8.72), dark, Vector3.ZERO, true)
	kit.box("LeverGuard", Vector3(0.52, 0.12, 0.52), Vector3(1.38, 0.76, 8.72), MatLib.hazard_material(), Vector3.ZERO, false)
	var lever_root: Node3D = Node3D.new()
	lever_root.position = Vector3(1.38, 0.82, 8.72)
	add_child(lever_root)
	var lever_kit: WorldKit = WorldKit.new(lever_root)
	lever_kit.cylinder("LeverPivot", 0.10, 0.34, Vector3.ZERO, MatLib.bronze(), Vector3(PI * 0.5, 0, 0), false, 10)
	lever_kit.beam("LeverArm", Vector3.ZERO, Vector3(0, 0.55, 0.18), 0.045, MatLib.steel(), false, 8)
	lever_kit.cylinder("LeverGrip", 0.06, 0.26, Vector3(0, 0.58, 0.19), MatLib.grip(), Vector3(PI * 0.5, 0, 0), false, 10)
	lever_kit.sphere("LeverKnob", 0.075, Vector3(0, 0.59, 0.19), MatLib.painted_steel(Color(0.8, 0.35, 0.1)), 10)
	# hydraulic cable
	for i in range(4):
		kit.cylinder("ConsoleBolt", 0.045, 0.05, Vector3(-0.78 + float(i) * 0.52, 0.90, 8.17), MatLib.steel(), Vector3(PI * 0.5, 0, 0), false, 8)
	kit.pipe("ConsoleHydraulic", [Vector3(-0.85, 0.72, 8.80), Vector3(-1.18, 0.40, 8.70), Vector3(-1.42, 0.12, 8.45)], 0.045, MatLib.copper(), false)
	kit.omni(Vector3(0.2, 2.55, 8.40), Color(0.65, 0.85, 0.95), 0.8, 3.6, false, "ConsoleLight")
	console_area = Area3D.new()
	console_area.name = "LockConsoleArea"
	console_area.position = Vector3(0, 1.10, 9.55)
	console_area.collision_layer = 8
	console_area.collision_mask = 0
	console_area.monitorable = true
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.85
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sphere
	console_area.add_child(col)
	add_child(console_area)
	add_to_group("interactable")
	# indicator strip low on the cabinet
	kit.box("StatusStrip", Vector3(1.3, 0.05, 0.03), Vector3(0, 0.52, 9.04), MatLib.emissive(Color(0.2, 0.8, 0.9), 1.0), Vector3.ZERO, false)


func interact(player: PlayerController) -> void:
	if core == null:
		return
	if core.is_locked():
		return
	if core.is_locking():
		# already closing: pressing E again must not report a new failure
		return
	if player.operating:
		return
	if session != null and not session.is_authority():
		var net_c: CoopNet = NetLookup.get_net()
		if net_c != null:
			net_c.submit_action("lock")
		return
	var result: Dictionary = core.request_lock()
	if not bool(result.get("ok", false)):
		fail_flash = 1.0
		lock_attempt_failed.emit(str(result.get("reason", "锁定失败")))
	else:
		player.hands.trigger_action("slam", 1.0)
		if session != null and session.is_authority():
			session.credit(session.local_pid, "lock_assist", 1.0, "启动液压锁爪")


func setup_coop(p_session: CoopSession) -> void:
	session = p_session


func get_prompt() -> String:
	if core == null:
		return ""
	if core.is_locked():
		return "核心已锁定"
	if core.is_locking():
		return "锁爪闭合中…"
	var interlock: String = core.lock_interlock_reason()
	if interlock != "":
		return "锁爪闭锁 · %s" % interlock
	if core.is_capturable():
		return "E 启动捕获锁爪  ·  偏差已进入捕获范围（捕获 ±%.2f）" % core.capture_net_limit()
	return "E 尝试捕获锁爪  ·  配重偏差超出 ±%.2f" % core.capture_net_limit()


func setup(p_core: CoreRig) -> void:
	core = p_core
	if not core.telemetry.is_connected(_on_telemetry):
		core.telemetry.connect(_on_telemetry)
	if not core.lock_failed.is_connected(_on_lock_failed):
		core.lock_failed.connect(_on_lock_failed)
	if not core.lock_started.is_connected(_on_lock_started):
		core.lock_started.connect(_on_lock_started)
	if not core.locked_done.is_connected(_on_locked_done):
		core.locked_done.connect(_on_locked_done)


func _on_telemetry(net: float, _angle: float, _omega: float, capturable: bool, locked: bool) -> void:
	if gauge != null:
		gauge.update_net(net, capturable)
	if lamp != null and not locked:
		var blink: bool = fmod(time * (2.0 + absf(net) * 5.0), 1.0) < 0.55
		var col: Color = Color(0.2, 0.95, 0.55) if capturable else (Color(1.0, 0.55, 0.1) if blink else Color(0.35, 0.1, 0.05))
		lamp.material_override = MatLib.emissive(col, 2.4 if capturable else 1.4)
	if status_lights.size() == 3:
		var red_on: bool = not capturable and not locked
		var amber_on: bool = capturable and not locked
		status_lights[0].material_override = MatLib.emissive(Color(1.0, 0.18, 0.08), 2.4 if red_on else 0.35)
		status_lights[1].material_override = MatLib.emissive(Color(1.0, 0.68, 0.15), 2.4 if amber_on else 0.35)
		status_lights[2].material_override = MatLib.emissive(Color(0.2, 1.0, 0.5), 2.4 if locked else 0.35)


func _on_lock_failed(reason: String) -> void:
	fail_flash = 1.0
	lock_attempt_failed.emit(reason)


func _on_lock_started() -> void:
	target_extension = 1.0


func _on_locked_done() -> void:
	locked_latch = true
	lock_succeeded.emit()
	if lamp != null:
		lamp.material_override = MatLib.emissive(Color(0.2, 1.0, 0.55), 3.2)
		gauge.update_net(0.0, true)


func _process(delta: float) -> void:
	time += delta
	if core != null and core.is_locked():
		target_extension = 1.0
	if fail_flash > 0.0:
		fail_flash = maxf(0.0, fail_flash - delta)
	extension = move_toward(extension, target_extension, delta * (0.9 if target_extension > extension else 0.55))
	for i in range(rams.size()):
		var pin: Node3D = pins[i]
		pin.position.z = -2.40 - extension * 1.53
		var open_close: float = ease(extension, 0.5)
		var top: Node3D = jaw_tops[i]
		var bottom: Node3D = jaw_bottoms[i]
		top.position.y = lerpf(0.48, 0.34, open_close)
		bottom.position.y = lerpf(-0.48, -0.34, open_close)
		if fail_flash > 0.0:
			var twitch: float = sin(fail_flash * 42.0) * 0.03 * fail_flash
			pin.position.z += twitch
	if fail_flash > 0.0 and lamp != null and not locked_latch:
		lamp.material_override = MatLib.emissive(Color(1.0, 0.15, 0.05), 3.0)


func reset_state() -> void:
	extension = 0.0
	target_extension = 0.0
	fail_flash = 0.0
	locked_latch = false
	for pin in pins:
		pin.position.z = -2.40
	for i in range(jaw_tops.size()):
		jaw_tops[i].position.y = 0.48
		jaw_bottoms[i].position.y = -0.48
	if lamp != null:
		lamp.material_override = MatLib.emissive(Color(1.0, 0.25, 0.1), 2.4)
	if gauge != null:
		gauge.update_net(0.0, false)
	for i in range(status_lights.size()):
		var on: bool = i == 0
		var cols: Array[Color] = [Color(1.0, 0.18, 0.08), Color(1.0, 0.68, 0.15), Color(0.2, 1.0, 0.5)]
		status_lights[i].material_override = MatLib.emissive(cols[i], 2.4 if on else 0.35)


func force_locked_visual() -> void:
	extension = 1.0
	target_extension = 1.0
	fail_flash = 0.0
	locked_latch = true
	for pin in pins:
		pin.position.z = -3.93
	for i in range(jaw_tops.size()):
		jaw_tops[i].position.y = 0.34
		jaw_bottoms[i].position.y = -0.34
	if lamp != null:
		lamp.material_override = MatLib.emissive(Color(0.2, 1.0, 0.55), 3.2)
	if gauge != null:
		gauge.update_net(0.0, true)
	if status_lights.size() == 3:
		status_lights[0].material_override = MatLib.emissive(Color(1.0, 0.18, 0.08), 0.35)
		status_lights[1].material_override = MatLib.emissive(Color(1.0, 0.68, 0.15), 0.35)
		status_lights[2].material_override = MatLib.emissive(Color(0.2, 1.0, 0.5), 3.0)

