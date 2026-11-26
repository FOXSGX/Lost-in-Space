extends RefCounted
class_name ArtPbrLib

## 《迷失太空》统一 PBR 材质库（严格对齐 ART-SAMPLE-002 & 《美术制作与AI协作指南》）
## - 支持 70/15/10/8/2 功能色板比例（奶油外壳 <= 0.62 / 工业橙 <= 8% / 青绿引导 / 暗钢基底）
## - 绑定真实 2K 多频法线/粗糙/掩膜贴图（paint / cast / mach / conc / rock）
## - 强制区分有顶点色 Col 的 Blender 烘焙件与无顶点色网格（vertex_mask_valid）

const SH_METAL := "res://shaders/aqs2_metal.gdshader"
const SH_ROCK := "res://shaders/aqs2_rock.gdshader"
const SH_CRYSTAL := "res://shaders/aqs2_crystal.gdshader"
const TEX_DIR := "res://assets/textures/art_pbr/"

const BAL := {
	"dust_amount": 0.48, "grime_amount": 0.65, "streak_amount": 0.62,
	"rust_amount": 0.55, "chip_gain": 0.85, "wear_gain": 0.92, "edge_rim": 0.62,
}

var _tex_cache: Dictionary = {}
var _mat_cache: Dictionary = {}

func _tex(fname: String) -> Texture2D:
	if _tex_cache.has(fname):
		return _tex_cache[fname] as Texture2D
	var path: String = TEX_DIR + fname
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[fname] = t
	return t

func make_metal(params: Dictionary, family: String = "paint", has_vertex_color: bool = true) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(SH_METAL)
	for k: String in params.keys():
		var v: Variant = params[k]
		if v is float and BAL.has(k):
			v = float(v) * float(BAL[k])
		m.set_shader_parameter(k, v)
	m.set_shader_parameter("vertex_mask_valid", has_vertex_color)
	m.set_shader_parameter("world_seed", randf() * 37.0)
	if not family.is_empty():
		var nt: Texture2D = _tex(family + "_normal.png")
		var rt: Texture2D = _tex(family + "_rough.png")
		var mt: Texture2D = _tex(family + "_mask.png")
		if nt != null:
			m.set_shader_parameter("detail_normal", nt)
			m.set_shader_parameter("use_detail", true)
		if rt != null:
			m.set_shader_parameter("detail_rough", rt)
		if mt != null:
			m.set_shader_parameter("detail_mask", mt)
			m.set_shader_parameter("use_detail_mask", true)
	return m

func make_rock(a: Color, b: Color, c: Color, dust: Color, strata: float = 2.4, crack: float = 0.35, has_vertex_color: bool = true) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(SH_ROCK)
	m.set_shader_parameter("stone_a", a)
	m.set_shader_parameter("stone_b", b)
	m.set_shader_parameter("stone_c", c)
	m.set_shader_parameter("dust_color", dust)
	m.set_shader_parameter("fresh_color", c.lightened(0.12))
	m.set_shader_parameter("damp_color", b.darkened(0.25))
	m.set_shader_parameter("strata_period", clampf(1.0 / maxf(0.3, strata), 0.12, 1.1))
	m.set_shader_parameter("patch_gain", clampf(crack, 0.0, 1.0))
	m.set_shader_parameter("ambient_fill", 0.14)
	m.set_shader_parameter("world_seed", randf() * 29.0)
	if not has_vertex_color:
		m.set_shader_parameter("arris_gain", 0.25)
		m.set_shader_parameter("cavity_gain", 0.20)
	var nt: Texture2D = _tex("rock_normal.png")
	var rt: Texture2D = _tex("rock_rough.png")
	var mt: Texture2D = _tex("rock_mask.png")
	if nt != null:
		m.set_shader_parameter("detail_normal", nt)
		m.set_shader_parameter("use_detail", true)
	if rt != null:
		m.set_shader_parameter("detail_rough", rt)
	if mt != null:
		m.set_shader_parameter("detail_mask", mt)
		m.set_shader_parameter("use_detail_mask", true)
	m.set_shader_parameter("detail_scale", 2.8)
	m.set_shader_parameter("detail_strength", 0.72)
	m.set_shader_parameter("cleft_scale", 0.45)
	return m

func make_crystal(deep: Color, body: Color, tip: Color, vein: Color, root: Color, energy: float = 0.65) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(SH_CRYSTAL)
	m.set_shader_parameter("deep_color", deep)
	m.set_shader_parameter("body_color", body)
	m.set_shader_parameter("tip_color", tip)
	m.set_shader_parameter("vein_color", vein)
	m.set_shader_parameter("root_color", root)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("vein_strength", 0.35)
	m.set_shader_parameter("core_strength", 0.50)
	m.set_shader_parameter("world_seed", randf() * 19.0)
	return m

## 构建统一标准材质表（theme: "ship" 或 "frost"）
func build_palette(theme: String = "frost", has_vertex_color: bool = true) -> Dictionary:
	var cache_key: String = "%s_%s" % [theme, str(has_vertex_color)]
	if _mat_cache.has(cache_key):
		return _mat_cache[cache_key] as Dictionary
	var dust: Color = Color(0.74, 0.82, 0.88) if theme == "frost" else Color(0.42, 0.46, 0.50)
	var d_amt: float = 0.72 if theme == "frost" else 0.28
	var mats: Dictionary = {}

	# 15% 高明度识别外壳（严控 PBR 反照率 <= 0.62 防炸白）
	mats["M_PaintCream"] = make_metal({
		"paint_color": Color(0.60, 0.58, 0.52) if theme == "ship" else Color(0.58, 0.59, 0.56),
		"primer_color": Color(0.46, 0.27, 0.21),
		"bare_color": Color(0.56, 0.58, 0.60),
		"dust_color": dust, "dust_amount": d_amt,
		"rough_paint": 0.44, "metallic_paint": 0.12,
		"wear_gain": 1.10, "chip_threshold": 0.58,
		"detail_scale": 2.8, "detail_strength": 0.58,
	}, "paint", has_vertex_color)

	# <=8% 工业橙（严格仅用于手柄、阀门、护杠、抓取位、操作按钮）
	mats["M_PaintOrange"] = make_metal({
		"paint_color": Color(0.700, 0.268, 0.062),
		"primer_color": Color(0.42, 0.22, 0.16),
		"dust_color": dust, "dust_amount": d_amt * 0.7,
		"rough_paint": 0.46, "metallic_paint": 0.12,
		"wear_gain": 1.15, "chip_threshold": 0.56,
		"detail_scale": 3.4, "detail_strength": 0.55,
	}, "paint", has_vertex_color)

	# 安全黄（限边缘警戒线/标牌）
	mats["M_PaintYellow"] = make_metal({
		"paint_color": Color(0.78, 0.54, 0.10),
		"primer_color": Color(0.44, 0.30, 0.18),
		"dust_color": dust, "dust_amount": d_amt * 0.6,
		"rough_paint": 0.46, "metallic_paint": 0.10,
		"wear_gain": 1.15, "chip_threshold": 0.54,
		"detail_scale": 3.4, "detail_strength": 0.52,
	}, "paint", has_vertex_color)

	# 5-10% 钢青/深青（我方/安全/导引）
	mats["M_PaintTeal"] = make_metal({
		"paint_color": Color(0.145, 0.34, 0.38),
		"dust_color": dust, "dust_amount": d_amt * 0.7,
		"rough_paint": 0.42, "metallic_paint": 0.16,
		"wear_gain": 1.0, "chip_threshold": 0.62,
		"detail_scale": 3.2, "detail_strength": 0.52,
	}, "paint", has_vertex_color)
	mats["M_Teal"] = mats["M_PaintTeal"]

	# 70% 主骨架/冷灰底色
	mats["M_PaintGrey"] = make_metal({
		"paint_color": Color(0.24, 0.28, 0.32),
		"dust_color": dust, "dust_amount": d_amt,
		"rough_paint": 0.52, "metallic_paint": 0.22,
		"wear_gain": 1.0, "chip_threshold": 0.62,
		"detail_scale": 3.0, "detail_strength": 0.55,
	}, "paint", has_vertex_color)

	mats["M_SteelDeep"] = make_metal({
		"paint_color": Color(0.105, 0.128, 0.152),
		"dust_color": dust, "dust_amount": d_amt * 0.6,
		"rough_paint": 0.46, "metallic_paint": 0.52,
		"wear_gain": 0.90, "chip_threshold": 0.66,
		"detail_scale": 3.4, "detail_strength": 0.72,
	}, "cast", has_vertex_color)
	mats["M_DarkSteel"] = mats["M_SteelDeep"]

	mats["M_CastSteel"] = make_metal({
		"paint_color": Color(0.26, 0.29, 0.32),
		"dust_color": dust, "dust_amount": d_amt * 0.75,
		"rough_paint": 0.60, "metallic_paint": 0.55,
		"wear_gain": 0.85, "chip_threshold": 0.66,
		"detail_scale": 3.8, "detail_strength": 0.78,
	}, "cast", has_vertex_color)

	mats["M_BareSteel"] = make_metal({
		"paint_color": Color(0.45, 0.48, 0.51),
		"bare_color": Color(0.62, 0.64, 0.66),
		"rough_paint": 0.28, "metallic_paint": 0.86,
		"wear_gain": 0.35, "chip_threshold": 1.60,
		"detail_scale": 4.6, "detail_strength": 0.48,
	}, "mach", has_vertex_color)

	mats["M_MachinedSteel"] = make_metal({
		"paint_color": Color(0.56, 0.58, 0.60),
		"bare_color": Color(0.68, 0.70, 0.72),
		"rough_paint": 0.18, "metallic_paint": 0.95,
		"wear_gain": 0.25, "chip_threshold": 1.60,
		"detail_scale": 5.8, "detail_strength": 0.36,
	}, "mach", has_vertex_color)

	mats["M_Bronze"] = make_metal({
		"paint_color": Color(0.54, 0.38, 0.16),
		"rust_color": Color(0.18, 0.36, 0.30),
		"rough_paint": 0.32, "metallic_paint": 0.86,
		"wear_gain": 0.55, "chip_threshold": 0.74, "rust_amount": 0.30,
		"detail_scale": 5.2, "detail_strength": 0.48,
	}, "cast", has_vertex_color)

	mats["M_Concrete"] = make_metal({
		"paint_color": Color(0.24, 0.27, 0.30) if theme == "frost" else Color(0.22, 0.24, 0.26),
		"primer_color": Color(0.35, 0.37, 0.39),
		"bare_color": Color(0.42, 0.44, 0.46),
		"dust_color": dust, "dust_amount": d_amt * 1.1,
		"rough_paint": 0.86, "metallic_paint": 0.0,
		"rust_amount": 0.0, "concrete_mode": 1.0,
		"detail_scale": 1.8, "detail_strength": 0.88,
	}, "conc", has_vertex_color)
	mats["M_Grout"] = mats["M_Concrete"]

	mats["M_Rubber"] = make_metal({
		"paint_color": Color(0.055, 0.060, 0.068),
		"dust_color": dust, "dust_amount": d_amt * 0.8,
		"rough_paint": 0.90, "metallic_paint": 0.0,
		"rust_amount": 0.0, "chip_threshold": 1.60,
		"detail_scale": 4.2, "detail_strength": 0.55,
	}, "cast", has_vertex_color)

	# 玻璃 / 状态发光（克制发光，保留色相梯度）
	var glass_warm: StandardMaterial3D = StandardMaterial3D.new()
	glass_warm.albedo_color = Color(0.95, 0.84, 0.64)
	glass_warm.emission_enabled = true
	glass_warm.emission = Color(1.0, 0.78, 0.45)
	glass_warm.emission_energy_multiplier = 1.45
	mats["M_Glass"] = glass_warm

	var glow_cyan: StandardMaterial3D = StandardMaterial3D.new()
	glow_cyan.albedo_color = Color(0.10, 0.42, 0.52)
	glow_cyan.emission_enabled = true
	glow_cyan.emission = Color(0.14, 0.72, 0.86)
	glow_cyan.emission_energy_multiplier = 0.85
	mats["M_GlowCyan"] = glow_cyan

	var glow_amber: StandardMaterial3D = StandardMaterial3D.new()
	glow_amber.albedo_color = Color(0.96, 0.62, 0.18)
	glow_amber.emission_enabled = true
	glow_amber.emission = Color(0.96, 0.54, 0.14)
	glow_amber.emission_energy_multiplier = 1.60
	mats["M_GlowAmber"] = glow_amber

	var glow_red: StandardMaterial3D = StandardMaterial3D.new()
	glow_red.albedo_color = Color(0.92, 0.22, 0.16)
	glow_red.emission_enabled = true
	glow_red.emission = Color(1.0, 0.20, 0.12)
	glow_red.emission_energy_multiplier = 1.50
	mats["M_GlowRed"] = glow_red

	var glow_green: StandardMaterial3D = StandardMaterial3D.new()
	glow_green.albedo_color = Color(0.16, 0.78, 0.46)
	glow_green.emission_enabled = true
	glow_green.emission = Color(0.18, 0.88, 0.52)
	glow_green.emission_energy_multiplier = 1.35
	mats["M_GlowGreen"] = glow_green

	var dome_glass: StandardMaterial3D = StandardMaterial3D.new()
	dome_glass.albedo_color = Color(0.76, 0.90, 0.92, 0.48)
	dome_glass.roughness = 0.14
	dome_glass.metallic = 0.12
	dome_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dome_glass.emission_enabled = true
	dome_glass.emission = Color(0.95, 0.74, 0.42)
	dome_glass.emission_energy_multiplier = 0.36
	mats["M_GlassWarm"] = dome_glass

	var plant_leaf: StandardMaterial3D = StandardMaterial3D.new()
	plant_leaf.albedo_color = Color(0.16, 0.48, 0.22)
	plant_leaf.roughness = 0.64
	plant_leaf.metallic = 0.0
	mats["M_PlantLeaf"] = plant_leaf

	var plant_leaf_light: StandardMaterial3D = StandardMaterial3D.new()
	plant_leaf_light.albedo_color = Color(0.30, 0.64, 0.30)
	plant_leaf_light.roughness = 0.60
	plant_leaf_light.metallic = 0.0
	mats["M_PlantLeafLight"] = plant_leaf_light

	var fabric_warm: StandardMaterial3D = StandardMaterial3D.new()
	fabric_warm.albedo_color = Color(0.62, 0.44, 0.34)
	fabric_warm.roughness = 0.82
	fabric_warm.metallic = 0.0
	mats["M_FabricWarm"] = fabric_warm

	var fabric_blue: StandardMaterial3D = StandardMaterial3D.new()
	fabric_blue.albedo_color = Color(0.24, 0.46, 0.58)
	fabric_blue.roughness = 0.80
	fabric_blue.metallic = 0.0
	mats["M_FabricBlue"] = fabric_blue

	# 极寒冰原特色：冷板岩基岩 + 陡切蓝冰晶 + 巨兽古骨
	mats["M_Bedrock"] = make_rock(
		Color(0.20, 0.27, 0.34), Color(0.10, 0.14, 0.19),
		Color(0.32, 0.40, 0.47), Color(0.76, 0.84, 0.90), 2.4, 0.38, has_vertex_color
	)
	mats["M_BedrockDark"] = make_rock(
		Color(0.13, 0.18, 0.23), Color(0.06, 0.09, 0.13),
		Color(0.22, 0.28, 0.34), Color(0.68, 0.78, 0.85), 3.0, 0.42, has_vertex_color
	)
	mats["M_FossilBone"] = make_rock(
		Color(0.62, 0.58, 0.50), Color(0.38, 0.35, 0.30),
		Color(0.70, 0.66, 0.58), Color(0.80, 0.86, 0.90), 1.6, 0.22, has_vertex_color
	)
	mats["M_CrystalShell"] = make_crystal(
		Color(0.015, 0.085, 0.145), Color(0.09, 0.42, 0.58),
		Color(0.68, 0.92, 1.00), Color(0.26, 0.78, 0.96),
		Color(0.16, 0.22, 0.27), 0.62
	)
	mats["M_CrystalCore"] = make_crystal(
		Color(0.03, 0.18, 0.28), Color(0.22, 0.68, 0.85),
		Color(0.82, 0.96, 1.00), Color(0.38, 0.88, 1.00),
		Color(0.16, 0.22, 0.27), 0.92
	)
	mats["M_ThermalCore"] = make_crystal(
		Color(0.22, 0.05, 0.02), Color(0.82, 0.34, 0.08),
		Color(1.00, 0.82, 0.42), Color(1.00, 0.56, 0.14),
		Color(0.18, 0.14, 0.12), 1.05
	)

	_mat_cache[cache_key] = mats
	return mats

## 批量按 GLB 材质名覆盖表面材质（保持零硬编码）
func bind_glb(root: Node, theme: String = "frost", has_vertex_color: bool = true) -> void:
	var mats: Dictionary = build_palette(theme, has_vertex_color)
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var key: String = src.resource_name
			if mats.has(key):
				mi.set_surface_override_material(s, mats[key] as Material)
