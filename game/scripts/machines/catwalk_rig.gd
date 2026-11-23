class_name CatwalkRig
extends Node3D

## Hinged maintenance catwalk over the core hall.
##
## * The deck really rotates about a wall-side hinge. Its collision is a child of
##   the deck node, so it rotates with it.
## * Two shear pins hold the free (east) end into a cantilever bracket. A strong
##   resonance recoil knocks them out; with a pin gone the deck can swing much
##   further on the next recoil, and ungrabbed players slide down it.
## * Players can grab three rails. A grabbed player is carried by the deck and
##   cannot slide.
## * Falling off the free end drops the player to the hall floor; they are winded
##   for a few seconds. A teammate can hoist them with the winch (real cable
##   movement, controls locked while lifted); alone they can climb the caged
##   ladder once they recover.

signal tilt_changed(tilt: float)
signal pin_popped(index: int)
signal pins_restored(pid: int)
signal preload_done(pid: int)
signal rescued(operator_pid: int, target_pid: int)
signal grab_changed(pid: int, grabbing: bool)
signal message(text: String)

const DECK_LENGTH := 5.8
const DECK_HALF_WIDTH := 0.75
const PIVOT_HEIGHT := 3.4
const RESEAT_TIME := 1.35
const PRELOAD_TIME := 1.15
const CLIMB_TIME := 3.6
const REEL_TIME := 3.2
const SLIDE_ACCEL := 4.6

var session: CoopSession
var machine_id: String = "catwalk_lock"
var deck: Node3D
var deck_kit: WorldKit
var kit: WorldKit
var tilt: float = 0.0
var max_tilt_seen: float = 0.0
var pins_seated: int = 2
var preload_state: float = 0.0
var pin_nodes: Array[Node3D] = []
var pin_lugs: Array[Node3D] = []
var grab_points: Array[GrabPoint] = []
var lock_node: Node3D
var winch_node: Node3D
var winch_cable: MeshInstance3D
var ladder_base: Node3D
var lock_station_node: CatwalkStation
var winch_station_node: CatwalkStation
var ladder_station_node: CatwalkStation
var _deck_contact: Dictionary = {}
var status_lamp: MeshInstance3D
var audio: AudioDirector
var player: PlayerController
var _prev_deck_xform: Transform3D
var _time: float = 0.0
## 每物理帧只查一次 `get_nodes_in_group("player")`（本文件有 4 处用到）。
var _players_cache: Array[Node] = []
var _players_frame: int = -1
## `tilt_changed` 只在倾斜真的变化时才广播。
var _last_emitted_tilt: float = 0.0
var _lock_active: PlayerController = null
var _lock_progress: float = 0.0
var _lock_mode: String = ""
var _winch_active: PlayerController = null
var _winch_operator: PlayerController = null
var _winch_progress: float = 0.0
var _winch_target: PlayerController = null
var _winch_start: Vector3
var _climb_active: PlayerController = null
var _climb_progress: float = 0.0
var _downed: Array[PlayerController] = []
var _built: bool = false


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	_build_support()
	_build_deck()
	_build_pins()
	_build_winch()
	_build_ladder()
	_prev_deck_xform = deck.global_transform


func _build_support() -> void:
	var dark: Material = MatLib.dark_steel()
	var steel: Material = MatLib.painted_steel(Color(0.24, 0.30, 0.32))
	var bronze: Material = MatLib.bronze()
	# wall-side hinge bracket
	kit.box("HingeWallPlate", Vector3(0.30, 2.4, 2.3), Vector3(-0.15, PIVOT_HEIGHT, 0), dark, Vector3.ZERO, true)
	for sz in [-0.95, 0.95]:
		kit.box("HingeBearing", Vector3(0.62, 0.72, 0.34), Vector3(0.22, PIVOT_HEIGHT, sz), steel, Vector3.ZERO, true)
		kit.cylinder("HingePin", 0.13, 0.86, Vector3(0.22, PIVOT_HEIGHT, sz), bronze, Vector3(PI * 0.5, 0, 0), false, 14)
		kit.cylinder("HingeGrease", 0.16, 0.10, Vector3(0.22, PIVOT_HEIGHT + 0.42, sz), MatLib.rubber(), Vector3.ZERO, false, 12)
	# free-end support column with cantilever arm
	var col_local: Vector3 = Vector3(6.65, 0, 2.35)
	kit.box("ColumnFoot", Vector3(1.75, 0.25, 1.75), col_local + Vector3(0, 0.12, 0), dark, Vector3.ZERO, true)
	kit.box("Column", Vector3(1.05, 4.55, 1.05), col_local + Vector3(0, 2.40, 0), steel, Vector3.ZERO, true)
	kit.box("ColumnBand", Vector3(1.16, 0.22, 1.16), col_local + Vector3(0, 0.95, 0), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.box("ColumnCap", Vector3(1.30, 0.24, 1.30), col_local + Vector3(0, 4.72, 0), bronze, Vector3.ZERO, false)
	for sx in [-0.62, 0.62]:
		kit.beam("ColumnBrace", col_local + Vector3(sx * 1.4, 0.2, 0), col_local + Vector3(sx * 0.55, 2.1, 0), 0.075, dark, false, 6)
	# cantilever arm reaching the deck's free end
	kit.box("Cantilever", Vector3(0.55, 0.42, 2.40), Vector3(6.30, 4.45, 1.20), steel, Vector3.ZERO, true)
	kit.beam("CantileverKnee", Vector3(6.65, 3.30, 1.90), Vector3(6.10, 4.30, 0.95), 0.10, dark, false, 8)
	kit.box("PinBracket", Vector3(0.40, 0.55, 1.55), Vector3(5.95, 4.05, 0.05), dark, Vector3.ZERO, true)
	kit.label3d("维修栈桥 · 限载 2 人", Vector3(2.6, 1.15, -1.05), 0.0020, Color(0.85, 0.95, 1.0), 26)
	# floor markings under the end so the drop zone is obvious
	kit.box("DropPad", Vector3(4.4, 0.04, 3.6), Vector3(6.6, 0.02, 0.0), MatLib.metal(Color(0.26, 0.24, 0.18), 0.6, 0.3, 0.6), Vector3.ZERO, false)
	for i in range(3):
		kit.box("DropStripe", Vector3(4.2, 0.02, 0.10), Vector3(6.6, 0.045, -1.25 + float(i) * 1.25), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.label3d("安全维修区 · 跌落落点", Vector3(6.6, 0.35, 1.55), 0.0022, Color(1.0, 0.86, 0.55), 28)
	kit.omni(Vector3(5.4, 3.9, 1.1), Color(1.0, 0.72, 0.42), 1.4, 5.0, false, "CatwalkWork")


func _build_deck() -> void:
	deck = Node3D.new()
	deck.name = "Deck"
	deck.position = Vector3(0, PIVOT_HEIGHT, 0)
	add_child(deck)
	deck_kit = WorldKit.new(deck)
	var grid: Material = MatLib.metal(Color(0.26, 0.28, 0.29), 0.52, 0.62, 0.6)
	var dark: Material = MatLib.dark_steel()
	var steel: Material = MatLib.painted_steel(Color(0.28, 0.33, 0.35))
	var bronze: Material = MatLib.bronze()
	# deck slab and grating ribs
	deck_kit.box("DeckPlate", Vector3(DECK_LENGTH, 0.14, DECK_HALF_WIDTH * 2.0), Vector3(DECK_LENGTH * 0.5, 0, 0), grid, Vector3.ZERO, true)
	for i in range(12):
		deck_kit.box("Grate", Vector3(0.07, 0.02, DECK_HALF_WIDTH * 2.0 - 0.08), Vector3(0.35 + float(i) * 0.46, 0.08, 0), dark, Vector3.ZERO, false)
	for i in range(3):
		deck_kit.box("CrossBeam", Vector3(0.16, 0.26, DECK_HALF_WIDTH * 2.0 + 0.1), Vector3(0.7 + float(i) * 2.1, -0.16, 0), steel, Vector3.ZERO, false)
	# hinge drum on the wall side
	deck_kit.cylinder("HingeDrum", 0.34, 1.9, Vector3(0.05, 0, 0), MatLib.metal(Color(0.34, 0.36, 0.38), 0.30, 0.9, 0.35), Vector3(PI * 0.5, 0, 0), false, 20)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		deck_kit.box("DrumBolt", Vector3(0.07, 0.07, 0.05), Vector3(0.05 + cos(a) * 0.22, sin(a) * 0.22, 0.97), MatLib.steel(), Vector3.ZERO, false)
	# side railings with kick plates (collision so nobody walks off the sides)
	for sz in [-1.0, 1.0]:
		var z: float = sz * DECK_HALF_WIDTH
		deck_kit.box("KickPlate", Vector3(DECK_LENGTH, 0.22, 0.05), Vector3(DECK_LENGTH * 0.5, 0.11, z), MatLib.dark_steel(), Vector3.ZERO, false)
		deck_kit.box("KickStripe", Vector3(DECK_LENGTH, 0.05, 0.055), Vector3(DECK_LENGTH * 0.5, 0.20, z), MatLib.hazard_material(), Vector3.ZERO, false)
		for i in range(7):
			var x: float = 0.30 + float(i) * 0.86
			deck_kit.box("RailPost", Vector3(0.06, 1.05, 0.06), Vector3(x, 0.52, z), steel, Vector3.ZERO, false)
		deck_kit.beam("TopRail", Vector3(0.2, 1.06, z), Vector3(DECK_LENGTH - 0.15, 1.06, z), 0.045, MatLib.steel(), true, 8)
		deck_kit.beam("MidRail", Vector3(0.2, 0.60, z), Vector3(DECK_LENGTH - 0.15, 0.60, z), 0.032, MatLib.steel(), false, 6)
	# free-end bracket + pin lugs
	deck_kit.box("EndBracket", Vector3(0.36, 0.50, 1.70), Vector3(DECK_LENGTH - 0.10, -0.16, 0), dark, Vector3.ZERO, false)
	for sz2 in [-0.62, 0.62]:
		var lug: Node3D = Node3D.new()
		lug.name = "PinLug"
		lug.position = Vector3(DECK_LENGTH - 0.12, -0.16, sz2)
		deck.add_child(lug)
		var lk: WorldKit = WorldKit.new(lug)
		lk.box("LugPlate", Vector3(0.34, 0.34, 0.20), Vector3.ZERO, bronze, Vector3.ZERO, false)
		lk.cylinder("LugEye", 0.10, 0.26, Vector3(0.10, 0, 0), MatLib.steel(), Vector3(0, 0, PI * 0.5), false, 12)
		pin_lugs.append(lug)
	# grab rails: three grab points on the north rail
	var grab_xs: Array[float] = [0.9, 2.9, 4.9]
	for i in range(grab_xs.size()):
		var gp: GrabPoint = GrabPoint.new()
		gp.name = "GrabPoint_%d" % i
		gp.position = Vector3(grab_xs[i], 1.06, DECK_HALF_WIDTH)
		gp.rig = self
		gp.index = i
		deck.add_child(gp)
		gp.build()
		grab_points.append(gp)
	# maintenance lock pedestal on the deck (mid span, north side)
	lock_node = Node3D.new()
	lock_node.name = "MaintenanceLock"
	lock_node.position = Vector3(2.9, 0.07, -0.42)
	deck.add_child(lock_node)
	_build_lock()
	var lock_station: CatwalkStation = CatwalkStation.new()
	lock_station.name = "LockStation"
	lock_station.position = Vector3(2.9, 0.45, 0.30)
	deck.add_child(lock_station)
	lock_station.setup(self, "lock")
	lock_station_node = lock_station
	deck_kit.label3d("E 预紧 / 复位保险", Vector3(2.9, 0.52, -0.42), 0.0016, Color(0.85, 0.95, 1.0), 20)


func _build_lock() -> void:
	var lk: WorldKit = WorldKit.new(lock_node)
	var steel: Material = MatLib.dark_steel()
	var bronze: Material = MatLib.bronze()
	lk.box("LockBase", Vector3(0.62, 0.72, 0.52), Vector3(0, 0.36, 0), steel, Vector3.ZERO, true)
	lk.box("LockCap", Vector3(0.70, 0.08, 0.58), Vector3(0, 0.75, 0), bronze, Vector3.ZERO, false)
	lk.cylinder("LockPivot", 0.075, 0.40, Vector3(0, 0.86, 0), bronze, Vector3(0, 0, PI * 0.5), false, 12)
	lk.beam("LockLever", Vector3(0, 0.86, 0), Vector3(0, 1.34, -0.22), 0.038, MatLib.steel(), false, 8)
	lk.cylinder("LockGrip", 0.05, 0.28, Vector3(0, 1.38, -0.23), MatLib.grip(), Vector3(0, 0, PI * 0.5), false, 10)
	lk.box("PinRack", Vector3(0.22, 0.34, 0.24), Vector3(0, 1.02, 0.20), bronze, Vector3.ZERO, false)
	lk.box("Notice", Vector3(0.44, 0.20, 0.02), Vector3(0, 0.62, -0.27), MatLib.hazard_material(), Vector3.ZERO, false)
	var wp: WorldKit = WorldKit.new(deck)
	wp.omni(Vector3(2.9, 1.50, 0), Color(1.0, 0.75, 0.45), 0.7, 3.2, false, "LockLamp")


func _build_pins() -> void:
	# Two shear pins running through the deck lugs into the fixed bracket.
	for i in range(2):
		var pin: Node3D = Node3D.new()
		pin.name = "ShearPin_%d" % i
		pin.position = Vector3(DECK_LENGTH + 0.02, PIVOT_HEIGHT - 0.16, -0.62 if i == 0 else 0.62)
		add_child(pin)
		var pk: WorldKit = WorldKit.new(pin)
		pk.cylinder("PinBody", 0.075, 0.62, Vector3.ZERO, MatLib.metal(Color(0.72, 0.18, 0.10), 0.35, 0.6, 0.4), Vector3(0, 0, PI * 0.5), false, 12)
		pk.cylinder("PinHead", 0.13, 0.08, Vector3(-0.28, 0, 0), MatLib.bronze(), Vector3(0, 0, PI * 0.5), false, 12)
		pin_nodes.append(pin)
	status_lamp = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	sm.radial_segments = 12
	status_lamp.mesh = sm
	status_lamp.material_override = MatLib.emissive(Color(0.2, 1.0, 0.55), 2.0)
	status_lamp.position = Vector3(6.45, 4.75, 0)
	add_child(status_lamp)


func _build_winch() -> void:
	var steel: Material = MatLib.dark_steel()
	var bronze: Material = MatLib.bronze()
	# winch on the column landing, cable leaves towards the drop pad
	kit.box("WinchBed", Vector3(1.1, 0.18, 1.2), Vector3(6.55, 4.62, 1.35), steel, Vector3.ZERO, true)
	winch_node = Node3D.new()
	winch_node.name = "WinchDrum"
	winch_node.position = Vector3(6.55, 4.95, 1.35)
	add_child(winch_node)
	var wk: WorldKit = WorldKit.new(winch_node)
	wk.cylinder("Drum", 0.32, 0.95, Vector3.ZERO, MatLib.painted_steel(Color(0.52, 0.34, 0.12)), Vector3(0, 0, PI * 0.5), false, 18)
	for i in range(3):
		wk.ring_box("DrumFlange", 0.34, 0.06, 0.05, Vector3(-0.36 + float(i) * 0.36, 0, 0), bronze, Basis(Vector3.UP, PI * 0.5), 20, false)
	wk.cylinder("DrumHub", 0.09, 1.05, Vector3.ZERO, MatLib.steel(), Vector3(0, 0, PI * 0.5), false, 12)
	kit.box("WinchPostA", Vector3(0.14, 0.85, 0.14), Vector3(6.05, 4.95, 1.35), steel, Vector3.ZERO, true)
	kit.box("WinchPostB", Vector3(0.14, 0.85, 0.14), Vector3(7.05, 4.95, 1.35), steel, Vector3.ZERO, true)
	# cable (updated in _physics_process)
	var cable_mesh: CylinderMesh = CylinderMesh.new()
	cable_mesh.top_radius = 0.028
	cable_mesh.bottom_radius = 0.028
	cable_mesh.height = 1.0
	cable_mesh.radial_segments = 6
	winch_cable = MeshInstance3D.new()
	winch_cable.name = "WinchCable"
	winch_cable.mesh = cable_mesh
	winch_cable.material_override = MatLib.steel()
	add_child(winch_cable)
	# console at the landing
	kit.box("WinchConsole", Vector3(0.62, 0.86, 0.50), Vector3(6.55, 4.55, 2.05), MatLib.metal(Color(0.20, 0.24, 0.25), 0.42, 0.72, 0.55), Vector3.ZERO, true)
	kit.box("WinchPanel", Vector3(0.56, 0.28, 0.06), Vector3(6.55, 4.86, 2.24), steel, Vector3(deg_to_rad(-22), 0, 0), false)
	kit.cylinder("WinchButton", 0.055, 0.05, Vector3(6.55, 4.84, 2.26), MatLib.emissive(Color(0.2, 0.95, 0.6), 1.6), Vector3(deg_to_rad(68), 0, 0), false, 12)
	kit.cylinder("WinchGauge", 0.10, 0.05, Vector3(6.72, 4.90, 2.20), bronze, Vector3(deg_to_rad(68), 0, 0), false, 14)
	kit.label3d("救援卷扬机 · W 收绳", Vector3(6.55, 5.28, 2.05), 0.0018, Color(0.9, 0.95, 0.8), 22)
	# landing platform between ladder and deck
	kit.box("Landing", Vector3(1.5, 0.16, 1.7), Vector3(6.15, PIVOT_HEIGHT - 0.08, 1.05), MatLib.metal(Color(0.22, 0.26, 0.27), 0.5, 0.55, 0.65), Vector3.ZERO, true)
	kit.railing(self, Vector3(6.9, PIVOT_HEIGHT, 0.25), Vector3(6.9, PIVOT_HEIGHT, 1.95), 1.05)
	kit.railing(self, Vector3(5.45, PIVOT_HEIGHT, 1.95), Vector3(6.9, PIVOT_HEIGHT, 1.95), 1.05)
	winch_station_node = CatwalkStation.new()
	winch_station_node.name = "WinchStation"
	winch_station_node.position = Vector3(6.55, 4.85, 2.45)
	add_child(winch_station_node)
	winch_station_node.setup(self, "winch")


func _build_ladder() -> void:
	var steel: Material = MatLib.steel()
	# caged ladder on the column's +Z face, from floor to the landing
	var z: float = 2.95
	for sx in [6.10, 6.80]:
		kit.beam("LadderRail", Vector3(sx, 0.15, z), Vector3(sx, PIVOT_HEIGHT + 0.15, z), 0.055, steel, false, 8)
	for i in range(9):
		kit.box("LadderRung", Vector3(0.78, 0.05, 0.06), Vector3(6.45, 0.45 + float(i) * 0.42, z), MatLib.steel(), Vector3.ZERO, false)
	for i in range(4):
		var y: float = 1.5 + float(i) * 0.75
		kit.beam("LadderHoop", Vector3(5.72, y, z), Vector3(5.72, y, z - 0.8), 0.032, MatLib.steel(), false, 6)
		kit.beam("LadderHoopB", Vector3(7.18, y, z), Vector3(7.18, y, z - 0.8), 0.032, MatLib.steel(), false, 6)
		kit.box("LadderHoopTop", Vector3(1.46, 0.04, 0.04), Vector3(6.45, y, z - 0.8), MatLib.steel(), Vector3.ZERO, false)
	kit.label3d("维修爬梯 · 自救通道", Vector3(6.45, 2.2, 3.15), 0.0018, Color(0.8, 0.92, 1.0), 22)
	var ladder_light: OmniLight3D = OmniLight3D.new()
	ladder_light.position = Vector3(6.45, 1.2, 3.4)
	ladder_light.light_color = Color(0.55, 0.8, 0.95)
	ladder_light.light_energy = 0.8
	ladder_light.omni_range = 3.5
	add_child(ladder_light)
	ladder_base = Node3D.new()
	ladder_base.name = "LadderBase"
	ladder_base.position = Vector3(6.45, 0.0, 3.35)
	add_child(ladder_base)
	ladder_station_node = CatwalkStation.new()
	ladder_station_node.name = "LadderStation"
	ladder_station_node.position = Vector3(6.45, 0.55, 3.95)
	add_child(ladder_station_node)
	ladder_station_node.setup(self, "ladder")


# ---------------------------------------------------------------------------
# Setup / interaction
# ---------------------------------------------------------------------------

func setup(p_session: CoopSession, p_audio: AudioDirector) -> void:
	session = p_session
	audio = p_audio
	if session != null:
		if not session.local_claim_granted.is_connected(_on_local_grant):
			session.local_claim_granted.connect(_on_local_grant)
		if not session.local_claim_denied.is_connected(_on_local_deny):
			session.local_claim_denied.connect(_on_local_deny)
	_refresh_pin_pose()


func bind_player(p: PlayerController) -> void:
	player = p
	if player == null:
		return
	if not player.operate_stopped.is_connected(_on_player_stopped):
		player.operate_stopped.connect(_on_player_stopped)


func get_prompt() -> String:
	# Fallback prompt when the player looks at the structure itself. It must
	# never advertise the deck lock to a body standing on the hall floor: the
	# lock is on the deck and starting it moves the operator to its anchor.
	if player != null and is_instance_valid(player) and player.global_position.y < PIVOT_HEIGHT - 0.8:
		return "维修栈桥 · 靠近爬梯按 E 上桥"
	if pins_seated < 2:
		return "E 在维修锁处复位安全销"
	if preload_state < 0.99:
		return "E 在维修锁处预紧栈桥保险"
	return "栈桥已预紧 · 抓扶横杆可按 E 抓扶"


## True only when a body is standing in the physical zone of one station.
## Each station's prompt and action is gated by this so a ray or the nearest
## fallback can never start the deck lock from the hall floor, the winch from
## the floor, or the ladder from on top of the deck.
func station_zone_ok(mode: String, p: PlayerController) -> bool:
	if p == null or not is_instance_valid(p):
		return true
	var pos: Vector3 = p.global_position
	match mode:
		"lock":
			if pos.y < PIVOT_HEIGHT - 0.8:
				return false
			return lock_station_node != null and _flat_distance(pos, lock_station_node.global_position) < 1.2
		"winch":
			if pos.y < PIVOT_HEIGHT - 0.8:
				return false
			return winch_station_node != null and _flat_distance(pos, winch_station_node.global_position) < 2.1
		"ladder":
			if pos.y > PIVOT_HEIGHT - 0.8:
				return false
			return ladder_station_node != null and _flat_distance(pos, ladder_station_node.global_position) < 3.0
	return true


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func interact(p: PlayerController) -> void:
	# A rig-level hit is only a fallback; route the intended station by the
	# body's real location instead of always starting the maintenance lock.
	if station_zone_ok("ladder", p):
		_begin_climb(p)
		return
	if station_zone_ok("lock", p):
		_begin_lock(p)
		return
	_toast("靠近维修爬梯或栈桥上的维修锁再按 E", 2.0)


func station_interact(mode: String, p: PlayerController) -> void:
	match mode:
		"lock":
			_begin_lock(p)
		"winch":
			_begin_winch(p)
		"ladder":
			_begin_climb(p)


func _begin_winch(p: PlayerController) -> void:
	if p.operating or p.grabbing or session == null:
		return
	if not station_zone_ok("winch", p):
		_toast("先沿维修爬梯上到栈桥平台，靠近卷扬机再操作", 2.2)
		return
	if session.is_claimed_by_other("winch", session.local_pid):
		_toast("%s 正在操作卷扬机" % session.ledger.display_name(session.claim_owner("winch")))
		return
	pending_player = p
	pending_mode = "winch"
	if session.is_authority():
		var result: Dictionary = session.try_claim("winch", session.local_pid)
		if bool(result.get("ok", false)):
			_start_winch(p)
		else:
			_toast(str(result.get("reason", "")))
	else:
		if session.is_pending_claim("winch"):
			return
		session.note_pending_claim("winch")
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_claim("winch")
		else:
			session.deny_local_claim("winch", "未连接主机")


func _start_winch(p: PlayerController) -> void:
	if not station_zone_ok("winch", p):
		# The claim can arrive after the player walked/fell away. Never reel
		# from a position the station does not physically serve.
		pending_player = null
		_cancel_claim("winch")
		_toast("离卷扬机太远，操作已取消", 2.0)
		return
	pending_player = null
	_winch_operator = p
	_winch_progress = 0.0
	_winch_target = _find_downed_near_pad()
	bind_player(p)
	var anchor: Transform3D = Transform3D(Basis(Vector3.UP, 0.0), to_global(Vector3(6.55, PIVOT_HEIGHT, 2.75)))
	p.enter_operate(anchor, self, 0.0, 0.9)
	p.hands.set_state("lever")
	session.local_operating_machine = "winch"
	if _winch_target == null:
		_toast("卷扬机已接通 · 落点暂时没有人需要救援", 2.4)


func _begin_climb(p: PlayerController) -> void:
	if p.operating or p.grabbing:
		return
	if not station_zone_ok("ladder", p):
		if p.global_position.y > PIVOT_HEIGHT - 0.8:
			_toast("你已经在栈桥上了", 1.6)
		else:
			_toast("靠近维修爬梯再按 E", 2.0)
		return
	if p.impaired_timer > 0.0:
		_toast("你刚从高处跌落，暂时无法攀爬（%0.1f 秒）— 队友可用卷扬机拉你上去" % p.impaired_timer, 2.6)
		return
	_climb_active = p
	_climb_progress = 0.0
	var anchor: Transform3D = Transform3D(Basis(Vector3.UP, PI), to_global(Vector3(6.45, 0.0, 3.05)))
	p.enter_operate(anchor, self, PI, 0.7)
	p.external_hold = true
	p.velocity = Vector3.ZERO
	p.hands.set_state("climb")
	if session != null and session.is_authority():
		# Solo path: this really is the self-rescue route.
		pass
	_toast("按住 W 沿爬梯上到栈桥", 1.8)


func _begin_lock(p: PlayerController) -> void:
	if p.operating or p.grabbing:
		return
	if session == null:
		return
	if not station_zone_ok("lock", p):
		_toast("先沿维修爬梯上到栈桥，靠近维修锁再操作", 2.2)
		return
	if session.is_claimed_by_other(machine_id, session.local_pid):
		_toast("%s 正在处理维修保险" % session.ledger.display_name(session.claim_owner(machine_id)))
		return
	pending_player = p
	if session.is_authority():
		var result: Dictionary = session.try_claim(machine_id, session.local_pid)
		if bool(result.get("ok", false)):
			_start_lock_work(p)
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


var pending_player: PlayerController = null
var pending_mode: String = "lock"


func _on_local_grant(granted_id: String) -> void:
	if granted_id != machine_id and granted_id != "winch":
		return
	if pending_player == null or not is_instance_valid(pending_player):
		return
	if granted_id == "winch":
		_start_winch(pending_player)
	else:
		_start_lock_work(pending_player)


func _on_local_deny(denied_id: String, reason: String) -> void:
	if denied_id != machine_id and denied_id != "winch":
		return
	pending_player = null
	_toast(reason)


func _start_lock_work(p: PlayerController) -> void:
	if not station_zone_ok("lock", p):
		pending_player = null
		_cancel_claim(machine_id)
		_toast("离维修锁太远，操作已取消", 2.0)
		return
	pending_player = null
	_lock_active = p
	_lock_progress = 0.0
	_lock_mode = "reseat" if pins_seated < 2 else "preload"
	var anchor: Transform3D = Transform3D(Basis(Vector3.UP, deck.global_rotation.y), deck.global_transform * Vector3(2.9, 0.0, 0.55))
	p.enter_operate(anchor, self, deck.global_rotation.y + PI, 0.9)
	p.hands.set_state("lever")
	if session != null:
		session.local_operating_machine = machine_id
	_toast("按住 W 完成维修保险", 1.6)


func _on_player_stopped(target: Node) -> void:
	if target != self:
		return
	if _lock_active != null:
		_lock_active = null
		_lock_progress = 0.0
		if session != null:
			if session.is_authority():
				session.release_claim(machine_id, session.local_pid)
			else:
				var net: CoopNet = _find_net()
				if net != null:
					net.submit_release(machine_id)
	if _winch_operator != null:
		_winch_operator = null
		if session != null:
			if session.is_authority():
				session.release_claim("winch", session.local_pid)
			else:
				var net2: CoopNet = _find_net()
				if net2 != null:
					net2.submit_release("winch")
	if _climb_active != null:
		_climb_active.external_hold = false
		_climb_active = null


func _toast(text: String, seconds: float = 2.0) -> void:
	if text == "":
		return
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var hud: GameHud = root.get_node_or_null("Hud") as GameHud
	if hud != null:
		hud.toast(text, seconds)


func _cancel_claim(machine: String) -> void:
	if session == null:
		return
	if session.is_authority():
		session.release_claim(machine, session.local_pid)
	else:
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_release(machine)
		session.clear_operating_machine()


func _find_net() -> CoopNet:
	var hub_net: CoopNet = NetLookup.get_net()
	if hub_net != null:
		return hub_net
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("CoopNet") as CoopNet


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	var authority: bool = session == null or session.is_authority()
	if authority:
		_update_tilt(delta)
		_update_lock_work(delta)
		_update_winch(delta)
		# The carry integrator needs THIS tick's pose as `deck_xform` and the
		# PREVIOUS tick's pose as `_prev_deck_xform`. Applying the pose here
		# (instead of only at the end of the tick) is what makes
		# `deck_xform * (prev_inv * p)` a real delta rather than the identity.
		# The trailing call below is kept so the final pose still lands before
		# `_prev_deck_xform` is captured.
		_apply_deck_pose()
		_update_grab_carry(delta)
		_check_falls(delta)
	# The emergency ladder is a local body movement on both host and client: the
	# client owns its own player transform, the host validates the climb through
	# the position stream before it credits anything.
	_update_climb(delta)
	_apply_deck_pose()
	max_tilt_seen = maxf(max_tilt_seen, absf(tilt))
	_update_cable()
	_update_status()
	_prev_deck_xform = deck.global_transform
	# 只在倾斜真的变化时才广播：tilt_changed 的订阅者（HUD / 物理连线）会重算，
	# 每物理帧无条件 emit 等于让它们 60 Hz 空转。
	if absf(tilt - _last_emitted_tilt) > 0.001:
		_last_emitted_tilt = tilt
		tilt_changed.emit(tilt)


## 每物理帧只取一次玩家列表：本文件在 _update_grab_carry / _check_falls /
## _update_climb / 断线清理里一共查了 4 次，每次都会分配一个新数组。
func _players_now() -> Array[Node]:
	var frame: int = Engine.get_physics_frames()
	if frame != _players_frame:
		_players_frame = frame
		_players_cache.clear()
		for node: Node in get_tree().get_nodes_in_group("player"):
			_players_cache.append(node)
	return _players_cache


func _update_tilt(delta: float) -> void:
	var target: float = 0.0
	if preload_state < 0.99:
		target = 0.0
	# The deck springs back to level; during a surge it is pushed down.
	tilt = move_toward(tilt, target, delta * 0.055)
	var max_tilt: float = _max_tilt()
	tilt = clampf(tilt, -max_tilt, max_tilt)


func _max_tilt() -> float:
	var base: float = 0.05
	if pins_seated == 1:
		base = 0.20
	elif pins_seated == 0:
		base = 0.34
	return base * (1.0 - 0.35 * clampf(preload_state, 0.0, 1.0))


func _apply_deck_pose() -> void:
	if deck != null:
		deck.rotation.z = -tilt


func _refresh_pin_pose() -> void:
	for i in range(pin_nodes.size()):
		var seated: bool = i < pins_seated
		var pin: Node3D = pin_nodes[i]
		pin.position.x = DECK_LENGTH + 0.02 if seated else DECK_LENGTH + 0.42
		pin.visible = true


func _update_lock_work(delta: float) -> void:
	if session == null:
		return
	var owner: int = session.claim_owner(machine_id)
	if owner == 0:
		_lock_active = null
		return
	if owner == session.local_pid and (_lock_active == null or not _lock_active.operating):
		# local operator walked away without releasing
		session.release_claim(machine_id, owner)
		_lock_active = null
		return
	if _lock_mode == "":
		_lock_mode = "reseat" if pins_seated < 2 else "preload"
	var local_axis: float = 0.0
	if owner == session.local_pid:
		local_axis = Input.get_axis("move_back", "move_forward")
	var axis: float = maxf(0.0, session.axis_for(machine_id, local_axis))
	_lock_progress = clampf(_lock_progress + axis * delta, 0.0, RESEAT_TIME if _lock_mode == "reseat" else PRELOAD_TIME)
	if audio != null and axis > 0.1:
		audio.tick_servo(delta)
	var need: float = RESEAT_TIME if _lock_mode == "reseat" else PRELOAD_TIME
	if _lock_progress >= need:
		if _lock_mode == "reseat":
			pins_seated = 2
			_refresh_pin_pose()
			if audio != null:
				audio.play_sfx("latch", lock_node.global_position, -3.0)
			session.credit(owner, "pin_reseat", 1.0, "复位栈桥安全销")
			pins_restored.emit(owner)
			_toast("安全销已复位并预紧", 2.0)
			preload_state = maxf(preload_state, 0.6)
		else:
			preload_state = 1.0
			session.credit(owner, "catwalk_pin_seat", 1.0, "预紧栈桥维修保险")
			preload_done.emit(owner)
			_toast("维修保险已预紧 · 栈桥限位收紧", 2.2)
		_lock_progress = 0.0
		_lock_mode = ""
		if _lock_active != null and is_instance_valid(_lock_active):
			_lock_active.stop_operating()
		else:
			session.release_claim(machine_id, owner)


func on_surge(severity: float) -> void:
	if session != null and not session.is_authority():
		return
	var impulse: float = (0.09 + 0.15 * severity) * (1.0 - 0.40 * clampf(preload_state, 0.0, 1.0))
	tilt = clampf(tilt + impulse, -_max_tilt(), _max_tilt())
	var pop_threshold: float = 0.86 + 0.30 * clampf(preload_state, 0.0, 1.0)
	if severity > pop_threshold and pins_seated > 0:
		pins_seated -= 1
		_refresh_pin_pose()
		pin_popped.emit(pins_seated)
		preload_state = maxf(0.0, preload_state - 0.5)
		if audio != null:
			audio.play_sfx("metal_clank", pin_nodes[0].global_position, -2.0)
		_toast("安全销被震脱！栈桥限位失效 — 需要重新固定", 3.0)
	if audio != null:
		audio.play_sfx("shock", global_position + Vector3(3, 3, 0), -3.0)


func _update_grab_carry(delta: float) -> void:
	# Carry players standing on the deck with its rotation, and slide them when
	# the deck is tilted and they are not holding a rail.
	var deck_xform: Transform3D = deck.global_transform
	var prev_inv: Transform3D = _prev_deck_xform.affine_inverse()
	for node in _players_now():
		var p: PlayerController = node as PlayerController
		if p == null or not is_instance_valid(p):
			continue
		if p.grabbing and p.grab_anchor != null and is_ancestor_of(p.grab_anchor):
			continue
		if not _is_on_deck(p, deck_xform):
			continue
		_deck_contact[p.get_instance_id()] = _time
		var local: Vector3 = deck_xform.affine_inverse() * p.global_position
		var carried: Vector3 = deck_xform * (prev_inv * p.global_position)
		if p.external_hold:
			continue
		if not p.is_on_floor():
			continue
		p.global_position = Vector3(carried.x, p.global_position.y, carried.z)
		if absf(tilt) > 0.10:
			var downhill: Vector3 = (deck_xform.basis * Vector3(1, 0, 0))
			downhill.y = 0.0
			if downhill.length() > 0.01:
				downhill = downhill.normalized()
				var slip: float = SLIDE_ACCEL * sin(absf(tilt)) * (1.0 - clampf(preload_state, 0.0, 1.0) * 0.5)
				p.velocity.x += downhill.x * slip * delta * 3.0
				p.velocity.z += downhill.z * slip * delta * 3.0
		if local.x > DECK_LENGTH - 0.05 and not p.grabbing:
			# walked/slid past the free end: nothing holds them any more
			p.global_position.x += 0.02


func _is_on_deck(p: PlayerController, deck_xform: Transform3D) -> bool:
	var local: Vector3 = deck_xform.affine_inverse() * p.global_position
	return local.x > -0.2 and local.x < DECK_LENGTH + 0.25 and absf(local.z) < DECK_HALF_WIDTH + 0.25 and local.y > -0.35 and local.y < 1.4


func set_grab(p: PlayerController, anchor: Node3D, index: int) -> bool:
	if p == null or anchor == null:
		return false
	p.start_grab(anchor, Vector3(0, -1.06, -0.55))
	var pid: int = _pid_for(p)
	if session != null and pid != 0:
		session.credit(pid, "surge_response", 1.0, "抓扶栈桥横杆")
	grab_changed.emit(pid, true)
	if audio != null:
		audio.play_sfx("metal_clank", anchor.global_position, -6.0)
	return true


func clear_grab(p: PlayerController) -> void:
	if p == null:
		return
	p.stop_grab()
	grab_changed.emit(_pid_for(p), false)


func _pid_for(p: PlayerController) -> int:
	if session == null:
		return 1
	return session.local_pid


func _update_winch(delta: float) -> void:
	if winch_node != null:
		winch_node.rotation.x = _winch_progress * 14.0
	if session == null:
		return
	var owner: int = session.claim_owner("winch")
	if owner == 0:
		return
	var local_axis: float = 0.0
	if owner == session.local_pid:
		if _winch_operator == null or not _winch_operator.operating:
			session.release_claim("winch", owner)
			_winch_operator = null
			return
		local_axis = Input.get_axis("move_back", "move_forward")
	var axis: float = maxf(0.0, session.axis_for("winch", local_axis))
	if _winch_target == null or not is_instance_valid(_winch_target):
		_winch_target = _find_downed_near_pad()
		_winch_progress = 0.0
	if _winch_target == null:
		return
	if not _winch_target.external_hold:
		_winch_start = _winch_target.global_position
		_winch_target.external_hold = true
		_winch_target.velocity = Vector3.ZERO
		_toast("卷扬机已挂上 %s，按住 W 收绳" % _player_name(_winch_target), 2.0)
	if axis > 0.05:
		_winch_progress = clampf(_winch_progress + delta / REEL_TIME * axis, 0.0, 1.0)
		if audio != null:
			audio.tick_servo(delta)
	var landing: Vector3 = to_global(Vector3(6.15, PIVOT_HEIGHT + 0.02, 1.05))
	var start: Vector3 = _winch_start
	var mid: Vector3 = start.lerp(landing, 0.5) + Vector3(0, 1.2, 0)
	var t: float = _winch_progress
	var pos: Vector3 = start.lerp(mid, t).lerp(mid.lerp(landing, t), t)
	_winch_target.global_position = pos
	if _winch_progress >= 0.995:
		var target: PlayerController = _winch_target
		target.global_position = landing
		target.external_hold = false
		target.clear_impaired()
		_winch_target = null
		_winch_progress = 0.0
		session.credit(owner, "rescue", 1.0, "用卷扬机救回队友")
		rescued.emit(owner, _pid_for(target))
		_toast("救援完成", 2.2)
		if audio != null:
			audio.play_sfx("ready", landing, -4.0)
		session.release_claim("winch", owner)
		if _winch_operator != null and is_instance_valid(_winch_operator):
			_winch_operator.stop_operating()
		_winch_operator = null


func _find_downed_near_pad() -> PlayerController:
	var pad: Vector3 = to_global(Vector3(6.6, 0.2, 0.0))
	var best: PlayerController = null
	var best_d: float = 4.2
	for node in _players_now():
		var p: PlayerController = node as PlayerController
		if p == null or not is_instance_valid(p) or p.external_hold:
			continue
		if p.global_position.distance_to(pad) < best_d:
			# only a player who really fell (or is hurt) can be hoisted
			if p.impaired_timer > 0.0 or p.global_position.y < 2.2:
				best = p
				best_d = p.global_position.distance_to(pad)
	return best


func _player_name(p: PlayerController) -> String:
	if session != null:
		return session.ledger.display_name(_pid_for(p))
	return "队友"


func _update_cable() -> void:
	if winch_cable == null:
		return
	var top: Vector3 = to_global(Vector3(6.55, 4.95, 1.35))
	var bottom: Vector3 = top
	if _winch_target != null and is_instance_valid(_winch_target):
		bottom = _winch_target.global_position + Vector3(0, 1.0, 0)
	else:
		bottom = to_global(Vector3(6.6, 0.35, 0.0))
	var d: Vector3 = bottom - top
	var length: float = d.length()
	if length < 0.01:
		return
	winch_cable.visible = true
	winch_cable.global_position = (top + bottom) * 0.5
	var up: Vector3 = Vector3.UP
	var dir: Vector3 = d.normalized()
	var axis: Vector3 = up.cross(dir)
	if axis.length() < 0.001:
		axis = Vector3.RIGHT
	var angle: float = acos(clampf(up.dot(dir), -1.0, 1.0))
	winch_cable.global_transform.basis = Basis(axis.normalized(), angle)
	winch_cable.scale = Vector3(1, length, 1)


func _update_climb(delta: float) -> void:
	if _climb_active == null:
		return
	var p: PlayerController = _climb_active
	if not is_instance_valid(p) or not p.operating:
		if is_instance_valid(p):
			p.external_hold = false
		_climb_active = null
		return
	var axis: float = Input.get_axis("move_back", "move_forward")
	var base: Vector3 = to_global(Vector3(6.45, 0.0, 3.05))
	var top: Vector3 = to_global(Vector3(6.45, PIVOT_HEIGHT + 0.02, 2.55))
	_climb_progress = clampf(_climb_progress + maxf(0.0, axis) * delta / CLIMB_TIME, 0.0, 1.0)
	p.global_position = base.lerp(top, _climb_progress)
	if _climb_progress >= 0.995:
		var was_impaired: bool = p.impaired_timer > 0.0
		p.clear_impaired()
		p.external_hold = false
		p.teleport(to_global(Vector3(6.15, PIVOT_HEIGHT + 0.02, 1.35)), p.yaw, -0.05)
		if was_impaired and session != null and session.is_authority():
			session.credit(_pid_for(p), "self_rescue", 1.0, "沿备用爬梯自救")
		_climb_active = null
		_climb_progress = 0.0
		p.stop_operating()
		_toast("已爬回栈桥", 1.8)


func _check_falls(_delta: float) -> void:
	for node in _players_now():
		var p: PlayerController = node as PlayerController
		if p == null or not is_instance_valid(p):
			continue
		if p.external_hold or p.grabbing:
			continue
		var last_contact: float = float(_deck_contact.get(p.get_instance_id(), -100.0))
		if _time - last_contact > 0.7:
			continue
		if p.global_position.y < PIVOT_HEIGHT - 1.3:
			_deck_contact.erase(p.get_instance_id())
			p.set_impaired(6.0)
			_toast("%s 从栈桥跌落 — 6 秒内无法攀爬，队友可用卷扬机拉回" % _player_name(p), 3.2)
			if audio != null:
				audio.play_sfx("shock", p.global_position, -3.0)


func has_downed_near_pad() -> bool:
	return _find_downed_near_pad() != null


func _update_status() -> void:
	if status_lamp == null:
		return
	var col: Color = Color(0.2, 1.0, 0.55) if pins_seated == 2 else Color(1.0, 0.25, 0.10)
	if pins_seated == 2 and preload_state < 0.99:
		col = Color(1.0, 0.72, 0.2)
	status_lamp.material_override = MatLib.emissive(col, 2.2)


# ---------------------------------------------------------------------------
# Save / restore
# ---------------------------------------------------------------------------

func reset_state() -> void:
	tilt = 0.0
	max_tilt_seen = 0.0
	pins_seated = 2
	preload_state = 0.0
	_lock_active = null
	_lock_progress = 0.0
	_winch_operator = null
	_winch_target = null
	_winch_progress = 0.0
	_climb_active = null
	_climb_progress = 0.0
	_deck_contact.clear()
	_refresh_pin_pose()
	_apply_deck_pose()
	for node in _players_now():
		var p: PlayerController = node as PlayerController
		if p != null:
			p.external_hold = false
			p.clear_impaired()


func snapshot() -> Dictionary:
	return {
		"tilt": tilt,
		"pins": pins_seated,
		"preload_state": preload_state,
		"reel": _winch_progress,
		"lock": _lock_progress,
	}


func apply_snapshot(data: Dictionary) -> void:
	tilt = float(data.get("tilt", tilt))
	pins_seated = int(data.get("pins", pins_seated))
	preload_state = float(data.get("preload_state", preload_state))
	_refresh_pin_pose()
	_apply_deck_pose()
