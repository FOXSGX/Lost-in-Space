extends Node3D

# Optional local loops. The common spine remains the reversible main route.
var world: Node3D
var caches: Array[Dictionary] = []
var landmarks: Dictionary = {}
var wind: AudioStreamPlayer
var cavity: AudioStreamPlayer

func build(owner_world: Node3D) -> void:
	world = owner_world
	base_life()
	rib_sled()
	nest_overlook()
	incident_terrace()
	ambience()

func sign_at(point: Vector3, key: String, width: float = 3.0, mount_y: float = 0.3) -> void:
	# Fixed framed panels mounted on two real supports, never billboards.
	world.box(point-Vector3(0,0,0.08),Vector3(width, width*0.5,0.16),Color("273f4b"),false)
	for side: float in [-1,1]:
		var top: float = point.y-width*0.24
		world.box(Vector3(point.x+side*width*0.4,(top+mount_y)*0.5,point.z-0.08),Vector3(0.09,maxf(0.05,top-mount_y),0.09),world.BONE,false)
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(width-0.08,width*0.5-0.08)
	visual.mesh = mesh
	visual.position = point+Vector3(0,0,0.02)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load("res://previews/frost_first_playable/signs/"+key+".png")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	add_child(visual)

func line(from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var view: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 8
	view.mesh = mesh
	view.position = (from+to)*0.5
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color.srgb_to_linear()
	view.material_override = material
	add_child(view)
	view.quaternion = Quaternion(Vector3.UP,(to-from).normalized())

func handrail(from: Vector3, to: Vector3) -> void:
	line(from+Vector3.UP,to+Vector3.UP,0.055,Color("d9ab6d"))
	var count: int = maxi(1,int(from.distance_to(to)/3))
	for i: int in count+1:
		var p: Vector3 = from.lerp(to,float(i)/count)
		line(p,p+Vector3.UP,0.07,Color("5b7380"))

func cache(id: String, base: Vector3, rewards: Array, frozen: bool) -> void:
	world.box(base+Vector3.UP*0.25,Vector3(2.3,0.5,1.7),Color("536e7a"))
	for side: float in [-1,1]:
		world.box(base+Vector3(side*1.1,0.65,0),Vector3(0.12,0.8,1.7),Color("b58f59"))
	var lid: StaticBody3D = world.box(base+Vector3(0,1.05,-0.65),Vector3(2.3,0.12,1.7),Color("d4aa6a"),false)
	var cover: int = -1
	if frozen:
		cover = world.ice.size()
		var ice_cover: Node3D = world.frost(base+Vector3.UP*1.7,Vector3(5.2,3.4,4.2))
		ice_cover.reveal_contents = true
		ice_cover.apply_amount(0)
	var point: Vector3 = base+Vector3(0,0.8,0.9)
	world.stations.append({"kind":"cache","id":id,"point":point,"cover":cover,"rewards":rewards,"text":"科考运输箱 · 融去封冰后取用物资；不刷新。"})
	caches.append({"id":id,"lid":lid})
	landmarks[id] = {"base":base,"point":point,"cover":cover}
	sign_at(base+Vector3(0,2.9,-1.05),"cache",2.7,base.y+1.05)

func base_life() -> void:
	# Warehouse loading tracks lead from the apron axis to the stock bays.
	for x: float in [-40,-36]:
		line(Vector3(x,0.46,-72),Vector3(x,0.46,-104),0.08,Color("b6bcc0"))
	for x: float in [-48,-28]:
		world.box(Vector3(x,0.7,-102),Vector3(5,0.45,8),Color("637a84"))
		for z: float in [-104,-100]:
			world.box(Vector3(x,1.7,z),Vector3(3.5,1.6,2.5),Color("a88a62"))
	# Bunks face a shared table, left behind in haste but not a battlefield.
	for z: float in [-199,-211,-220]:
		for height: float in [0.8,2.5]:
			world.box(Vector3(49,height,z),Vector3(3.8,0.25,6),Color("6b8898"))
			world.box(Vector3(49,height+0.25,z),Vector3(3.6,0.3,5.7),Color("a9b9b8"),false)
			world.box(Vector3(49,height+0.5,z-1.8),Vector3(3,0.35,1.4),Color("c2a98b"),false)
		for dx: float in [-1.9,1.9]:
			line(Vector3(49+dx,0.2,z-2.8),Vector3(49+dx,3,z-2.8),0.09,Color("546b76"))
	world.box(Vector3(29,1.2,-211),Vector3(5,0.25,7),Color("a6977f"))
	for z: float in [-208,-213]:
		world.box(Vector3(25,0.65,z),Vector3(1.5,0.8,1.5),Color("6b7f88"))
		world.specimen(Vector3(29,1.55,z),0.25,Color("ceb48e"))
	sign_at(Vector3(38,3.3,-225.5),"evacuation",5)
	# Empty docking clamps and bundled gear emphasize an orderly later evacuation.
	for x: float in [24,28,32]:
		world.box(Vector3(x,0.65,-229),Vector3(2.5,1,2),Color("657883"))
		line(Vector3(x-0.7,1.3,-229),Vector3(x+0.7,1.3,-229),0.07,Color("d0a46b"))

func rib_sled() -> void:
	sign_at(Vector3(9,2.4,-471),"rib_route",4)
	var site: Vector3 = Vector3(-44,0.35,-516)
	# Low shelf, wide snow approach, and skid marks connect it to expedition work.
	world.box(site-Vector3.UP*0.2,Vector3(15,0.4,14),world.BONE)
	for x: float in [-46,-42]:
		line(Vector3(x,0.45,-498),Vector3(x,0.45,-520),0.1,Color("d1ad79"))
	world.ramp(Vector3(-53,0.35,-500),Vector3(-53,0.35,-516),6)
	cache("rib_sled",site+Vector3.UP*0.4,["cell","medical","fuel"],true)
	world.lamp(site+Vector3(-4,2,4),Color("78bbd0"),13)
	world.station("record",Vector3(-56,1.2,-505),"运输橇记录：货物太重，先留在入口。电池不够时融开箱体取用；封冰只在表层，暗岩和骨骼不融。")

func nest_overlook() -> void:
	sign_at(Vector3(9,2.5,-620),"nest_route",4)
	# Existing eastern organism throws towards this broad platform. The rear
	# slope is reversible even with empty oxygen tanks and a flat battery.
	world.box(Vector3(27,4.85,-716),Vector3(20,0.7,16),world.BONE)
	world.box(Vector3(40,4.85,-710),Vector3(9,0.7,8),world.BONE)
	world.ramp(Vector3(43,0.35,-683),Vector3(43,5.2,-706.2),6)
	handrail(Vector3(18,5.2,-724),Vector3(36,5.2,-724))
	handrail(Vector3(18,5.2,-724),Vector3(18,5.2,-710))
	for x: float in [20,25,30,35]:
		world.box(Vector3(x,5.23,-708.5),Vector3(0.6,0.05,1.2),Color("e2b571"),false)
	cache("nest_overlook",Vector3(28,5.2,-718),["fuel","cell"],false)
	landmarks["nest_launch"] = Vector3(25,0.3,-702)
	landmarks["nest_landing"] = Vector3(25,5.2,-711)
	world.station("record",Vector3(22,6,-719),"观察员便笺：给幼体背部加热，收缩前会鼓起、变亮并发声。落台后可从东侧缓坡下来；不要把队友和样件留在背上。")
	# Colony rings and membranes give this room a living silhouette.
	for i: int in 7:
		var p: Vector3 = Vector3(-53+i*3,2+float(i%3),-654-i*6)
		world.specimen(p,2.8,Color("b58bb7"))
		line(p,p+Vector3(2,5,-2),0.18,Color("90728f"))
	valve(Vector3(22,8.0,-675),false)
	sign_at(Vector3(22,10.1,-676),"valve_normal",2.6,8.0)

func valve(point: Vector3, damaged: bool) -> void:
	world.box(point+Vector3.UP*0.35,Vector3(2,0.65,1.1),Color("64838b"),false)
	world.specimen(point+Vector3(0,0.9,0),0.55,Color("91b1b8"))
	for i: int in (1 if damaged else 3):
		world.box(point+Vector3(-0.6+i*0.6,0.9,0.52),Vector3(0.13,0.5,0.13),Color("e4bb72"),false)
	if damaged:
		world.box(point+Vector3(1.7,0.02,0),Vector3(1.1,0.04,1.1),Color("a0b0b5"),false)
		for i: int in 2:
			world.box(point+Vector3(1.5+i*0.35,0.12,0),Vector3(0.13,0.13,0.5),Color("e4bb72"),false)
		line(point+Vector3(-0.8,0.7,0.5),point+Vector3(0.8,0.7,0.5),0.045,Color("dc8d61"))

func incident_terrace() -> void:
	sign_at(Vector3(9,2.5,-770),"incident_route",4)
	world.box(Vector3(44,4.15,-854),Vector3(20,0.7,16),world.BONE)
	world.ramp(Vector3(50,0.35,-821),Vector3(50,4.5,-846.2),6)
	handrail(Vector3(35,4.5,-862),Vector3(53,4.5,-862))
	world.box(Vector3(43,4.95,-860),Vector3(5,0.9,2),Color("4a5d68"))
	valve(Vector3(42,5.4,-860),true)
	sign_at(Vector3(43,7.1,-861),"valve_damaged",3,5.4)
	world.station("record",Vector3(44,5.4,-859.5),"侧台检验：两枚锁销完整放在工具布上，线束被另一根线旁接；护壳外侧碎裂，里面的拆装面却整齐。记录只能证明有人动过设备，不能确定操作者或动机。",false,false)
	cache("incident_kit",Vector3(49,4.5,-857),["medical","cell"],false)
	for side: float in [-1,1]:
		var rib: StaticBody3D = world.box(Vector3(side*48,12,-865),Vector3(3,25,4),world.BONE,false)
		rib.rotation.z = side*0.9
		world.rounded_bone(rib,25,1.7)
	# Return markers are physical amber lamps rather than an added shortcut.
	for z: float in [-781,-804,-845]:
		world.lamp(Vector3(-8,1.7,z),Color("daa264"),13)

func apply_progress(progress: Dictionary) -> void:
	var opened: Array = progress.get("opened_caches",[])
	for entry: Dictionary in caches:
		entry.lid.rotation.x = -1.2 if entry.id in opened else 0.0

func ambience() -> void:
	wind = AudioStreamPlayer.new()
	var wind_stream: AudioStreamWAV = load("res://previews/frost_first_playable/audio/wind.wav").duplicate() as AudioStreamWAV
	wind_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind_stream.loop_end = int(wind_stream.get_length()*wind_stream.mix_rate)
	wind.stream = wind_stream
	wind.volume_db = -24
	add_child(wind)
	wind.play()
	cavity = AudioStreamPlayer.new()
	var cave_stream: AudioStreamWAV = load("res://previews/frost_first_playable/audio/cavity.wav").duplicate() as AudioStreamWAV
	cave_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	cave_stream.loop_end = int(cave_stream.get_length()*cave_stream.mix_rate)
	cavity.stream = cave_stream
	cavity.volume_db = -50
	add_child(cavity)
	cavity.play()

func _process(delta: float) -> void:
	var director: Node3D = world.get_parent()
	if not director.game_started:
		return
	apply_progress(director.progress)
	var actor: Node3D = director.players.get(multiplayer.get_unique_id()) as Node3D
	if actor != null:
		var interior: float = clampf((-actor.position.z-454)/30,0,1)
		wind.volume_db = lerpf(wind.volume_db,lerpf(-24,-48,interior),minf(1,delta*2))
		cavity.volume_db = lerpf(cavity.volume_db,lerpf(-50,-22,interior),minf(1,delta*2))
