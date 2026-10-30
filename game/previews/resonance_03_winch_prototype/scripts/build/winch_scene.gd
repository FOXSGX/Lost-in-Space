extends Node3D

# -----------------------------------------------------------------------------
# WinchScene - the industrial test bay for Resonance 03.1.
#
# Deliberately a "sample", not a level: a 26 x 22 m hall with panel walls, a
# ceiling grid, work lights, a rail-service floor, a cable spool, crates and a
# mine cart. The real cave is NOT rebuilt here; the bay exists so the winch,
# the two lifting eyes and the rail can be read and judged on their own.
#
# `build()` is called explicitly by the app, never from _ready, so the caller
# controls the order in which the mechanic parts are added.
# -----------------------------------------------------------------------------

const Kit := preload("res://scripts/build/mesh_kit.gd")

func build() -> void:
	_build_environment()
	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_lights()
	_build_crystals()
	_build_props()
	_build_signage()

func _build_environment() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.40, 0.52)
	env.ambient_light_energy = 0.50
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.name = "BayEnvironment"
	holder.environment = env
	add_child(holder)

func _build_floor() -> void:
	var stone: Material = Kit.material(Color(0.15, 0.155, 0.17), 0.05, 0.95)
	var plate_a: Material = Kit.material(Color(0.185, 0.19, 0.20), 0.18, 0.82)
	var plate_b: Material = Kit.material(Color(0.165, 0.17, 0.18), 0.18, 0.86)
	var walk_mat: Material = Kit.material(Color(0.17, 0.16, 0.12), 0.08, 0.9)
	var hazard: Material = Kit.material(Color(0.45, 0.31, 0.10), 0.2, 0.7)
	Kit.static_box(self, "Floor", Vector3(26.0, 0.6, 22.0), Vector3(3.0, -0.30, 0.0), stone)
	# 3 x 3.4 m deck plates. Visual only; the single floor body carries collision.
	for ix: int in range(8):
		for iz: int in range(6):
			var mat: Material = plate_a if (ix + iz) % 2 == 0 else plate_b
			Kit.box(self, "FloorPlate_%d_%d" % [ix, iz], Vector3(2.96, 0.06, 3.26), Vector3(-9.4 + float(ix) * 3.05, 0.01, -9.65 + float(iz) * 3.45), mat)
	# Service walkway along the winch side of the rail.
	Kit.box(self, "Walkway", Vector3(21.0, 0.03, 1.9), Vector3(2.5, 0.035, 4.6), walk_mat)
	Kit.box(self, "WalkwayEdgeA", Vector3(21.0, 0.02, 0.08), Vector3(2.5, 0.045, 3.68), hazard)
	Kit.box(self, "WalkwayEdgeB", Vector3(21.0, 0.02, 0.08), Vector3(2.5, 0.045, 5.52), hazard)
	# Painted machine pads.
	Kit.box(self, "WinchPad", Vector3(3.6, 0.03, 2.8), Vector3(-2.6, 0.04, 3.4), Kit.material(Color(0.20, 0.21, 0.22), 0.2, 0.8))
	Kit.box(self, "LockPad", Vector3(2.8, 0.03, 2.4), Vector3(7.0, 0.04, 1.2), Kit.material(Color(0.20, 0.21, 0.22), 0.2, 0.8))

func _build_walls() -> void:
	var collision_mat: Material = Kit.material(Color(0.10, 0.105, 0.115), 0.05, 0.95)
	var panel_mat: Material = Kit.material(Color(0.17, 0.18, 0.20), 0.55, 0.55)
	var rib_mat: Material = Kit.material(Color(0.25, 0.27, 0.30), 0.70, 0.42)
	var strip_mat: Material = Kit.material(Color(0.12, 0.52, 0.68), 0.1, 0.35, Color(0.10, 0.62, 0.85), 1.5)
	var hazard: Material = Kit.material(Color(0.78, 0.52, 0.14), 0.2, 0.55)
	var positions: Array[Vector3] = []
	var rotations: Array[float] = []
	for index: int in range(7):
		positions.append(Vector3(-9.5 + float(index) * 4.4, 0.0, -10.0))
		rotations.append(0.0)
	for index: int in range(7):
		positions.append(Vector3(-9.5 + float(index) * 4.4, 0.0, 10.0))
		rotations.append(PI)
	for index: int in range(4):
		positions.append(Vector3(-10.4, 0.0, -7.0 + float(index) * 4.6))
		rotations.append(PI * 0.5)
	for index: int in range(4):
		positions.append(Vector3(16.0, 0.0, -7.0 + float(index) * 4.6))
		rotations.append(-PI * 0.5)
	for index: int in range(positions.size()):
		var slot: Node3D = Node3D.new()
		slot.name = "WallSlot%d" % index
		slot.position = positions[index]
		slot.rotation.y = rotations[index]
		add_child(slot)
		# Collision wall (also the base surface behind the panels).
		Kit.static_box(slot, "WallCollision", Vector3(4.7, 6.4, 1.6), Vector3(0, 3.2, 0), collision_mat)
		# Interior panel detail, local +z faces the bay for every slot rotation.
		Kit.box(slot, "WallPanel", Vector3(4.35, 6.1, 0.12), Vector3(0, 3.05, 0.80), panel_mat)
		Kit.box(slot, "WallRib", Vector3(0.18, 6.05, 0.22), Vector3(0, 3.05, 0.90), rib_mat)
		Kit.box(slot, "WallStrip", Vector3(4.10, 0.06, 0.06), Vector3(0, 1.28, 0.92), strip_mat)
		Kit.box(slot, "WallHazard", Vector3(4.10, 0.16, 0.06), Vector3(0, 0.38, 0.92), hazard)
		Kit.box(slot, "WallCap", Vector3(4.45, 0.20, 0.55), Vector3(0, 6.25, 0.72), rib_mat)
	# Structural columns at the bay corners and midpoints.
	var column_positions: Array[Vector3] = [
		Vector3(-9.6, 0, -9.3), Vector3(-9.6, 0, 9.3), Vector3(14.6, 0, -9.3),
		Vector3(14.6, 0, 9.3), Vector3(-9.6, 0, 0.0), Vector3(14.6, 0, 0.0),
	]
	for index: int in range(column_positions.size()):
		var col: StaticBody3D = Kit.static_box(self, "Column%d" % index, Vector3(0.55, 7.2, 0.55), column_positions[index] + Vector3(0, 3.6, 0), rib_mat)
		Kit.box(col, "ColumnFoot", Vector3(0.85, 0.35, 0.85), Vector3(0, -3.45, 0), hazard)

func _build_ceiling() -> void:
	var roof: Material = Kit.material(Color(0.06, 0.07, 0.08), 0.2, 0.9)
	var beam: Material = Kit.material(Color(0.14, 0.15, 0.17), 0.75, 0.45)
	Kit.box(self, "Ceiling", Vector3(26.0, 0.3, 22.0), Vector3(3.0, 7.5, 0.0), roof)
	for index: int in range(5):
		Kit.box(self, "CeilingBeamX%d" % index, Vector3(26.0, 0.28, 0.28), Vector3(3.0, 7.25, -8.0 + float(index) * 4.0), beam)
	for index: int in range(5):
		Kit.box(self, "CeilingBeamZ%d" % index, Vector3(0.24, 0.24, 22.0), Vector3(-8.0 + float(index) * 5.5, 7.1, 0.0), beam)

func _build_lights() -> void:
	var lamp_mat: Material = Kit.material(Color(0.95, 0.80, 0.55), 0.1, 0.4, Color(1.0, 0.78, 0.48), 2.2)
	# Hanging fixtures over the rail, the winch and the lock socket.
	var fixtures: Array = [
		[Vector3(2.2, 5.9, 1.2), Color(1.0, 0.83, 0.62), 4.2, 5.0],
		[Vector3(-2.6, 5.4, 3.4), Color(1.0, 0.80, 0.58), 2.6, 4.6],
		[Vector3(7.0, 5.4, 1.2), Color(0.62, 0.86, 1.0), 2.4, 4.4],
	]
	for spec: Array in fixtures:
		var at: Vector3 = spec[0] as Vector3
		var light_color: Color = spec[1] as Color
		var energy: float = float(spec[2])
		var range_value: float = float(spec[3])
		Kit.cylinder(self, "LampDrop%d" % get_child_count(), 0.035, 1.3, at + Vector3(0, 0.65, 0), Kit.material(Color(0.18, 0.19, 0.21), 0.6, 0.5), "y", 8)
		Kit.cylinder(self, "LampShade%d" % get_child_count(), 0.42, 0.16, at + Vector3(0, 0.1, 0), Kit.material(Color(0.22, 0.24, 0.26), 0.7, 0.45), "y", 18)
		Kit.cylinder(self, "LampGlow%d" % get_child_count(), 0.32, 0.05, at, lamp_mat, "y", 18)
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "WorkLight%d" % get_child_count()
		lamp.position = at + Vector3(0, -0.25, 0)
		lamp.light_color = light_color
		lamp.light_energy = energy
		lamp.omni_range = range_value * 3.0
		lamp.shadow_enabled = true
		add_child(lamp)
	# Cool wall wash at the far corners.
	for spec: Array in [[Vector3(-8.4, 3.4, -8.6), Color(0.35, 0.62, 0.95), 1.3], [Vector3(14.0, 3.4, -8.6), Color(0.35, 0.62, 0.95), 1.1]]:
		var at2: Vector3 = spec[0] as Vector3
		var wash: OmniLight3D = OmniLight3D.new()
		wash.name = "WallWash%d" % get_child_count()
		wash.position = at2
		wash.light_color = spec[1] as Color
		wash.light_energy = float(spec[2])
		wash.omni_range = 10.0
		add_child(wash)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "FillLight"
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(38.0), 0.0)
	sun.light_energy = 0.30
	sun.light_color = Color(0.55, 0.66, 0.82)
	add_child(sun)

func _build_crystals() -> void:
	var crystal_mat: Material = Kit.material(Color(0.16, 0.48, 0.64), 0.12, 0.32, Color(0.16, 0.70, 0.95), 0.9)
	var specs: Array = [
		[Vector3(12.8, 0.0, -7.4), 0.75],
		[Vector3(-8.6, 0.0, -7.2), 0.62],
	]
	for spec: Array in specs:
		var at: Vector3 = spec[0] as Vector3
		var scale_value: float = float(spec[1])
		var holder: Node3D = Node3D.new()
		holder.name = "CrystalCluster%d" % get_child_count()
		holder.position = at
		add_child(holder)
		for index: int in range(7):
			var angle: float = TAU * float(index) / 7.0 + 0.4
			var height: float = (0.75 + 0.22 * float(index % 3)) * scale_value
			var shard: MeshInstance3D = Kit.prism(
				holder,
				"Shard%d" % index,
				0.015,
				0.12 * scale_value,
				height,
				Vector3(cos(angle) * 0.32, height * 0.5, sin(angle) * 0.32),
				crystal_mat,
				6
			)
			shard.rotation = Vector3(cos(angle) * 0.18, angle, sin(angle) * 0.18)
		var glow: OmniLight3D = OmniLight3D.new()
		glow.position = at + Vector3.UP * 0.5
		glow.light_color = Color(0.30, 0.82, 1.0)
		glow.light_energy = 0.55
		glow.omni_range = 5.5
		add_child(glow)

func _build_props() -> void:
	var cart_mat: Material = Kit.material(Color(0.34, 0.30, 0.24), 0.55, 0.6)
	var hazard: Material = Kit.material(Color(0.80, 0.55, 0.16), 0.35, 0.55)
	var steel: Material = Kit.material(Color(0.28, 0.31, 0.34), 0.75, 0.42)
	var crate: Material = Kit.material(Color(0.27, 0.24, 0.19), 0.4, 0.7)
	var dark: Material = Kit.material(Color(0.12, 0.13, 0.14), 0.5, 0.6)
	# Mine cart on the approach track.
	var cart: Node3D = Node3D.new()
	cart.name = "MineCart"
	cart.position = Vector3(-5.6, 0.0, 0.0)
	add_child(cart)
	Kit.box(cart, "CartBed", Vector3(1.9, 0.30, 1.30), Vector3(0, 0.62, 0), cart_mat)
	Kit.box(cart, "CartSideL", Vector3(1.9, 0.62, 0.10), Vector3(0, 0.92, -0.62), cart_mat)
	Kit.box(cart, "CartSideR", Vector3(1.9, 0.62, 0.10), Vector3(0, 0.92, 0.62), cart_mat)
	Kit.box(cart, "CartHazard", Vector3(1.92, 0.08, 1.32), Vector3(0, 0.72, 0), hazard)
	for sx: float in [-0.62, 0.62]:
		for sz: float in [-0.52, 0.52]:
			Kit.cylinder(cart, "Wheel", 0.26, 0.10, Vector3(sx, 0.30, sz), dark, "z", 16)
	# Loose debris at the jam, so "stuck in the rubble" reads visually.
	var rubble: Material = Kit.material(Color(0.17, 0.16, 0.15), 0.05, 0.98)
	for index: int in range(7):
		var at: Vector3 = Vector3(3.4 + float(index) * 0.48, 0.16, -1.45 + float(index % 3) * 0.85)
		Kit.static_box(self, "Debris%d" % index, Vector3(0.42, 0.32, 0.36), at, rubble, Vector3(0.1 * index, 0.4 * index, 0.05 * index))
	# Cable spool against the far wall.
	var spool: Node3D = Node3D.new()
	spool.name = "CableSpool"
	spool.position = Vector3(11.4, 0.0, 6.2)
	spool.rotation.y = deg_to_rad(-18.0)
	add_child(spool)
	Kit.cylinder(spool, "SpoolCore", 0.42, 0.72, Vector3.ZERO, dark, "x", 20)
	Kit.cylinder(spool, "SpoolFlangeA", 0.78, 0.10, Vector3(-0.38, 0, 0), steel, "x", 22)
	Kit.cylinder(spool, "SpoolFlangeB", 0.78, 0.10, Vector3(0.38, 0, 0), steel, "x", 22)
	Kit.box(spool, "SpoolStand", Vector3(1.1, 0.35, 0.9), Vector3(0, -0.62, 0), steel)
	# Crates.
	var crate_specs: Array = [
		[Vector3(-8.2, 0.0, 6.8), 0.0], [Vector3(-6.9, 0.0, 7.2), 0.3],
		[Vector3(12.6, 0.0, 3.6), -0.2], [Vector3(13.4, 0.0, 4.7), 0.5],
	]
	for index: int in range(crate_specs.size()):
		var spec: Array = crate_specs[index]
		var at: Vector3 = spec[0] as Vector3
		var box: StaticBody3D = Kit.static_box(self, "Crate%d" % index, Vector3(0.9, 0.9, 0.9), at + Vector3(0, 0.45, 0), crate)
		box.rotation.y = float(spec[1])
		Kit.box(box, "CrateStripe", Vector3(0.92, 0.10, 0.92), Vector3(0, 0.1, 0), hazard)
	# Tool cart beside the winch.
	var tool_cart: Node3D = Node3D.new()
	tool_cart.name = "ToolCart"
	tool_cart.position = Vector3(-4.9, 0.0, 4.7)
	add_child(tool_cart)
	Kit.box(tool_cart, "ToolTop", Vector3(1.2, 0.10, 0.7), Vector3(0, 0.96, 0), steel)
	Kit.box(tool_cart, "ToolBody", Vector3(1.1, 0.8, 0.6), Vector3(0, 0.5, 0), dark)
	Kit.box(tool_cart, "ToolHazard", Vector3(1.12, 0.08, 0.62), Vector3(0, 0.9, 0), hazard)
	for sx: float in [-0.42, 0.42]:
		for sz: float in [-0.24, 0.24]:
			Kit.cylinder(tool_cart, "ToolWheel", 0.12, 0.08, Vector3(sx, 0.12, sz), dark, "z", 12)
	# Conduits along the north wall.
	var pipe: Material = Kit.material(Color(0.32, 0.34, 0.36), 0.8, 0.4)
	for index: int in range(3):
		Kit.cylinder(self, "Conduit%d" % index, 0.09, 21.0, Vector3(2.8, 4.15 + float(index) * 0.30, -9.25), pipe, "x", 12)
	for index: int in range(5):
		Kit.box(self, "ConduitBracket%d" % index, Vector3(0.12, 0.95, 0.40), Vector3(-6.0 + float(index) * 4.4, 4.45, -9.28), dark)
	# A small barrier beside the jam, so the loose end reads as a work zone.
	for index: int in range(3):
		Kit.box(self, "BarrierPost%d" % index, Vector3(0.10, 0.85, 0.10), Vector3(5.0 + float(index) * 1.1, 0.42, 2.35), hazard)
	Kit.box(self, "BarrierRailA", Vector3(2.3, 0.08, 0.06), Vector3(6.1, 0.70, 2.35), hazard)
	Kit.box(self, "BarrierRailB", Vector3(2.3, 0.08, 0.06), Vector3(6.1, 0.40, 2.35), hazard)

func _build_signage() -> void:
	var wall_sign: Label3D = Label3D.new()
	wall_sign.text = "轨道维修区"
	wall_sign.font_size = 42
	wall_sign.pixel_size = 0.006
	wall_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	wall_sign.outline_size = 8
	wall_sign.outline_modulate = Color(0.01, 0.02, 0.03, 0.9)
	wall_sign.modulate = Color(0.55, 0.85, 0.95)
	wall_sign.position = Vector3(11.0, 4.4, -8.95)
	add_child(wall_sign)
	var winch_sign: Label3D = Label3D.new()
	winch_sign.text = "绞盘"
	winch_sign.font_size = 40
	winch_sign.pixel_size = 0.0040
	winch_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	winch_sign.outline_size = 7
	winch_sign.outline_modulate = Color(0.01, 0.02, 0.03, 0.9)
	winch_sign.modulate = Color(0.70, 0.90, 1.0)
	winch_sign.position = Vector3(-2.6, 2.70, 3.4)
	add_child(winch_sign)
	var lock_sign: Label3D = Label3D.new()
	lock_sign.text = "锁定销"
	lock_sign.font_size = 36
	lock_sign.pixel_size = 0.0038
	lock_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lock_sign.outline_size = 7
	lock_sign.outline_modulate = Color(0.01, 0.02, 0.03, 0.9)
	lock_sign.modulate = Color(0.70, 1.0, 0.78)
	lock_sign.position = Vector3(7.05, 1.95, 1.16)
	add_child(lock_sign)
