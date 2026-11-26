class_name Act5PhysicalLinks
extends Node3D

const PhysicalLinkKit := preload("res://scripts/core/physical_link_kit.gd")
const ArtAtmosphereKit := preload("res://scripts/core/art_atmosphere_kit.gd")

## Act 5 real-time physical conduits, counterweight-to-lock hydraulic feedback,
## damper->isolation->data->exit interlock bus, and non-floating schematic plaques.

var _mats: Dictionary = {}
var _lamps: Dictionary = {}
var _dials: Dictionary = {}
var _level: LevelBuilder = null


func build(lvl: LevelBuilder) -> void:
	name = "Act5PhysicalLinks"
	_level = lvl

	var copper := MatLib.copper()
	var dark := MatLib.dark_steel()

	# 1. Dynamic coop machine conduits (replacing static glow pipes in _build_coop_links)
	var m_brake := PhysicalLinkKit.make_flow_material()
	var m_stab_w := PhysicalLinkKit.make_flow_material()
	var m_stab_e := PhysicalLinkKit.make_flow_material()
	var m_damper := PhysicalLinkKit.make_flow_material()
	_mats["brake"] = m_brake
	_mats["stab_w"] = m_stab_w
	_mats["stab_e"] = m_stab_e
	_mats["damper"] = m_damper

	PhysicalLinkKit.build_conduit_run(self, "BrakeFlow", [
		Vector3(-10.9, 0.80, -7.4),
		Vector3(-9.4, 0.80, -6.0),
		Vector3(-7.4, 0.80, -4.4),
		Vector3(-5.9, 0.80, -3.2),
	], 0.0, null, m_brake, Vector3.ZERO, false)

	PhysicalLinkKit.build_conduit_run(self, "StabilizerFlowW", [
		Vector3(-6.6, 0.72, -7.8),
		Vector3(-5.4, 0.72, -6.4),
		Vector3(-3.9, 0.72, -5.3),
	], 0.0, null, m_stab_w, Vector3.ZERO, false)

	PhysicalLinkKit.build_conduit_run(self, "StabilizerFlowE", [
		Vector3(6.6, 0.72, -7.8),
		Vector3(5.4, 0.72, -6.4),
		Vector3(3.9, 0.72, -5.3),
	], 0.0, null, m_stab_e, Vector3.ZERO, false)

	var iso_pos: Vector3 = lvl.isolation.position if lvl.isolation != null else Vector3(12.6, 0.0, -10.8)
	var data_pos: Vector3 = lvl.data_plinth.position if lvl.data_plinth != null else Vector3(-3.0, 0.0, -12.6)

	PhysicalLinkKit.build_conduit_run(self, "DamperFlow", [
		Vector3(7.4, 0.66, -4.2),
		iso_pos + Vector3(-3.2, 0.66, 4.0),
		iso_pos + Vector3(-1.2, 0.66, 1.6),
	], 0.0, null, m_damper, Vector3.ZERO, false)

	# 2. WeightCarts (x=+-5.4, y=2.08, z=1.2) -> BalanceGauge/LockRig Console (0, 0.65, 4.4)
	var m_cart_l := PhysicalLinkKit.make_flow_material()
	var m_cart_r := PhysicalLinkKit.make_flow_material()
	var m_bal_lock := PhysicalLinkKit.make_flow_material()
	_mats["cart_l"] = m_cart_l
	_mats["cart_r"] = m_cart_r
	_mats["bal_lock"] = m_bal_lock

	PhysicalLinkKit.build_conduit_run(self, "CartFeedbackL", [
		Vector3(-5.0, 2.08, 1.85),
		Vector3(-5.0, 0.14, 2.15),
		Vector3(-2.6, 0.14, 3.65),
		Vector3(-0.45, 0.14, 4.35),
		Vector3(-0.45, 0.62, 4.35),
	], 0.045, copper, m_cart_l, Vector3(0.0, 0.032, 0.0), true)

	PhysicalLinkKit.build_conduit_run(self, "CartFeedbackR", [
		Vector3(5.0, 2.08, 1.85),
		Vector3(5.0, 0.14, 2.15),
		Vector3(2.6, 0.14, 3.65),
		Vector3(0.45, 0.14, 4.35),
		Vector3(0.45, 0.62, 4.35),
	], 0.045, copper, m_cart_r, Vector3(0.0, 0.032, 0.0), true)

	PhysicalLinkKit.build_conduit_run(self, "BalanceToLockRams", [
		Vector3(0.0, 0.72, 4.15),
		Vector3(0.0, 0.76, 2.85),
	], 0.055, copper, m_bal_lock, Vector3(0.0, 0.040, 0.0), false)

	_lamps["lock_ready"] = PhysicalLinkKit.build_status_lamp(self, "LockBalanceReadyLamp", Vector3(0.76, 2.02, 4.62), 0.08, dark)

	# 3. ExtractionIsolationRig + NavigationDataPlinth -> ExitInterlockBox -> ExitBlastDoor
	var m_iso_bus := PhysicalLinkKit.make_flow_material()
	var m_data_bus := PhysicalLinkKit.make_flow_material()
	var m_exit_feed := PhysicalLinkKit.make_flow_material()
	_mats["iso_bus"] = m_iso_bus
	_mats["data_bus"] = m_data_bus
	_mats["exit_feed"] = m_exit_feed

	PhysicalLinkKit.build_conduit_run(self, "IsoToExitBus", [
		iso_pos + Vector3(-2.6, 0.22, -1.6),
		Vector3(2.0, 0.22, -12.6),
		Vector3(-9.8, 0.22, -11.4),
		Vector3(-9.8, 0.22, 1.85),
		Vector3(-13.8, 0.22, 1.85),
		Vector3(-14.78, 0.22, 0.65),
		Vector3(-14.78, 1.18, 0.52),
	], 0.048, copper, m_iso_bus, Vector3.ZERO, true)

	PhysicalLinkKit.build_conduit_run(self, "DataToExitBus", [
		data_pos + Vector3(0.0, 0.22, 0.0),
		Vector3(-9.4, 0.22, -11.1),
		Vector3(-9.4, 0.22, 2.15),
		Vector3(-13.6, 0.22, 2.15),
		Vector3(-14.72, 0.22, 0.78),
		Vector3(-14.72, 1.45, 0.54),
	], 0.045, copper, m_data_bus, Vector3.ZERO, true)

	PhysicalLinkKit.build_conduit_run(self, "ExitDoorFeed", [
		Vector3(-14.55, 1.85, 0.45),
		Vector3(-15.55, 2.35, -0.15),
	], 0.06, copper, m_exit_feed, Vector3.ZERO, false)

	_build_exit_interlock_box(Vector3(-14.55, 0.0, 0.45), dark)

	# 4. Non-floating schematic plaques (observation balcony + LockRig + Isolation/Damper)
	PhysicalLinkKit.build_diagram_plaque(self, "BalconyOverviewSchematic", Vector3(1.85, 5.18, 14.32), Vector3(-12.0, 0.0, 0.0), Vector2(1.10, 0.46), [
		{"num": 1, "icon": "cart", "col": Color(1.0, 0.74, 0.24)},
		{"num": 2, "icon": "lock", "col": Color(0.32, 0.90, 1.0)},
		{"num": 3, "icon": "damper", "col": Color(1.0, 0.42, 0.20)},
		{"num": 4, "icon": "door", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.32, 0.88, 1.0))

	PhysicalLinkKit.build_diagram_plaque(self, "LockRigSchematic", Vector3(0.0, 0.96, 4.92), Vector3(-18.0, 0.0, 0.0), Vector2(0.86, 0.34), [
		{"num": 1, "icon": "cart", "col": Color(1.0, 0.74, 0.24)},
		{"num": 2, "icon": "balance", "col": Color(0.32, 0.90, 1.0)},
		{"num": 3, "icon": "lock", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.32, 0.88, 1.0))
	_dials["balance"] = PhysicalLinkKit.build_live_dial(self, "LockBalanceDial", Vector3(0.76, 1.72, 4.62), Vector3(-10.0, 0.0, 0.0), 0.20, 0.35, 0.65)

	PhysicalLinkKit.build_diagram_plaque(self, "IsolationOrderSchematic", iso_pos + Vector3(0.0, 1.92, 2.08), Vector3(0.0, 0.0, 0.0), Vector2(0.92, 0.38), [
		{"num": 1, "icon": "lock", "col": Color(0.32, 0.90, 1.0)},
		{"num": 2, "icon": "damper", "col": Color(1.0, 0.68, 0.20)},
		{"num": 3, "icon": "plug", "col": Color(0.28, 0.96, 0.72)},
	], Color(1.0, 0.68, 0.20))

	# Grounding skirts, gravel, catenary hoses, steam vents & core shafts
	ArtAtmosphereKit.build_ground_skirt(self, "LockRigSkirt", Vector3(0.0, 0.0, 4.4), Vector2(3.2, 2.2))
	ArtAtmosphereKit.build_ground_skirt(self, "DamperSkirt", Vector3(6.4, 0.0, -4.4), Vector2(2.8, 2.6))
	ArtAtmosphereKit.build_gravel_cluster(self, "DamperGravel", Vector3(6.4, 0.0, -4.4), 1.45, 10, 5001)
	ArtAtmosphereKit.build_ground_skirt(self, "IsolationSkirt", iso_pos, Vector2(4.2, 3.6))
	ArtAtmosphereKit.build_gravel_cluster(self, "IsolationGravel", iso_pos, 2.1, 12, 5002)
	ArtAtmosphereKit.build_ground_skirt(self, "DataPlinthSkirt", data_pos, Vector2(2.2, 2.2))
	ArtAtmosphereKit.build_ground_skirt(self, "ExitBoxSkirt", Vector3(-14.55, 0.0, 0.45), Vector2(1.8, 1.4))
	ArtAtmosphereKit.build_ground_skirt(self, "BrakeSkirt", Vector3(-11.8, 0.0, -7.4), Vector2(2.8, 2.4))
	ArtAtmosphereKit.build_catenary_hose(self, "LockLeftHose", Vector3(-1.1, 0.82, 4.4), Vector3(-1.6, 0.12, 4.1), 0.18, 0.024)
	ArtAtmosphereKit.build_catenary_hose(self, "LockRightHose", Vector3(1.1, 0.82, 4.4), Vector3(1.6, 0.12, 4.1), 0.18, 0.024)
	ArtAtmosphereKit.build_catenary_hose(self, "ExitBoxHose", Vector3(-14.68, 1.55, 0.35), Vector3(-15.35, 1.25, 0.65), 0.22, 0.024)
	ArtAtmosphereKit.build_catenary_hose(self, "DamperHose", Vector3(7.1, 1.55, -4.4), Vector3(7.6, 0.65, -4.9), 0.24, 0.025)
	ArtAtmosphereKit.build_steam_vent(self, "DamperExhaustSteam", Vector3(6.4, 1.85, -4.6), Vector3(0.15, 1.0, 0.0), Color(0.84, 0.90, 0.94), 10, 0.28)
	ArtAtmosphereKit.build_steam_vent(self, "IsolationExhaustSteam", iso_pos + Vector3(-1.2, 1.75, 0.2), Vector3(-0.2, 1.0, 0.15), Color(0.84, 0.90, 0.94), 10, 0.28)
	ArtAtmosphereKit.build_godray_cone(self, "CoreDomeShaft", Vector3(0.0, 12.5, 0.0), Vector3(-0.08, -1.0, -0.05), 11.5, 1.6, 4.2, Color(0.32, 0.86, 1.0), 0.10)
	ArtAtmosphereKit.build_godray_cone(self, "ExitPortalShaft", Vector3(-14.8, 4.2, -2.0), Vector3(-0.35, -1.0, 0.0), 4.2, 0.9, 1.9, Color(0.85, 0.95, 1.0), 0.09)
	ArtAtmosphereKit.build_ambient_motes(self, "Act5CoreSpores", Vector3(0.0, 3.2, -1.0), Vector3(11.0, 2.8, 10.0), Color(0.38, 0.88, 1.0), 28, 0.058)


func _build_exit_interlock_box(pos: Vector3, body_mat: Material) -> void:
	var box := Node3D.new()
	box.name = "ExitInterlockBox"
	box.position = pos
	box.rotation_degrees = Vector3(0.0, 72.0, 0.0)
	add_child(box)

	var cab := MeshInstance3D.new()
	cab.name = "InterlockCab"
	var cm := BoxMesh.new()
	cm.size = Vector3(1.02, 1.88, 0.38)
	cab.mesh = cm
	cab.position = Vector3(0.0, 0.94, 0.0)
	cab.material_override = body_mat
	box.add_child(cab)
	# 机柜是玩家会贴上去按 E 的实体：没有碰撞时人物会直接穿进箱体
	# （test_collision_audit 的“可达大体积可见体必须有碰撞”会判红）。
	var cab_body := StaticBody3D.new()
	cab_body.name = "InterlockCabBody"
	cab_body.collision_layer = 1
	cab_body.collision_mask = 0
	var cab_shape := CollisionShape3D.new()
	var cab_box := BoxShape3D.new()
	cab_box.size = Vector3(1.02, 1.88, 0.38)
	cab_shape.shape = cab_box
	cab_shape.position = Vector3(0.0, 0.94, 0.0)
	cab_body.add_child(cab_shape)
	box.add_child(cab_body)

	_lamps["exit_iso"] = PhysicalLinkKit.build_status_lamp(box, "ExitLamp_Iso", Vector3(-0.24, 1.62, 0.21), 0.075, body_mat)
	_lamps["exit_data"] = PhysicalLinkKit.build_status_lamp(box, "ExitLamp_Data", Vector3(0.24, 1.62, 0.21), 0.075, body_mat)
	_lamps["exit_master"] = PhysicalLinkKit.build_status_lamp(box, "ExitLamp_Master", Vector3(0.0, 1.92, 0.0), 0.10, body_mat)

	PhysicalLinkKit.build_diagram_plaque(box, "ExitOrderSchematic", Vector3(0.0, 1.02, 0.20), Vector3.ZERO, Vector2(0.88, 0.36), [
		{"num": 1, "icon": "plug", "col": Color(1.0, 0.66, 0.22)},
		{"num": 2, "icon": "crystal", "col": Color(0.32, 0.90, 1.0)},
		{"num": 3, "icon": "door", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.28, 0.96, 0.72))


func refresh(capturable: bool, locked: bool) -> void:
	if _level == null:
		return
	# 1. Brake
	if _level.brake != null:
		var b_state := "active" if _level.brake.latched else ("ready" if _level.brake.pressure > 0.08 else "idle_dim")
		PhysicalLinkKit.set_flow_state(_mats.get("brake") as ShaderMaterial, b_state)
	# 2. Stabilizers
	if _level.stabilizers.size() >= 2:
		for idx: int in range(2):
			var stab := _level.stabilizers[idx]
			var key := "stab_w" if idx == 0 else "stab_e"
			var st_state := "active" if stab.latched else ("ready" if stab.extension > 0.05 else "idle_dim")
			PhysicalLinkKit.set_flow_state(_mats.get(key) as ShaderMaterial, st_state)
	# 3. Damper -> Isolation
	var damp_ok := _level.damper != null and _level.damper.latched_flag
	var damp_state := "active" if damp_ok else ("ready" if (_level.damper != null and _level.damper.pressure > 0.08) else ("locked" if locked else "idle_dim"))
	PhysicalLinkKit.set_flow_state(_mats.get("damper") as ShaderMaterial, damp_state)
	# 4. Counterweight carts -> BalanceGauge -> LockRig
	var l_p := _level.left_cart.get_p() if _level.left_cart != null else 0.12
	var r_p := _level.right_cart.get_p() if _level.right_cart != null else 0.88
	var sym_err := absf((l_p + r_p) - 1.0)
	var net_val := _level.core.get_net() if _level.core != null else (r_p - (1.0 - l_p))
	PhysicalLinkKit.set_dial_value(_dials.get("balance") as Node3D, clampf(0.5 + net_val * 0.6, 0.0, 1.0))
	PhysicalLinkKit.set_flow_state(_mats.get("cart_l") as ShaderMaterial, "active" if (locked or capturable or sym_err < 0.18) else "ready", Color(0.26, 0.92, 1.0) if (capturable or locked) else Color(1.0, 0.68, 0.20))
	PhysicalLinkKit.set_flow_state(_mats.get("cart_r") as ShaderMaterial, "active" if (locked or capturable or sym_err < 0.18) else "ready", Color(0.26, 0.92, 1.0) if (capturable or locked) else Color(1.0, 0.68, 0.20))
	var bal_state := "active" if (locked or capturable) else "locked"
	PhysicalLinkKit.set_flow_state(_mats.get("bal_lock") as ShaderMaterial, bal_state)
	PhysicalLinkKit.set_lamp_state(_lamps.get("lock_ready") as StandardMaterial3D, bal_state)
	# 5. Isolation + Data -> ExitDoor
	var iso_done := _level.isolation != null and _level.isolation.separated_flag
	var data_done := _level.data_plinth != null and _level.data_plinth.taken
	PhysicalLinkKit.set_flow_state(_mats.get("iso_bus") as ShaderMaterial, "active" if iso_done else ("surge" if locked else "locked"))
	PhysicalLinkKit.set_flow_state(_mats.get("data_bus") as ShaderMaterial, "active" if data_done else ("ready" if iso_done else "locked"))
	var exit_ok := iso_done and data_done
	PhysicalLinkKit.set_flow_state(_mats.get("exit_feed") as ShaderMaterial, "active" if exit_ok else "locked")
	PhysicalLinkKit.set_lamp_state(_lamps.get("exit_iso") as StandardMaterial3D, "active" if iso_done else "locked")
	PhysicalLinkKit.set_lamp_state(_lamps.get("exit_data") as StandardMaterial3D, "active" if data_done else ("ready" if iso_done else "locked"))
	PhysicalLinkKit.set_lamp_state(_lamps.get("exit_master") as StandardMaterial3D, "active" if exit_ok else "locked")
