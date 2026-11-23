class_name Act4PhysicalLinks
extends Node3D

const PhysicalLinkKit := preload("res://scripts/core/physical_link_kit.gd")
const ArtAtmosphereKit := preload("res://scripts/core/art_atmosphere_kit.gd")

## Act 4 physical waveguides, memory->gate power buses, junction indicators,
## and non-floating schematic plaques so every mechanical dependency is legible
## in 3D space without relying on HUD guesses or floating 3D text.

var _mats: Dictionary = {}
var _lamps: Dictionary = {}
var _game: Node = null


func build(game_node: Node) -> void:
	name = "Act4PhysicalLinks"
	_game = game_node

	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = Color(0.14, 0.15, 0.17)
	jacket.metallic = 0.65
	jacket.roughness = 0.52

	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color(0.48, 0.27, 0.14)
	copper.metallic = 0.78
	copper.roughness = 0.40

	# 1. Floor/wall resonance waveguide channels linking bell -> fixed/relay -> memory crystals
	var bell_p := R04LevelBuilder.BELL_BASE
	var f1_p := R04LevelBuilder.F1_BASE
	var f2_p := R04LevelBuilder.F2_BASE
	var m1_p := R04LevelBuilder.M1_BASE
	var w1_p := R04LevelBuilder.W1_BASE
	var w2_p := R04LevelBuilder.W2_BASE
	var b1_p := R04LevelBuilder.B1_POSITION
	var w3_p := R04LevelBuilder.W3_BASE
	var m2_p := R04LevelBuilder.M2_BASE
	var b3_p := R04LevelBuilder.B3_POSITION
	var t2_p := R04LevelBuilder.T2_BASE
	var m3_p := R04LevelBuilder.M3_BASE

	var m_east := PhysicalLinkKit.make_flow_material(Color(0.24, 0.90, 1.0), 0.55, 0.55, 8.0)
	_mats["wg_east"] = m_east
	PhysicalLinkKit.build_conduit_run(self, "Waveguide_East", [
		Vector3(bell_p.x, 0.04, bell_p.z),
		Vector3(f1_p.x, 0.04, f1_p.z),
		Vector3(f2_p.x, 0.04, f2_p.z),
		Vector3(10.1, 0.04, -10.8),
		Vector3(10.1, 2.04, -11.4),
		Vector3(m1_p.x, 2.04, m1_p.z),
	], 0.045, copper, m_east, Vector3(0.0, 0.025, 0.0), false)

	var m_west_in := PhysicalLinkKit.make_flow_material(Color(0.24, 0.90, 1.0), 0.55, 0.55, 8.0)
	_mats["wg_west_in"] = m_west_in
	PhysicalLinkKit.build_conduit_run(self, "Waveguide_WestIn", [
		Vector3(bell_p.x, 0.04, bell_p.z),
		Vector3(w1_p.x, 0.04, w1_p.z),
		Vector3(w2_p.x, 0.04, w2_p.z),
		Vector3(b1_p.x, 0.04, b1_p.z),
	], 0.045, copper, m_west_in, Vector3(0.0, 0.025, 0.0), false)

	var m_west_out := PhysicalLinkKit.make_flow_material(Color(0.95, 0.24, 0.14), 0.25, 0.0, 8.0)
	_mats["wg_west_out"] = m_west_out
	PhysicalLinkKit.build_conduit_run(self, "Waveguide_WestOut", [
		Vector3(b1_p.x, 0.04, b1_p.z),
		Vector3(w3_p.x, 0.04, w3_p.z),
		Vector3(m2_p.x, 0.04, m2_p.z),
	], 0.045, copper, m_west_out, Vector3(0.0, 0.025, 0.0), false)

	var m_up_in := PhysicalLinkKit.make_flow_material(Color(0.18, 0.52, 0.62), 0.30, 0.25, 8.0)
	_mats["wg_upper_in"] = m_up_in
	PhysicalLinkKit.build_conduit_run(self, "Waveguide_UpperIn", [
		Vector3(m2_p.x, 0.04, m2_p.z),
		Vector3(-15.0, 0.04, -18.5),
		Vector3(-15.0, 3.44, -19.0),
		Vector3(b3_p.x, 3.44, b3_p.z),
	], 0.045, copper, m_up_in, Vector3(0.0, 0.025, 0.0), false)

	var m_up_out := PhysicalLinkKit.make_flow_material(Color(0.95, 0.24, 0.14), 0.25, 0.0, 8.0)
	_mats["wg_upper_out"] = m_up_out
	PhysicalLinkKit.build_conduit_run(self, "Waveguide_UpperOut", [
		Vector3(b3_p.x, 3.44, b3_p.z),
		Vector3(t2_p.x, 3.72, t2_p.z),
		Vector3(-5.8, 3.72, -24.2),
		Vector3(-5.8, 0.05, -24.8),
		Vector3(m3_p.x, 0.05, m3_p.z),
	], 0.045, copper, m_up_out, Vector3(0.0, 0.025, 0.0), false)

	# 2. Three-memory power bus -> GatePowerJunction -> ExitGate motor housing
	var j_pos := Vector3(2.45, 0.0, -21.85)
	_build_gate_junction(j_pos, jacket)

	var bus1 := PhysicalLinkKit.make_flow_material()
	var bus2 := PhysicalLinkKit.make_flow_material()
	var bus3 := PhysicalLinkKit.make_flow_material()
	var gate_feed := PhysicalLinkKit.make_flow_material()
	_mats["bus_m1"] = bus1
	_mats["bus_m2"] = bus2
	_mats["bus_m3"] = bus3
	_mats["gate_feed"] = gate_feed

	PhysicalLinkKit.build_conduit_run(self, "GateBus_M1", [
		Vector3(m1_p.x, 2.08, m1_p.z),
		Vector3(m1_p.x - 1.2, 0.04, m1_p.z - 0.6),
		Vector3(10.8, 0.04, -18.5),
		Vector3(6.2, 0.04, -22.2),
		Vector3(2.85, 0.04, -22.2),
		Vector3(2.58, 1.15, -21.95),
	], 0.046, jacket, bus1, Vector3.ZERO, true)

	PhysicalLinkKit.build_conduit_run(self, "GateBus_M2", [
		Vector3(m2_p.x, 0.55, m2_p.z),
		Vector3(m2_p.x + 0.5, 0.04, m2_p.z - 1.2),
		Vector3(-9.5, 0.04, -25.4),
		Vector3(2.15, 0.04, -25.4),
		Vector3(2.45, 0.04, -22.35),
		Vector3(2.45, 1.40, -21.95),
	], 0.046, jacket, bus2, Vector3.ZERO, true)

	PhysicalLinkKit.build_conduit_run(self, "GateBus_M3", [
		Vector3(m3_p.x, 0.12, m3_p.z),
		Vector3(-1.4, 0.04, -24.8),
		Vector3(2.05, 0.04, -24.8),
		Vector3(2.30, 0.04, -22.20),
		Vector3(2.32, 1.65, -21.95),
	], 0.046, jacket, bus3, Vector3.ZERO, true)

	PhysicalLinkKit.build_conduit_run(self, "GateMotorFeed", [
		Vector3(2.45, 1.92, -21.85),
		Vector3(2.85, 3.65, -22.25),
		Vector3(3.05, 4.72, -22.65),
	], 0.062, copper, gate_feed, Vector3.ZERO, true)

	# 3. Stanchion schematic plaque beside HammerRig console (non-floating, facing spawn)
	_build_bell_stand(Vector3(3.15, 0.0, -1.85), jacket)

	# 4. B1 & B3 alignment sightlines & lamps (empty=red, seated wrong-dir=amber, aligned=cyan)
	var m_b1_guide := PhysicalLinkKit.make_flow_material()
	var m_b3_guide := PhysicalLinkKit.make_flow_material()
	_mats["b1_guide"] = m_b1_guide
	_mats["b3_guide"] = m_b3_guide
	PhysicalLinkKit.build_conduit_run(self, "B1_AlignSightline", [
		Vector3(b1_p.x, 0.05, b1_p.z - 0.55),
		Vector3(b1_p.x + 1.25, 0.05, b1_p.z - 1.15),
	], 0.030, jacket, m_b1_guide, Vector3.ZERO, false)
	_lamps["b1_align"] = PhysicalLinkKit.build_status_lamp(self, "B1_AlignLamp", Vector3(b1_p.x, 0.72, b1_p.z - 0.65), 0.075, jacket)

	PhysicalLinkKit.build_conduit_run(self, "B3_AlignSightline", [
		Vector3(b3_p.x, 3.45, b3_p.z - 0.55),
		Vector3(b3_p.x + 1.20, 3.45, b3_p.z - 1.10),
	], 0.030, jacket, m_b3_guide, Vector3.ZERO, false)
	_lamps["b3_align"] = PhysicalLinkKit.build_status_lamp(self, "B3_AlignLamp", Vector3(b3_p.x, 4.12, b3_p.z - 0.65), 0.075, jacket)

	# Grounding skirts, catenary hose, godrays & crystal spores for Act 4
	ArtAtmosphereKit.build_ground_skirt(self, "GateHubSkirt", j_pos, Vector2(2.0, 2.0))
	ArtAtmosphereKit.build_gravel_cluster(self, "GateHubGravel", j_pos, 1.05, 10, 4001)
	ArtAtmosphereKit.build_ground_skirt(self, "B1CradleSkirt", Vector3(b1_p.x, 0.0, b1_p.z), Vector2(1.9, 1.9))
	ArtAtmosphereKit.build_gravel_cluster(self, "B1CradleGravel", Vector3(b1_p.x, 0.0, b1_p.z), 0.95, 10, 4002)
	ArtAtmosphereKit.build_catenary_hose(self, "GateHubRearHose", j_pos + Vector3(-0.35, 1.25, -0.15), j_pos + Vector3(0.35, 0.95, -0.15), 0.22, 0.025)
	ArtAtmosphereKit.build_godray_cone(self, "BellCrystalShaft", bell_p + Vector3(0.0, 6.2, 0.0), Vector3(0.05, -1.0, 0.10), 6.0, 0.7, 2.2, Color(0.32, 0.88, 1.0), 0.10)
	ArtAtmosphereKit.build_godray_cone(self, "ExitGateShaft", Vector3(0.0, 5.4, -22.5), Vector3(0.0, -1.0, 0.15), 5.2, 0.8, 2.0, Color(0.96, 0.78, 0.46), 0.09)
	ArtAtmosphereKit.build_ambient_motes(self, "Act4CrystalSpores", bell_p + Vector3(0.0, 2.2, -3.5), Vector3(5.5, 2.0, 6.0), Color(0.42, 0.88, 1.0), 26, 0.055)

	refresh()


func _build_gate_junction(pos: Vector3, body_mat: Material) -> void:
	var j := Node3D.new()
	j.name = "GatePowerJunction"
	j.position = pos
	j.rotation_degrees = Vector3(0.0, -35.0, 0.0)
	add_child(j)

	var pedestal := MeshInstance3D.new()
	pedestal.name = "JunctionCabinet"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.15, 1.92, 0.42)
	pedestal.mesh = bm
	pedestal.position = Vector3(0.0, 0.96, 0.0)
	pedestal.material_override = body_mat
	j.add_child(pedestal)

	for i: int in range(3):
		var lx := -0.34 + float(i) * 0.34
		_lamps["m%d" % (i + 1)] = PhysicalLinkKit.build_status_lamp(j, "BusLamp_M%d" % (i + 1), Vector3(lx, 1.68, 0.24), 0.08, body_mat)

	_lamps["gate_master"] = PhysicalLinkKit.build_status_lamp(j, "BusLamp_GateMaster", Vector3(0.0, 1.98, 0.0), 0.11, body_mat)

	PhysicalLinkKit.build_diagram_plaque(j, "GateSchematic", Vector3(0.0, 1.05, 0.22), Vector3.ZERO, Vector2(0.96, 0.42), [
		{"num": 1, "icon": "hammer", "col": Color(0.32, 0.90, 1.0)},
		{"num": 2, "icon": "crystal", "col": Color(0.72, 0.56, 1.0)},
		{"num": 3, "icon": "gate", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.32, 0.88, 1.0))


func _build_bell_stand(pos: Vector3, body_mat: Material) -> void:
	var stand := Node3D.new()
	stand.name = "BellOverviewStand"
	stand.position = pos
	stand.rotation_degrees = Vector3(0.0, -18.0, 0.0)
	add_child(stand)

	var post := MeshInstance3D.new()
	post.name = "OverviewPost"
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.08
	pm.height = 1.18
	post.mesh = pm
	post.position = Vector3(0.0, 0.59, 0.0)
	post.material_override = body_mat
	stand.add_child(post)

	PhysicalLinkKit.build_diagram_plaque(stand, "Act4FlowSchematic", Vector3(0.0, 1.24, 0.02), Vector3(-16.0, 0.0, 0.0), Vector2(1.06, 0.46), [
		{"num": 1, "icon": "bell", "col": Color(0.32, 0.90, 1.0)},
		{"num": 2, "icon": "platform", "col": Color(1.0, 0.74, 0.24)},
		{"num": 3, "icon": "cradle", "col": Color(0.72, 0.56, 1.0)},
		{"num": 4, "icon": "gate", "col": Color(0.28, 0.96, 0.72)},
	], Color(0.95, 0.72, 0.24))


func pulse_wave(source_id: String) -> void:
	if source_id == "bell":
		PhysicalLinkKit.set_flow_state(_mats.get("wg_east") as ShaderMaterial, "active", Color(0.28, 0.96, 1.0))
		PhysicalLinkKit.set_flow_state(_mats.get("wg_west_in") as ShaderMaterial, "active", Color(0.28, 0.96, 1.0))
	refresh()


func refresh() -> void:
	if _game == null:
		return
	var seen: Dictionary = _game.get("seen_memories") as Dictionary
	var m1_done := bool(seen.get(1, false))
	var m2_done := bool(seen.get(2, false))
	var m3_done := bool(seen.get(3, false))
	var b1_ok := bool(_game.call("_relay_ready", "b1"))
	var b3_ok := bool(_game.call("_relay_ready", "b3"))

	PhysicalLinkKit.set_flow_state(_mats.get("wg_east") as ShaderMaterial, "active" if m1_done else "ready", Color(0.24, 0.92, 1.0))
	PhysicalLinkKit.set_flow_state(_mats.get("wg_west_in") as ShaderMaterial, "active" if m1_done else "idle_dim", Color(0.24, 0.92, 1.0))
	PhysicalLinkKit.set_flow_state(_mats.get("wg_west_out") as ShaderMaterial,
		"active" if b1_ok else ("ready" if m1_done else "locked"),
		Color(0.45, 0.85, 1.0) if b1_ok else Color(-1, 0, 0))
	PhysicalLinkKit.set_flow_state(_mats.get("wg_upper_in") as ShaderMaterial,
		"active" if b3_ok else ("ready" if m2_done else "idle_dim"),
		Color(0.68, 0.52, 1.0) if (b3_ok or m2_done) else Color(-1, 0, 0))
	PhysicalLinkKit.set_flow_state(_mats.get("wg_upper_out") as ShaderMaterial,
		"active" if b3_ok else ("ready" if m2_done else "locked"),
		Color(0.68, 0.52, 1.0) if b3_ok else Color(-1, 0, 0))

	PhysicalLinkKit.set_flow_state(_mats.get("bus_m1") as ShaderMaterial, "active" if m1_done else "locked", Color(0.26, 0.94, 1.0) if m1_done else Color(-1, 0, 0))
	PhysicalLinkKit.set_flow_state(_mats.get("bus_m2") as ShaderMaterial, "active" if m2_done else "locked", Color(0.70, 0.52, 1.0) if m2_done else Color(-1, 0, 0))
	PhysicalLinkKit.set_flow_state(_mats.get("bus_m3") as ShaderMaterial, "active" if m3_done else "locked", Color(0.32, 0.98, 0.80) if m3_done else Color(-1, 0, 0))
	var all_done := m1_done and m2_done and m3_done
	PhysicalLinkKit.set_flow_state(_mats.get("gate_feed") as ShaderMaterial, "active" if all_done else "locked", Color(0.28, 0.98, 0.78) if all_done else Color(-1, 0, 0))

	var cradles: Dictionary = _game.get("cradles") as Dictionary if _game.get("cradles") is Dictionary else {}
	for cid: String in ["b1", "b3"]:
		var st := "locked"
		var c_node: Variant = cradles.get(cid)
		if c_node != null and (c_node as Object).get("occupied") != null:
			st = "active" if bool((c_node as Object).get("aligned")) else "ready"
		PhysicalLinkKit.set_flow_state(_mats.get(cid + "_guide") as ShaderMaterial, st)
		PhysicalLinkKit.set_lamp_state(_lamps.get(cid + "_align") as StandardMaterial3D, st)

	PhysicalLinkKit.set_lamp_state(_lamps.get("m1") as StandardMaterial3D, "active" if m1_done else "ready", Color(0.26, 0.94, 1.0) if m1_done else Color(-1, 0, 0))
	PhysicalLinkKit.set_lamp_state(_lamps.get("m2") as StandardMaterial3D, "active" if m2_done else ("ready" if m1_done else "locked"), Color(0.70, 0.52, 1.0) if m2_done else Color(-1, 0, 0))
	PhysicalLinkKit.set_lamp_state(_lamps.get("m3") as StandardMaterial3D, "active" if m3_done else ("ready" if m2_done else "locked"), Color(0.32, 0.98, 0.80) if m3_done else Color(-1, 0, 0))
	PhysicalLinkKit.set_lamp_state(_lamps.get("gate_master") as StandardMaterial3D, "active" if all_done else "locked")
