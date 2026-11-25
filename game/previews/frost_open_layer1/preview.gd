extends "res://previews/frost_layer1/preview.gd"

# Only the layer-1 space changes. Reuse the already exercised offline host,
# first-person adapter, five-cell HP, inventory, oxygen and inner-side gate.
const EAST_PATH: Array[Vector3] = [Vector3(23,0,44),Vector3(46,0,30),Vector3(48,0,8),Vector3(33,0,-12),Vector3(24,0,-6),Vector3(16,0,-6),Vector3(16,0,0),Vector3(0,0,0)]
const WEST_PATH: Array[Vector3] = [Vector3(-22,0,45),Vector3(-40,0,30),Vector3(-46,0,10),Vector3(-40,0,-12),Vector3(-20,0,-15),Vector3(-14,0,-7),Vector3(0,0,-7),Vector3(0,0,0)]
const CROSS_PATH: Array[Vector3] = [Vector3(20,0,47),Vector3(33,0,39),Vector3(49,0,42),Vector3(54,0,23),Vector3(43,0,0),Vector3(24,0,-6),Vector3(16,0,-6),Vector3(16,0,0),Vector3(0,0,0)]
var terrain_mesh: ArrayMesh

func _ready() -> void:
	super._ready()
	DisplayServer.window_set_title("霜烬星 · 开放探索第1层")
	print("FROST_OPEN_READY: continuous terrain / two approaches / cross-country walking")

func _process(delta: float) -> void:
	super._process(delta)
	# Returning by either outside route remains valid; opening the shortcut is
	# a spatial opportunity, not an invisible completion gate.
	if entered and not returned and walker.position.distance_to(Vector3(0,0,48))<6:
		returned = true
		trace.append({"event":"returned_without_shortcut","seconds":elapsed,"distance":distance_walked})
		print("FROST_OPEN_RETURNED_OUTSIDE ",elapsed)
	if not returned:
		status.text = "霜烬星 · 开放探索预览"

func _build_space() -> void:
	_build_sky()
	_build_terrain()
	# Visible mountains form the outer horizon and the physical boundary.
	# The interior is continuous walkable terrain; no corridor-cell walls.
	for index: int in 48:
		var angle: float = TAU * float(index) / 48.0
		var p: Vector3 = Vector3(cos(angle)*88.0,0,sin(angle)*88.0)
		_rock(p,9.0,17.0+float(index%5)*3.0,Color("#638296"))
	# Sparse local ice outcrops leave broad openings and alternative approaches.
	for data: Vector3 in [Vector3(-25,3,49),Vector3(30,4,20),Vector3(60,5,34),Vector3(-60,4,28),Vector3(37,3,-34),Vector3(-29,4,-34),Vector3(13,3,-50)]:
		_rock(Vector3(data.x,0,data.z),data.y,4.0+data.y,Color("#7b9eaf"))
	_build_pad()
	_build_buried_ridge()
	_build_ruin()
	_build_outer_landmarks()
	# Broken heat hardware is environmental guidance only, with no new mechanic.
	for p: Vector3 in [Vector3(-18,0,38),Vector3(19,0,37),Vector3(-36,0,23),Vector3(39,0,12),Vector3(-24,0,-11),Vector3(25,0,-9)]:
		_vent(p)

func _build_sky() -> void:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#3d678c")
	sky_material.sky_horizon_color = Color("#c0d6df")
	sky_material.ground_bottom_color = Color("#6b8297")
	sky_material.ground_horizon_color = Color("#c0d6df")
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9cdd8")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-37,-38,0)
	sun.light_color = Color("#f5e9ce")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)

func open_height(x: float, z: float) -> float:
	var west: float = 5.8*exp(-pow((x+46.0)/22.0,2)-pow((z-1.0)/30.0,2))
	var east: float = -1.1*exp(-pow((x-45.0)/22.0,2)-pow((z-8.0)/29.0,2))
	var ripples: float = sin(x*0.09+z*0.05)*0.35+cos(z*0.12)*0.2
	var center_mask: float = clampf(maxf(absf(x)-24.0,absf(z-4.0)-34.0)/10.0,0,1)
	var pad_mask: float = clampf((Vector2(x,z-48).length()-13.0)/10.0,0,1)
	var rim: float = minf(28.0,pow(maxf(0.0,Vector2(x,z).length()-67.0)/21.0,2)*10.0)
	return (west+east+ripples)*center_mask*pad_mask+rim

func _build_terrain() -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: int in range(-96,96,4):
		for z: int in range(-96,96,4):
			var a: Vector3 = Vector3(x,open_height(x,z),z)
			var b: Vector3 = Vector3(x+4,open_height(x+4,z),z)
			var c: Vector3 = Vector3(x,open_height(x,z+4),z+4)
			var d: Vector3 = Vector3(x+4,open_height(x+4,z+4),z+4)
			# Godot uses clockwise front faces; keep the walkable side facing up.
			for p: Vector3 in [a,b,c,b,d,c]:
				var shade: float = clampf((p.y+1.0)/9.0,0,1)
				var color: Color = Color("#92b2bf").lerp(Color("#d7e0e3"),shade)
				# Bare blue ice is a visible basin, without new ice movement rules.
				if Vector2(p.x-43,p.z-9).length()<18:
					color = Color("#779fad")
				surface.set_color(color)
				surface.add_vertex(p)
	surface.generate_normals()
	terrain_mesh = surface.commit()
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "ContinuousSnowTerrain"
	ground.collision_layer = 2
	ground.collision_mask = 0
	add_child(ground)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = terrain_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	visual.material_override = material
	ground.add_child(visual)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = terrain_mesh.create_trimesh_shape()
	ground.add_child(collision)

func _rock(p: Vector3, radius: float, height: float, tint: Color) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = Vector3(p.x,open_height(p.x,p.z)+height*0.42,p.z)
	body.rotation.y = p.x*0.31+p.z*0.19
	body.name = "VisibleIceOutcrop"
	body.collision_layer = 2
	body.collision_mask = 0
	add_child(body)
	var rock_mesh: CylinderMesh = CylinderMesh.new()
	rock_mesh.radial_segments = 5
	rock_mesh.top_radius = radius*(0.04 if height>15 else 0.45)
	rock_mesh.bottom_radius = radius
	rock_mesh.height = height
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = rock_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.96
	visual.material_override = material
	body.add_child(visual)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = rock_mesh.create_trimesh_shape()
	body.add_child(collision)

func _build_pad() -> void:
	_box("LandingPad",Vector3(0,0.02,48),Vector3(16,0.04,15),Color("#4c6571"))
	for x: float in [-6.5,6.5]:
		_box("PadStrip",Vector3(x,0.07,48),Vector3(0.18,0.08,12),Color("#e6b86e"),false,true)
	_box("PadShelterBack",Vector3(0,2.5,59.5),Vector3(14,5,0.5),Color("#384f5a"))
	_box("PadShelterRoof",Vector3(0,5,55.5),Vector3(14,0.4,8.5),Color("#384f5a"))
	for x: float in [-6.5,6.5]:
		_box("ShelterPost",Vector3(x,2.5,52),Vector3(0.4,5,0.4),Color("#384f5a"))
	_box("PadCargo",Vector3(5,0.7,55),Vector3(2,1.4,1.5),Color("#7b8d94"))

func _build_buried_ridge() -> void:
	# A local snow-covered buttress closes the direct path, visible from outside.
	# Its sole tunnel is the shortcut; the wider basin remains open on both sides.
	_box("BuriedWestButtress",Vector3(-9,4,21),Vector3(10,8,16),Color("#7896a6"))
	_box("BuriedEastButtress",Vector3(9,4,21),Vector3(10,8,16),Color("#7896a6"))
	_box("SnowCap",Vector3(0,7.8,21),Vector3(28,1.2,16),Color("#adc5d0"))
	for x: float in [-16,16]:
		_rock(Vector3(x,0,23),4,9,Color("#91afbd"))
	_box("TunnelCeiling",Vector3(0,7.6,20),Vector3(8,0.8,20),Color("#425a68"))
	gate = _box("ShortcutDoor",Vector3(0,3.3,28),Vector3(7.8,6.6,0.65),Color("#465563"))
	gate_panel = gate.get_child(0) as MeshInstance3D
	_box("LatchPost",Vector3(2.7,1.25,27.3),Vector3(0.35,2.5,0.5),Color("#304c5a"))
	_box("InsideLatch",Vector3(2.7,1.2,27.05),Vector3(0.65,0.9,0.18),Color("#304c5a"))
	latch_lever = _box("LatchLever",Vector3(2.7,1.2,26.85),Vector3(0.15,0.65,0.18),Color("#edb65e"),true,true)
	latch_lever.rotation_degrees.z = -25
	_wall_arrow(Vector3(2.7,2.3,27.6),false)
	for x: float in [-4.5,4.5]:
		_box("PortalFrame",Vector3(x,3.6,30),Vector3(0.7,7.2,0.8),Color("#3e5664"))
		_box("PortalLamp",Vector3(x,2.6,30.5),Vector3(0.18,1.3,0.12),Color("#f0bb6e"),false,true)

func _build_ruin() -> void:
	_box("TowerBase",Vector3(-5,5,-3),Vector3(4,10,4),Color("#344854"))
	_box("TowerMast",Vector3(-5,20,-3),Vector3(1.6,22,1.6),Color("#344854"))
	_box("TowerCrossarm",Vector3(-5,29,-3),Vector3(6,0.5,0.8),Color("#344854"))
	_box("TowerBeacon",Vector3(-5,31.7,-3),Vector3(2.4,1.1,2.4),Color("#f4b66c"),false,true)
	_box("RuinRoof",Vector3(6,5.8,0),Vector3(27,0.6,23),Color("#3b535f"))
	_box("RuinNorth",Vector3(5.5,2.8,-11.5),Vector3(28,5.6,0.6),Color("#405966"))
	_box("WestWallNorth",Vector3(-8,2.8,-10),Vector3(0.6,5.6,3),Color("#405966"))
	_box("WestWallSouth",Vector3(-8,2.8,4),Vector3(0.6,5.6,15),Color("#405966"))
	_box("WestEntryLintel",Vector3(-8,5,-6),Vector3(0.6,1.6,5),Color("#405966"))
	_box("EastWallSouth",Vector3(19.5,2.8,4.5),Vector3(0.6,5.6,14),Color("#405966"))
	_box("EastWallNorth",Vector3(19.5,2.8,-10.3),Vector3(0.6,5.6,2.4),Color("#405966"))
	_box("EastEntryLintel",Vector3(19.5,5,-6),Vector3(0.6,1.6,6),Color("#405966"))
	_box("FrontLeft",Vector3(-5.8,2.8,11.5),Vector3(4.4,5.6,0.6),Color("#405966"))
	_box("FrontRight",Vector3(11.8,2.8,11.5),Vector3(15.6,5.6,0.6),Color("#405966"))
	for p: Vector3 in [Vector3(2,2.7,-3),Vector3(11,2.7,3)]:
		_box("RuinColumn",p,Vector3(1.2,5.4,1.2),Color("#405966"))
	_box("OldEquipment",Vector3(7,0.6,-7),Vector3(4,1.2,1.2),Color("#758b96"))
	_box("MechanismFoot",Vector3(-3,0.4,4),Vector3(3.2,0.8,3.2),Color("#42535d"))
	for x: float in [-4.3,-1.7]:
		_box("MechanismFrame",Vector3(x,2.2,4),Vector3(0.6,3.6,0.8),Color("#607b87"))
	_box("BrokenMechanism",Vector3(-3.2,3.8,4),Vector3(2,0.6,0.8),Color("#607b87")).rotation_degrees.z = -18
	_light(Vector3(16,3,-6),Color("#f2bc77"),13,1.8)
	_light(Vector3(-5,3,-7),Color("#f2bc77"),12,1.4)
	_light(Vector3(0,3,4),Color("#97d4d8"),14,1.5)
	for p: Vector3 in [Vector3(-10,0,-4),Vector3(21,0,-4)]:
		_vent(p)

func _build_outer_landmarks() -> void:
	# West: an open, walkable antenna overlook on the natural high ground.
	var west_y: float = open_height(-56,-6)
	_box("AntennaFoot",Vector3(-56,west_y+0.5,-6),Vector3(4,1,4),Color("#516a78"))
	_box("AntennaPylon",Vector3(-56,west_y+5,-6),Vector3(0.8,9,0.8),Color("#455c69"))
	_box("AntennaBrokenDish",Vector3(-56,west_y+9,-6),Vector3(8,0.5,4),Color("#b9d0d9")).rotation_degrees.z = 27
	_box("AntennaBrace",Vector3(-56,west_y+7,-6),Vector3(6,0.35,0.4),Color("#455c69"))
	# East: a rust-colored loader silhouette, freely approachable.
	var east_y: float = open_height(55,-5)
	_box("LoaderFoot",Vector3(55,east_y+0.5,-5),Vector3(5,1,5),Color("#6f655d"))
	_box("LoaderPylon",Vector3(55,east_y+5,-5),Vector3(1.3,9,1.3),Color("#9e7653"))
	_box("LoaderArm",Vector3(51,east_y+10,-5),Vector3(10,0.7,1),Color("#b78758"))
	_box("LoaderCable",Vector3(47,east_y+6.5,-5),Vector3(0.12,6,0.12),Color("#384c58"))
	_box("LoaderCargo",Vector3(61,open_height(61,-7)+0.8,-7),Vector3(4,1.6,3),Color("#6f7f86"))

func _vent(p: Vector3) -> void:
	var h: float = open_height(p.x,p.z)
	_box("VentHousing",Vector3(p.x,h+0.28,p.z),Vector3(1.1,0.56,0.8),Color("#475f69"))
	for offset: float in [-0.26,0,0.26]:
		_box("VentGrille",Vector3(p.x+offset,h+0.57,p.z),Vector3(0.12,0.03,0.6),Color("#e7ad62"),false,true)
	_light(Vector3(p.x,h+1,p.z),Color("#eab577"),7,0.7)
