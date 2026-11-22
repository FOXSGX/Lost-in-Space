extends Node3D
class_name GuluAssetDressing

## 奶龙星「外部星球素材」场景装饰（2026-11-23）
##
## 素材来源：同一仓库的其他星球预览（共振星洞穴 / 采矿站 / 无人机坪 / 反应堆塔），
## 全部为本项目自建 Blender 资产，复制进 `assets/props/` 只做缩放、摆位、材质微调，
## 不修改原始文件，也不改变任何玩法、碰撞或球路。
##
## 原则：
## - 只摆在原边界墙之外或边线外的空地，绝不进入球路（z≈0 的 x -5..12 走廊）。
## - 大型远景不投阴影；近景才开阴影，控制 draw call 与阴影贴图开销。
## - 所有模型按包围盒等比缩放，底部对齐 y=0，水平中心对齐落点。

const ROCK_WALL := preload("res://assets/props/resonance_cave_rock_wall.glb")
const STALACTITE := preload("res://assets/props/resonance_cave_stalactite.glb")
const ORE_CRYSTAL := preload("res://assets/props/resonance_cave_ore_crystal.glb")
const SAFETY_GATE := preload("res://assets/props/resonance_support_safety_gate.glb")
const DRONE_DOCK := preload("res://assets/props/resonance_drone_dock.glb")
const REACTOR_TOWER := preload("res://assets/props/resonance_reactor_tower.glb")

const ORE_AMBER := Color("#ffb45a")
const ORE_CYAN := Color("#5fe0ff")

# 洞穴岩石原材质几乎是黑的（albedo≈0.16），直接放进暖色沙漠会变成一圈黑影。
# 统一改成与场地程序化岩体同源的砂岩色，保留模型本身的块面细节。
const CLIFF_BASE := Color("#a89e89")
const CLIFF_DARK := Color("#7c7364")
const CLIFF_LIGHT := Color("#c6bca8")
const CLIFF_COOL := Color("#93a49c")

var _cliff_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	# 注意：aqs2_rock 用顶点色当 arris/ao/patch/up，外部 GLB 没有顶点色，
	# 直接套会因 COLOR=1 被压成近黑。所以导入岩石用纯 StandardMaterial3D 砂岩。
	_cliff_mats = [
		_stone_mat(CLIFF_BASE),
		_stone_mat(CLIFF_COOL),
		_stone_mat(CLIFF_LIGHT),
	]
	_build_backdrop_cliffs()
	_build_spires()
	_build_gate()
	_build_crystals()
	_build_landing_pad()
	_build_skyline()


# ---------------------------------------------------------------- 远景岩壁

func _build_backdrop_cliffs() -> void:
	# cave_rock_wall 的长轴是 Z：转到 90° 后长轴沿 X，正好给南北两侧当崖壁。
	var spec := [
		[Vector3(0.0, 0.0, -25.0), 90.0, 7.0],
		[Vector3(0.0, 0.0, 25.0), -90.0, 7.0],
		[Vector3(-26.0, 0.0, 0.0), 0.0, 6.4],
		[Vector3(26.0, 0.0, 21.0), 90.0, 6.0],
	]
	for item in spec:
		var cliff := _place(ROCK_WALL, item[0], item[1], item[2], false)
		cliff.name = "BackdropCliff"
		_tint_rock(cliff)


func _build_spires() -> void:
	# 石笋剪影：比程序化岩块更尖、更像“被风蚀出来的地标”。
	var spec := [
		[Vector3(-20.5, 0.0, -18.0), 20.0, 7.4],
		[Vector3(17.0, 0.0, -18.5), -35.0, 6.2],
		[Vector3(-21.0, 0.0, 15.0), 65.0, 6.8],
		[Vector3(14.5, 0.0, 18.0), -15.0, 5.6],
		[Vector3(-24.0, 0.0, -9.0), 110.0, 8.2],
	]
	for item in spec:
		var spire := _place(STALACTITE, item[0], item[1], item[2], false)
		spire.name = "RockSpire"
		_tint_rock(spire)


# ---------------------------------------------------------------- 场站大门

func _build_gate() -> void:
	# 放在西侧墙线上，背对出生点 → 回头时是一道有尺度的场站门。
	var gate := _place(SAFETY_GATE, Vector3(-16.6, 0.0, 0.0), 90.0, 6.3, true)
	gate.name = "YardGate"
	# 只给两根立柱加碰撞，避免玩家穿模；门洞和门前保持可通行。
	for side in [-1.0, 1.0]:
		_solid(Vector3(1.0, 6.3, 1.0), Vector3(-16.6, 3.15, side * 3.4))
	# 门楣下加一盏冷光，把大门从背景里剥出来。
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-15.4, 4.4, 0.0)
	lamp.light_color = Color("#ffe0b8")
	lamp.light_energy = 0.95
	lamp.omni_range = 9.0
	add_child(lamp)


# ---------------------------------------------------------------- 矿石晶簇

func _build_crystals() -> void:
	# 只在边线外/窝区外侧做点缀，不进入球路；矿石材质加自发光。
	var spec := [
		[Vector3(-3.4, 0.0, -6.2), 0.0, 1.15],
		[Vector3(6.4, 0.0, 5.6), 40.0, 0.95],
		[Vector3(-17.2, 0.0, -7.4), 80.0, 1.25],
		[Vector3(-17.4, 0.0, 8.2), -30.0, 1.05],
		[Vector3(16.2, 0.0, 6.4), 130.0, 1.1],
		[Vector3(12.0, 0.0, -7.2), -70.0, 0.85],
	]
	var index := 0
	for item in spec:
		var node := _place(ORE_CRYSTAL, item[0], item[1], item[2], true)
		node.name = "OreCluster%d" % index
		_make_ore_glow(node)
		index += 1
	# 只给最近的两簇加真实点光，其余靠自发光，控制灯数量。
	for at in [Vector3(-3.4, 0.0, -6.2), Vector3(-17.2, 0.0, -7.4)]:
		var light := OmniLight3D.new()
		light.position = at + Vector3.UP * 0.9
		light.light_color = ORE_AMBER
		light.light_energy = 0.45
		light.omni_range = 4.5
		add_child(light)


func _stone_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.94
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


func _tint_rock(root: Node) -> void:
	# 用场地同款砂岩材质覆盖洞穴岩石的暗色 albedo，块面细节保留。
	# Crack* 是模型自带的暖橙色裂隙条，保留原材质，当作岩层里的暖色纹理。
	for mi in _meshes(root):
		if mi.name.begins_with("Crack"):
			continue
		for surface in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(
				surface, _cliff_mats[(surface + mi.get_index()) % _cliff_mats.size()])


func _make_ore_glow(root: Node) -> void:
	for mi in _meshes(root):
		var mesh: Mesh = mi.mesh
		for surface in range(mesh.get_surface_count()):
			var material := mi.get_active_material(surface)
			if material == null:
				continue
			var mat_name := material.resource_name
			if not mat_name.begins_with("Cave_Ore"):
				continue
			var emissive := StandardMaterial3D.new()
			emissive.albedo_color = ORE_CYAN if mat_name.contains("Cyan") else ORE_AMBER
			emissive.emission_enabled = true
			emissive.emission = ORE_CYAN if mat_name.contains("Cyan") else ORE_AMBER
			emissive.emission_energy_multiplier = 1.35
			emissive.roughness = 0.28
			mi.set_surface_override_material(surface, emissive)


# ---------------------------------------------------------------- 无人机坪 / 天际线

func _build_landing_pad() -> void:
	# 东墙外的无人机坪：给装货口背后一个“有来处”的轮廓。
	var dock := _place(DRONE_DOCK, Vector3(25.5, 0.0, -7.5), 25.0, 5.6, false)
	dock.name = "DroneDock"


func _build_skyline() -> void:
	# 远处采矿站反应堆塔：只做天际线，不投阴影，隔着雾看。
	var tower := _place(REACTOR_TOWER, Vector3(48.0, 0.0, -31.0), -28.0, 30.0, false)
	tower.name = "DistantReactor"
	for mi in _meshes(tower):
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


# ---------------------------------------------------------------- 工具

func _place(scene: PackedScene, at: Vector3, yaw_deg: float, target_height: float,
		cast_shadow: bool) -> Node3D:
	# 先入树、在原点量包围盒，再把整个 holder 缩放到目标高度并归位。
	# 注意：AABB 必须用 world 变换量，否则旋转过的模型会长错方向。
	var holder := Node3D.new()
	holder.rotation.y = deg_to_rad(yaw_deg)
	add_child(holder)
	var model := scene.instantiate() as Node3D
	holder.add_child(model)

	var box := _aabb(holder)
	var factor := target_height / maxf(box.size.y, 0.001)
	holder.scale = Vector3.ONE * factor
	var center := box.get_center()
	holder.position = at - Vector3(center.x, box.position.y, center.z) * factor

	for mi in _meshes(holder):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out


func _aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var world: AABB = mi.global_transform * mi.get_aabb()
		if first:
			box = world
			first = false
		else:
			box = box.merge(world)
	return box





func _solid(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
