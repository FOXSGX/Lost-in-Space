extends "res://previews/frost_first_playable/world.gd"

const FROST_ART: Script = preload("res://previews/frost_station/frost_art.gd")
const BASIN_TERRAIN: Script = preload("res://previews/frost_station/basin_terrain.gd")
const OPEN_SHELF_GLB: PackedScene = preload("res://assets/models/rebuild/hero_open_supply_shelf.glb")
const COUNTER_SHELF_GLB: PackedScene = preload("res://assets/models/rebuild/hero_wall_counter_shelf.glb")

var _shelf_pbr: ArtPbrLib

var rooms: Dictionary = {}
var extra_rooms: Dictionary = {}
var landmarks: Dictionary = {}
var power_lights: Array[OmniLight3D] = []
var radar_lights: Array[OmniLight3D] = []
var power_parts: Array[MeshInstance3D] = []
var cart: CharacterBody3D
var snowmobile: CharacterBody3D
var art: Node3D
var frost_art: Node3D
var basin_terrain: Node3D
var warehouse_ice: Array[int] = []
var museum_bones: Array[Node3D] = []
var safe_door: Node3D
var energy_visual: Node3D
var collection_models: Array[Node3D] = []

func box(point: Vector3, size_value: Vector3, color: Color, collision: bool = true) -> StaticBody3D:
	var tint: Color = color
	if color == ROCK and size_value.y>3 and (size_value.x<0.7 or size_value.z<0.7):tint = Color("75919c")
	return super.box(point,size_value,tint,collision)

func build(_small: bool = false) -> void:
	sky()
	art = load("res://previews/frost_first_playable/research_station.gd").new()
	art.world = self
	add_child(art)
	art.set_process(false)
	# 404×310m 宽阔平整极地科考城主地坪（容纳全部 15 栋大型建筑 + 飞船与宽阔车行大道）
	box(Vector3(0,-0.5,-60),Vector3(404,1,310),ROCK)
	for x: int in range(-6,7):
		for z: int in range(-16,4):
			var covered: bool = false
			for area: Vector4 in [Vector4(0,-110,60,32),Vector4(-49,-70,32,38),Vector4(49,-63,32,38),Vector4(58,-116,26,28),Vector4(46,-22,44,28),Vector4(-43,-22,40,28)]:
				if absf(float(x*11)-area.x)<area.z/2+5.5 and absf(float(z*12)-area.y)<area.w/2+6:covered = true
			if not covered:frost(Vector3(x*11,0.13,z*12),Vector3(11,0.26,12))
	ship()
	main_building()
	museum()
	living()
	power_station()
	garage()
	warehouse()
	_build_expanded_town_buildings()
	_place_courtyard_toys()
	for z: float in [-80,-65,-50]:
		box(Vector3(0,0.25,z),Vector3(10,0.15,13),Color("7a9198"))
	for x: float in [-19,19]:
		for z: float in [-82,-52]:
			box(Vector3(x,0.5,z),Vector3(2.5,0.6,1.6),Color("91a8ac"))
	# 720×920m 立体极地盆地程序化地形（替代旧版紧贴站区的旋转方盒岩脊）
	basin_terrain = BASIN_TERRAIN.new() as Node3D
	add_child(basin_terrain)
	basin_terrain.build()
	_build_outer_basin_expedition()
	# A real ground route east of the main building links the yard to the bone mouth.
	for z: int in range(-82,-191,-14):
		box(Vector3(36,0.23,z),Vector3(9,0.12,12),Color("697e88"))
	# 旧版方盒骨口已由 frost_art 中的四道 Blender 雕塑古骨巨肋拱（hero_fossil_arch.glb）替代
	hall(0,-250,Color("78b4c1"))
	hall(1,-400,Color("b38bc6"))
	hall(2,-550,Color("d9a570"))
	landmarks.merge({"ship":Vector3(0,0.9,8),"main_entry":Vector3(0,0.35,-91),"lab":Vector3(17,0.35,-103),"stairs_bottom":Vector3(-23,0.35,-96),"stairs_top":Vector3(-23,4.35,-116),"safe":Vector3(-5,5.1,-120),"gallery":Vector3(19,4.35,-120),"mouth":Vector3(0,0.35,-185),"key":Vector3(-2.4,12.9,-602)})
	for z: float in [-160,-100,-60,-20]:
		var light: OmniLight3D = district_lamp(Vector3(31,3,z))
		power_lights.append(light)
	install_art()

## 美术层只在视觉上加东西；FROST_ART=0 可整体关闭，用于同机位改造前后对照。
func install_art() -> void:
	if OS.get_environment("FROST_ART") == "0":
		return
	frost_art = FROST_ART.new()
	frost_art.name = "FrostArt"
	add_child(frost_art)
	frost_art.install(self)

func shell(id: String, center: Vector3, width: float, depth: float, tint: Color, door_width: float = 7.0, height: float = 7.0) -> void:
	rooms[id] = {"center":center,"width":width,"depth":depth}
	box(center+Vector3(0,0.1,0),Vector3(width,0.2,depth),Color("7c929c"))
	box(center+Vector3(-width/2,height/2,0),Vector3(0.5,height,depth),ROCK)
	box(center+Vector3(width/2,height/2,0),Vector3(0.5,height,depth),ROCK)
	box(center+Vector3(0,height/2,-depth/2),Vector3(width,height,0.5),ROCK)
	for side: float in [-1,1]:
		box(center+Vector3(side*(width+door_width)/4,height/2,depth/2),Vector3((width-door_width)/2,height,0.5),ROCK)
	box(center+Vector3(0,height-0.7,depth/2),Vector3(door_width,1.4,0.5),tint)
	box(center+Vector3(0,height,0),Vector3(width+0.5,0.35,depth+0.5),ROCK)
	for side: float in [-1,1]:
		box(center+Vector3(side*(door_width/2+0.2),2,depth/2+0.3),Vector3(0.16,4,0.12),tint,false)
	panel_sign(center+Vector3(0,height-0.6,depth/2+0.32),id,Vector2(minf(width*0.7,9),2.4))
	lamp(center+Vector3(0,4,0),Color("b4d4df"),maxf(width,depth)*0.65)
	for side: float in [-1,1]:
		box(center+Vector3(side*(width/2-0.4),1.0,0),Vector3(0.12,0.35,depth-1),tint,false)
	landmarks[id] = center+Vector3(0,0.35,depth/2+3)

func partition(point: Vector3, width: float, height: float = 3.8, gap: float = 3.0) -> void:
	for side: float in [-1,1]:
		box(point+Vector3(side*(width+gap)/4,height/2,0),Vector3((width-gap)/2,height,0.22),Color("69838d"))

func panel_sign(point: Vector3, key: String, size_value: Vector2 = Vector2(4,1.8)) -> void:
	box(point-Vector3(0,0,0.07),Vector3(size_value.x+0.12,size_value.y+0.12,0.12),Color("294955"),false)
	var view: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size_value
	view.mesh = quad
	view.position = point
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load("res://previews/frost_station/signs/"+key+".png")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view.material_override = material
	add_child(view)

func furniture(key: String, point: Vector3, size_value: Vector3, yaw: float = 0) -> void:
	art.asset(key,point,size_value,yaw,true)

## 精确计算每种可拾取物品的半高，确保稳稳贴合桌面/柜台/栈板表面（零悬空、零穿模、零滚落）
func _item_half_height(kind: String) -> float:
	return {
		"oxygen": 0.34,
		"medical": 0.21,
		"heater": 0.19,
		"cell": 0.19,
		"fuel": 0.20,
		"suction": 0.24,
		"chips": 0.21,
		"keepsake": 0.15,
		"crate": 0.28,
		"bounce_pad": 0.16,
		"flare": 0.29,
		"boombox": 0.21,
		"bumper_orb": 0.32,
		"thermos": 0.24,
	}.get(kind, 0.21)

## 将物品以自然朝向稳稳摆放在指定支撑面高度上（货架层板/壁柜台面/床头柜/货箱顶面）
func on_surface(kind: String, x: float, surface_y: float, z: float, yaw_deg: float = 0.0, data: Dictionary = {}) -> void:
	var extra: Dictionary = data.duplicate(true)
	extra["yaw"] = deg_to_rad(yaw_deg)
	extra["placed"] = true
	supply(kind, Vector3(x, surface_y + _item_half_height(kind) + 0.004, z), extra)

func _add_shelf_collider(parent: Node3D, local_pos: Vector3, sz: Vector3, layer: int) -> void:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.position = local_pos
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bx: BoxShape3D = BoxShape3D.new()
	bx.size = sz
	cs.shape = bx
	sb.add_child(cs)
	parent.add_child(sb)

## 开放式三层工业极地物资货架（下层 0.56m / 中层 1.24m / 上层 1.92m），自然分层陈列物品！
## items 元素格式：[kind, tier(0/1/2), local_x, local_z, local_yaw_deg, extra_dict]
func open_shelf(base_pos: Vector3, yaw_deg: float, items: Array) -> Node3D:
	if _shelf_pbr == null:
		_shelf_pbr = ArtPbrLib.new()
	var holder: Node3D = Node3D.new()
	holder.name = "OpenSupplyShelf"
	holder.position = base_pos
	holder.rotation_degrees.y = yaw_deg
	add_child(holder)
	var vis: Node3D = OPEN_SHELF_GLB.instantiate() as Node3D
	_shelf_pbr.bind_glb(vis, "frost", true)
	holder.add_child(vis)
	# 背板与两侧立柱用 layer=2 阻挡穿墙；三层实心托板用 layer=1 托住刚体物品且绝不遮挡正面伸手拿取！
	_add_shelf_collider(holder, Vector3(0.0, 1.16, -0.40), Vector3(3.32, 2.32, 0.14), 2)
	for sx: float in [-1.64, 1.64]:
		_add_shelf_collider(holder, Vector3(sx, 1.16, 0.0), Vector3(0.14, 2.32, 0.86), 2)
	var tier_heights: Array[float] = [0.56, 1.24, 1.92]
	for ty: float in tier_heights:
		_add_shelf_collider(holder, Vector3(0.0, ty - 0.03, 0.0), Vector3(3.26, 0.06, 0.84), 1)
	var basis_y: Basis = Basis(Vector3.UP, deg_to_rad(yaw_deg))
	for item_spec: Array in items:
		var kind: String = String(item_spec[0])
		var tier: int = clampi(int(item_spec[1]), 0, 2)
		var lx: float = float(item_spec[2])
		var lz: float = float(item_spec[3])
		var lyaw: float = float(item_spec[4])
		var extra: Dictionary = (item_spec[5] as Dictionary) if item_spec.size() > 5 else {}
		var world_p: Vector3 = base_pos + basis_y * Vector3(lx, 0.0, lz)
		on_surface(kind, world_p.x, base_pos.y + tier_heights[tier], world_p.z, yaw_deg + lyaw, extra)
	return holder

## 生活/医疗/实验壁挂双层柜台架（下柜台面 0.96m / 上层壁架 1.64m），充满生活烟火气！
## items 元素格式：[kind, tier(0=台面/1=上架), local_x, local_z, local_yaw_deg, extra_dict]
func counter_shelf(base_pos: Vector3, yaw_deg: float, items: Array) -> Node3D:
	if _shelf_pbr == null:
		_shelf_pbr = ArtPbrLib.new()
	var holder: Node3D = Node3D.new()
	holder.name = "WallCounterShelf"
	holder.position = base_pos
	holder.rotation_degrees.y = yaw_deg
	add_child(holder)
	var vis: Node3D = COUNTER_SHELF_GLB.instantiate() as Node3D
	_shelf_pbr.bind_glb(vis, "frost", true)
	holder.add_child(vis)
	# 下柜体与背板用 layer=2，上层开放置物板用 layer=1 保证拿取顺手
	_add_shelf_collider(holder, Vector3(0.0, 0.48, 0.0), Vector3(3.16, 0.96, 0.86), 2)
	_add_shelf_collider(holder, Vector3(0.0, 1.58, -0.40), Vector3(3.16, 1.24, 0.12), 2)
	_add_shelf_collider(holder, Vector3(0.0, 1.615, -0.10), Vector3(3.10, 0.05, 0.56), 1)
	var tier_heights: Array[float] = [0.96, 1.64]
	var basis_y: Basis = Basis(Vector3.UP, deg_to_rad(yaw_deg))
	for item_spec: Array in items:
		var kind: String = String(item_spec[0])
		var tier: int = clampi(int(item_spec[1]), 0, 1)
		var lx: float = float(item_spec[2])
		var lz: float = float(item_spec[3])
		var lyaw: float = float(item_spec[4])
		var extra: Dictionary = (item_spec[5] as Dictionary) if item_spec.size() > 5 else {}
		var world_p: Vector3 = base_pos + basis_y * Vector3(lx, 0.0, lz)
		on_surface(kind, world_p.x, base_pos.y + tier_heights[tier], world_p.z, yaw_deg + lyaw, extra)
	return holder

func ship() -> void:
	box(Vector3(0,0.35,7),Vector3(30,0.7,30),Color("607985"))
	ramp(Vector3(0,0.2,-11),Vector3(0,0.7,-6),24)
	shell("ship",Vector3(0,0.7,12),14,14,Color("e5b676"),6,7)
	for child: Node in get_children():
		if child is StaticBody3D and child.position.distance_to(Vector3(0,4.2,5))<0.1:child.queue_free()
	for x: float in [-5,5]:box(Vector3(x,4.2,5),Vector3(4,7,0.5),ROCK)
	station("core",Vector3(0,2.1,16),"核心已损坏。去主科研楼二层首席办公室寻找备用能源线索。")
	station("charge",Vector3(-5,2.1,9),"飞船维护台 · 按住 E 慢充热风机和补氧，动力站未恢复时也可用。")
	station("collection",Vector3(5,2.1,9),"生活收藏柜 · 携带纪念物按 E 收入，之后可在这里查看收藏。",false)
	station("board",Vector3(5.6,1.9,14.8),"返回飞船主舱 · 按 E 通过加压气闸舱门回到【归航号】主舱",false)
	for i: int in 4:
		var cup: StaticBody3D = box(Vector3(4.5+float(i)*0.32,2.76,9),Vector3(0.23,0.3,0.23),Color("9bcdd0"),false)
		cup.visible = false
		collection_models.append(cup)
	panel_sign(Vector3(0,3.2,18.7),"mission",Vector2(7,2.7))
	# 飞船出口两侧开放式三层出舱物资货架（像真实科考前哨装备架一样分上中下三层错落摆放，彻底告别死板展示桌！）
	open_shelf(Vector3(-10.5, 0.7, 0.8), 22.0, [
		["oxygen", 0, -0.78, 0.08, 12.0],
		["cell", 0, 0.36, 0.14, -18.0],
		["heater", 1, -0.68, 0.06, 20.0, {"charge": 180.0}],
		["flare", 1, 0.24, 0.10, -10.0],
		["thermos", 1, 0.92, 0.12, -25.0],
		["cell", 2, 0.12, 0.04, 15.0],
	])
	open_shelf(Vector3(10.5, 0.7, 0.8), -22.0, [
		["bounce_pad", 0, -0.58, 0.02, 8.0],
		["oxygen", 0, 0.82, 0.10, -10.0],
		["heater", 1, -0.72, 0.08, -16.0, {"charge": 180.0}],
		["boombox", 1, 0.56, 0.08, 14.0],
		["bumper_orb", 2, -0.10, 0.06, 0.0],
	])
	# 一出门正左前方向阳雪地上立刻就能看见并骑走的极地科幻雪地摩托（避开船首残骸与东侧 X=10 测试通道！）
	snowmobile = load("res://previews/frost_station/snowmobile.gd").new()
	snowmobile.name = "ArcticSnowmobile"
	add_child(snowmobile)
	snowmobile.setup(get_parent(), Vector3(-7.2, 0.85, -14.2), -24.0)
	landmarks["snowmobile"] = Vector3(-7.2, 0.85, -14.2)
	# Initial low snowbank can be melted, but never locks the whole open station.
	for x: float in [-2.5,0,2.5]:frost(Vector3(x,1.3,-10),Vector3(2.5,2.6,1.2))

func main_building() -> void:
	shell("main",Vector3(0,0,-110),60,32,Color("72c5ce"),10,9)
	# Upper deck leaves a true central void over the arrival hall.
	box(Vector3(0,4.05,-120),Vector3(58,0.3,10),Color("708f97"))
	box(Vector3(25,4.05,-104),Vector3(8,0.3,22),Color("708f97"))
	# Leave the stairwell open overhead instead of capping it with the ring deck.
	box(Vector3(-28,4.05,-104),Vector3(3,0.3,22),Color("708f97"))
	for x: float in [-20.5,20.5]:
		box(Vector3(x,4.8,-103),Vector3(0.12,1.3,21),Color("acc7c9"))
	box(Vector3(0,4.8,-114.8),Vector3(40,1.3,0.12),Color("acc7c9"))
	# Short 0.2 m risers support ordinary walking; no jet or powered lift required.
	for i: int in 20:
		box(Vector3(-23,0.1+float(i)*0.1,-96-float(i)),Vector3(5.0,0.2+float(i)*0.2,1.02),Color("abc0bc"))
	partition(Vector3(-12,0,-114),14)
	partition(Vector3(-12,0,-104),14)
	panel_sign(Vector3(-17,2.4,-113.8),"archives")
	furniture("computer-wide",Vector3(-18,0.2,-121),Vector3(4,1.3,1.7))
	furniture("container-tall",Vector3(-26,0.2,-118),Vector3(2,2.6,1.5))
	furniture("table-large",Vector3(15,0.2,-107),Vector3(6,1.1,2.7))
	furniture("table-display-planet",Vector3(21,0.2,-119),Vector3(3,1.8,3))
	furniture("container-tall",Vector3(27,0.2,-119),Vector3(2,2.6,1.5))
	furniture("container-tall",Vector3(-27,0.2,-110),Vector3(2,2.6,1.5))
	for point: Vector3 in [Vector3(-17,7.8,-105),Vector3(16,7.8,-105),Vector3(0,8.6,-120)]:
		box(point,Vector3(5,0.12,1),Color("d6e3d8"),false)
		lamp(point-Vector3.UP*0.3,Color("c1e0dd"),24)
	panel_sign(Vector3(10,3,-125.65),"suction",Vector2(7,2.4))
	# 东实验台保留 1 把吸推器（兼容原路线），后排与西侧改为真实科研三层架与壁挂柜台！
	on_surface("suction", 15.0, 1.30, -106.0, 14.0)
	open_shelf(Vector3(22.4, 0.2, -112.4), 0.0, [
		["cell", 0, -0.75, 0.10, 16.0],
		["suction", 1, 0.20, 0.08, -22.0],
		["flare", 2, -0.35, 0.06, 10.0],
	])
	counter_shelf(Vector3(-10.0, 0.2, -100.0), 180.0, [
		["thermos", 0, -0.78, 0.14, 24.0],
		["cell", 1, 0.56, -0.04, -14.0],
	])
	for x: float in [10.0, 14.0, 18.0]:
		on_surface("crate", x, 0.20, -102.0, 0.0)
	# The office has a broad door from the ring, and an actual cabinet upstairs.
	partition(Vector3(-5,4.2,-119),22,3.5,5)
	furniture("computer-wide",Vector3(-12,4.2,-123),Vector3(4,1.3,1.6))
	box(Vector3(-5,5.5,-123.55),Vector3(3,2.6,0.12),Color("5c7c87"))
	for x: float in [-6.4,-3.6]:box(Vector3(x,5.5,-123),Vector3(0.2,2.6,1.2),Color("5c7c87"))
	for y: float in [4.25,6.75]:box(Vector3(-5,y,-123),Vector3(3,0.12,1.2),Color("5c7c87"))
	safe_door = Node3D.new()
	safe_door.position = Vector3(-6.4,5.5,-122.35)
	add_child(safe_door)
	var leaf: StaticBody3D = box(Vector3.ZERO,Vector3(2.7,2.4,0.12),Color("d1b57a"),false)
	leaf.reparent(safe_door,false)
	leaf.position = Vector3(1.4,0,0)
	energy_visual = box(Vector3(-5,5.5,-123),Vector3(0.8,1,0.6),Color("9ae5d1"),false)
	station("safe",Vector3(-5,5.1,-121.5),"首席办公室：备用能源在保险柜里。首席带钥匙进入巨型骨口，前往遗迹深处，尚未返回。",false,false)
	panel_sign(Vector3(-5,6.6,-122.25),"safe",Vector2(2.4,1.4))
	# Cut a view window in the north upper wall without a new exit.
	for child: Node in get_children():
		if child is StaticBody3D and child.position.distance_to(Vector3(0,4.5,-126))<0.1:
			child.queue_free()
	box(Vector3(-8,4.5,-126),Vector3(44,9,0.5),ROCK)
	box(Vector3(27,4.5,-126),Vector3(6,9,0.5),ROCK)
	box(Vector3(19,1.8,-126),Vector3(10,3.6,0.5),ROCK)
	box(Vector3(19,8.8,-126),Vector3(10,0.4,0.5),ROCK)
	var glass: StaticBody3D = box(Vector3(19,6.05,-126),Vector3(10,4.9,0.16),Color("b9d9df"))
	var mat: StandardMaterial3D = glass.get_child(0).material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6,0.8,0.85,0.12)
	# Strong silhouette visible from the landing platform above the roof.
	box(Vector3(0,14,-116),Vector3(2,12,2),Color("93aeb5"))
	specimen(Vector3(0,21,-116),3,Color("74b8c6"))
	panel_sign(Vector3(-8,2.6,-93.65),"layout",Vector2(5,2))

func museum() -> void:
	shell("museum",Vector3(-49,0,-70),32,38,Color("c7b995"),7,11)
	for i: int in 7:
		var z: float = -83+float(i)*3.6
		for side: float in [-1,1]:
			var bone: StaticBody3D = box(Vector3(-49+side*3.4,3,z),Vector3(0.65,6,0.7),BONE)
			bone.rotation.z = side*0.45
			rounded_bone(bone,6,0.45)
			museum_bones.append(bone)
	box(Vector3(-49,2.7,-72),Vector3(0.8,0.8,28),BONE)
	for x: float in [-60,-38]:box(Vector3(x,4,-75),Vector3(0.5,8,0.5),Color("75919b"))
	counter_shelf(Vector3(-59.2, 0.2, -83.4), 0.0, [
		["thermos", 0, -0.72, 0.12, -18.0],
		["keepsake", 1, 0.45, -0.05, 22.0],
	])
	panel_sign(Vector3(-49,3.2,-88.65),"biology",Vector2(9,3.2))
	station("record",Vector3(-49,1.5,-86),"骨架介绍：长节骨脊与多对肋骨支撑巨大的躯体。标本仍在拼装；与遗迹骨架的关系尚待研究。",false,false)

func living() -> void:
	shell("living",Vector3(49,0,-63),32,38,Color("9dbb9f"))
	partition(Vector3(49,0,-65),30,3.5,5)
	partition(Vector3(49,0,-75),30,3.5,5)
	for x: float in [38,60]:
		for z: float in [-78,-70]:
			box(Vector3(x,0.7,z),Vector3(3,0.9,5),Color("749098"))
			box(Vector3(x,1.25,z),Vector3(2.8,0.25,4.7),Color("c4d2c5"))
			box(Vector3(x,1.5,z-1.6),Vector3(2.5,0.3,1.1),Color("d9c6a7"),false)
	# 餐厨区靠墙双层生活橱柜架（台面放热可可与开袋零食，上层置物架放备用零食与磁力小音响！）
	counter_shelf(Vector3(41.2, 0.2, -64.1), 0.0, [
		["thermos", 0, -0.85, 0.14, 18.0],
		["chips", 0, 0.25, 0.10, -24.0],
		["chips", 1, -0.45, -0.06, 12.0],
		["boombox", 1, 0.72, -0.04, -10.0],
	])
	# 医疗角靠墙双层医疗药柜架（下台面医疗包，上层药架备用氧气瓶与急救药箱）
	counter_shelf(Vector3(63.4, 0.2, -57.5), -90.0, [
		["medical", 0, -0.58, 0.12, 10.0],
		["oxygen", 1, 0.62, -0.04, -15.0],
	])
	# 宿舍区床头矮柜（私人科考纪念杯端端正正摆在床头柜上）
	furniture("container-wide",Vector3(41.2,0.2,-70.0),Vector3(1.2,0.85,1.2))
	furniture("container-wide",Vector3(56.8,0.2,-78.0),Vector3(1.2,0.85,1.2))
	on_surface("keepsake", 41.2, 1.05, -70.0, 20.0)
	on_surface("keepsake", 56.8, 1.05, -78.0, -25.0)
	for z: float in [-70,-78]:furniture("container-tall",Vector3(63,0.2,z),Vector3(2,2.3,1.4))
	panel_sign(Vector3(49,3,-81.65),"living_info",Vector2(7,2))

func power_station() -> void:
	shell("power",Vector3(58,0,-116),26,28,Color("e1ae65"))
	partition(Vector3(58,0,-115),24,3.5,5)
	partition(Vector3(58,0,-124),24,3.5,4)
	furniture("computer-system",Vector3(50,0.2,-109),Vector3(2,2,1.2))
	station("district_power",Vector3(50,1.3,-108),"站区旁路：E 恢复照明、供暖和维护台。能源保险柜仍需遗迹钥匙。",false,false)
	for x: float in [51,64]:
		box(Vector3(x,2,-121),Vector3(3.5,3.5,4),Color("8aa8ab"))
		for z: float in [-122,-120]:box(Vector3(x,4,z),Vector3(2.7,0.3,0.5),Color("d3a45b"),false)
	station("charge",Vector3(65,1.4,-109),"站区维护台 · 恢复旁路后按住 E 慢充和补氧。",false)
	stations[-1].district_power = true
	# 工程师靠墙三层工具物资架（错落收纳电池、热风机与医疗箱）
	open_shelf(Vector3(58.0, 0.2, -128.4), 0.0, [
		["cell", 0, -0.78, 0.10, 14.0],
		["heater", 1, 0.08, 0.08, -16.0, {"charge": 180.0}],
		["medical", 1, 0.96, 0.06, 20.0],
		["cell", 2, -0.42, 0.04, -8.0],
	])
	panel_sign(Vector3(58,3,-129.65),"power_info",Vector2(7,2.3))
	landmarks.power_switch = Vector3(50,1.3,-108)

func garage() -> void:
	shell("garage",Vector3(46,0,-22),44,28,Color("d8b47a"),12)
	partition(Vector3(46,0,-29),42,3.5,6)
	furniture("container-tall",Vector3(28,0.2,-31),Vector3(2.5,3,2))
	open_shelf(Vector3(60.0, 0.2, -31.8), 0.0, [
		["cell", 0, -0.82, 0.08, 12.0],
		["bumper_orb", 0, 0.65, 0.08, 0.0],
		["flare", 1, -0.30, 0.10, -18.0],
		["keepsake", 2, 0.48, 0.04, 24.0],
	])
	panel_sign(Vector3(46,3,-35.65),"cart",Vector2(8,2.5))
	cart = load("res://previews/frost_station/cart.gd").new()
	cart.name = "SurveyCart"
	add_child(cart)
	cart.setup(get_parent(),Vector3(45,1.1,-20))
	landmarks.cart = Vector3(45,1.1,-20)

func warehouse() -> void:
	shell("warehouse",Vector3(-43,0,-22),40,28,Color("b8be9b"),10)
	for x: float in [-53,-33]:
		box(Vector3(x,1.8,-29),Vector3(0.3,3.6,12),Color("718a86"))
	for x: float in [-58,-47,-38,-28]:
		for z: float in [-17,-30]:
			furniture("container-wide",Vector3(x,0.2,z),Vector3(2.8,1.1,1.4))
			on_surface("chips" if x<-45 else "cell", x, 1.30, z, 5.0 if x < -45 else -5.0)
	# Two room doorways have ice collision. Front spaces remain accessible.
	for x: float in [-57,-28]:
		warehouse_ice.append(ice.size())
		frost(Vector3(x,1.8,-22),Vector3(4.5,3.6,1))
		partition(Vector3(x,0,-22),10,3.8,4.5)
		# 冷藏室深处放置稳固展示箱台，科考纪念杯端正摆在箱台上（不再悬空掉落）
		furniture("container-wide",Vector3(x,0.2,-32.5),Vector3(1.8,1.0,1.4))
		on_surface("keepsake", x, 1.20, -32.5, 12.0)
		landmarks["frozen_"+str(x)] = Vector3(x,0.4,-19)
	panel_sign(Vector3(-43,3,-35.65),"warehouse_info",Vector2(8,2.5))

func district_lamp(point: Vector3) -> OmniLight3D:
	box(point,Vector3(0.2,0.5,0.2),Color("d0b277"),false)
	box(Vector3(point.x,point.y/2,point.z),Vector3(0.12,point.y,0.12),ROCK)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = point
	light.light_color = Color("ffcd8b")
	light.omni_range = 18
	light.light_energy = 0
	add_child(light)
	return light

func apply_power(enabled: bool) -> void:
	for light: OmniLight3D in power_lights:light.light_energy = 1.2 if enabled else 0.0

func apply_radar(enabled: bool) -> void:
	for light: OmniLight3D in radar_lights:light.light_energy = 1.65 if enabled else 0.25

func apply_progress(progress: Dictionary) -> void:
	var pwr: bool = bool(progress.get("district_power",false))
	var rdr: bool = bool(progress.get("radar_online",false))
	apply_power(pwr)
	apply_radar(rdr)
	if frost_art != null and frost_art.has_method("set_network_power"):
		frost_art.set_network_power(pwr, rdr)
	var opened: bool = bool(progress.get("energy",false)) or bool(progress.get("installed",false))
	safe_door.rotation.y = -1.3 if opened else 0.0
	energy_visual.visible = not opened
	for i: int in collection_models.size():collection_models[i].visible = i<int(progress.get("collection_count",0))

func _place_courtyard_toys() -> void:
	# 所有出舱装备已整齐集成到 ship() 门口双出舱工作台，严禁在室外空地雪堆随意散落物品
	pass

func extra_shell(id: String, center: Vector3, width: float, depth: float, tint: Color, door_width: float = 7.0, height: float = 7.0) -> void:
	extra_rooms[id] = {"center": center, "width": width, "depth": depth}
	box(center + Vector3(0, 0.1, 0), Vector3(width, 0.2, depth), Color("7c929c"))
	box(center + Vector3(-width / 2.0, height / 2.0, 0), Vector3(0.5, height, depth), ROCK)
	box(center + Vector3(width / 2.0, height / 2.0, 0), Vector3(0.5, height, depth), ROCK)
	box(center + Vector3(0, height / 2.0, -depth / 2.0), Vector3(width, height, 0.5), ROCK)
	for side: float in [-1.0, 1.0]:
		box(center + Vector3(side * (width + door_width) / 4.0, height / 2.0, depth / 2.0), Vector3((width - door_width) / 2.0, height, 0.5), ROCK)
	box(center + Vector3(0, height - 0.7, depth / 2.0), Vector3(door_width, 1.4, 0.5), tint)
	box(center + Vector3(0, height, 0), Vector3(width + 0.5, 0.35, depth + 0.5), ROCK)
	for side: float in [-1.0, 1.0]:
		box(center + Vector3(side * (door_width / 2.0 + 0.2), 2.0, depth / 2.0 + 0.3), Vector3(0.16, 4.0, 0.12), tint, false)
	lamp(center + Vector3(0, 4.2, 0), Color("ffe0b2"), maxf(width, depth) * 0.75)
	landmarks[id] = center + Vector3(0, 0.35, depth / 2.0 + 3.0)

func _build_expanded_town_buildings() -> void:
	# 宽阔极地车环城大道（东西双干道 + 南北双干道，串联全部 15 栋大型建筑群！）
	for x_seg: int in range(-180, 185, 24):
		box(Vector3(float(x_seg), 0.16, -54.0), Vector3(22.0, 0.12, 11.0), Color("667b86"))
		box(Vector3(float(x_seg), 0.16, -138.0), Vector3(22.0, 0.12, 11.0), Color("667b86"))
	for z_seg: int in range(-170, 55, 22):
		box(Vector3(-76.0, 0.16, float(z_seg)), Vector3(11.0, 0.12, 20.0), Color("667b86"))
		box(Vector3(82.0, 0.16, float(z_seg)), Vector3(11.0, 0.12, 20.0), Color("667b86"))

	# 建筑 #7：巨型极地生态穹顶温室 (32×32m，高 14.5m，内部恒温暖房 + 发光水培植物园！)
	var gh: Vector3 = Vector3(-108.0, 0.0, -112.0)
	extra_rooms["greenhouse"] = {"center": gh, "width": 30.0, "depth": 30.0}
	box(gh + Vector3(0, 0.14, 0), Vector3(32.0, 0.28, 32.0), Color("748d8a"))
	lamp(gh + Vector3(0, 6.2, 0), Color("ffe2a8"), 30.0)
	# 温室园艺壁挂操作柜架（下台面热可可与零食，上架科考杯与信号弹）
	counter_shelf(gh + Vector3(0.0, 0.28, -5.2), 0.0, [
		["thermos", 0, -0.82, 0.12, 18.0],
		["chips", 0, 0.68, 0.10, -16.0],
		["keepsake", 1, -0.20, -0.05, 14.0],
	])
	landmarks["greenhouse"] = gh + Vector3(0, 0.35, 18.0)

	# 建筑 #8：高空通讯灯塔总部 (34×30×10m 巨型指挥电台楼 + 26m 通讯高塔！)
	var ch: Vector3 = Vector3(112.0, 0.0, -108.0)
	extra_shell("comms_hub", ch, 34.0, 30.0, Color("6ec7cf"), 10.0, 10.0)
	partition(ch + Vector3(0, 0, -4.0), 32.0, 4.2, 6.0)
	station("charge", ch + Vector3(10.0, 1.4, -2.0), "通讯总部应急补给台 · 按住 E 补氧与充能。", false)
	open_shelf(ch + Vector3(-11.5, 0.2, 6.5), 25.0, [
		["boombox", 1, -0.62, 0.08, 15.0],
		["thermos", 1, 0.72, 0.12, -20.0],
		["flare", 0, 0.10, 0.10, 12.0],
	])
	open_shelf(ch + Vector3(11.5, 0.2, 6.5), -25.0, [
		["cell", 0, -0.65, 0.10, 8.0],
		["cell", 1, 0.55, 0.08, -14.0],
		["flare", 2, -0.15, 0.04, 18.0],
	])

	# 建筑 #9：西线重型货运总站 (42×32×10m，14m 超大极地车穿行库门！)
	var cd: Vector3 = Vector3(-108.0, 0.0, -32.0)
	extra_shell("cargo_depot", cd, 42.0, 32.0, Color("e0a458"), 14.0, 10.0)
	open_shelf(cd + Vector3(-5.8, 0.2, -11.4), 0.0, [
		["oxygen", 0, -0.78, 0.10, 8.0],
		["medical", 1, -0.10, 0.08, -14.0],
		["bumper_orb", 1, 0.85, 0.06, 0.0],
	])
	open_shelf(cd + Vector3(5.8, 0.2, -11.4), 0.0, [
		["cell", 0, -0.68, 0.10, -12.0],
		["thermos", 1, 0.22, 0.12, 20.0],
		["bumper_orb", 0, 0.80, 0.08, 0.0],
	])
	on_surface("crate", cd.x, 0.20, cd.z - 10.5, 6.0)

	# 建筑 #10：东线极地机甲维修厂 (42×34×11m 巨型机库维修大厅！)
	var mh: Vector3 = Vector3(112.0, 0.0, -34.0)
	extra_shell("mech_hangar", mh, 42.0, 34.0, Color("e89e4e"), 14.0, 11.0)
	station("charge", mh + Vector3(-12.0, 1.4, -3.5), "机甲维修厂重型充能台 · 按住 E 补氧与充能。", false)
	open_shelf(mh + Vector3(-14.5, 0.2, -8.5), 18.0, [
		["suction", 1, -0.58, 0.08, 12.0],
		["cell", 0, 0.65, 0.10, -15.0],
		["bounce_pad", 0, -0.68, 0.02, 5.0],
	])
	open_shelf(mh + Vector3(14.5, 0.2, -8.5), -18.0, [
		["bounce_pad", 0, -0.62, 0.02, -8.0],
		["bumper_orb", 1, -0.35, 0.08, 0.0],
		["bumper_orb", 1, 0.68, 0.08, 0.0],
		["bumper_orb", 2, 0.12, 0.04, 0.0],
	])

	# 建筑 #11：西翼天文观测大穹顶 (32×32m 巨型观测圆顶 + 24m 极地观测塔！)
	var obs: Vector3 = Vector3(-164.0, 0.0, -78.0)
	extra_rooms["observatory"] = {"center": obs, "width": 30.0, "depth": 30.0}
	box(obs + Vector3(0, 0.14, 0), Vector3(32.0, 0.28, 32.0), Color("6d8692"))
	lamp(obs + Vector3(0, 6.4, 0), Color("bfe8ff"), 30.0)
	counter_shelf(obs + Vector3(0.0, 0.28, 9.2), 180.0, [
		["thermos", 0, -0.78, 0.12, 16.0],
		["flare", 0, 0.32, 0.10, -22.0],
		["boombox", 1, -0.42, -0.04, 8.0],
		["keepsake", 1, 0.78, -0.06, -15.0],
	])
	landmarks["observatory"] = obs + Vector3(0, 0.35, 18.0)

	# 建筑 #12：东翼地热反应堆电厂 (38×34×12m 超大型双涡轮电厂！)
	var rh: Vector3 = Vector3(166.0, 0.0, -76.0)
	extra_shell("reactor_hall", rh, 38.0, 34.0, Color("f0a848"), 12.0, 12.0)
	station("charge", rh + Vector3(0.0, 1.4, -12.0), "反应堆电厂高压补给台 · 按住 E 补氧与充能。", false)
	open_shelf(rh + Vector3(-11.5, 0.2, 10.5), 180.0, [
		["cell", 0, -0.72, 0.10, 10.0],
		["cell", 1, 0.15, 0.08, -14.0],
		["oxygen", 0, 0.85, 0.08, 6.0],
	])
	open_shelf(rh + Vector3(11.5, 0.2, 10.5), 180.0, [
		["bounce_pad", 0, -0.58, 0.04, 12.0],
		["heater", 1, -0.45, 0.08, -12.0, {"charge": 180.0}],
		["medical", 1, 0.78, 0.08, 16.0],
	])

	# 建筑 #13：西北冰川钻探中心 (36×28×10m 峡谷西翼大型科考堡垒！)
	var dr: Vector3 = Vector3(-72.0, 0.0, -166.0)
	extra_shell("drill_station", dr, 36.0, 28.0, Color("72c5ce"), 10.0, 10.0)
	open_shelf(dr + Vector3(-10.2, 0.2, 7.8), 155.0, [
		["suction", 1, -0.52, 0.08, 12.0],
		["medical", 0, 0.68, 0.10, -18.0],
		["cell", 2, -0.10, 0.04, 10.0],
	])
	open_shelf(dr + Vector3(10.2, 0.2, 7.8), -155.0, [
		["oxygen", 0, -0.68, 0.10, 6.0],
		["cell", 1, 0.56, 0.08, -14.0],
		["thermos", 2, -0.25, 0.04, 18.0],
	])
	# 钻探大厅入口两侧备有两只可直接用吸推器拖上压板的样本箱！
	on_surface("crate", dr.x - 4.6, 0.20, dr.z + 7.2, 8.0)
	on_surface("crate", dr.x + 4.6, 0.20, dr.z + 7.2, -10.0)

	# 建筑 #14：南区星港物流枢纽 (40×30×9.5m 停机坪东侧大型补给库与食堂！)
	var sh: Vector3 = Vector3(72.0, 0.0, 42.0)
	extra_shell("south_hub", sh, 40.0, 30.0, Color("84c6b4"), 14.0, 9.5)
	counter_shelf(sh + Vector3(0.0, 0.2, 9.5), 180.0, [
		["chips", 0, -0.82, 0.12, 14.0],
		["thermos", 0, 0.18, 0.10, -12.0],
		["boombox", 1, -0.48, -0.04, 10.0],
		["medical", 1, 0.72, -0.04, -18.0],
	])

	# 建筑 #15：西南极光特技生态基地 (32×32m 巨型圆顶 + 18m 极地飞车大跳台！)
	var so: Vector3 = Vector3(-84.0, 0.0, 44.0)
	extra_rooms["south_outpost"] = {"center": so, "width": 30.0, "depth": 30.0}
	box(so + Vector3(0, 0.14, 0), Vector3(32.0, 0.28, 32.0), Color("687c85"))
	ramp(so + Vector3(24.0, 0.1, 14.0), so + Vector3(24.0, 4.6, -8.0), 9.0)
	lamp(so + Vector3(0, 6.2, 0), Color("ffe0a8"), 30.0)
	open_shelf(so + Vector3(0.0, 0.28, 8.5), 180.0, [
		["bounce_pad", 0, -0.68, 0.04, 8.0],
		["bumper_orb", 1, -0.45, 0.08, 0.0],
		["bumper_orb", 1, 0.52, 0.08, 0.0],
		["thermos", 2, 0.10, 0.04, 15.0],
	])
	landmarks["south_outpost"] = so + Vector3(0, 0.35, 18.0)

func _build_outer_basin_expedition() -> void:
	# 建筑 #16：北峡谷大型前哨要塞（34×28×9.5m，位于 X=74, Z=-166，远离 X=36 东侧主公路！）
	var outpost: Vector3 = Vector3(74.0, 0.0, -166.0)
	extra_shell("north_fort", outpost, 34.0, 28.0, Color("e6a256"), 10.0, 9.5)
	station("charge", outpost + Vector3(8.5, 1.4, -4.5), "北哨前哨要塞 · 动力恢复后可在此补氧与充能。", false)
	stations[-1].district_power = true
	open_shelf(outpost + Vector3(-6.8, 0.2, 6.5), 160.0, [
		["cell", 0, -0.70, 0.10, 12.0],
		["flare", 1, -0.25, 0.08, -14.0],
		["flare", 1, 0.65, 0.08, 18.0],
	])
	open_shelf(outpost + Vector3(6.8, 0.2, 6.5), -160.0, [
		["thermos", 1, -0.62, 0.10, 14.0],
		["medical", 0, 0.58, 0.08, -10.0],
		["oxygen", 0, -0.78, 0.10, 8.0],
	])
	power_lights.append(district_lamp(outpost + Vector3(0, 4.5, 15.5)))
	landmarks["north_outpost"] = outpost + Vector3(-18, 0.4, 0)

	# 外围远征地标 A · 西线钢构冰缝大桥（X = -255, Z = -72）与坠毁轨道探测舱（X = -340, Z = -90）
	var bridge_y: float = 0.65
	box(Vector3(-255, bridge_y, -72), Vector3(48, 0.50, 13.0), Color("586c77"))
	for side_z: float in [-6.2, 6.2]:
		box(Vector3(-255, bridge_y + 0.85, -72 + side_z), Vector3(48, 1.2, 0.32), Color("d49a4c"))
	box(Vector3(-255, -7.5, -72), Vector3(16, 0.8, 115), Color("4da8bf"), false)

	var pod_pos: Vector3 = Vector3(-340, BASIN_TERRAIN.sample_height(-340, -90), -90)
	box(pod_pos + Vector3(0, 0.3, 0), Vector3(22, 0.6, 22), Color("5f7480"))
	var pod_hull: StaticBody3D = box(pod_pos + Vector3(0, 2.4, -2), Vector3(8.0, 4.2, 10.0), Color("7d8d94"))
	pod_hull.rotation_degrees = Vector3(8.0, 24.0, -11.0)
	station("west_probe", pod_pos + Vector3(6.2, 1.4, 2.5), "坠毁探测舱黑匣子 · E 读取外围冰川地质遥测并解锁补给。", false, false)
	open_shelf(pod_pos + Vector3(-4.2, 0.6, 5.8), 18.0, [
		["cell", 0, -0.70, 0.10, 10.0],
		["cell", 1, 0.45, 0.08, -16.0],
		["keepsake", 2, -0.12, 0.04, 20.0],
	])
	on_surface("crate", pod_pos.x + 7.5, pod_pos.y + 0.60, pod_pos.z - 2.5, 12.0)
	radar_lights.append(_beacon_post(pod_pos + Vector3(0, 0.6, 9.5), Color("#6be0f0")))
	landmarks["west_probe"] = pod_pos + Vector3(0, 1.0, 12.0)

	# 外围远征地标 B · 东线气象雷达高地（(325, -75)，海拔 +16m，盘山雪坡直达）
	var radar_pos: Vector3 = Vector3(325, BASIN_TERRAIN.sample_height(325, -75), -75)
	box(radar_pos + Vector3(0, 0.3, 0), Vector3(32, 0.6, 32), Color("677b86"))
	station("radar_tower", radar_pos + Vector3(0, 1.5, 5.5), "气象雷达主塔 · E 重启全盆地航标灯并同步外围物资坐标。", false, false)
	station("charge", radar_pos + Vector3(9.5, 1.5, 0.0), "雷达站应急补氧台 · 按住 E 补氧与充能。", false)
	open_shelf(radar_pos + Vector3(-9.5, 0.6, 0.0), 90.0, [
		["medical", 0, -0.68, 0.10, 10.0],
		["chips", 1, 0.20, 0.08, -14.0],
		["keepsake", 2, 0.72, 0.04, 18.0],
	])
	radar_lights.append(_beacon_post(radar_pos + Vector3(0, 16.5, -6.0), Color("#ffba5c")))
	landmarks["east_radar"] = radar_pos + Vector3(-14, 1.0, 10.0)

	# 外围远征地标 C · 远南极地空投补给站（X = -185, Z = 165）
	var drop_pos: Vector3 = Vector3(-185, BASIN_TERRAIN.sample_height(-185, 165), 165)
	box(drop_pos + Vector3(0, 0.3, 0), Vector3(20, 0.6, 20), Color("687c85"))
	box(drop_pos + Vector3(0, 2.0, 0), Vector3(4.5, 3.2, 4.5), Color("d99848"))
	open_shelf(drop_pos + Vector3(0.0, 0.6, 5.4), 0.0, [
		["oxygen", 0, -0.82, 0.10, 8.0],
		["bounce_pad", 0, 0.56, 0.02, -6.0],
		["cell", 1, -0.12, 0.08, 16.0],
	])
	radar_lights.append(_beacon_post(drop_pos + Vector3(0, 3.8, 0), Color("#6be0f0")))
	landmarks["south_drop"] = drop_pos + Vector3(10, 0.8, 0)

	# 全盆地公路航标灯桩
	var route_points: Array[Vector2] = [
		Vector2(-190, -68), Vector2(-225, -72), Vector2(-285, -78), Vector2(-318, -84),
		Vector2(205, -42), Vector2(245, -52), Vector2(285, -64),
		Vector2(43, -125), Vector2(43, -165), Vector2(-120, 95), Vector2(-155, 130),
	]
	for pt: Vector2 in route_points:
		var py: float = BASIN_TERRAIN.sample_height(pt.x, pt.y)
		radar_lights.append(_beacon_post(Vector3(pt.x, py, pt.y), Color("#ffb961")))

func _beacon_post(base_pos: Vector3, color: Color) -> OmniLight3D:
	box(base_pos + Vector3(0, 2.2, 0), Vector3(0.24, 4.4, 0.24), Color("465a66"))
	box(base_pos + Vector3(0, 4.55, 0), Vector3(0.55, 0.55, 0.55), color, false)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = base_pos + Vector3(0, 4.7, 0)
	light.light_color = color
	light.omni_range = 28.0
	light.light_energy = 0.25
	add_child(light)
	return light

func location(point: Vector3) -> String:
	for id: String in rooms:
		var room: Dictionary = rooms[id]
		var offset: Vector3 = point - room.center
		if absf(offset.x) < float(room.width) / 2.0 and absf(offset.z) < float(room.depth) / 2.0:
			return {"main":"主科研楼 · 二层环廊" if point.y>3 else "主科研楼 · 大厅与综合实验室","museum":"标本馆","living":"生活医疗楼","power":"动力与生命保障站","garage":"机修车库","warehouse":"物资仓库","ship":"飞船"}.get(id,id)
	for id2: String in extra_rooms:
		var er: Dictionary = extra_rooms[id2]
		var off2: Vector3 = point - er.center
		if absf(off2.x) < float(er.width) / 2.0 and absf(off2.z) < float(er.depth) / 2.0:
			return {
				"greenhouse": "巨型极地生态穹顶温室 · 恒温暖房",
				"comms_hub": "高空通讯灯塔总部",
				"cargo_depot": "西线重型货运总站",
				"mech_hangar": "东线极地机甲维修厂",
				"observatory": "西翼天文观测大穹顶",
				"reactor_hall": "东翼地热反应堆电厂",
				"drill_station": "西北冰川钻探中心",
				"south_hub": "南区星港物流枢纽",
				"north_fort": "北峡谷大型前哨要塞",
				"south_outpost": "西南极光特技生态基地",
			}.get(id2, id2)
	if point.z < -180:
		return "骨骸遗迹"
	if point.x < -210 and point.z < 30:
		return "西线 · 冻裂冰缝与探测舱"
	if point.x > 210:
		return "东线 · 气象雷达高地"
	if point.z > 85:
		return "南线 · 极地空投雪原"
	if point.z < -135:
		return "北线 · 冰原公路与前哨要塞"
	return "极地科考城 · 中心大道"
