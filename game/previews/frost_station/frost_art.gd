extends Node3D

## 霜烬星 · 美术层（对齐 ART-PLANET-VISUAL-STANDARD v1 / 共振星 cave_art 模板）
##
## 只做视觉，不碰玩法：
##   · 把程序化低模的“单色方块”换成五族分层材质（涂装钢构 / 基岩 / 雪 / 冰 / 骨）；
##   · 重建环境与灯光（主光 + 副光 + 轮廓光 + 每栋可见灯具），替掉原来的单灯半球光；
##   · 补出形体级细节：混凝土基座、门斗、檐口积雪、冰锥、雪堆、雪地裂隙、冰晶簇、飘雪。
##
## 不改 box() 的碰撞、不改任何 interaction 锚点、不删改关卡几何；所有新增节点都在
## FrostArtDetail 下且没有碰撞体。`OS.get_environment("FROST_ART") == "0"` 可整体关掉，
## 用于改造前后同机位对照。

const PANEL_SHADER: Shader = preload("res://shaders/frost_panel.gdshader")
const ROCK_SHADER: Shader = preload("res://shaders/frost_rock.gdshader")
const SNOW_SHADER: Shader = preload("res://shaders/frost_snow.gdshader")
const ICE_SHADER: Shader = preload("res://shaders/frost_ice.gdshader")
const BONE_SHADER: Shader = preload("res://shaders/frost_bone.gdshader")

const PORCH_GLB: PackedScene = preload("res://assets/models/rebuild/hero_station_porch.glb")
const FOSSIL_ARCH_GLB: PackedScene = preload("res://assets/models/rebuild/hero_fossil_arch.glb")
const LEVIATHAN_SKULL_GLB: PackedScene = preload("res://assets/models/rebuild/hero_leviathan_skull.glb")
const GEO_GEN_GLB: PackedScene = preload("res://assets/models/rebuild/hero_geothermal_generator.glb")
const ROCK_GLB: PackedScene = preload("res://assets/models/rebuild/hero_glacier_rock.glb")
const ICE_SPIRE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_ice_spire.glb")
const LEVER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_lever_console.glb")
const ARCTIC_ROOF_GLB: PackedScene = preload("res://assets/models/rebuild/hero_arctic_roof.glb")
const WALL_BUTTRESS_GLB: PackedScene = preload("res://assets/models/rebuild/hero_wall_buttress.glb")
const GEO_DOME_GLB: PackedScene = preload("res://assets/models/rebuild/hero_geo_dome.glb")
const COMMS_TOWER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_comms_tower.glb")

## 霜烬星色板：冷奶白钢构 + 锈红底漆 + 蓝灰金属 + 冰青，点缀色沿用每栋既有识别色。
const PALETTE: Dictionary = {
	"paint": Color("#9e9789"),
	"primer": Color("#7d3f30"),
	"bare": Color("#8b9296"),
	"snow": Color("#c9d8e4"),
	"grime": Color("#22262a"),
	"concrete": Color("#7b8387"),
	"rock": Color("#3a4f5e"),
	"rock_layer": Color("#58717f"),
	"rock_dark": Color("#1b2831"),
	"frost": Color("#9ec2d4"),
	"bone": Color("#c9bfa6"),
	"ice_deep": Color("#0a2f3b"),
	"ice_body": Color("#4a8fa3"),
	"ice_rim": Color("#c3edf7"),
	"warm_lamp": Color("#ffcf9a"),
	"cool_fill": Color("#8cbbff"),
	"key_light": Color("#ffe2c6"),
}

## 十栋站房 + 飞船（原有 6 栋 + 扩建 3 栋壳体建筑，另有 2 座玻璃穹顶独立挂载）：
const BUILDINGS: Array = [
	# id, 中心, 宽, 深, 檐高, 门宽, 识别色
	["ship", Vector3(0, 0.7, 12), 14.0, 14.0, 7.0, 6.0, Color("#e5b676")],
	["main", Vector3(0, 0.0, -110), 60.0, 32.0, 9.0, 10.0, Color("#72c5ce")],
	["museum", Vector3(-49, 0.0, -70), 32.0, 38.0, 11.0, 7.0, Color("#c7b995")],
	["living", Vector3(49, 0.0, -63), 32.0, 38.0, 7.0, 7.0, Color("#9dbb9f")],
	["power", Vector3(58, 0.0, -116), 26.0, 28.0, 7.0, 7.0, Color("#e1ae65")],
	["garage", Vector3(46, 0.0, -22), 44.0, 28.0, 7.0, 12.0, Color("#d8b47a")],
	["warehouse", Vector3(-43, 0.0, -22), 40.0, 28.0, 7.0, 10.0, Color("#b8be9b")],
	["comms_hub", Vector3(98, 0.0, -96), 18.0, 18.0, 7.0, 7.0, Color("#6ec7cf")],
	["cargo_depot", Vector3(-96, 0.0, -28), 26.0, 22.0, 7.5, 12.0, Color("#e0a458")],
	["north_fort", Vector3(58, 0.0, -155), 16.0, 14.0, 6.5, 6.5, Color("#e6a256")],
]

const BONE_TINTS: Array = [Color("#c6b69a")]
const ROCK_TINTS: Array = [Color("#344b59"), Color("#75919c")]
const SLAB_TINTS: Array = [
	Color("#7c929c"), Color("#708f97"), Color("#697e88"), Color("#7a9198"), Color("#718a86"),
	Color("#607985"), Color("#506574"), Color("#536877"), Color("#abc0bc"), Color("#acc7c9"),
	Color("#91a8ac"), Color("#8aa8ab"), Color("#93aeb5"), Color("#d6e3d8"), Color("#5c7c87"),
]

var world: Node3D
var detail_root: Node3D
var environment: Environment
var sun: DirectionalLight3D
var material_cache: Dictionary = {}
var material_families: Dictionary = {}
var lights: Array[Light3D] = []
var ice_chunks: Array = []
var applied_meshes: int = 0
var detail_meshes: int = 0
var detail_lights: int = 0
var _snow_batch: Array[Transform3D] = []
var _ice_batch: Array[Transform3D] = []
var _pbr: ArtPbrLib
var _power_conduit_mats: Array[ShaderMaterial] = []
var _radar_conduit_mats: Array[ShaderMaterial] = []
var _objective_beacon: MeshInstance3D
var _objective_beacon_mat: ShaderMaterial

func install(target: Node3D) -> void:
	world = target
	_pbr = ArtPbrLib.new()
	detail_root = Node3D.new()
	detail_root.name = "FrostArtDetail"
	add_child(detail_root)
	_snow_batch.clear()
	_ice_batch.clear()
	_power_conduit_mats.clear()
	_radar_conduit_mats.clear()
	_replace_environment()
	_open_fossil_canyon()
	_apply_materials(world)
	_harmonize_furniture()
	_convert_ice_chunks()
	_build_lighting()
	_build_buildings()
	_build_ground()
	_build_ridges()
	_build_hero_landmarks_and_conduits()
	_build_objective_beacon()
	_commit_multimesh_batches()
	_build_air()
	set_process(true)

## 彻底拆除旧版遗迹方盒隧道壳与旧管状假骨头（保留所有可走地板、坡道与碰撞，只呈现真解剖巨兽头骨与脊椎肋骨笼！）
func _open_fossil_canyon() -> void:
	for child: Node in world.get_children():
		if not (child is StaticBody3D):
			continue
		var body: StaticBody3D = child as StaticBody3D
		if body.position.z > -165.0:
			continue
		for sub: Node in body.get_children():
			if sub is MeshInstance3D:
				var mi: MeshInstance3D = sub as MeshInstance3D
				if mi.mesh is BoxMesh:
					var sz: Vector3 = (mi.mesh as BoxMesh).size
					# 隐藏旧版巨型灰方盒外墙、封顶盖板以及高处的旧条状假骨头
					if sz.y > 15.0 or (sz.x > 32.0 and body.position.y > 10.0) or (body.position.y > 13.0 and (sz.x > 8.0 or sz.y > 8.0)):
						mi.visible = false
				elif (mi.mesh is CylinderMesh or mi.mesh is CapsuleMesh or mi.mesh is SphereMesh) and body.position.y > 4.0:
					# 隐藏旧版 rounded_bone 拼装的管道假骨拱
					mi.visible = false

func _build_objective_beacon() -> void:
	# 3D 物理主线天空光柱（无悬浮文字，400m 外清晰指向当前主线目标）
	_objective_beacon = ArtAtmosphereKit.build_godray_cone(detail_root, Vector3(-5.0, 68.0, -120.0), 68.0, 1.4, 3.8, Color("#4ef0ff"), 0.14)
	_objective_beacon.name = "ActiveObjectiveBeacon"
	_objective_beacon_mat = _objective_beacon.material_override as ShaderMaterial

func set_objective_beacon(pos: Vector3, color: Color) -> void:
	if _objective_beacon == null:
		return
	_objective_beacon.position = Vector3(pos.x, pos.y + 34.0, pos.z)
	if _objective_beacon_mat != null:
		_objective_beacon_mat.set_shader_parameter("ray_color", color)

func set_network_power(power_on: bool, radar_on: bool) -> void:
	for mat: ShaderMaterial in _power_conduit_mats:
		mat.set_shader_parameter("active_state", 1.0 if power_on else 0.0)
		mat.set_shader_parameter("ready_state", 0.65 if not power_on else 1.0)
	for mat: ShaderMaterial in _radar_conduit_mats:
		mat.set_shader_parameter("active_state", 1.0 if radar_on else 0.0)
		mat.set_shader_parameter("ready_state", 0.55 if not radar_on else 1.0)

func stats() -> Dictionary:
	return {
		"families": material_families.duplicate(true),
		"applied_meshes": applied_meshes,
		"materials": material_cache.size(),
		"detail_meshes": detail_meshes,
		"lights": lights.size(),
		"detail_lights": detail_lights,
		"ice_chunks": ice_chunks.size(),
	}

# ---------------------------------------------------------------- 环境与灯光

func _replace_environment() -> void:
	# 旧版只有一盏平行光和一张渐变天空；这里整体替换，避免双主光。
	var previous: Array[Node] = []
	for child: Node in world.get_children():
		if child is WorldEnvironment or child is DirectionalLight3D:
			previous.append(child)
	for child: Node in previous:
		world.remove_child(child)
		child.queue_free()

	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "FrostArtEnvironment"
	environment = Environment.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#0c1f36")
	sky_material.sky_horizon_color = Color("#cf9b7c")
	sky_material.ground_horizon_color = Color("#748ea3")
	sky_material.ground_bottom_color = Color("#243340")
	sky_material.sky_energy_multiplier = 0.95
	sky_material.sun_angle_max = 3.5
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#7094b2")
	environment.ambient_light_energy = 0.30
	environment.ssr_enabled = false
	environment.ssil_enabled = false
	environment.volumetric_fog_enabled = false
	environment.fog_enabled = true
	environment.fog_light_color = Color("#98a9ba")
	environment.fog_light_energy = 0.65
	environment.fog_density = 0.0020
	environment.fog_sky_affect = 0.28
	environment.fog_aerial_perspective = 0.22
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.92
	environment.tonemap_white = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.12
	environment.adjustment_saturation = 1.12
	we.environment = environment
	world.add_child(we)

func _build_lighting() -> void:
	# 主光：低角度极地金桃色斜阳，拉出强烈明暗立体感与长影
	sun = DirectionalLight3D.new()
	sun.name = "FrostArtKey"
	sun.rotation_degrees = Vector3(-19.0, -132.0, 0.0)
	sun.light_color = Color("#ffd19c")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 360.0
	sun.directional_shadow_blend_splits = true
	world.add_child(sun)
	lights.append(sun)

	# 副光：天空侧的冷补光，只托住暗面，不抢主光。
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "FrostArtSkyFill"
	fill.rotation_degrees = Vector3(-12.0, 48.0, 0.0)
	fill.light_color = PALETTE.cool_fill
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	world.add_child(fill)
	lights.append(fill)

	# 轮廓光：从骨口方向压过来的低角度冷光，把屋脊从远处雪脊里剥出来。
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.name = "FrostArtRim"
	rim.rotation_degrees = Vector3(-6.0, 8.0, 0.0)
	rim.light_color = Color("#c8e6ff")
	rim.light_energy = 0.22
	rim.shadow_enabled = false
	world.add_child(rim)
	lights.append(rim)

func _add_omni(node_name: String, at: Vector3, color: Color, energy: float, radius: float, shadows: bool = false, parent: Node3D = null) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = node_name
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.25
	light.shadow_enabled = shadows
	(parent if parent != null else world).add_child(light)
	lights.append(light)
	detail_lights += 1
	return light

# ---------------------------------------------------------------- 材质族

func _apply_materials(root: Node) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	for mesh: MeshInstance3D in meshes:
		_apply_mesh(mesh)

func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			into.append(child as MeshInstance3D)
		_collect_meshes(child, into)

func _apply_mesh(view: MeshInstance3D) -> void:
	if not (view.get_parent() is StaticBody3D):
		return
	var material: StandardMaterial3D = view.material_override as StandardMaterial3D
	if material == null:
		return
	if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	if material.albedo_texture != null or material.emission_enabled:
		return
	var size: Vector3 = _mesh_size(view)
	if size == Vector3.ZERO:
		return
	var tint: Color = material.albedo_color.linear_to_srgb()
	var family: String = _classify(size, tint)
	if family == "":
		return
	var built: ShaderMaterial = _family_material(family, view)
	if built == null:
		return
	view.material_override = built
	view.set_meta("frost_art_family", family)
	material_families[family] = int(material_families.get(family, 0)) + 1
	applied_meshes += 1

func _mesh_size(view: MeshInstance3D) -> Vector3:
	if view.mesh is BoxMesh:
		return (view.mesh as BoxMesh).size
	if view.mesh == null:
		return Vector3.ZERO
	return view.mesh.get_aabb().size

func _classify(size: Vector3, tint: Color) -> String:
	var smallest: float = minf(size.x, size.z)
	# 竖长条 = 站房墙体 / 隔断 / 门柱：一律按涂装钢板处理，不再用岩色糊过去。
	if size.y >= 2.6 and smallest <= 0.9:
		return "wall"
	for accent: Array in BUILDINGS:
		if _near(tint, accent[6], 0.05):
			return "painted"
	for bone: Color in BONE_TINTS:
		if _near(tint, bone, 0.04):
			return "bone"
	# 薄而大的水平面（屋面、雨棚、地台）先归混凝土：屋面要积雪，不能读成岩层。
	if size.y <= 0.6 and minf(size.x, size.z) >= 1.2:
		return "slab"
	for rock: Color in ROCK_TINTS:
		if _near(tint, rock, 0.04):
			return "rock"
	for slab: Color in SLAB_TINTS:
		if _near(tint, slab, 0.04):
			return "slab" if size.y <= 1.2 else "painted"
	if maxf(size.x, maxf(size.y, size.z)) < 0.45:
		return "fitting"
	return "painted"

func _near(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) <= tolerance

func _family_material(family: String, view: MeshInstance3D) -> ShaderMaterial:
	var variation: int = abs(hash(str(view.get_parent().name) + str(view.position.round()))) % 5
	var accent: Color = _building_accent_for(view)
	var cache_key: String = "%s|%s|%d" % [family, accent.to_html(false), variation]
	if material_cache.has(cache_key):
		return material_cache[cache_key] as ShaderMaterial
	var mat: ShaderMaterial = ShaderMaterial.new()
	var v: float = float(variation) / 5.0
	match family:
		"wall":
			mat.shader = PANEL_SHADER
			mat.set_shader_parameter("paint_color", PALETTE.paint)
			mat.set_shader_parameter("primer_color", PALETTE.primer)
			mat.set_shader_parameter("bare_color", PALETTE.bare)
			mat.set_shader_parameter("accent_color", accent.darkened(0.18))
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("grime_color", PALETTE.grime)
			mat.set_shader_parameter("panel_size", Vector2(2.85 + v * 0.35, 1.80 + v * 0.20))
			mat.set_shader_parameter("stripe_height", 0.95)
			mat.set_shader_parameter("rivet_amount", 1.0)
			mat.set_shader_parameter("chip_threshold", 0.70 + v * 0.04)
			mat.set_shader_parameter("grime_amount", 0.55 + v * 0.12)
			mat.set_shader_parameter("metallic_paint", 0.12)
			mat.set_shader_parameter("roughness_base", 0.44 + v * 0.06)
			mat.set_shader_parameter("variation", v)
		"painted":
			mat.shader = PANEL_SHADER
			mat.set_shader_parameter("paint_color", accent.darkened(0.10))
			mat.set_shader_parameter("primer_color", PALETTE.primer)
			mat.set_shader_parameter("bare_color", PALETTE.bare)
			mat.set_shader_parameter("accent_color", accent.lightened(0.10))
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("grime_color", PALETTE.grime)
			mat.set_shader_parameter("panel_size", Vector2(0.85 + v * 0.20, 0.55 + v * 0.10))
			mat.set_shader_parameter("stripe_height", 0.30)
			mat.set_shader_parameter("rivet_amount", 0.8)
			mat.set_shader_parameter("chip_threshold", 0.58 + v * 0.06)
			mat.set_shader_parameter("grime_amount", 0.40)
			mat.set_shader_parameter("metallic_paint", 0.22)
			mat.set_shader_parameter("roughness_base", 0.40)
			mat.set_shader_parameter("variation", v)
		"fitting":
			mat.shader = PANEL_SHADER
			mat.set_shader_parameter("paint_color", PALETTE.bare)
			mat.set_shader_parameter("primer_color", PALETTE.primer)
			mat.set_shader_parameter("bare_color", PALETTE.bare)
			mat.set_shader_parameter("accent_color", accent.darkened(0.25))
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("grime_color", PALETTE.grime)
			mat.set_shader_parameter("panel_size", Vector2(0.34, 0.22))
			mat.set_shader_parameter("stripe_height", 0.02)
			mat.set_shader_parameter("rivet_amount", 0.0)
			mat.set_shader_parameter("chip_threshold", 0.52)
			mat.set_shader_parameter("grime_amount", 0.65)
			mat.set_shader_parameter("metallic_paint", 0.55)
			mat.set_shader_parameter("roughness_base", 0.34)
			mat.set_shader_parameter("variation", v)
		"slab":
			mat.shader = PANEL_SHADER
			mat.set_shader_parameter("paint_color", PALETTE.concrete)
			mat.set_shader_parameter("primer_color", PALETTE.primer)
			mat.set_shader_parameter("bare_color", PALETTE.bare)
			mat.set_shader_parameter("accent_color", PALETTE.concrete.darkened(0.25))
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("grime_color", PALETTE.grime)
			mat.set_shader_parameter("concrete_mode", 1.0)
			mat.set_shader_parameter("rivet_amount", 0.0)
			mat.set_shader_parameter("snow_amount", 1.0)
			mat.set_shader_parameter("grime_amount", 0.70)
			mat.set_shader_parameter("roughness_base", 0.84)
			mat.set_shader_parameter("metallic_paint", 0.0)
			mat.set_shader_parameter("variation", v)
		"rock":
			mat.shader = ROCK_SHADER
			mat.set_shader_parameter("base_color", PALETTE.rock)
			mat.set_shader_parameter("layer_color", PALETTE.rock_layer)
			mat.set_shader_parameter("dark_color", PALETTE.rock_dark)
			mat.set_shader_parameter("frost_color", PALETTE.frost)
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("layer_height", 0.58 + v * 0.22)
			mat.set_shader_parameter("frost_amount", 0.55 + v * 0.20)
			mat.set_shader_parameter("snow_amount", 0.85)
			mat.set_shader_parameter("variation", v)
		"bone":
			mat.shader = BONE_SHADER
			mat.set_shader_parameter("bone_color", PALETTE.bone)
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("variation", v)
		_:
			return null
	mat.resource_name = "FrostArt_%s_%s" % [family, accent.to_html(false)]
	material_cache[cache_key] = mat
	return mat

func _building_accent_for(view: MeshInstance3D) -> Color:
	var point: Vector3 = view.global_position
	var best: Color = BUILDINGS[1][6]
	var best_distance: float = 1.0e9
	for entry: Array in BUILDINGS:
		var center: Vector3 = entry[1]
		var width: float = float(entry[2]) * 0.5 + 8.0
		var depth: float = float(entry[3]) * 0.5 + 8.0
		var offset: Vector3 = point - center
		var over: float = maxf(absf(offset.x) - width, absf(offset.z) - depth)
		if over < best_distance:
			best_distance = over
			best = entry[6]
	return best

# ---------------------------------------------------------------- 家具色彩统一

## 站内家具来自 Kenney 风格的 GLB 套件，原色是高明度粉紫/黄。直接用会和新的
## 工业材质语言打架（标准 B7：背景不能是另一个精度/色彩档次）。这里只把它们的
## 底色往站区蓝灰里压、把粗糙度提上去，保留原有造型与贴图细节。
func _harmonize_furniture() -> void:
	var art_node: Node = world.get("art") as Node
	if art_node == null:
		return
	var target: Color = Color("#7f8b90")
	for view: MeshInstance3D in art_node.find_children("*", "MeshInstance3D", true, false):
		var override: StandardMaterial3D = view.material_override as StandardMaterial3D
		if override != null:
			view.material_override = _muted(override, target)
			continue
		if view.mesh == null:
			continue
		for surface: int in view.mesh.get_surface_count():
			var material: BaseMaterial3D = view.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			view.set_surface_override_material(surface, _muted(material, target))

func _muted(material: BaseMaterial3D, target: Color) -> BaseMaterial3D:
	var copy: BaseMaterial3D = material.duplicate() as BaseMaterial3D
	if copy == null:
		return material
	var tint: Color = copy.albedo_color
	var muted: Color = tint.lerp(target, 0.55)
	muted.s = minf(muted.s, 0.16)
	copy.albedo_color = muted
	copy.roughness = maxf(copy.roughness, 0.58)
	copy.metallic = minf(copy.metallic, 0.25) if copy.metallic > 0.0 else 0.05
	return copy

# ---------------------------------------------------------------- 冰与雪堆

func _convert_ice_chunks() -> void:
	for child: Node in world.get_children():
		if not (child is StaticBody3D) or not child.has_method("apply_amount"):
			continue
		var chunk: Node3D = child as Node3D
		var visual: MeshInstance3D = chunk.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if visual == null:
			for candidate: Node in chunk.get_children():
				if candidate is MeshInstance3D:
					visual = candidate as MeshInstance3D
					break
		if visual == null:
			continue
		var size: Vector3 = _mesh_size(visual)
		var thin: bool = size.y <= 0.9
		var mat: ShaderMaterial = ShaderMaterial.new()
		if thin:
			# 地面雪块共用一个相位：世界坐标噪声已经连续，再叠随机相位会出现方块接缝。
			mat.shader = SNOW_SHADER
			mat.set_shader_parameter("snow_color", Color("#cfdde8"))
			mat.set_shader_parameter("shadow_color", Color("#8fb0c8"))
			mat.set_shader_parameter("grit_color", Color("#4c5359"))
			mat.set_shader_parameter("ripple_strength", 0.45)
			mat.set_shader_parameter("variation", 0.0)
		else:
			mat.shader = ICE_SHADER
			mat.set_shader_parameter("deep_color", PALETTE.ice_deep)
			mat.set_shader_parameter("body_color", PALETTE.ice_body)
			mat.set_shader_parameter("rim_color", PALETTE.ice_rim)
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("variation", float(abs(hash(str(chunk.name))) % 100) / 100.0)
		visual.material_override = mat
		if not thin and size.y > 1.2:
			_dress_ice_chunk(chunk, size)
		ice_chunks.append([weakref(chunk), weakref(mat)])
		applied_meshes += 1
		var family_key: String = "ice" if not thin else "snowpile"
		material_families[family_key] = int(material_families.get(family_key, 0)) + 1

## 封门冰障与初期雪障：用不等边棱面蓝冰晶簇（hero_ice_spire.glb）包裹替代生硬长方体，随融冰同步缩小
func _dress_ice_chunk(chunk: Node3D, size: Vector3) -> void:
	var at: Vector3 = chunk.position
	var half: Vector3 = size * 0.5
	# 对高度较大的立面冰障，隐藏旧生硬蓝方盒视觉（保留完整物理碰撞），挂上真实棱面蓝冰晶簇
	if size.y >= 2.0:
		for c: Node in chunk.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false
		var spire_holder: Node3D = Node3D.new()
		spire_holder.name = "FacetedIceVisual"
		var s_mesh: Node3D = ICE_SPIRE_GLB.instantiate() as Node3D
		s_mesh.scale = Vector3(maxf(size.x * 0.52, 0.9), maxf(size.y * 0.24, 0.55), maxf(size.z * 0.72, 0.7))
		s_mesh.position = Vector3(0.0, -half.y, 0.0)
		_pbr.bind_glb(s_mesh, "frost", true)
		spire_holder.add_child(s_mesh)
		chunk.add_child(spire_holder)
	_snow_pillow("IceSkirt_%d" % int(absf(at.x * 10.0 + at.z)), at + Vector3(0, -half.y + 0.22, half.z + 0.35), Vector3(half.x * 0.95, 0.30, 0.55))

func _process(_delta: float) -> void:
	# 融冰：玩法只改 amount 与网格尺寸，这里把 amount 转成材质上的“湿 / 透 / 暗”。
	for entry: Array in ice_chunks:
		var chunk: Node3D = (entry[0] as WeakRef).get_ref() as Node3D
		var mat: ShaderMaterial = (entry[1] as WeakRef).get_ref() as ShaderMaterial
		if chunk == null or mat == null:
			continue
		var melt: float = clampf(float(chunk.get("amount")), 0.0, 1.0)
		var current: Variant = mat.get_shader_parameter("melt")
		var current_f: float = 0.0 if current == null else float(current)
		if absf(current_f - melt) > 0.01:
			mat.set_shader_parameter("melt", melt)

# ---------------------------------------------------------------- 站房细节

func _build_buildings() -> void:
	for entry: Array in BUILDINGS:
		var id: String = entry[0]
		var center: Vector3 = entry[1]
		var width: float = entry[2]
		var depth: float = entry[3]
		var height: float = entry[4]
		var door_width: float = entry[5]
		var accent: Color = entry[6]
		var front_z: float = center.z + depth * 0.5
		# 混凝土基座：把原本“浮在雪上”的方盒子压到地面上。
		_box_mesh("Plinth_" + id, Vector3(center.x, center.y + 0.11, center.z), Vector3(width + 1.1, 0.34, depth + 1.1), "slab")
		# 檐口积雪 + Blender 英雄双坡保温屋盖与加强肋拱（彻底消除平顶鞋盒感）
		_snow_cornice(id, center, width, depth, height)
		var roof: Node3D = ARCTIC_ROOF_GLB.instantiate() as Node3D
		roof.name = "HeroArcticRoof_" + id
		roof.position = Vector3(center.x, center.y + height + 0.15, center.z)
		roof.scale = Vector3(width / 10.0, clampf(height / 7.5, 0.85, 1.35), depth / 10.0)
		_pbr.bind_glb(roof, "frost", true)
		detail_root.add_child(roof)
		detail_meshes += 1
		# Blender 英雄门斗（工业橙柱靴 + 奶油白倒角方柱 + 防雪斜雨棚 + 接地暗晕）
		var porch: Node3D = PORCH_GLB.instantiate() as Node3D
		porch.name = "HeroPorch_" + id
		porch.position = Vector3(center.x, center.y, front_z + 1.1)
		var sx_fit: float = clampf((door_width + 1.8) / 8.4, 0.72, 1.45)
		porch.scale = Vector3(sx_fit, 1.0, 1.0)
		_pbr.bind_glb(porch, "frost", true)
		detail_root.add_child(porch)
		ArtAtmosphereKit.build_ground_skirt(detail_root, Vector3(center.x, center.y, front_z + 1.1), door_width * 0.65, 0.45)
		detail_meshes += 1
		# 门口机装工作灯真实光源
		_add_omni("DoorLamp_" + id, Vector3(center.x, center.y + 3.25, front_z + 1.8), PALETTE.warm_lamp, 1.25, 13.0)
		# 给全部科考站外墙加装 Blender 外骨架承力扶壁与暖光保温舷窗（彻底消灭裸露灰平板墙）
		if id != "ship":
			var sy_fit: float = clampf(height / 7.0, 0.95, 1.45)
			# 面向作业院的侧墙（左/右）与正面两侧
			for side_x: float in [-1.0, 1.0]:
				var bay_count: int = maxi(1, int(depth / 12.0))
				for b: int in bay_count:
					var bz: float = center.z - depth * 0.5 + (float(b) + 0.5) * (depth / float(bay_count))
					var wb: Node3D = WALL_BUTTRESS_GLB.instantiate() as Node3D
					wb.position = Vector3(center.x + side_x * (width * 0.5 + 0.12), center.y, bz)
					wb.rotation.y = side_x * PI * 0.5
					wb.scale = Vector3(minf(depth / float(bay_count) / 10.2, 1.25), sy_fit, 1.0)
					_pbr.bind_glb(wb, "frost", true)
					detail_root.add_child(wb)
					detail_meshes += 1
			# 正面入口左右两侧墙段（避开大门净宽）
			var wing_w: float = (width - door_width - 2.4) * 0.5
			if wing_w >= 6.0:
				for side_x: float in [-1.0, 1.0]:
					var wx: float = center.x + side_x * (door_width * 0.5 + 1.2 + wing_w * 0.5)
					var wbf: Node3D = WALL_BUTTRESS_GLB.instantiate() as Node3D
					wbf.position = Vector3(wx, center.y, front_z + 0.12)
					wbf.scale = Vector3(clampf(wing_w / 10.2, 0.65, 1.35), sy_fit, 1.0)
					_pbr.bind_glb(wbf, "frost", true)
					detail_root.add_child(wbf)
					detail_meshes += 1
		# 冰锥：檐口滴水冻结，只在朝南的檐下挂，形态长短不一。
		_icicles(id, center, width, depth, height, front_z)
		# 室内：只给两栋大空间补一盏靠墙机装灯（其余房间沿用 shell 自带的吊灯）。
		if id == "main" or id == "museum":
			var lamp_at: Vector3 = Vector3(center.x - (width * 0.5 - 0.35), center.y + 3.1, center.z + depth * 0.28)
			_box_mesh("IndoorLampBody_" + id, lamp_at, Vector3(0.16, 0.55, 0.28), "fitting")
			_box_mesh("IndoorLampLens_" + id, lamp_at + Vector3(0.12, 0.0, 0.0), Vector3(0.06, 0.42, 0.20), "lamp", accent)
			_add_omni("IndoorFill_" + id, lamp_at + Vector3(1.4, -0.15, 0.0), Color("#cfe2ee"), 0.85, 22.0)

func _snow_cornice(id: String, center: Vector3, width: float, depth: float, height: float) -> void:
	var y: float = center.y + height + 0.13
	_snow_pillow("EaveSnowF_" + id, Vector3(center.x, y, center.z + depth * 0.5), Vector3(width * 0.5 + 0.35, 0.20, 0.44))
	_snow_pillow("EaveSnowB_" + id, Vector3(center.x, y, center.z - depth * 0.5), Vector3(width * 0.5 + 0.35, 0.20, 0.44))
	_snow_pillow("EaveSnowL_" + id, Vector3(center.x - width * 0.5, y, center.z), Vector3(0.44, 0.20, depth * 0.5 + 0.35))
	_snow_pillow("EaveSnowR_" + id, Vector3(center.x + width * 0.5, y, center.z), Vector3(0.44, 0.20, depth * 0.5 + 0.35))

func _icicles(id: String, center: Vector3, width: float, depth: float, height: float, front_z: float) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = abs(hash(id))
	var count: int = 7 + rng.randi_range(0, 4)
	for i: int in count:
		var t: float = (float(i) + 0.35 + rng.randf() * 0.4) / float(count)
		var x: float = center.x - width * 0.5 + t * width
		var length: float = 0.35 + rng.randf() * 0.85
		var radius: float = 0.045 + rng.randf() * 0.05
		_queue_ice(Vector3(x, center.y + height - 0.05 - length * 0.5, front_z + 0.12), radius, length + 0.1, Vector3(0.0, 0.0, (rng.randf() - 0.5) * 0.16))
		# 檐口另一侧也补两三根，避免只有一面有冬天。
		if i % 3 == 0:
			_queue_ice(Vector3(x, center.y + height - 0.05 - length * 0.5, center.z - depth * 0.5 - 0.12), radius, length + 0.1, Vector3.ZERO)

func _wall_lamp(node_name: String, at: Vector3, accent: Color) -> void:
	_box_mesh(node_name + "_Body", at, Vector3(0.34, 0.20, 0.16), "fitting")
	_box_mesh(node_name + "_Lens", at + Vector3(0.0, -0.10, 0.0), Vector3(0.28, 0.06, 0.12), "lamp", accent)
	_add_omni(node_name, at + Vector3(0.0, -0.25, 0.4), PALETTE.warm_lamp, 0.55, 9.0)

func _post(node_name: String, at: Vector3, length: float, radius: float, accent: Color) -> void:
	var post: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.08
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 3
	post.mesh = mesh
	post.name = node_name
	post.position = at + Vector3.UP * length * 0.5
	post.material_override = _detail_material("painted", accent)
	detail_root.add_child(post)
	detail_meshes += 1

func _box_mesh(node_name: String, at: Vector3, size: Vector3, family: String, accent: Color = Color(0, 0, 0, 0)) -> MeshInstance3D:
	var view: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	view.mesh = mesh
	view.name = node_name
	view.position = at
	view.material_override = _detail_material(family, accent)
	detail_root.add_child(view)
	detail_meshes += 1
	return view

func _snow_pillow(_node_name: String, at: Vector3, radii: Vector3) -> void:
	var xf: Transform3D = Transform3D(Basis.from_scale(radii), at)
	_snow_batch.append(xf)

func _queue_ice(at: Vector3, radius: float, length: float, rot: Vector3) -> void:
	var basis: Basis = Basis.from_euler(rot) * Basis.from_scale(Vector3(radius, length, radius))
	_ice_batch.append(Transform3D(basis, at))

func _commit_multimesh_batches() -> void:
	# 将所有雪堆/雪檐合并为单次 Draw Call，所有冰锥/冰晶簇合并为单次 Draw Call
	if not _snow_batch.is_empty():
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 18
		sphere.rings = 8
		var smat: ShaderMaterial = ShaderMaterial.new()
		smat.shader = SNOW_SHADER
		smat.set_shader_parameter("snow_color", Color("#d2e0ea"))
		smat.set_shader_parameter("shadow_color", Color("#93b6ce"))
		smat.set_shader_parameter("grit_color", Color("#4e565c"))
		smat.set_shader_parameter("ripple_strength", 0.35)
		sphere.material = smat
		var smm: MultiMesh = MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.mesh = sphere
		smm.instance_count = _snow_batch.size()
		for i: int in _snow_batch.size():
			smm.set_instance_transform(i, _snow_batch[i])
		var smi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		smi.name = "SnowDetailsBatch"
		smi.multimesh = smm
		detail_root.add_child(smi)
		detail_meshes += 1

	if not _ice_batch.is_empty():
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 1.0
		cone.bottom_radius = 0.10
		cone.height = 1.0
		cone.radial_segments = 7
		cone.rings = 2
		var imat: ShaderMaterial = ShaderMaterial.new()
		imat.shader = ICE_SHADER
		imat.set_shader_parameter("deep_color", PALETTE.ice_deep)
		imat.set_shader_parameter("body_color", PALETTE.ice_body)
		imat.set_shader_parameter("rim_color", PALETTE.ice_rim)
		imat.set_shader_parameter("snow_color", PALETTE.snow)
		imat.set_shader_parameter("emission_strength", 0.22)
		cone.material = imat
		var imm: MultiMesh = MultiMesh.new()
		imm.transform_format = MultiMesh.TRANSFORM_3D
		imm.mesh = cone
		imm.instance_count = _ice_batch.size()
		for i: int in _ice_batch.size():
			imm.set_instance_transform(i, _ice_batch[i])
		var imi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		imi.name = "IceDetailsBatch"
		imi.multimesh = imm
		detail_root.add_child(imi)
		detail_meshes += 1

func _detail_material(family: String, accent: Color = Color(0, 0, 0, 0)) -> ShaderMaterial:
	var use_accent: Color = accent
	if use_accent.a <= 0.0:
		use_accent = BUILDINGS[1][6]
	var cache_key: String = "detail|%s|%s" % [family, use_accent.to_html(false)]
	if material_cache.has(cache_key):
		return material_cache[cache_key] as ShaderMaterial
	var mat: ShaderMaterial = ShaderMaterial.new()
	match family:
		"slab":
			mat.shader = PANEL_SHADER
			mat.set_shader_parameter("paint_color", PALETTE.concrete.darkened(0.12))
			mat.set_shader_parameter("concrete_mode", 1.0)
			mat.set_shader_parameter("rivet_amount", 0.0)
			mat.set_shader_parameter("metallic_paint", 0.0)
			mat.set_shader_parameter("roughness_base", 0.86)
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("snow_amount", 0.9)
			mat.set_shader_parameter("grime_amount", 0.35)
		"painted":
			mat.shader = PANEL_SHADER
			mat.set_shader_parameter("paint_color", use_accent.darkened(0.12))
			mat.set_shader_parameter("accent_color", use_accent.lightened(0.08))
			mat.set_shader_parameter("panel_size", Vector2(0.9, 0.5))
			mat.set_shader_parameter("stripe_height", 0.25)
			mat.set_shader_parameter("snow_color", PALETTE.snow)
			mat.set_shader_parameter("grime_color", PALETTE.grime)
			mat.set_shader_parameter("metallic_paint", 0.28)
			mat.set_shader_parameter("roughness_base", 0.38)
		"fitting":
			mat.shader = PANEL_SHADER
			mat.set_shader_parameter("paint_color", PALETTE.bare)
			mat.set_shader_parameter("accent_color", PALETTE.bare.darkened(0.2))
			mat.set_shader_parameter("panel_size", Vector2(0.22, 0.16))
			mat.set_shader_parameter("stripe_height", 0.02)
			mat.set_shader_parameter("rivet_amount", 0.0)
			mat.set_shader_parameter("metallic_paint", 0.65)
			mat.set_shader_parameter("roughness_base", 0.32)
			mat.set_shader_parameter("snow_color", PALETTE.snow)
		"lamp":
			mat.shader = PANEL_SHADER
			mat.set_shader_parameter("paint_color", Color("#f7e4bd"))
			mat.set_shader_parameter("accent_color", Color("#f7e4bd"))
			mat.set_shader_parameter("emission_color", PALETTE.warm_lamp)
			mat.set_shader_parameter("emission_strength", 1.6)
			mat.set_shader_parameter("stripe_height", 0.0)
			mat.set_shader_parameter("rivet_amount", 0.0)
			mat.set_shader_parameter("snow_amount", 0.0)
			mat.set_shader_parameter("grime_amount", 0.0)
		_:
			return null
	mat.resource_name = "FrostArt_Detail_%s" % family
	material_cache[cache_key] = mat
	return mat

# ---------------------------------------------------------------- 地面细节

func _build_ground() -> void:
	# 雪堆：贴着每栋建筑迎风面与墙角，交代“风从骨口方向吹进站区”。
	for entry: Array in BUILDINGS:
		var center: Vector3 = entry[1]
		var width: float = float(entry[2])
		var depth: float = float(entry[3])
		if center.z > 0.0:
			continue
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = Vector3(center.x + side * (width * 0.5 + 2.4), center.y + 0.12, center.z + depth * 0.25)
			_snow_pillow("Drift_%s_%d" % [entry[0], int(side)], at, Vector3(4.2 + float(abs(int(center.x)) % 3), 0.55, 5.6))
		_snow_pillow("DriftFront_%s" % entry[0], Vector3(center.x - width * 0.18, center.y + 0.10, center.z + depth * 0.5 + 3.0), Vector3(width * 0.28, 0.42, 2.6))
		# 檐下挂冰的融水会把墙脚打湿，加一条深色湿痕带（无碰撞薄片）。
		_box_mesh("WetFoot_" + String(entry[0]), Vector3(center.x, center.y + 0.18, center.z + depth * 0.5 + 0.22), Vector3(width * 0.92, 0.22, 0.10), "slab")
	# 雪地裂隙：从作业院中心向外放射的黑色冰缝，配合采光读出地表的“冰盖”成因。
	var cracks: Array = [
		[Vector3(0, 0.16, -55), 14.0, 0.35, 0.10], [Vector3(-8, 0.16, -70), 9.0, 0.30, -0.90],
		[Vector3(12, 0.16, -66), 11.0, 0.32, 0.55], [Vector3(-18, 0.16, -44), 8.0, 0.28, 1.40],
		[Vector3(6, 0.16, -34), 10.0, 0.30, -0.35], [Vector3(20, 0.16, -80), 7.0, 0.26, 1.10],
	]
	for entry: Array in cracks:
		var seam: MeshInstance3D = _box_mesh("IceCrack_%d" % cracks.find(entry), entry[0], Vector3(float(entry[1]), 0.05, float(entry[2])), "rock")
		seam.rotation.y = float(entry[3])
	# 冰晶簇：只在仓库冰封门与骨口附近从地面裂隙里长出来（晶体与地表有关系）。
	var clusters: Array = [
		[Vector3(-57.0, 0.2, -19.5), 5], [Vector3(-28.0, 0.2, -20.5), 4],
		[Vector3(24.0, 0.2, -184.0), 6], [Vector3(-22.0, 0.2, -178.0), 5],
	]
	for entry: Array in clusters:
		_ice_cluster(entry[0], int(entry[1]))

func _ice_cluster(at: Vector3, count: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = abs(hash(at))
	for i: int in count:
		var offset: Vector3 = Vector3(rng.randf_range(-1.1, 1.1), 0.0, rng.randf_range(-1.1, 1.1))
		var length: float = 0.45 + rng.randf() * 1.25
		var radius: float = 0.09 + rng.randf() * 0.11
		_queue_ice(at + offset + Vector3.UP * length * 0.4, radius, length, Vector3(PI + rng.randf_range(-0.30, 0.30), rng.randf_range(0.0, TAU), rng.randf_range(-0.35, 0.35)))

# ---------------------------------------------------------------- 盆地外围雪原与冰缝结晶

func _build_ridges() -> void:
	# 旧版方盒岩脊已由 720×920m 程序化地形替代；此处沿西线冰缝与东线盘山公路补充合批冰晶簇（零额外 Draw Call）
	for z: float in [-96.0, -82.0, -60.0, -48.0]:
		_ice_cluster(Vector3(-126.0, -4.2, z), 5)
		_ice_cluster(Vector3(-144.0, -4.2, z), 5)
	_ice_cluster(Vector3(-206.0, 1.8, -82.0), 6)
	_ice_cluster(Vector3(205.0, 14.2, -68.0), 6)

func _build_hero_landmarks_and_conduits() -> void:
	# 1. 开放式远古巨兽生物骨架峡谷：入口巨兽头骨（眼眶+鼻脊+弯钩利齿）+ 8 组连贯解剖脊椎肋骨笼
	var skull: Node3D = LEVIATHAN_SKULL_GLB.instantiate() as Node3D
	skull.name = "HeroLeviathanSkull"
	skull.position = Vector3(0.0, 0.0, -172.0)
	skull.scale = Vector3(1.28, 1.28, 1.28)
	_pbr.bind_glb(skull, "frost", true)
	detail_root.add_child(skull)
	detail_meshes += 1

	for arch_z: float in [-192.0, -214.0, -238.0, -264.0, -294.0, -328.0, -368.0, -412.0]:
		var arch: Node3D = FOSSIL_ARCH_GLB.instantiate() as Node3D
		arch.name = "HeroFossilArch_%.0f" % arch_z
		arch.position = Vector3(0.0, 0.0, arch_z)
		var sc: float = 1.48 if arch_z > -250.0 else 1.32
		arch.scale = Vector3(sc, sc, sc)
		_pbr.bind_glb(arch, "frost", true)
		detail_root.add_child(arch)
		detail_meshes += 1
	# 峡谷两侧天然解理冰川峭壁巨岩（露出金桃色极地日落天空，再无方盒机库墙）
	var cliff_cloak: Array = [
		[Vector3(-44.0, 2.0, -182.0), Vector3(6.8, 9.5, 6.2), 22.0],
		[Vector3(44.0, 2.0, -182.0), Vector3(6.8, 9.5, 6.2), -28.0],
		[Vector3(-48.0, 2.0, -228.0), Vector3(7.4, 11.2, 7.0), -15.0],
		[Vector3(48.0, 2.0, -228.0), Vector3(7.4, 11.2, 7.0), 34.0],
		[Vector3(-50.0, 3.0, -286.0), Vector3(8.0, 12.0, 7.5), 18.0],
		[Vector3(50.0, 3.0, -286.0), Vector3(8.0, 12.0, 7.5), -24.0],
	]
	for idx: int in cliff_cloak.size():
		var cl: Node3D = ROCK_GLB.instantiate() as Node3D
		cl.name = "HeroCliffCloak_%d" % idx
		cl.position = cliff_cloak[idx][0]
		cl.scale = cliff_cloak[idx][1]
		cl.rotation_degrees.y = float(cliff_cloak[idx][2])
		_pbr.bind_glb(cl, "frost", true)
		detail_root.add_child(cl)
		detail_meshes += 1
	# 骨口巨拱下的极地光柱（克制假体积光）
	ArtAtmosphereKit.build_godray_cone(detail_root, Vector3(0.0, 28.0, -184.0), 28.0, 5.5, 13.5, Color("#8ce4ff"), 0.09)

	# 2. 地热涡轮发电机英雄件（动力站外侧、北哨中继站、东线气象雷达高地）
	var gen_spots: Array = [
		[Vector3(64.0, 0.0, -100.0), 1.0, true],
		[Vector3(71.0, 0.0, -155.0), 0.78, true],
		[Vector3(222.0, 14.2, -82.0), 0.92, true],
	]
	for idx: int in gen_spots.size():
		var gp: Vector3 = gen_spots[idx][0]
		var gs: float = float(gen_spots[idx][1])
		var gen: Node3D = GEO_GEN_GLB.instantiate() as Node3D
		gen.name = "HeroGeoGen_%d" % idx
		gen.position = gp
		gen.scale = Vector3.ONE * gs
		_pbr.bind_glb(gen, "frost", true)
		detail_root.add_child(gen)
		ArtAtmosphereKit.build_ground_skirt(detail_root, gp, 2.8 * gs, 0.50)
		ArtAtmosphereKit.build_steam_vent(detail_root, gp + Vector3(0.0, 5.0 * gs, 0.0), Color(0.85, 0.94, 1.0, 0.34), 1.0)
		_add_omni("GeoGenGlow_%d" % idx, gp + Vector3(0.0, 1.8 * gs, 1.8 * gs), Color("#ff9842"), 1.8, 14.0)
		detail_meshes += 1

	# 2.5 新增极地玻璃穹顶温室 (#7 & #11) 与 19m 高空通讯气象塔 (#8 & 东雷达高地)
	for dome_info: Array in [
		["GreenhouseDome", Vector3(-88.0, 0.12, -108.0), 1.0],
		["SouthOutpostDome", Vector3(-115.0, 2.65, 85.0), 0.96],
	]:
		var dm: Node3D = GEO_DOME_GLB.instantiate() as Node3D
		dm.name = String(dome_info[0])
		dm.position = dome_info[1]
		dm.scale = Vector3.ONE * float(dome_info[2])
		_pbr.bind_glb(dm, "frost", true)
		detail_root.add_child(dm)
		ArtAtmosphereKit.build_ground_skirt(detail_root, dome_info[1], 9.2, 0.48)
		_add_omni(String(dome_info[0]) + "_WarmGlow", (dome_info[1] as Vector3) + Vector3(0.0, 3.8, 0.0), Color("#ffcb78"), 2.4, 24.0)
		detail_meshes += 1

	for tower_info: Array in [
		["CommsHubTower", Vector3(98.0, 0.0, -109.5), 1.0, 18.0],
		["EastRadarTower", Vector3(215.0, 14.3, -80.5), 1.12, -25.0],
	]:
		var tw: Node3D = COMMS_TOWER_GLB.instantiate() as Node3D
		tw.name = String(tower_info[0])
		tw.position = tower_info[1]
		tw.scale = Vector3.ONE * float(tower_info[2])
		tw.rotation_degrees.y = float(tower_info[3])
		_pbr.bind_glb(tw, "frost", true)
		detail_root.add_child(tw)
		ArtAtmosphereKit.build_ground_skirt(detail_root, tower_info[1], 4.8, 0.50)
		_add_omni(String(tower_info[0]) + "_Beacon", (tower_info[1] as Vector3) + Vector3(0.0, 19.2 * float(tower_info[2]), 0.0), Color("#ff5030"), 2.8, 30.0)
		detail_meshes += 1

	# 3. 英雄级解理玄武岩巨石 + 不等边三层光学蓝冰晶簇（接地暗晕 + 实用冷青光）
	var rock_spots: Array = [
		[Vector3(-32.0, 0.0, -52.0), 1.15, 25.0], [Vector3(34.0, 0.0, -90.0), 1.05, -40.0],
		[Vector3(-68.0, 0.0, -98.0), 1.45, 70.0], [Vector3(74.0, 0.0, -44.0), 1.35, 110.0],
		[Vector3(-28.0, 0.0, -158.0), 1.65, 15.0], [Vector3(24.0, 0.0, -162.0), 1.40, -65.0],
		[Vector3(-106.0, 0.0, -54.0), 1.55, 35.0], [Vector3(-164.0, 0.5, -96.0), 1.65, -22.0],
		[Vector3(145.0, 6.2, -32.0), 1.50, 82.0], [Vector3(188.0, 11.8, -58.0), 1.60, -18.0],
	]
	for idx: int in rock_spots.size():
		var rp: Vector3 = rock_spots[idx][0]
		var rs: float = float(rock_spots[idx][1])
		var rock: Node3D = ROCK_GLB.instantiate() as Node3D
		rock.name = "HeroGlacierRock_%d" % idx
		rock.position = rp
		rock.rotation_degrees.y = float(rock_spots[idx][2])
		rock.scale = Vector3.ONE * rs
		_pbr.bind_glb(rock, "frost", true)
		detail_root.add_child(rock)
		ArtAtmosphereKit.build_ground_skirt(detail_root, rp, 3.6 * rs, 0.44)
		detail_meshes += 1

	var spire_spots: Array = [
		[Vector3(-25.0, 0.0, -48.0), 1.15, 12.0], [Vector3(26.0, 0.0, -86.0), 1.05, -35.0],
		[Vector3(-20.0, 0.0, -166.0), 1.65, 48.0], [Vector3(22.0, 0.0, -172.0), 1.70, -25.0],
		[Vector3(-124.0, -1.2, -62.0), 1.85, 15.0], [Vector3(-146.0, -1.2, -82.0), 1.90, -52.0],
		[Vector3(-202.0, 1.4, -78.0), 1.45, 72.0], [Vector3(204.0, 14.0, -64.0), 1.55, -18.0],
	]
	for idx: int in spire_spots.size():
		var sp: Vector3 = spire_spots[idx][0]
		var ss: float = float(spire_spots[idx][1])
		var spire: Node3D = ICE_SPIRE_GLB.instantiate() as Node3D
		spire.name = "HeroIceSpire_%d" % idx
		spire.position = sp
		spire.rotation_degrees.y = float(spire_spots[idx][2])
		spire.scale = Vector3.ONE * ss
		_pbr.bind_glb(spire, "frost", true)
		detail_root.add_child(spire)
		ArtAtmosphereKit.build_ground_skirt(detail_root, sp, 1.8 * ss, 0.42)
		if idx < 6:
			_add_omni("IceSpireGlow_%d" % idx, sp + Vector3(0.0, 2.2 * ss, 0.0), Color("#38d2ff"), 1.35, 12.0)
		detail_meshes += 1

	# 4. 关键交互点的英雄拉杆控制台装饰（纯视觉，零碰撞干扰）
	for entry: Array in [
		[Vector3(50.0, 0.1, -108.0), 0.0],
		[Vector3(215.0, 14.5, -71.5), 0.0],
		[Vector3(-204.8, 1.8, -87.5), -PI * 0.5],
	]:
		var lc: Node3D = LEVER_GLB.instantiate() as Node3D
		lc.position = entry[0]
		lc.rotation.y = float(entry[1])
		_pbr.bind_glb(lc, "frost", true)
		detail_root.add_child(lc)

	# 5. 跨雪原物理因果装甲导管（看得见的因果连线：不用读文字就能沿着发光导管找到动力站/主楼/北哨/雷达塔）
	_power_conduit_mats.append(PhysicalLinkKit.build_conduit_path(detail_root, [
		Vector3(58.0, 0.35, -100.0), Vector3(32.0, 0.35, -92.0), Vector3(12.0, 0.35, -92.0)
	], 0.14, Color("#ffae42")))
	_power_conduit_mats.append(PhysicalLinkKit.build_conduit_path(detail_root, [
		Vector3(58.0, 0.35, -100.0), Vector3(44.0, 0.35, -125.0), Vector3(48.0, 0.35, -155.0)
	], 0.14, Color("#28dbff")))
	_radar_conduit_mats.append(PhysicalLinkKit.build_conduit_path(detail_root, [
		Vector3(0.0, 0.35, -12.0), Vector3(0.0, 0.35, -50.0), Vector3(0.0, 0.35, -90.0)
	], 0.13, Color("#28dbff")))
	_radar_conduit_mats.append(PhysicalLinkKit.build_conduit_path(detail_root, [
		Vector3(64.0, 0.35, -100.0), Vector3(115.0, 4.2, -52.0), Vector3(170.0, 9.8, -62.0), Vector3(215.0, 14.6, -72.0)
	], 0.14, Color("#28dbff")))
	# 新增连接极地温室、货运站与通讯灯塔的发光能量导管，让 11 栋建筑连成完整极地小镇
	_power_conduit_mats.append(PhysicalLinkKit.build_conduit_path(detail_root, [
		Vector3(-30.0, 0.35, -108.0), Vector3(-62.0, 0.35, -108.0), Vector3(-80.0, 0.35, -108.0)
	], 0.14, Color("#ffae42")))
	_power_conduit_mats.append(PhysicalLinkKit.build_conduit_path(detail_root, [
		Vector3(71.0, 0.35, -108.0), Vector3(88.0, 0.35, -96.0)
	], 0.14, Color("#28dbff")))
	_power_conduit_mats.append(PhysicalLinkKit.build_conduit_path(detail_root, [
		Vector3(-63.0, 0.35, -28.0), Vector3(-82.0, 0.35, -28.0)
	], 0.14, Color("#ffae42")))

# ---------------------------------------------------------------- 空气

func _build_air() -> void:
	# 稀疏飘雪：只给三个玩家会停留的区域，不铺满全图。
	_snowfall("SnowfallYard", Vector3(0, 9.0, -60), 46, 26.0)
	_snowfall("SnowfallEntrance", Vector3(0, 8.0, -92), 30, 18.0)
	_snowfall("SnowfallBone", Vector3(0, 10.0, -182), 30, 20.0)

func _snowfall(node_name: String, at: Vector3, amount: int, radius: float) -> void:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = 16.0
	particles.randomness = 0.85
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(radius, 2.0, radius)
	particles.direction = Vector3(0.55, -1.0, 0.32)
	particles.spread = 18.0
	particles.gravity = Vector3(0.10, -0.34, 0.06)
	particles.initial_velocity_min = 0.25
	particles.initial_velocity_max = 0.75
	particles.scale_amount_min = 0.020
	particles.scale_amount_max = 0.052
	particles.position = at
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 5
	mesh.rings = 3
	particles.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.96, 1.0, 0.42)
	mat.emission_enabled = true
	mat.emission = Color("#cfe9ff")
	mat.emission_energy_multiplier = 0.28
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particles.material_override = mat
	detail_root.add_child(particles)
