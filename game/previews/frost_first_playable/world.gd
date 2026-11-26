extends Node3D

const ICE: Script = preload("res://previews/frost_first_playable/ice.gd")
const CREATURE: Script = preload("res://previews/frost_first_playable/creature.gd")
const ROCK: Color = Color("344b59")
const BONE: Color = Color("c6b69a")
var ice: Array[Node3D] = []
var creatures: Array[Node3D] = []
var stations: Array[Dictionary] = []
var loot: Array[Dictionary] = []
var prototype: bool = false
var content: Node3D
var station03: Node3D

func build(small: bool = false) -> void:
	prototype = small
	sky()
	if small:
		box(Vector3(0,-0.5,0),Vector3(45,1,65),ROCK)
		for x: int in range(-2,3):
			for z: int in range(-3,3):
				frost(Vector3(x*6,0.15,z*6),Vector3(6,0.3,6))
		frost(Vector3(0,2,-8),Vector3(5,4,1))
		creature(Vector3(0,0,-15))
		box(Vector3(0,2,-23),Vector3(12,4,6),BONE)
		ramp(Vector3(9,0,-13),Vector3(9,4,-23),4)
		return
	base()
	hall(0,-530,Color("78b4c1"))
	hall(1,-680,Color("b38bc6"))
	hall(2,-830,Color("d9a570"))
	content = load("res://previews/frost_first_playable/content.gd").new()
	content.name = "ExpeditionContent"
	add_child(content)
	content.build(self)
	station03 = load("res://previews/frost_first_playable/research_station.gd").new()
	station03.name = "ResearchStation03"
	add_child(station03)
	station03.build(self)

func sky() -> void:
	var world_env: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	var material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	material.sky_top_color = Color("274a68")
	material.sky_horizon_color = Color("a9c6d3")
	material.ground_horizon_color = Color("a9c6d3")
	var scene_sky: Sky = Sky.new()
	scene_sky.sky_material = material
	env.background_mode = Environment.BG_SKY
	env.sky = scene_sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9bbacb")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38,-28,0)
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150
	add_child(sun)

func box(point: Vector3, size_value: Vector3, color: Color, collision: bool = true) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = point
	body.collision_layer = 2 if collision else 0
	body.collision_mask = 0
	var view: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size_value
	view.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color.srgb_to_linear()
	material.roughness = 0.8
	view.material_override = material
	body.add_child(view)
	if collision:
		var shape: CollisionShape3D = CollisionShape3D.new()
		var cube: BoxShape3D = BoxShape3D.new()
		cube.size = size_value
		shape.shape = cube
		body.add_child(shape)
	add_child(body)
	return body

func frost(point: Vector3, dimensions: Vector3) -> Node3D:
	var chunk: Node3D = ICE.new()
	chunk.name = "Snow_%04d" % ice.size()
	chunk.configure(point, dimensions)
	add_child(chunk)
	ice.append(chunk)
	return chunk

func rounded_bone(body: StaticBody3D, length: float, radius: float, horizontal: bool = false) -> void:
	var view: MeshInstance3D = body.get_child(0) as MeshInstance3D
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 4
	view.mesh = mesh
	if horizontal:
		view.rotation.z = PI/2

func specimen(point: Vector3, size_value: float, tint: Color) -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = size_value
	mesh.height = size_value*1.5
	mesh.radial_segments = 16
	mesh.rings = 8
	visual.mesh = mesh
	visual.position = point
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = tint.srgb_to_linear()
	material.emission_enabled = true
	material.emission = tint.srgb_to_linear()
	material.emission_energy_multiplier = 0.18
	visual.material_override = material
	add_child(visual)

func creature(point: Vector3) -> void:
	var soft: Node3D = CREATURE.new()
	soft.name = "Soft_%d" % creatures.size()
	soft.position = point
	add_child(soft)
	creatures.append(soft)

func ramp(from: Vector3, to: Vector3, width: float) -> void:
	var slope: StaticBody3D = box((from+to)*0.5-Vector3.UP*0.16,Vector3(width,0.32,from.distance_to(to)+0.6),BONE)
	slope.look_at(to,Vector3.UP)

func lamp(point: Vector3, color: Color, reach: float = 18) -> void:
	box(point,Vector3(0.25,0.7,0.25),color,false)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = point
	light.light_color = color
	light.light_energy = 0.65
	light.omni_range = reach
	add_child(light)

func station(kind: String, point: Vector3, text: String, with_sign: bool = true, build_device: bool = true) -> void:
	if build_device:
		box(point-Vector3.UP*0.3,Vector3(1.6,1.2,0.7),Color("4e727c"))
		box(point+Vector3(0,0.4,0),Vector3(1.45,0.15,0.8),Color("e5b169"))
	stations.append({"kind":kind,"point":point,"text":text})
	if with_sign:
		pictogram(point+Vector3(0,1.15,0.4),"res://previews/frost_first_playable/signs/"+kind+".png")

func supply(kind: String, point: Vector3, data: Dictionary = {}) -> void:
	var entry: Dictionary = {"kind":kind,"position":point,"uid":"supply_%d" % loot.size(),"safe_position":point,"area":"frost_adventure","placed":true}
	entry.merge(data,true)
	loot.append(entry)

func pictogram(point: Vector3, texture_path: String) -> void:
	box(point-Vector3(0,0,0.05),Vector3(2.2,1.5,0.1),Color("263e4c"),false)
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(2.1,1.4)
	visual.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load(texture_path)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	visual.position = point+Vector3(0,0,0.012)
	add_child(visual)

func shelter(point: Vector3, width: float, depth: float, accent: Color, detailed_lab: bool = false) -> void:
	box(point+Vector3(0,0.1,0),Vector3(width,0.2,depth),Color("536877"))
	if detailed_lab:
		# A sealed observation window, never an extra exit or return shortcut.
		box(point+Vector3(-6,6,-depth/2),Vector3(20,12,0.6),ROCK)
		box(point+Vector3(14,6,-depth/2),Vector3(4,12,0.6),ROCK)
		box(point+Vector3(8,1.5,-depth/2),Vector3(8,3,0.6),ROCK)
		box(point+Vector3(8,9.2,-depth/2),Vector3(8,5.6,0.6),ROCK)
		var glass: StaticBody3D = box(point+Vector3(8,4.7,-depth/2),Vector3(8,3.4,0.2),Color("9ac7d4"))
		var glass_material: StandardMaterial3D = (glass.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass_material.albedo_color = Color(0.5,0.75,0.8,0.14)
	else:
		box(point+Vector3(0,6,-depth/2),Vector3(width,12,0.6),ROCK)
	box(point+Vector3(-width/2,6,0),Vector3(0.6,12,depth),ROCK)
	if detailed_lab:
		# Side hatch at local Z=5 joins the small service annex.
		box(point+Vector3(width/2,6,-7.35),Vector3(0.6,12,20.3),ROCK)
		box(point+Vector3(width/2,6,12.35),Vector3(0.6,12,10.3),ROCK)
		box(point+Vector3(width/2,7.8,5),Vector3(0.6,8.4,4.4),ROCK)
	else:
		box(point+Vector3(width/2,6,0),Vector3(0.6,12,depth),ROCK)
	box(point+Vector3(0,12,0),Vector3(width+1,0.5,depth+1),ROCK)
	box(point+Vector3(0,9,depth/2),Vector3(width,1,0.6),accent)
	for x: float in [-width/3,0,width/3]:
		frost(point+Vector3(x,12.5,0),Vector3(width/3,0.5,depth))
	lamp(point+Vector3(0,5,0),accent,25)

func base() -> void:
	box(Vector3(0,-1,-220),Vector3(150,2,520),ROCK)
	# Finite surface snow; every pale blue surface is a mutable collision chunk.
	for x: int in range(-6,7):
		for z: int in range(-39,3):
			frost(Vector3(x*11,0.15,z*12),Vector3(11,0.3,12))
	box(Vector3(0,0.4,4),Vector3(30,0.8,28),Color("506574"))
	ramp(Vector3(0,0.8,-9.8),Vector3(0,0.3,-13),8)
	# Ship cabin opens towards the apron, with an actual doorway in its front.
	box(Vector3(0,4,19),Vector3(14,8,0.5),ROCK)
	box(Vector3(0,8,11),Vector3(14,0.5,16),ROCK)
	for side: float in [-1,1]:
		box(Vector3(side*7,4,11),Vector3(0.5,8,16),ROCK)
		box(Vector3(side*4.8,4,3),Vector3(4.5,8,0.5),ROCK)
	box(Vector3(0,6.8,3),Vector3(5.2,2.4,0.5),Color("dda568"))
	lamp(Vector3(0,4,10),Color("ffcc94"),12)
	station("core",Vector3(0,1.5,15),"高能核心烧毁；普通燃料仍有储备。科考站保险柜内有替代能源。")
	station("charge",Vector3(-5,1.4,5),"船载慢充台：E 为随身热风机充电、补充氧气。消耗时间，不生成新物品。")
	for i: int in 4:
		var x: float = [-6.0,-4.0,4.0,6.0][i]
		supply("heater",Vector3(x,1.3,-4),{"charge":180.0})
		supply("cell",Vector3(x,1.3,-7))
		supply("oxygen",Vector3(x,1.3,-10))
	pictogram(Vector3(0,2.6,-17.3),"res://previews/frost_first_playable/heat.svg")
	# A walled loading apron makes melting the exit meaningful.
	for x: float in [-19,19]:
		box(Vector3(x,8,0),Vector3(2,16,40),ROCK)
	box(Vector3(0,8,21),Vector3(40,16,2),ROCK)
	for x: float in [-12,12]:
		box(Vector3(x,8,-18),Vector3(16,16,2),ROCK)
	for x: float in [-2.7,0,2.7]:
		frost(Vector3(x,3,-18),Vector3(2.7,6,1.5))
	# Long open logistics axis: 460 m / 5.8 m/s ~79 s without stops.
	for z: int in range(-45,-465,-24):
		box(Vector3(0,0.33,z),Vector3(9,0.12,20),Color("536979"))
		box(Vector3(4.2,0.4,z),Vector3(0.25,0.08,12),Color("deb77c"),false)
	for side: float in [-1,1]:
		for z: int in range(20,-490,-28):
			var ridge: StaticBody3D = box(Vector3(side*76,14,z),Vector3(14,28,30),ROCK)
			ridge.rotation.z = side*0.1
			var cliff: CylinderMesh = CylinderMesh.new()
			cliff.top_radius = 10
			cliff.bottom_radius = 18
			cliff.height = 34+float(posmod(z,5))
			cliff.radial_segments = 5
			(ridge.get_child(0) as MeshInstance3D).mesh = cliff
			(ridge.get_child(1) as CollisionShape3D).shape = cliff.create_trimesh_shape()
	# Storage beside transport; laboratories face the excavation.
	shelter(Vector3(-38,0,-95),30,34,Color("dcad70"))
	shelter(Vector3(38,0,-210),32,38,Color("73bdce"))
	shelter(Vector3(-36,0,-340),32,35,Color("79bdba"),true)
	pictogram(Vector3(-38,7.5,-77.5),"res://previews/frost_first_playable/signs/warehouse.png")
	pictogram(Vector3(38,7.5,-190.5),"res://previews/frost_first_playable/signs/research.png")
	pictogram(Vector3(-36,7.5,-322),"res://previews/frost_first_playable/signs/safe.png")
	station("safe",Vector3(-36,1.3,-349),"能源保险柜：首席科学家携带钥匙进入遗迹，尚未归队。")
	station("record",Vector3(38,1.3,-219),"后勤记录：先收到深入小队遭袭的求救；随后暴雪封锁航线，留守人员被迫撤离。搜救未完成。")
	station("charge",Vector3(-29,1.2,-84),"维护充电台 · E 慢充与补氧")
	for p: Vector3 in [Vector3(-36,1,-92),Vector3(34,1,-205),Vector3(-31,1,-336)]:
		for j: int in 3:
			supply("cell",p+Vector3(j,0,0))
		supply("medical",p+Vector3(0,0,2))
		supply("fuel",p+Vector3(3,0,2))
		for k: int in 3:
			box(p+Vector3(k*4-5,0.5,-5),Vector3(3,2.5,3),Color("7a7166"))
	# Giant fossil mouth, visible across the base.
	for side: float in [-1,1]:
		var jaw: StaticBody3D = box(Vector3(side*24,18,-463),Vector3(8,42,12),BONE)
		jaw.rotation.z = side*0.32
		rounded_bone(jaw,42,5)
	box(Vector3(0,38,-463),Vector3(50,8,12),BONE)
	for x: float in [-18,-10,10,18]:
		box(Vector3(x,29,-458),Vector3(3,12,4),BONE)
	lamp(Vector3(0,17,-470),Color("79c2df"),45)

func hall(index: int, z: float, accent: Color) -> void:
	# 110 m wide connected cavities, not a corridor grid.
	box(Vector3(0,-1,z),Vector3(142,2,152),ROCK)
	for side: float in [-1,1]:
		box(Vector3(side*69,18,z),Vector3(8,36,152),ROCK)
	box(Vector3(0,39,z),Vector3(145,5,154),ROCK)
	for x: int in range(-5,6):
		for iz: int in range(-6,7):
			if (x+iz+index)%3 == 0:
				frost(Vector3(x*11,0.3,z+iz*11),Vector3(9,0.6,9))
	# Ribs create a recognisable vaulted silhouette and real upper walkways.
	for dz: float in [-50,-25,0,25,50]:
		for side: float in [-1,1]:
			var rib: StaticBody3D = box(Vector3(side*36,16,z+dz),Vector3(3,34,4),BONE)
			rib.rotation.z = side*0.38
			rounded_bone(rib,34,1.8)
			var arch: StaticBody3D = box(Vector3(side*17,32,z+dz),Vector3(35,3,4),BONE)
			arch.rotation.z = -side*0.2
			rounded_bone(arch,35,1.8,true)
		lamp(Vector3(-25,7,z+dz),accent,26)
	# Continuous reversible bone spine; optional jumps/jet cut across its bends.
	var points: Array[Vector3] = [Vector3(0,0.35,z+68),Vector3(-23,4,z+38),Vector3(18,8,z+6),Vector3(-15,12,z-32),Vector3(0,12,z-52)]
	for i: int in points.size()-1:
		ramp(points[i],points[i+1],5.5)
		box(points[i]-Vector3.UP*0.3,Vector3(10,0.6,10),BONE)
	box(points[-1]-Vector3.UP*0.3,Vector3(24,0.6,20),BONE)
	if index < 2:
		# A low vertebral ridge forces a real high route, accessible from both sides.
		box(Vector3(0,3,z-63),Vector3(138,6,2),BONE)
		ramp(Vector3(0,12,z-61.8),Vector3(0,0.35,z-78),7)
	else:
		box(Vector3(0,18,z-75),Vector3(140,36,5),ROCK)
	for i: int in 5:
		box(Vector3(20,1+i*1.2,z+36-i*6),Vector3(7,1.2,4),BONE)
	creature(Vector3(0,0.3,z+22))
	box(Vector3(0,4,z+10),Vector3(13,1,10),BONE)
	ramp(Vector3(12,0.35,z+25),Vector3(12,4.5,z+10),5)
	# High and low routes meet in the same room and remain visible to teammates.
	for x: float in [-20,22]:
		frost(Vector3(x,2,z+45),Vector3(5,4,3))
		supply("cell",Vector3(x,1,z+43))
	supply("fuel",Vector3(8,12.6,z-50))
	station("charge",Vector3(-25,1.3,z+56),"科考慢充站 · E 慢充与补氧")
	if index == 0:
		pictogram(Vector3(-23,2.4,z+55.5),"res://previews/frost_first_playable/creature.svg")
		station("record",Vector3(-20,4.8,z+38),"生态记录：柔软后代受热膨胀，约四秒后弹射。站在背上向下吹也可触发。骨脊斜坡可以原路返回。")
	elif index == 1:
		creature(Vector3(-22,0.3,z-5))
		creature(Vector3(25,0.3,z-22))
		for i: int in 8:
			specimen(Vector3(-44+float(i%2)*88,3+float(i%3),z-50+i*13),2.5,Color("a57aab"))
		station("record",Vector3(21,8.8,z+6),"正常样件：三枚完整锁销固定安全阀；内侧封盖完整。请勿拆卸。",false,false)
		for i: int in 3:
			box(Vector3(20+i*0.45,9,z+5.5),Vector3(0.16,0.5,0.16),Color("e8c77e"),false)
	else:
		# A broad broken skull above the incident site distinguishes the final cavity.
		for side: float in [-1,1]:
			specimen(Vector3(side*20,25,z-65),12,BONE)
			specimen(Vector3(side*18,25,z-54),6,ROCK)
		var crest: StaticBody3D = box(Vector3(0,34,z-65),Vector3(42,5,5),BONE,false)
		rounded_bone(crest,42,3,true)
		station("key",Vector3(-2.4,12.9,z-52),"首席科学家的遗体旁有保险柜钥匙。内侧锁销被整齐拔出，两枚放在工具布上；封盖重新拧紧。")
		station("evidence",Vector3(-5,12.9,z-50),"独立故障记录：安全回路被人工旁接，发生于求救信号之前。结合拆卸痕迹，可排除单纯坠落损坏；操作者与动机未知。")
		box(Vector3(3,12.4,z-52),Vector3(0.9,0.65,2.1),Color("8c9ca6"))
		box(Vector3(3,12.4,z-50.5),Vector3(0.7,0.7,0.7),Color("adc1ca"))
		for i: int in 2:
			box(Vector3(1+i*0.4,12.2,z-50),Vector3(0.14,0.15,0.6),Color("e8c77e"))

