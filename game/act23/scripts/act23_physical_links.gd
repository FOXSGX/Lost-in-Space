class_name Act23PhysicalLinks
extends Node3D

const PhysicalLinkKit := preload("res://scripts/core/physical_link_kit.gd")
const ArtAtmosphereKit := preload("res://scripts/core/art_atmosphere_kit.gd")

## Act 2/3 physical causal links inside RepairYard (s=90..98) and CrystalDock (s=106):
## - RepairYard: WinchStation -> LockStation bus, GuidePedestal -> Receiver bus,
##   SafetyProp -> WinchStation interlock bus, alignment target arc & status lamps,
##   and non-floating schematic plaques (no floating 3D text).
## - CrystalDock: cart-in-zone deck marker, clamp status lamp, DockToGateBus,
##   and non-floating docking sequence plaque.

var _mats: Dictionary = {}
var _lamps: Dictionary = {}
var _dials: Dictionary = {}
var _last_sig := ""


func setup(stage: Node3D, yard_node: Node3D, dock_node: Node3D) -> void:
	name = "Act23PhysicalLinks"
	stage.add_child(self)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.16, 0.18)
	dark.metallic = 0.65
	dark.roughness = 0.50

	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color(0.50, 0.28, 0.14)
	copper.metallic = 0.78
	copper.roughness = 0.40

	if yard_node != null:
		_build_yard_links(yard_node, dark, copper)
	if dock_node != null:
		_build_dock_links(dock_node, dark, copper)


func _build_yard_links(yard: Node3D, dark: StandardMaterial3D, copper: StandardMaterial3D) -> void:
	var root := Node3D.new()
	root.name = "YardPhysicalLinks"
	yard.add_child(root)

	# 1. Target capture corridor on ballast near Receiver mouth (x = 5.6 .. 6.4, flush at y=0.04)
	var m_arc := PhysicalLinkKit.make_flow_material()
	_mats["yard_target"] = m_arc
	PhysicalLinkKit.build_conduit_run(root, "ReceiverTargetLine", [
		Vector3(5.65, 0.04, -1.62),
		Vector3(6.35, 0.04, -1.62),
		Vector3(6.60, 0.04, -2.10),
		Vector3(6.60, 0.04, 2.10),
		Vector3(6.35, 0.04, 1.62),
		Vector3(5.65, 0.04, 1.62),
	], 0.026, dark, m_arc, Vector3.ZERO, false)

	# 2. WinchStation -> LockStation sync bus along south wall (|z| >= 2.2, outside cart hull)
	var m_winch_lock := PhysicalLinkKit.make_flow_material()
	_mats["winch_lock"] = m_winch_lock
	PhysicalLinkKit.build_conduit_run(root, "WinchToLockBus", [
		Vector3(-2.60, 0.45, 3.40),
		Vector3(-1.80, 0.04, 3.30),
		Vector3(3.20, 0.04, 2.95),
		Vector3(7.95, 0.04, 2.45),
		Vector3(7.95, 1.25, 2.45),
	], 0.042, copper, m_winch_lock, Vector3.ZERO, true)

	# 3. GuidePedestal -> LockStation assist conduit (runs along north edge then across under receiver floor y=0.04)
	var m_guide := PhysicalLinkKit.make_flow_material()
	_mats["guide_assist"] = m_guide
	PhysicalLinkKit.build_conduit_run(root, "GuideToLockBus", [
		Vector3(5.55, 0.45, -2.35),
		Vector3(6.60, 0.04, -2.35),
		Vector3(7.95, 0.04, -2.35),
		Vector3(7.95, 0.04, 2.45),
	], 0.032, dark, m_guide, Vector3.ZERO, true)

	# 4. SafetyProp -> WinchStation interlock conduit (runs under approach ballast at x=1.90, y=0.04)
	var m_prop := PhysicalLinkKit.make_flow_material()
	_mats["prop_interlock"] = m_prop
	PhysicalLinkKit.build_conduit_run(root, "SafetyPropInterlockWire", [
		Vector3(1.90, 0.12, -2.55),
		Vector3(1.90, 0.04, -1.80),
		Vector3(-0.90, 0.04, -1.80),
		Vector3(-0.90, 0.04, 2.85),
		Vector3(-2.45, 0.04, 3.25),
		Vector3(-2.45, 0.45, 3.25),
	], 0.032, dark, m_prop, Vector3.ZERO, true)

	# Status lamps on Receiver, LockStation, GuidePedestal, SafetyProp, Winch
	_lamps["winch_ready"] = PhysicalLinkKit.build_status_lamp(root, "WinchAttachLamp", Vector3(-1.75, 1.55, 2.85), 0.075, dark)
	_lamps["receiver_l"] = PhysicalLinkKit.build_status_lamp(root, "ReceiverLampL", Vector3(6.60, 1.18, -2.10), 0.08, dark)
	_lamps["receiver_r"] = PhysicalLinkKit.build_status_lamp(root, "ReceiverLampR", Vector3(6.60, 1.18, 2.10), 0.08, dark)
	_lamps["lock_ready"] = PhysicalLinkKit.build_status_lamp(root, "LockReadyLamp", Vector3(7.95, 2.02, 2.45), 0.085, dark)
	_lamps["guide"] = PhysicalLinkKit.build_status_lamp(root, "GuideAssistLamp", Vector3(5.55, 1.48, -2.35), 0.068, dark)
	_lamps["prop"] = PhysicalLinkKit.build_status_lamp(root, "PropClearLamp", Vector3(1.90, 0.62, -2.55), 0.068, dark)

	# Non-floating schematic plaques (flush mounted with grounded pedestal beside Winch & LockStation)
	var w_post := MeshInstance3D.new()
	w_post.name = "WinchPlaquePost"
	var wpm := CylinderMesh.new()
	wpm.top_radius = 0.045
	wpm.bottom_radius = 0.06
	wpm.height = 1.15
	w_post.mesh = wpm
	w_post.position = Vector3(-1.35, 0.575, 2.75)
	w_post.material_override = dark
	root.add_child(w_post)
	PhysicalLinkKit.build_diagram_plaque(root, "WinchFlowSchematic", Vector3(-1.35, 1.18, 2.75), Vector3(-12.0, -145.0, 0.0), Vector2(0.84, 0.34), [
		{"num": 1, "icon": "plug", "col": Color(1.0, 0.68, 0.22)},
		{"num": 2, "icon": "winch", "col": Color(0.32, 0.90, 1.0)},
		{"num": 3, "icon": "pin", "col": Color(0.28, 0.96, 0.72)},
	], Color(1.0, 0.68, 0.22))

	PhysicalLinkKit.build_diagram_plaque(root, "LockFlowSchematic", Vector3(7.95, 1.25, 2.20), Vector3(0.0, 180.0, 0.0), Vector2(0.76, 0.30), [
		{"num": 1, "icon": "winch", "col": Color(0.32, 0.90, 1.0)},
		{"num": 2, "icon": "pin", "col": Color(0.28, 0.96, 0.72)},
		{"num": 3, "icon": "cart", "col": Color(1.0, 0.72, 0.22)},
	], Color(0.28, 0.96, 0.72))
	_dials["align"] = PhysicalLinkKit.build_live_dial(root, "LockAlignDial", Vector3(7.95, 1.62, 2.18), Vector3(0.0, 180.0, 0.0), 0.17, 0.36, 0.64)
	_dials["tension"] = PhysicalLinkKit.build_live_dial(root, "WinchTensionDial", Vector3(-1.35, 1.56, 2.75), Vector3(-12.0, -145.0, 0.0), 0.16, 0.20, 0.75)

	# Grounding skirts, gravel chips, catenary hoses & subtle cave life (RepairYard)
	ArtAtmosphereKit.build_ground_skirt(root, "LockStationSkirt", Vector3(7.95, 0.0, 2.45), Vector2(1.9, 1.9))
	ArtAtmosphereKit.build_gravel_cluster(root, "LockStationGravel", Vector3(7.95, 0.0, 2.45), 0.95, 10, 2301)
	ArtAtmosphereKit.build_ground_skirt(root, "GuidePedestalSkirt", Vector3(5.55, 0.0, -2.35), Vector2(1.4, 1.4))
	ArtAtmosphereKit.build_gravel_cluster(root, "GuidePedestalGravel", Vector3(5.55, 0.0, -2.35), 0.75, 8, 2302)
	ArtAtmosphereKit.build_ground_skirt(root, "SafetyPropSkirt", Vector3(1.90, 0.0, -2.55), Vector2(1.3, 1.3))
	ArtAtmosphereKit.build_gravel_cluster(root, "SafetyPropGravel", Vector3(1.90, 0.0, -2.55), 0.70, 8, 2303)
	ArtAtmosphereKit.build_ground_skirt(root, "WinchStationSkirt", Vector3(-2.60, 0.0, 3.40), Vector2(2.4, 2.4))
	ArtAtmosphereKit.build_gravel_cluster(root, "WinchStationGravel", Vector3(-2.60, 0.0, 3.40), 1.20, 12, 2304)
	ArtAtmosphereKit.build_ground_skirt(root, "ReceiverSkirtL", Vector3(6.60, 0.0, -2.10), Vector2(1.2, 1.2))
	ArtAtmosphereKit.build_ground_skirt(root, "ReceiverSkirtR", Vector3(6.60, 0.0, 2.10), Vector2(1.2, 1.2))
	ArtAtmosphereKit.build_catenary_hose(root, "WinchHoseLoop", Vector3(-2.30, 1.05, 3.55), Vector3(-3.10, 0.85, 3.15), 0.22, 0.026)
	ArtAtmosphereKit.build_catenary_hose(root, "LockHoseLoop", Vector3(7.75, 1.15, 2.65), Vector3(8.25, 0.80, 2.25), 0.20, 0.024)
	ArtAtmosphereKit.build_steam_vent(root, "WinchExhaustSteam", Vector3(-2.60, 1.45, 3.50), Vector3(0.2, 1.0, -0.1), Color(0.86, 0.88, 0.90), 10, 0.26)
	ArtAtmosphereKit.build_ambient_motes(root, "YardDustMotes", Vector3(3.0, 2.2, 0.0), Vector3(6.5, 1.8, 3.2), Color(0.95, 0.78, 0.52), 24, 0.05)


func _build_dock_links(dock: Node3D, dark: StandardMaterial3D, copper: StandardMaterial3D) -> void:
	var root := Node3D.new()
	root.name = "DockPhysicalLinks"
	dock.add_child(root)

	var m_dock_zone := PhysicalLinkKit.make_flow_material()
	var m_dock_gate := PhysicalLinkKit.make_flow_material()
	_mats["dock_zone"] = m_dock_zone
	_mats["dock_gate"] = m_dock_gate

	# Target stop bar along the docking landing sill facing the cart side
	PhysicalLinkKit.build_conduit_run(root, "DockZoneTargetStrip", [
		Vector3(-0.90, 0.42, -0.78),
		Vector3(2.90, 0.42, -0.78),
	], 0.028, dark, m_dock_zone, Vector3.ZERO, false)

	# Clamp latch pylon -> Crystal mine entrance conduit
	PhysicalLinkKit.build_conduit_run(root, "DockToCrystalGateBus", [
		Vector3(1.20, 0.44, -0.72),
		Vector3(2.85, 0.44, -1.25),
		Vector3(3.45, 0.08, -1.25),
		Vector3(6.20, 0.08, -0.90),
		Vector3(6.20, 1.35, -0.90),
	], 0.044, copper, m_dock_gate, Vector3.ZERO, true)

	_lamps["dock_zone"] = PhysicalLinkKit.build_status_lamp(root, "DockCartZoneLamp", Vector3(0.55, 1.55, -0.82), 0.08, dark)
	_lamps["dock_lock"] = PhysicalLinkKit.build_status_lamp(root, "DockClampLockLamp", Vector3(1.20, 2.26, -0.92), 0.09, dark)

	# Docking sequence plaque on grounded post beside DockClamp handle (faces arriving player from -Z)
	var d_post := MeshInstance3D.new()
	d_post.name = "DockPlaquePost"
	var dpm := CylinderMesh.new()
	dpm.top_radius = 0.045
	dpm.bottom_radius = 0.06
	dpm.height = 0.98
	d_post.mesh = dpm
	d_post.position = Vector3(-0.35, 0.89, -1.35)
	d_post.material_override = dark
	root.add_child(d_post)
	PhysicalLinkKit.build_diagram_plaque(root, "DockOrderSchematic", Vector3(-0.35, 1.42, -1.35), Vector3(10.0, 180.0, 0.0), Vector2(0.76, 0.30), [
		{"num": 1, "icon": "cart", "col": Color(1.0, 0.68, 0.22)},
		{"num": 2, "icon": "clamp", "col": Color(0.32, 0.90, 1.0)},
		{"num": 3, "icon": "gate", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.32, 0.88, 1.0))

	ArtAtmosphereKit.build_ground_skirt(root, "DockPlaqueSkirt", Vector3(-0.35, 0.0, -1.35), Vector2(1.0, 1.0))
	ArtAtmosphereKit.build_godray_cone(root, "DockCyanShaft", Vector3(0.5, 5.2, 0.0), Vector3(0.15, -1.0, -0.05), 5.0, 0.9, 2.4, Color(0.28, 0.86, 1.0), 0.10)
	ArtAtmosphereKit.build_ambient_motes(root, "DockCrystalMotes", Vector3(1.5, 2.0, 0.0), Vector3(4.5, 1.8, 3.0), Color(0.32, 0.90, 1.0), 22, 0.055)


func refresh(yard: Node3D, dock: Node3D, _cart: Node3D) -> void:
	var attached := false
	var in_band := false
	var locked := false
	var guide_held := false
	var prop_held := false

	var angle_norm := 0.0
	var tens_norm := 0.0
	if yard != null:
		var rig: Node3D = yard.get("rig") as Node3D
		var rail: Node3D = yard.get("rail") as Node3D
		if rig != null:
			var t_state: Dictionary = rig.call("tension_state") as Dictionary
			attached = bool(t_state.get("attached", false))
			tens_norm = clampf(float(t_state.get("tension", 0.0)) / 12000.0, 0.0, 1.0)
			guide_held = int(rig.get("guide_holder")) > 0
			prop_held = int(rig.get("bracket_holder")) > 0
		if rail != null:
			var info: Dictionary = rail.call("alignment") as Dictionary
			in_band = bool(info.get("in_band", false))
			locked = bool(info.get("locked", false))
			var ang_deg: float = float(info.get("angle_deg", 15.0))
			angle_norm = clampf(0.5 - ang_deg / 30.0, 0.0, 1.0)

	PhysicalLinkKit.set_dial_value(_dials.get("align") as Node3D, angle_norm)
	PhysicalLinkKit.set_dial_value(_dials.get("tension") as Node3D, tens_norm)

	var cart_zone := false
	var dock_latched := false
	var dock_ok := false
	if dock != null:
		var ds: Dictionary = dock.call("state") as Dictionary
		cart_zone = bool(ds.get("cart_in_zone", false))
		dock_latched = bool(ds.get("latched", false))
		dock_ok = bool(ds.get("docked", false))

	var sig := "%s%s%s%s%s%s%s%s" % [attached, in_band, locked, guide_held, prop_held, cart_zone, dock_latched, dock_ok]
	if sig == _last_sig:
		return
	_last_sig = sig

	# RepairYard
	PhysicalLinkKit.set_flow_state(_mats.get("yard_target") as ShaderMaterial,
		"active" if locked else ("ready" if in_band else "locked"))
	PhysicalLinkKit.set_flow_state(_mats.get("winch_lock") as ShaderMaterial,
		"active" if locked else ("ready" if in_band else ("amber" if attached else "locked")))
	PhysicalLinkKit.set_flow_state(_mats.get("guide_assist") as ShaderMaterial,
		"active" if (guide_held or locked) else "idle_dim")
	PhysicalLinkKit.set_flow_state(_mats.get("prop_interlock") as ShaderMaterial,
		"surge" if prop_held else ("active" if attached else "idle_dim"))

	PhysicalLinkKit.set_lamp_state(_lamps.get("winch_ready") as StandardMaterial3D,
		"active" if locked else ("ready" if attached else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("receiver_l") as StandardMaterial3D,
		"active" if locked else ("ready" if in_band else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("receiver_r") as StandardMaterial3D,
		"active" if locked else ("ready" if in_band else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("lock_ready") as StandardMaterial3D,
		"active" if locked else ("ready" if in_band else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("guide") as StandardMaterial3D,
		"active" if guide_held else ("ready" if in_band else "off"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("prop") as StandardMaterial3D,
		"ready" if prop_held else "active")

	# CrystalDock
	PhysicalLinkKit.set_flow_state(_mats.get("dock_zone") as ShaderMaterial,
		"active" if dock_ok else ("ready" if cart_zone else "locked"))
	PhysicalLinkKit.set_flow_state(_mats.get("dock_gate") as ShaderMaterial,
		"active" if dock_ok else ("ready" if (cart_zone or dock_latched) else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("dock_zone") as StandardMaterial3D,
		"active" if cart_zone else "locked")
	PhysicalLinkKit.set_lamp_state(_lamps.get("dock_lock") as StandardMaterial3D,
		"active" if dock_ok else ("ready" if cart_zone else "locked"))
