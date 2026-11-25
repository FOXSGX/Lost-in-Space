extends Node3D

const KIT: String = "res://assets/ship-hub/kenney/space-station/"
var world: Node3D
var door: StaticBody3D
var handle: StaticBody3D
var sample: Node3D
var sample_screen: MeshInstance3D
var power_lights: Array[OmniLight3D] = []
var lamps: Array[MeshInstance3D] = []
var energy: Node3D
var safe_door: Node3D
var hatch_cover: int = -1
var sample_cover: int = -1
var bounds_cache: Dictionary = {}
var landmarks: Dictionary = {}

func build(owner_world: Node3D) -> void:
	world = owner_world
	facade_and_services()
	reception_and_lab()
	service_annex()
	observation_deck()
	energy_store()
	landmarks = {"entry":Vector3(-36,0.3,-318),"hatch":Vector3(-21.5,1.3,-335),"relay":Vector3(-10,1.3,-340),"sample":Vector3(-48,1.3,-330.8),"deck_foot":Vector3(-22.6,0.3,-339.5),"deck_top":Vector3(-22.6,3.2,-352.2)}

func branch_bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var here: Transform3D = parent_transform*node.transform
	var result: AABB = here*(node as MeshInstance3D).get_aabb() if node is MeshInstance3D else AABB()
	for child: Node in node.get_children():
		if child is Node3D:
			var child_bounds: AABB = branch_bounds(child as Node3D,here)
			if child_bounds.size.length_squared()>0:
				result = result.merge(child_bounds) if result.size.length_squared()>0 else child_bounds
	return result

func asset(key: String, bottom: Vector3, dimensions: Vector3, yaw: float = 0, solid: bool = false) -> Node3D:
	var scene: PackedScene = load(KIT+key+".glb") as PackedScene
	var visual: Node3D = scene.instantiate() as Node3D
	var bounds: AABB
	if bounds_cache.has(key):
		bounds = bounds_cache[key]
	else:
		bounds = branch_bounds(visual,Transform3D.IDENTITY)
		bounds_cache[key] = bounds
	var fit: Vector3 = dimensions/Vector3(maxf(0.001,bounds.size.x),maxf(0.001,bounds.size.y),maxf(0.001,bounds.size.z))
	var holder: Node3D = Node3D.new()
	holder.name = "Station_"+key
	holder.position = bottom
	holder.rotation.y = yaw
	add_child(holder)
	var normalizer: Node3D = Node3D.new()
	normalizer.scale = fit
	normalizer.position = -Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*fit
	holder.add_child(normalizer)
	normalizer.add_child(visual)
	if solid:
		var body: StaticBody3D = world.box(bottom+Vector3.UP*dimensions.y*0.5,dimensions,Color("6d8391"))
		body.rotation.y = yaw
		(body.get_child(0) as MeshInstance3D).visible = false
	return holder

func plate(point: Vector3, key: String, size_value: Vector2, yaw: float = 0) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.position = point
	holder.rotation.y = yaw
	add_child(holder)
	var backing: MeshInstance3D = panel(Vector3.ZERO,Vector3(size_value.x+0.08,size_value.y+0.08,0.08),Color("213b49"))
	backing.reparent(holder,false)
	var view: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size_value
	view.mesh = quad
	view.position.z = 0.048
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load("res://previews/frost_first_playable/signs/station03/"+key+".png")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view.material_override = material
	holder.add_child(view)
	return holder

func panel(point: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var view: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	view.mesh = mesh
	view.position = point
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color.srgb_to_linear()
	material.roughness = 0.65
	view.material_override = material
	add_child(view)
	return view

func facade_and_services() -> void:
	# A broad open entrance keeps four people together; the glazing defines
	# occupied work bays without placing another locked door on the mainline.
	world.box(Vector3(-48.5,6,-322.5),Vector3(7,12,0.6),Color("405b6a"))
	world.box(Vector3(-39,7.8,-322.5),Vector3(12,8.4,0.6),Color("405b6a"))
	for x: float in [-32,-21]:
		world.box(Vector3(x,6,-322.5),Vector3(2,12,0.6),Color("405b6a"))
	world.box(Vector3(-26.5,0.5,-322.5),Vector3(9,1,0.6),Color("405b6a"))
	world.box(Vector3(-26.5,7.9,-322.5),Vector3(9,8.2,0.6),Color("405b6a"))
	var glass: StaticBody3D = world.box(Vector3(-26.5,2.4,-322.5),Vector3(9,2.8,0.15),Color("a0c2ce"))
	var material: StandardMaterial3D = (glass.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.5,0.7,0.8,0.12)
	for x: float in [-44.5,-33.5]:
		world.box(Vector3(x,1.75,-322),Vector3(0.16,3.5,0.25),Color("a5bdc3"))
		world.box(Vector3(x,1.75,-321.84),Vector3(0.09,2.8,0.02),Color("e3b56b"),false)
	for x: float in [-48,-29]:
		asset("structure-panel",Vector3(x,4.6,-331),Vector3(6.5,0.12,7),0,true)
		for z: float in [-328.2,-333.8]:
			world.content.line(Vector3(x,4.72,z),Vector3(x,12,z),0.06,Color("6e8996"))

func work_light(point: Vector3) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.position = point
	light.light_color = Color("d1eef0")
	light.light_energy = 0.13
	light.omni_range = 13
	add_child(light)
	power_lights.append(light)
	var lamp: MeshInstance3D = panel(point+Vector3.UP*0.2,Vector3(1.4,0.12,0.4),Color("587783"))
	lamps.append(lamp)

func reception_and_lab() -> void:
	# All tables and partitions leave the west mainline aisle at X=-42 clear.
	asset("computer-wide",Vector3(-30,0.3,-326.8),Vector3(4,1.3,1.6),0,true)
	plate(Vector3(-30,2.35,-327.4),"station_plan",Vector2(3.8,1.9))
	world.box(Vector3(-30,1.2,-327.5),Vector3(4.2,2,0.2),Color("405b69"),false)
	world.station("record",Vector3(-34,1.3,-325.5),"科考楼值班台：样本处理在西侧，设备检修在东侧附间，能源由后部保险柜保管。首席带钥匙随深入小队进入遗迹。旁路电源只影响实验设备，不影响保险柜。",false,false)
	asset("table-large",Vector3(-48,0.3,-332),Vector3(4.5,1,2.4),0,true)
	asset("computer-screen",Vector3(-49.4,1.3,-332.7),Vector3(0.9,0.85,0.7))
	asset("table-display-planet",Vector3(-47.2,1.3,-332.4),Vector3(1.4,0.7,1.2))
	plate(Vector3(-48,3.0,-333.5),"sample_process",Vector2(4.5,2.25))
	world.box(Vector3(-48,1.8,-333.65),Vector3(4.7,3,0.18),Color("4f6a76"),false)
	sample = Node3D.new()
	sample.position = Vector3(-48,1.5,-331.8)
	add_child(sample)
	var orb: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.36
	sphere.height = 0.55
	orb.mesh = sphere
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = Color("c58bad")
	orb.material_override = skin
	sample.add_child(orb)
	var tissue: StaticBody3D = world.box(Vector3(-48,1.5,-331.8),Vector3(0.7,0.5,0.7),Color("c58bad"))
	(tissue.get_child(0) as MeshInstance3D).visible = false
	tissue.set_meta("lab_specimen",true)
	sample_screen = panel(Vector3(-49.4,1.95,-332.28),Vector3(0.6,0.32,0.025),Color("294957"))
	sample_cover = world.ice.size()
	var cover: Node3D = world.frost(Vector3(-48,2.1,-331.8),Vector3(2.8,1.6,1.8))
	cover.reveal_contents = true
	cover.apply_amount(0)
	world.stations.append({"kind":"lab_sample","point":Vector3(-48,1.3,-330.8),"cover":sample_cover,"text":"样本台：融开托盘冰层，恢复实验旁路电源后按 E 观察。记录不影响保险柜与返航。"})
	for z: float in [-338,-345,-353]:
		asset("container-tall",Vector3(-49,0.3,z),Vector3(2.0,2.4,1.4),PI/2,true)
		for i: int in 3:
			world.specimen(Vector3(-47.9,0.9+i*0.55,z),0.2,Color("78b5c6") if i%2==0 else Color("c4a87d"))
	# A cold cabinet and tagged return rack give sample movement a clear purpose.
	asset("container-wide",Vector3(-26,0.3,-332),Vector3(3.8,1.2,1.5),0,true)
	asset("computer-system",Vector3(-26,1.5,-332),Vector3(1.1,0.9,1))
	world.content.cache("station_medical",Vector3(-48,0.3,-351),["medical","cell"],false)
	work_light(Vector3(-47,4.3,-333))
	work_light(Vector3(-29,4.5,-329))
	# Overhead utility trunks link the service room and instruments.
	world.content.line(Vector3(-49,4.2,-336),Vector3(-20,4.2,-336),0.12,Color("8aa0a7"))
	world.content.line(Vector3(-49,4.2,-336),Vector3(-49,4.2,-353),0.12,Color("8aa0a7"))
	# A delivery apron connects sample intake to the existing transport axis.
	for x: float in [-31,-26]:
		world.content.line(Vector3(x,0.38,-307),Vector3(x,0.38,-321),0.06,Color("d6af6d"))
	asset("container-wide",Vector3(-12,0.3,-311),Vector3(3.2,1.1,1.8),0,true)
	asset("container",Vector3(-15,0.3,-313),Vector3(1.6,1.6,1.4),0,true)

func service_annex() -> void:
	world.box(Vector3(-10.75,0.1,-335),Vector3(18.5,0.2,22),Color("58717d"))
	world.box(Vector3(-1.5,2.6,-335),Vector3(0.3,5.2,22),Color("3d5868"))
	world.box(Vector3(-10.75,2.6,-346),Vector3(18.5,5.2,0.3),Color("3d5868"))
	world.box(Vector3(-10.75,2.6,-324),Vector3(18.5,5.2,0.3),Color("3d5868"))
	world.box(Vector3(-10.75,5.2,-335),Vector3(18.5,0.25,22),Color("3d5868"))
	# The existing main building's split wall is the annex's west wall.
	door = world.box(Vector3(-19.8,1.7,-335),Vector3(0.28,3.4,4.2),Color("82a8b2"))
	hatch_cover = world.ice.size()
	var cover: Node3D = world.frost(Vector3(-20.25,1.95,-335),Vector3(0.9,3.3,4.2))
	cover.reveal_contents = true
	cover.apply_amount(0)
	plate(Vector3(-20.8,2.4,-338.9),"thaw_hatch",Vector2(2.7,1.35),-PI/2)
	world.stations.append({"kind":"lab_hatch","point":Vector3(-21.5,1.3,-335),"cover":hatch_cover,"text":"检修门：便携热风融开封冰，按 E 滑开门；沿原门返回主楼。"})
	asset("computer-system",Vector3(-10,0.3,-341),Vector3(2.3,2.3,1.2),0,true)
	handle = world.box(Vector3(-10,1.7,-340.3),Vector3(0.16,0.8,0.18),Color("dfad66"),false)
	plate(Vector3(-10,3.6,-341.5),"relay",Vector2(3.5,1.75))
	world.stations.append({"kind":"lab_relay","point":Vector3(-10,1.3,-340),"text":"旁路电源：E 复位，恢复实验台与本地充电台；能源保险柜仍由钥匙开启。"})
	world.station("charge",Vector3(-3,1.3,-340),"实验维护台：旁路通电后，按住 E 为热风机慢充与补氧。",false)
	world.stations[-1].station03_power = true
	asset("container-tall",Vector3(-3,0.3,-344),Vector3(2.1,2.7,1.2),0,true)
	for x: float in [-16,-13]:
		asset("pipe",Vector3(x,0.3,-344),Vector3(0.45,3.9,0.6))
		asset("pipe-bend",Vector3(x,3.7,-343.5),Vector3(0.7,0.6,1.3))
	for x: float in [-15,-5]:
		asset("structure-panel",Vector3(x,0.5,-345.4),Vector3(3.5,3.5,0.2))
	asset("table-inset",Vector3(-4,0.3,-328),Vector3(3,0.9,1.4),0,true)
	for i: int in 3:
		asset("container",Vector3(-5+i,1.2,-328),Vector3(0.65,0.65,0.6))
	world.content.line(Vector3(-15,4,-344),Vector3(-3,4,-344),0.10,Color("91a6ae"))
	world.content.cache("station_spares",Vector3(-9,0.3,-328),["cell","fuel","oxygen"],false)
	work_light(Vector3(-9,4.5,-335))

func observation_deck() -> void:
	# Leave the hatch approach clear and keep the stair channel open overhead.
	world.box(Vector3(-29.5,2.95,-349),Vector3(9,0.5,14),Color("5e7a88"))
	world.box(Vector3(-24,2.95,-354),Vector3(7,0.5,4),Color("5e7a88"))
	world.ramp(Vector3(-22.6,0.3,-339.5),Vector3(-22.6,3.2,-352.2),3.0)
	for x: float in [-33,-25.3]:
		for z: float in [-354,-343]:
			world.box(Vector3(x,1.6,z),Vector3(0.25,3.2,0.25),Color("6f8894"))
	world.content.handrail(Vector3(-33.3,3.2,-342.2),Vector3(-25.3,3.2,-342.2))
	world.content.handrail(Vector3(-33.3,3.2,-342.2),Vector3(-33.3,3.2,-355))
	asset("table-inset",Vector3(-28,3.2,-354.5),Vector3(4.5,0.9,1.6),0,true)
	asset("computer-wide",Vector3(-28,4.1,-354.5),Vector3(1.7,0.9,1.1))
	world.station("record",Vector3(-28,4.2,-353),"观察档案：窗外骨口与科考道路相接。出发小队携带防护样件，首席随身保管能源钥匙。求救先于暴雪停航；其后留守人员撤离，搜救未完成。",false,false)
	plate(Vector3(-25,4.8,-352),"evac_timeline",Vector2(3,1.5),-PI/2)
	asset("container",Vector3(-31,3.2,-347),Vector3(1.5,1.2,1.3),0,true)
	world.supply("fuel",Vector3(-31,4.7,-347))
	world.supply("cell",Vector3(-30.2,4.7,-347))
	work_light(Vector3(-27,6,-350))

func energy_store() -> void:
	for x: float in [-38.2,-33.8]:
		world.box(Vector3(x,1.9,-349.6),Vector3(0.22,3.5,2),Color("87a5b0"))
	world.box(Vector3(-36,3.7,-349.6),Vector3(4.6,0.25,2),Color("87a5b0"))
	world.box(Vector3(-36,1.9,-350.55),Vector3(4.6,3.5,0.18),Color("3d5868"))
	safe_door = Node3D.new()
	safe_door.position = Vector3(-38.1,1.9,-348.5)
	add_child(safe_door)
	var leaf: MeshInstance3D = panel(Vector3(2.1,0,0),Vector3(4.2,3.3,0.15),Color("8aa6b0"))
	leaf.reparent(safe_door,false)
	var face: Node3D = plate(Vector3(2.1,0,0.09),"energy_case",Vector2(3.7,1.85))
	face.reparent(safe_door,false)
	energy = asset("container",Vector3(-36,1.6,-349.5),Vector3(1.1,1.1,0.9))
	var core_light: MeshInstance3D = panel(Vector3(-36,2.2,-348.98),Vector3(0.24,0.7,0.04),Color("c3e9e3"))
	core_light.reparent(energy,true)
	world.content.line(Vector3(-39,0.35,-346),Vector3(-33,0.35,-346),0.04,Color("e0ae66"))

func state(director: Node) -> Dictionary:
	return director.progress.get("station03",{})

func location(point: Vector3) -> String:
	if point.z > -357.5 and point.z < -322.5:
		if point.x > -20 and point.x < -1.5:
			return "科考站 · 检修附间"
		if point.x > -52 and point.x < -20:
			if point.y > 2.7:
				return "科考站 · 观察夹层"
			return "科考站 · 样本处理" if point.x < -44 else "科考站 · 能源与档案"
	return ""

func interact(director: Node, id: int, entry: Dictionary) -> void:
	var data: Dictionary = state(director).duplicate(true)
	match entry.kind:
		"lab_hatch":
			if world.ice[hatch_cover].amount<0.98:
				director.tell(id,"检修门被封冰包住 · 先用热风机融开")
				return
			data.hatch_open = true
			director.tell(id,"检修门已滑开 · 里面的旁路手柄能恢复实验设备")
		"lab_relay":
			if not data.get("hatch_open",false):
				director.tell(id,"先从检修门进入附间")
				return
			data.power_on = true
			director.tell(id,"实验区已通电 · 仪器与附间维护台恢复，保险柜仍需钥匙")
		"lab_sample":
			if not data.get("power_on",false):
				director.tell(id,"样本观察仪没有电 · 东侧检修间有实验旁路手柄")
				return
			if world.ice[sample_cover].amount<0.98:
				director.tell(id,"样本托盘尚未解冻 · 用热风机融去表层冰")
				return
			data.sample_read = true
			var fact: String = "样本观察：骨质与遗迹大骨架纹理一致。继续对粉色切片吹风可观察鼓胀，松手后缓慢回缩；切片不会弹射。科考队在研究生物遗骸与存活后代。"
			var notes: Array = director.progress.get("notes",[])
			if fact not in notes:
				notes.append(fact)
				director.progress.notes = notes
			director.tell(id,fact)
	director.progress.station03 = data
	apply_progress(director.progress)

func heat(director: Node, delta: float) -> void:
	var data: Dictionary = state(director).duplicate(true)
	data.sample_heat = minf(1.0,float(data.get("sample_heat",0))+delta*0.6)
	director.progress.station03 = data

func tick(director: Node, delta: float) -> void:
	var data: Dictionary = state(director)
	if float(data.get("sample_heat",0))>0:
		data.sample_heat = maxf(0,float(data.sample_heat)-delta*0.10)
		director.progress.station03 = data

func apply_progress(progress: Dictionary) -> void:
	var data: Dictionary = progress.get("station03",{})
	var powered: bool = data.get("power_on",false)
	door.position.z = -339.8 if data.get("hatch_open",false) else -335.0
	handle.rotation.z = -0.8 if powered else 0.8
	for light: OmniLight3D in power_lights:
		light.light_energy = 1.0 if powered else 0.13
	for lamp: MeshInstance3D in lamps:
		var material: StandardMaterial3D = lamp.material_override as StandardMaterial3D
		material.albedo_color = Color("c7e8df") if powered else Color("587783")
		material.emission_enabled = powered
		material.emission = Color("9ccebf")
		material.emission_energy_multiplier = 0.5
	var screen: StandardMaterial3D = sample_screen.material_override as StandardMaterial3D
	screen.albedo_color = Color("b5d5b9") if data.get("sample_read",false) else (Color("679fba") if powered else Color("294957"))
	sample.rotation.y = 0.7 if data.get("sample_read",false) else 0.0
	var warmth: float = float(data.get("sample_heat",0))
	sample.scale = Vector3(1+warmth*0.4,1+warmth*0.8,1+warmth*0.4)
	energy.visible = not progress.energy and not progress.installed
	safe_door.rotation.y = -1.5 if progress.energy or progress.installed else 0.0

func _process(_delta: float) -> void:
	if world == null:
		return
	var director: Node = world.get_parent()
	if director.game_started:
		apply_progress(director.progress)
