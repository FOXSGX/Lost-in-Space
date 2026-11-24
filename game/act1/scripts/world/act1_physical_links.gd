class_name Act1PhysicalLinks
extends Node3D

const PhysicalLinkKit := preload("res://scripts/core/physical_link_kit.gd")
const ArtAtmosphereKit := preload("res://scripts/core/art_atmosphere_kit.gd")

## Act 1 physical causal links across all 4 zones:
## 1) Entry airlock: gantry clearance -> mechanical latch -> powered door
## 2) Power room: cart dock -> rail winch -> socket clamp -> main power bus -> FanStartCabinet
## 3) Vent hall: East RotorLock + Coupling cross-hall conduits + 3-lamp cabinet -> Fan -> Damper -> Station
## 4) Departure station: Vent -> WheelChock -> ParkingBrake -> Cargo -> LaunchConsole

var _mats: Dictionary = {}
var _lamps: Dictionary = {}
var _dials: Dictionary = {}
var _last_sig := ""


func setup(stage: Node) -> void:
	name = "Act1PhysicalLinks"
	stage.add_child(self)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.16, 0.18)
	dark.metallic = 0.65
	dark.roughness = 0.50

	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color(0.50, 0.28, 0.14)
	copper.metallic = 0.78
	copper.roughness = 0.40

	# ------------------------------------------------------------------
	# 1. Entry Airlock (z = 8.9 .. 9.6)
	# ------------------------------------------------------------------
	var m_entry := PhysicalLinkKit.make_flow_material()
	_mats["entry_interlock"] = m_entry
	PhysicalLinkKit.build_conduit_run(self, "EntryGantryToLatchWire", [
		Vector3(0.0, 0.04, 8.95),
		Vector3(2.72, 0.04, 9.00),
		Vector3(2.72, 1.35, 9.25),
	], 0.032, dark, m_entry, Vector3.ZERO, true)
	_lamps["entry_latch"] = PhysicalLinkKit.build_status_lamp(self, "EntryLatchLamp", Vector3(2.72, 2.12, 9.25), 0.075, dark)
	PhysicalLinkKit.build_diagram_plaque(self, "EntrySchematic", Vector3(-2.85, 1.52, 9.10), Vector3.ZERO, Vector2(0.76, 0.32), [
		{"num": 1, "icon": "cart", "col": Color(1.0, 0.66, 0.20)},
		{"num": 2, "icon": "lever", "col": Color(0.32, 0.90, 1.0)},
		{"num": 3, "icon": "door", "col": Color(0.28, 0.96, 0.72)},
	], Color(1.0, 0.68, 0.22))

	# ------------------------------------------------------------------
	# 2. Power Room -> Main Bus -> FanStartCabinet / FanHousing
	# ------------------------------------------------------------------
	_lamps["pow_dock"] = PhysicalLinkKit.build_status_lamp(self, "SocketDockLamp", Vector3(3.10, 2.38, -6.00), 0.08, dark)
	_lamps["pow_clamp"] = PhysicalLinkKit.build_status_lamp(self, "SocketClampLamp", Vector3(5.40, 2.38, -6.00), 0.08, dark)
	PhysicalLinkKit.build_diagram_plaque(self, "PowerSchematic", Vector3(4.25, 2.02, -6.00), Vector3.ZERO, Vector2(0.84, 0.34), [
		{"num": 1, "icon": "cart", "col": Color(1.0, 0.68, 0.20)},
		{"num": 2, "icon": "winch", "col": Color(0.32, 0.90, 1.0)},
		{"num": 3, "icon": "clamp", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.32, 0.88, 1.0))

	var m_pow_bus := PhysicalLinkKit.make_flow_material()
	_mats["power_bus"] = m_pow_bus
	# Floor-edge main feeder from SocketBack into VentHall West FanStartCabinet + branch to FanHousing
	PhysicalLinkKit.build_conduit_run(self, "PowerToFanBus", [
		Vector3(4.25, 0.95, -6.35),
		Vector3(5.40, 0.05, -7.20),
		Vector3(5.40, 0.05, -10.80),
		Vector3(2.35, 0.05, -12.20),
		Vector3(-5.80, 0.05, -18.20),
		Vector3(-8.12, 0.05, -24.80),
		Vector3(-8.12, 1.35, -24.80),
	], 0.046, copper, m_pow_bus, Vector3.ZERO, true)

	PhysicalLinkKit.build_conduit_run(self, "PowerToRotorMotorBus", [
		Vector3(5.40, 0.05, -10.80),
		Vector3(9.60, 0.05, -18.50),
		Vector3(10.30, 0.05, -24.80),
		Vector3(10.30, 3.80, -26.80),
	], 0.042, copper, m_pow_bus, Vector3.ZERO, true)

	# ------------------------------------------------------------------
	# 3. Vent Hall Interlocks (East Pin & Coupling -> West Start Cabinet)
	# ------------------------------------------------------------------
	var m_pin := PhysicalLinkKit.make_flow_material()
	var m_coupling := PhysicalLinkKit.make_flow_material()
	var m_wind := PhysicalLinkKit.make_flow_material()
	_mats["rotor_pin"] = m_pin
	_mats["coupling"] = m_coupling
	_mats["wind_pressure"] = m_wind

	PhysicalLinkKit.build_conduit_run(self, "RotorLockConduit", [
		Vector3(7.65, 0.05, -23.55),
		Vector3(7.65, 0.05, -20.25),
		Vector3(-7.45, 0.05, -20.25),
		Vector3(-8.12, 0.05, -24.65),
		Vector3(-8.12, 1.55, -24.65),
	], 0.036, dark, m_pin, Vector3.ZERO, true)

	PhysicalLinkKit.build_conduit_run(self, "CouplingConduit", [
		Vector3(8.15, 0.05, -29.05),
		Vector3(8.15, 0.05, -31.85),
		Vector3(-7.45, 0.05, -31.85),
		Vector3(-8.12, 0.05, -25.65),
		Vector3(-8.12, 1.35, -25.65),
	], 0.036, dark, m_coupling, Vector3.ZERO, true)

	# Flush 3-Lamp + Master Cabinet Display + Sequence Plaque on FanStartCabinet east face
	_build_fan_cabinet_panel(dark)

	_lamps["damper_ready"] = PhysicalLinkKit.build_status_lamp(self, "DamperStatusLamp", Vector3(8.20, 2.20, -31.50), 0.085, dark)
	_lamps["gov_ready"] = PhysicalLinkKit.build_status_lamp(self, "GovernorStatusLamp", Vector3(-8.20, 2.20, -21.65), 0.085, dark)
	_dials["gov"] = PhysicalLinkKit.build_live_dial(self, "GovernorPressureDial", Vector3(-8.08, 1.92, -21.65), Vector3(0.0, 90.0, 0.0), 0.22, Act1Ventilation.PRESSURE_MIN, 1.0)
	_dials["damper"] = PhysicalLinkKit.build_live_dial(self, "DamperPressureDial", Vector3(8.12, 2.08, -31.50), Vector3(0.0, -90.0, 0.0), 0.22, Act1Ventilation.PRESSURE_MIN, 1.0)
	PhysicalLinkKit.build_conduit_run(self, "DamperPressurePipe", [
		Vector3(9.80, 3.60, -28.20),
		Vector3(9.80, 0.08, -28.20),
		Vector3(9.60, 0.08, -31.40),
		Vector3(8.55, 0.08, -31.50),
		Vector3(8.55, 1.85, -31.50),
	], 0.044, copper, m_wind, Vector3.ZERO, true)
	PhysicalLinkKit.build_diagram_plaque(self, "VentEndSchematic", Vector3(8.12, 1.72, -31.80), Vector3(0.0, -90.0, 0.0), Vector2(0.76, 0.30), [
		{"num": 1, "icon": "fan", "col": Color(0.32, 0.90, 1.0)},
		{"num": 2, "icon": "gauge", "col": Color(1.0, 0.68, 0.22)},
		{"num": 3, "icon": "damper", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.32, 0.88, 1.0))

	# ------------------------------------------------------------------
	# 4. VentComplete -> Station Chock -> ParkingBrake -> Cargo -> Launch
	# ------------------------------------------------------------------
	var m_vent_sta := PhysicalLinkKit.make_flow_material()
	var m_chock_brk := PhysicalLinkKit.make_flow_material()
	var m_brk_cgo := PhysicalLinkKit.make_flow_material()
	_mats["vent_station"] = m_vent_sta
	_mats["chock_brake"] = m_chock_brk
	_mats["brake_cargo"] = m_brk_cgo

	PhysicalLinkKit.build_conduit_run(self, "VentToChockWire", [
		Vector3(-4.20, 0.05, -35.80),
		Vector3(-4.80, 0.05, -39.50),
		Vector3(-5.62, 0.05, -45.50),
		Vector3(-5.62, 0.05, -46.15),
		Vector3(-5.62, 0.45, -46.15),
	], 0.038, dark, m_vent_sta, Vector3.ZERO, true)
	_lamps["chock"] = PhysicalLinkKit.build_status_lamp(self, "ChockInterlockLamp", Vector3(-5.62, 0.95, -46.25), 0.075, dark)

	PhysicalLinkKit.build_conduit_run(self, "ChockToBrakeWire", [
		Vector3(-5.62, 0.05, -46.25),
		Vector3(-5.62, 0.05, -42.50),
		Vector3(-2.60, 0.05, -40.80),
		Vector3(5.10, 0.05, -40.80),
		Vector3(5.35, 1.56, -42.40),
		Vector3(6.40, 1.56, -49.50),
	], 0.038, dark, m_chock_brk, Vector3.ZERO, true)
	_lamps["brake"] = PhysicalLinkKit.build_status_lamp(self, "BrakeInterlockLamp", Vector3(6.40, 2.95, -49.65), 0.08, dark)

	PhysicalLinkKit.build_conduit_run(self, "BrakeToCargoWire", [
		Vector3(6.40, 1.56, -49.80),
		Vector3(5.05, 1.56, -49.80),
		Vector3(5.05, 1.56, -48.60),
	], 0.038, dark, m_brk_cgo, Vector3.ZERO, true)
	_lamps["cargo"] = PhysicalLinkKit.build_status_lamp(self, "CargoLockLamp", Vector3(5.05, 2.25, -48.60), 0.08, dark)

	_build_departure_panel(dark)

	# Grounding skirts, catenary hoses, steam vents, ambient motes & soft light shafts
	ArtAtmosphereKit.build_ground_skirt(self, "EntryLatchSkirt", Vector3(2.72, 0.0, 9.25), Vector2(1.4, 1.4))
	ArtAtmosphereKit.build_ground_skirt(self, "PowerSocketSkirt", Vector3(4.25, 0.0, -6.00), Vector2(3.6, 2.2))
	ArtAtmosphereKit.build_ground_skirt(self, "GovCabSkirt", Vector3(-8.12, 0.0, -21.65), Vector2(2.0, 2.0))
	ArtAtmosphereKit.build_ground_skirt(self, "StartCabSkirt", Vector3(-8.12, 0.0, -24.80), Vector2(2.4, 2.2))
	ArtAtmosphereKit.build_ground_skirt(self, "DamperCabSkirt", Vector3(8.12, 0.0, -31.50), Vector2(2.2, 2.2))
	ArtAtmosphereKit.build_ground_skirt(self, "RotorPedSkirt", Vector3(7.65, 0.0, -23.55), Vector2(1.5, 1.5))
	ArtAtmosphereKit.build_ground_skirt(self, "CouplingPedSkirt", Vector3(8.15, 0.0, -29.05), Vector2(1.5, 1.5))
	ArtAtmosphereKit.build_gravel_cluster(self, "VentRotorGravel", Vector3(7.65, 0.0, -23.55), 0.78, 8, 1001)
	ArtAtmosphereKit.build_gravel_cluster(self, "VentCouplingGravel", Vector3(8.15, 0.0, -29.05), 0.78, 8, 1002)
	ArtAtmosphereKit.build_catenary_hose(self, "PowerConsoleHose", Vector3(3.35, 1.45, -6.10), Vector3(5.15, 1.45, -6.10), 0.30, 0.025)
	ArtAtmosphereKit.build_catenary_hose(self, "VentCabHose", Vector3(-8.05, 1.35, -22.20), Vector3(-8.05, 1.35, -24.20), 0.26, 0.025)
	ArtAtmosphereKit.build_catenary_hose(self, "DamperManifoldHose", Vector3(8.25, 1.75, -31.20), Vector3(8.25, 1.45, -29.30), 0.28, 0.025)
	ArtAtmosphereKit.build_steam_vent(self, "VentManifoldSteam", Vector3(8.40, 2.60, -29.80), Vector3(-0.30, 1.0, -0.20), Color(0.84, 0.90, 0.94), 10, 0.28)
	ArtAtmosphereKit.build_ambient_motes(self, "VentHallMotes", Vector3(0.0, 2.8, -26.0), Vector3(7.0, 2.2, 5.5), Color(0.45, 0.85, 1.0), 22, 0.055)
	ArtAtmosphereKit.build_godray_cone(self, "VentSkylightShaft", Vector3(6.2, 10.5, -26.8), Vector3(0.18, -1.0, 0.08), 10.2, 0.9, 2.8, Color(1.0, 0.78, 0.48), 0.10)
	ArtAtmosphereKit.build_godray_cone(self, "FanOutletShaft", Vector3(8.5, 4.6, -27.0), Vector3(-1.0, -0.18, 0.0), 5.5, 1.1, 2.2, Color(0.28, 0.85, 1.0), 0.09)


func _build_fan_cabinet_panel(body_mat: Material) -> void:
	var panel := Node3D.new()
	panel.name = "FanInterlockPanel"
	panel.position = Vector3(-8.08, 0.0, -25.20)
	panel.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	add_child(panel)

	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.12, 0.24, 0.08)
	strip.mesh = sm
	strip.position = Vector3(0.0, 2.34, 0.0)
	strip.material_override = body_mat
	panel.add_child(strip)

	_lamps["fan_pwr"] = PhysicalLinkKit.build_status_lamp(panel, "FanPwrLamp", Vector3(-0.38, 2.50, 0.02), 0.068, body_mat)
	_lamps["fan_pin"] = PhysicalLinkKit.build_status_lamp(panel, "FanPinLamp", Vector3(-0.13, 2.50, 0.02), 0.068, body_mat)
	_lamps["fan_cpl"] = PhysicalLinkKit.build_status_lamp(panel, "FanCplLamp", Vector3(0.13, 2.50, 0.02), 0.068, body_mat)
	_lamps["fan_run"] = PhysicalLinkKit.build_status_lamp(panel, "FanMasterLamp", Vector3(0.38, 2.50, 0.02), 0.082, body_mat)

	PhysicalLinkKit.build_diagram_plaque(panel, "VentStartSchematic", Vector3(0.0, 1.72, 0.04), Vector3.ZERO, Vector2(0.96, 0.34), [
		{"num": 1, "icon": "plug", "col": Color(0.32, 0.90, 1.0)},
		{"num": 2, "icon": "pin", "col": Color(1.0, 0.68, 0.22)},
		{"num": 3, "icon": "clamp", "col": Color(1.0, 0.68, 0.22)},
		{"num": 4, "icon": "fan", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.32, 0.88, 1.0))


func _build_departure_panel(body_mat: Material) -> void:
	var panel := Node3D.new()
	panel.name = "DepartureInterlockPanel"
	panel.position = Vector3(5.45, 1.52, -49.15)
	panel.rotation_degrees = Vector3(0.0, -68.0, 0.0)
	add_child(panel)

	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.18, 1.48, 0.22)
	post.mesh = pm
	post.position = Vector3(0.0, 0.74, 0.0)
	post.material_override = body_mat
	panel.add_child(post)

	_lamps["dep_vent"] = PhysicalLinkKit.build_status_lamp(panel, "DepVentLamp", Vector3(-0.39, 1.54, 0.0), 0.062, body_mat)
	_lamps["dep_chock"] = PhysicalLinkKit.build_status_lamp(panel, "DepChockLamp", Vector3(-0.13, 1.54, 0.0), 0.062, body_mat)
	_lamps["dep_brake"] = PhysicalLinkKit.build_status_lamp(panel, "DepBrakeLamp", Vector3(0.13, 1.54, 0.0), 0.062, body_mat)
	_lamps["dep_cargo"] = PhysicalLinkKit.build_status_lamp(panel, "DepCargoLamp", Vector3(0.39, 1.54, 0.0), 0.062, body_mat)

	PhysicalLinkKit.build_diagram_plaque(panel, "DepartureSchematic", Vector3(0.0, 1.05, 0.12), Vector3.ZERO, Vector2(1.02, 0.38), [
		{"num": 1, "icon": "pin", "col": Color(1.0, 0.56, 0.18)},
		{"num": 2, "icon": "brake", "col": Color(1.0, 0.72, 0.22)},
		{"num": 3, "icon": "clamp", "col": Color(0.32, 0.90, 1.0)},
		{"num": 4, "icon": "lever", "col": Color(0.28, 0.96, 0.72)},
	], Color(1.0, 0.68, 0.22))


func refresh(flags: Dictionary, builder: Object) -> void:
	var debris: bool = bool(flags.get("debris_cleared", false))
	var latch: bool = bool(flags.get("latch_released", false))
	var pow_dock: bool = bool(flags.get("power_docked", false))
	var pow_seat: bool = bool(flags.get("power_seated", false))
	var pow_clamp: bool = bool(flags.get("power_clamped", false))
	var pow_ready: bool = bool(flags.get("power_ready", false))
	var pin_rel: bool = bool(flags.get("rotor_lock_released", false))
	var cpl_eng: bool = bool(flags.get("coupling_engaged", false))
	var fan_run: bool = bool(flags.get("fan_started", false))
	var damper_open: bool = bool(flags.get("damper_open", false))
	var vent_done: bool = bool(flags.get("vent_complete", false))
	var chock_rem: bool = bool(flags.get("chock_removed", false))
	var brk_rel: bool = bool(flags.get("brake_released", false))
	var cgo_sec: bool = bool(flags.get("cargo_secured", false))
	var pressure_ok := false
	var pressure_val := 0.0
	if builder != null:
		var vent_obj: Variant = builder.get("vent")
		if vent_obj != null:
			pressure_val = float((vent_obj as Object).get("pressure"))
			pressure_ok = pressure_val >= Act1Ventilation.PRESSURE_MIN

	PhysicalLinkKit.set_dial_value(_dials.get("gov") as Node3D, pressure_val)
	PhysicalLinkKit.set_dial_value(_dials.get("damper") as Node3D, pressure_val)

	var sig := "%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s" % [
		debris, latch, pow_dock, pow_seat, pow_clamp, pow_ready,
		pin_rel, cpl_eng, fan_run, damper_open, vent_done,
		pressure_ok, chock_rem, brk_rel, cgo_sec
	]
	if sig == _last_sig:
		return
	_last_sig = sig

	# Entry
	PhysicalLinkKit.set_flow_state(_mats.get("entry_interlock") as ShaderMaterial,
		"active" if latch else ("ready" if debris else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("entry_latch") as StandardMaterial3D,
		"active" if latch else ("ready" if debris else "locked"))

	# Power room
	PhysicalLinkKit.set_lamp_state(_lamps.get("pow_dock") as StandardMaterial3D,
		"active" if pow_seat else ("ready" if pow_dock else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("pow_clamp") as StandardMaterial3D,
		"active" if pow_clamp else ("ready" if pow_seat else "locked"))
	PhysicalLinkKit.set_flow_state(_mats.get("power_bus") as ShaderMaterial,
		"active" if pow_ready else ("ready" if pow_seat else "locked"))

	# Vent Hall
	PhysicalLinkKit.set_flow_state(_mats.get("rotor_pin") as ShaderMaterial, "active" if pin_rel else "locked")
	PhysicalLinkKit.set_flow_state(_mats.get("coupling") as ShaderMaterial, "active" if cpl_eng else ("ready" if pin_rel else "locked"))
	PhysicalLinkKit.set_flow_state(_mats.get("wind_pressure") as ShaderMaterial,
		"active" if vent_done else ("ready" if (fan_run and damper_open) else ("amber" if fan_run else "locked")))

	PhysicalLinkKit.set_lamp_state(_lamps.get("fan_pwr") as StandardMaterial3D, "active" if pow_ready else "locked")
	PhysicalLinkKit.set_lamp_state(_lamps.get("fan_pin") as StandardMaterial3D, "active" if pin_rel else "locked")
	PhysicalLinkKit.set_lamp_state(_lamps.get("fan_cpl") as StandardMaterial3D, "active" if cpl_eng else ("ready" if pin_rel else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("fan_run") as StandardMaterial3D,
		"active" if vent_done else ("ready" if fan_run else ("amber" if (pow_ready and pin_rel and cpl_eng) else "locked")))
	PhysicalLinkKit.set_lamp_state(_lamps.get("damper_ready") as StandardMaterial3D,
		"active" if (damper_open and fan_run) else ("ready" if fan_run else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("gov_ready") as StandardMaterial3D,
		"active" if pressure_ok else ("ready" if fan_run else "locked"))

	# Departure Station
	PhysicalLinkKit.set_flow_state(_mats.get("vent_station") as ShaderMaterial, "active" if vent_done else "locked")
	PhysicalLinkKit.set_flow_state(_mats.get("chock_brake") as ShaderMaterial, "active" if chock_rem else ("ready" if vent_done else "locked"))
	PhysicalLinkKit.set_flow_state(_mats.get("brake_cargo") as ShaderMaterial, "active" if brk_rel else ("ready" if chock_rem else "locked"))

	PhysicalLinkKit.set_lamp_state(_lamps.get("chock") as StandardMaterial3D, "active" if chock_rem else ("ready" if vent_done else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("brake") as StandardMaterial3D, "active" if brk_rel else ("ready" if chock_rem else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("cargo") as StandardMaterial3D, "active" if cgo_sec else ("ready" if brk_rel else "locked"))

	PhysicalLinkKit.set_lamp_state(_lamps.get("dep_vent") as StandardMaterial3D, "active" if vent_done else "locked")
	PhysicalLinkKit.set_lamp_state(_lamps.get("dep_chock") as StandardMaterial3D, "active" if chock_rem else ("ready" if vent_done else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("dep_brake") as StandardMaterial3D, "active" if brk_rel else ("ready" if chock_rem else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("dep_cargo") as StandardMaterial3D, "active" if cgo_sec else ("ready" if brk_rel else "locked"))
