extends RefCounted
class_name RuinSurfaceLib

## 腐墟星表面材质库（planet-02 唯一材质入口）。
##
## 目的：把 ART-SAMPLE-002 的 2K 分族贴图与 aqs2_metal / aqs2_rock / aqs2_crystal
## 接入腐墟星的程序化几何，做出《美术制作与 AI 协作指南》要求的四层表面：
##   面漆/表壳 → 露底漆/原胚 → 凹缝/接地污垢 → 朝上积尘
##
## 约定：
## - 传进来的 Color 一律按 sRGB 十六进制语义书写（与 ruin_cartoon_art.gd 原调色板一致）；
##   aqs2_* 的 `source_color` uniform 会负责 sRGB→线性转换，这里不再手动转换。
## - 程序化网格没有顶点色，所有 ShaderMaterial 必须 `vertex_mask_valid = false`，
##   否则 COLOR 恒为 1，会被当成“整件都磨损 + 整件都遮蔽”，整件发黑烂漆。
## - world_seed 用颜色/家族哈希确定，不用 randf()：主机与客户端、改造前后截图必须一致。
## - 材质按 key 缓存：整张地图只保留十几份材质，不再每个网格 new 一份。

const SH_METAL := "res://shaders/ruin_surface.gdshader"
const SH_ROCK := "res://shaders/ruin_rock.gdshader"
const SH_CRYSTAL := "res://shaders/ruin_crystal.gdshader"
const TEX_SAMPLE := "res://assets/art-sample-002/textures/"
const TEX_RUIN := "res://assets/ruin/textures/"

## 材质家族。顺序即语义，不要随意改数值之外的顺序。
enum Family {
	PAINT_CLEAN,    # 建筑外壳/浅色设备罩壳：轻磨损、低锈
	PAINT_WORN,     # 街具/门板/外壳：明显棱角磨损与雨痕
	PAINT_ACCENT,   # 可操作件与警示边界：工业橙/琥珀，磨损更重
	CAST,           # 铸铁底座、深色结构件、砂型铸件
	MACH,           # 机加工：栏杆、手柄、阀体、管件
	CONC,           # 混凝土：承台、勒脚、路面、铺装
	ROCK,           # 自然岩体（aqs2_rock）
	BIO,            # 菌群：菌盖、菌褶、菌丝、感染体表皮
	FOLIAGE,        # 树冠/灌木/草：哑光、轻磨损，不吃锈
	GLASS,          # 窗玻璃/顶棚采光
	EMISSIVE,       # 灯具/灯带/状态灯（StandardMaterial3D + 软膝）
}

const FAMILY_TEX := {
	Family.PAINT_CLEAN: "paint",
	Family.PAINT_WORN: "paint",
	Family.PAINT_ACCENT: "paint",
	Family.CAST: "cast",
	Family.MACH: "mach",
	Family.CONC: "conc",
	Family.ROCK: "rock",
	Family.BIO: "bio",
	Family.FOLIAGE: "paint",
}

## 各族默认参数（可被 override 覆盖）。
## 数值以《指南》3.x 参数模板为准，并按腐墟星“傍晚阴天 + 低饱和”整体收一档。
const PRESETS := {
	Family.PAINT_CLEAN: {
		"primer_color": Color("#8a7c65"),
		"bare_color": Color("#8e9298"),
		"rust_color": Color("#6b4a32"),
		"dust_color": Color("#a99d86"),
		"rough_paint": 0.50, "metallic_paint": 0.08, "rough_bare": 0.30,
		"wear_gain": 0.55, "chip_threshold": 0.68, "chip_gain": 0.75,
		"rust_amount": 0.10, "grime_amount": 0.38, "streak_amount": 0.50,
		"dust_amount": 0.30, "cavity_amount": 0.60, "edge_rim": 0.32,
		"detail_scale": 3.0, "detail_strength": 0.85, "rough_variation": 0.18,
	},
	Family.PAINT_WORN: {
		"primer_color": Color("#7d5a45"),
		"bare_color": Color("#8e9298"),
		"rust_color": Color("#70452d"),
		"dust_color": Color("#a99d86"),
		"rough_paint": 0.47, "metallic_paint": 0.10, "rough_bare": 0.28,
		"wear_gain": 1.05, "chip_threshold": 0.56, "chip_gain": 0.95,
		"rust_amount": 0.34, "grime_amount": 0.54, "streak_amount": 0.60,
		"dust_amount": 0.36, "cavity_amount": 0.72, "edge_rim": 0.45,
		"detail_scale": 3.2, "detail_strength": 0.80, "rough_variation": 0.20,
	},
	Family.PAINT_ACCENT: {
		"primer_color": Color("#7d5a45"),
		"bare_color": Color("#9a9a94"),
		"rust_color": Color("#70452d"),
		"dust_color": Color("#b0a48c"),
		"rough_paint": 0.48, "metallic_paint": 0.10, "rough_bare": 0.26,
		"wear_gain": 1.25, "chip_threshold": 0.52, "chip_gain": 1.05,
		"rust_amount": 0.45, "grime_amount": 0.62, "streak_amount": 0.65,
		"dust_amount": 0.42, "cavity_amount": 0.75, "edge_rim": 0.55,
		"detail_scale": 3.6, "detail_strength": 0.60, "rough_variation": 0.18,
	},
	Family.CAST: {
		"primer_color": Color("#3c3a34"),
		"bare_color": Color("#8e9298"),
		"rust_color": Color("#6a4128"),
		"dust_color": Color("#9d927c"),
		"rough_paint": 0.64, "metallic_paint": 0.48, "rough_bare": 0.34,
		"wear_gain": 0.85, "chip_threshold": 0.66, "chip_gain": 0.85,
		"rust_amount": 0.35, "grime_amount": 0.66, "streak_amount": 0.55,
		"dust_amount": 0.40, "cavity_amount": 0.80, "edge_rim": 0.38,
		"detail_scale": 4.0, "detail_strength": 0.85, "rough_variation": 0.16,
	},
	Family.MACH: {
		"primer_color": Color("#4a4a46"),
		"bare_color": Color("#a8adb2"),
		"rust_color": Color("#7a4a2c"),
		"dust_color": Color("#9d927c"),
		"rough_paint": 0.26, "metallic_paint": 0.85, "rough_bare": 0.20,
		"wear_gain": 0.40, "chip_threshold": 1.10, "chip_gain": 0.60,
		"rust_amount": 0.12, "grime_amount": 0.40, "streak_amount": 0.42,
		"dust_amount": 0.25, "cavity_amount": 0.55, "edge_rim": 0.55,
		"detail_scale": 5.0, "detail_strength": 0.42, "rough_variation": 0.10,
	},
	Family.CONC: {
		"primer_color": Color("#5a5347"),
		"bare_color": Color("#8e8b80"),
		"rust_color": Color("#6a4128"),
		"dust_color": Color("#b0a48c"),
		"rough_paint": 0.88, "metallic_paint": 0.0, "rough_bare": 0.90,
		"wear_gain": 0.55, "chip_threshold": 0.88, "chip_gain": 0.70,
		"rust_amount": 0.0, "grime_amount": 0.46, "streak_amount": 0.48,
		"dust_amount": 0.28, "cavity_amount": 0.85, "edge_rim": 0.10,
		"detail_scale": 1.9, "detail_strength": 1.00, "rough_variation": 0.16,
		"concrete_mode": 1.0,
	},
	Family.BIO: {
		"primer_color": Color("#6b6250"),
		"bare_color": Color("#cfc7ae"),
		"rust_color": Color("#55604a"),
		"dust_color": Color("#c9c0a6"),
		"rough_paint": 0.62, "metallic_paint": 0.0, "rough_bare": 0.38,
		"wear_gain": 0.35, "chip_threshold": 0.95, "chip_gain": 0.55,
		"rust_amount": 0.0, "grime_amount": 0.42, "streak_amount": 0.30,
		"dust_amount": 0.25, "cavity_amount": 0.80, "edge_rim": 0.18,
		"detail_scale": 4.6, "detail_strength": 0.75, "rough_variation": 0.22,
	},
	Family.FOLIAGE: {
		"primer_color": Color("#46523f"),
		"bare_color": Color("#5e6b53"),
		"rust_color": Color("#46523f"),
		"dust_color": Color("#8e9180"),
		"rough_paint": 0.86, "metallic_paint": 0.0, "rough_bare": 0.90,
		"wear_gain": 0.18, "chip_threshold": 1.20, "chip_gain": 0.40,
		"rust_amount": 0.0, "grime_amount": 0.22, "streak_amount": 0.18,
		"dust_amount": 0.22, "cavity_amount": 0.55, "edge_rim": 0.12,
		"detail_scale": 5.6, "detail_strength": 0.55, "rough_variation": 0.20,
	},
}

static var _materials: Dictionary = {}
static var _textures: Dictionary = {}
static var _shaders: Dictionary = {}


# ── 公共入口 ───────────────────────────────────────────────────

## 通用分层表面（喷漆/铸铁/机加工/混凝土/菌群）。
static func surface(color: Color, family: int = Family.PAINT_WORN, overrides: Dictionary = {}) -> ShaderMaterial:
	var key := "s|%d|%s|%s" % [family, color.to_html(false), var_to_str(overrides)]
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var params: Dictionary = (PRESETS.get(family, PRESETS[Family.PAINT_WORN]) as Dictionary).duplicate(true)
	params["paint_color"] = color
	for k in overrides.keys():
		params[k] = overrides[k]
	for color_key in ["paint_color", "primer_color", "bare_color", "rust_color", "dust_color"]:
		if params.has(color_key) and params[color_key] is Color:
			params[color_key] = _linear(params[color_key] as Color)
	var material := _metal(params, family, key)
	_materials[key] = material
	return material


## 自然岩体（远景低丘、崩积、碎岩）。
static func rock(stone_a: Color, stone_b: Color, stone_c: Color, strata := 2.4, crack := 0.32, ambient := 0.42) -> ShaderMaterial:
	var key := "r|%s|%s|%s|%.2f|%.2f|%.2f" % [stone_a.to_html(false), stone_b.to_html(false), stone_c.to_html(false), strata, crack, ambient]
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = _shader(SH_ROCK)
	m.set_shader_parameter("stone_a", _linear(stone_a))
	m.set_shader_parameter("stone_b", _linear(stone_b))
	m.set_shader_parameter("stone_c", _linear(stone_c))
	m.set_shader_parameter("strata_period", clampf(1.0 / maxf(0.3, strata), 0.08, 1.2))
	m.set_shader_parameter("patch_gain", clampf(crack, 0.0, 1.0))
	m.set_shader_parameter("ambient_fill", ambient * 0.25)
	m.set_shader_parameter("world_seed", _seed_for(key))
	_bind_family(m, Family.ROCK, Family.ROCK)
	_materials[key] = m
	return m


## 星髓晶体（能源站 B2 / 外景裂缝）。
static func crystal(deep: Color, body: Color, tip: Color, vein: Color, energy := 0.55, vein_strength := 0.30, core := 0.40) -> ShaderMaterial:
	var key := "c|%s|%s|%s|%s|%.2f|%.2f|%.2f" % [deep.to_html(false), body.to_html(false), tip.to_html(false), vein.to_html(false), energy, vein_strength, core]
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = _shader(SH_CRYSTAL)
	m.set_shader_parameter("deep_color", _linear(deep))
	m.set_shader_parameter("body_color", _linear(body))
	m.set_shader_parameter("tip_color", _linear(tip))
	m.set_shader_parameter("vein_color", _linear(vein))
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("vein_strength", vein_strength)
	m.set_shader_parameter("core_strength", core)
	m.set_shader_parameter("world_seed", _seed_for(key))
	_materials[key] = m
	return m


## 颜色 → 材质家族的保守启发式（给旧模块快速接管用；新代码应显式传 family）。
static func auto_family(color: Color) -> int:
	if color.get_luminance() < 0.16:
		return Family.CAST
	if color.s < 0.20:
		return Family.CONC
	if color.s > 0.50 and color.get_luminance() > 0.42:
		return Family.PAINT_ACCENT
	return Family.PAINT_WORN


## 便捷入口：按颜色自动分族。
static func auto_surface(color: Color) -> ShaderMaterial:
	return surface(color, auto_family(color))


## 铺装/地面用轻量 PBR：只加 2K 法线与粗糙度，不走整屏三平面四层 shader。
static func pavement(color: Color, uv_scale: Vector3 = Vector3.ONE, tile_family := "conc", roughness := 0.92, vertex_color := false) -> StandardMaterial3D:
	var key := "p|%s|%s|%s|%.2f|%s" % [color.to_html(false), str(uv_scale), tile_family, roughness, str(vertex_color)]
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	var linear := color.srgb_to_linear()
	m.albedo_color = Color(linear.r, linear.g, linear.b, color.a)
	m.roughness = roughness
	m.metallic = 0.0
	m.uv1_scale = uv_scale
	m.vertex_color_use_as_albedo = vertex_color
	var nt := _tex(TEX_SAMPLE + tile_family + "_normal.png")
	var rt := _tex(TEX_SAMPLE + tile_family + "_rough.png")
	if nt != null:
		m.normal_enabled = true
		m.normal_texture = nt
		m.normal_scale = 0.85
	if rt != null:
		m.roughness_texture = rt
	_materials[key] = m
	return m


## 纯色片：血迹、纸张、油渍、路面标线这类不该带墙面四层旧化的小贴片。
## 仍然按 sRGB 书写、转线性后交给 albedo，避免整体发白。
static func flat(color: Color, roughness := 0.90, unshaded := false) -> StandardMaterial3D:
	var key := "f|%s|%.2f|%s" % [color.to_html(false), roughness, str(unshaded)]
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	var linear := color.srgb_to_linear()
	m.albedo_color = Color(linear.r, linear.g, linear.b, color.a)
	m.roughness = roughness
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = m
	return m


## 积水/湿地：低粗糙 + 一点天空色自发光，GL 下没有 SSR 也不会读成一块纯色片。
static func wet(color: Color = Color("#5f7a78")) -> StandardMaterial3D:
	var key := "w|%s" % color.to_html(false)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	var linear := color.srgb_to_linear()
	m.albedo_color = Color(linear.r * 0.45, linear.g * 0.45, linear.b * 0.45, 1.0)
	m.metallic = 0.15
	m.roughness = 0.08
	m.emission_enabled = true
	m.emission = Color(linear.r, linear.g, linear.b)
	m.emission_energy_multiplier = 0.10
	_materials[key] = m
	return m


## 发光件（灯罩/灯带/状态灯/孢子囊）：统一软膝，保留色相。
static func glow(color: Color, energy := 0.8) -> StandardMaterial3D:
	var key := "g|%s|%.2f" % [color.to_html(false), energy]
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	var linear := color.srgb_to_linear()
	m.albedo_color = Color(linear.r, linear.g, linear.b, color.a)
	m.roughness = 0.55
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = linear
	m.emission_energy_multiplier = soft_knee(energy)
	_materials[key] = m
	return m


## 窗玻璃：GL 没有 SSR，纯低粗糙会读成黑洞；用低反射 + 一点脏青自发光保住“玻璃”读法。
static func glass(color: Color = Color("#4b6f72")) -> StandardMaterial3D:
	var key := "glass|%s" % color.to_html(false)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	var linear := color.srgb_to_linear()
	m.albedo_color = Color(minf(linear.r * 1.25, 1.0), minf(linear.g * 1.25, 1.0), minf(linear.b * 1.25, 1.0), 1.0)
	m.metallic = 0.08
	m.roughness = 0.20
	m.emission_enabled = true
	m.emission = linear
	m.emission_energy_multiplier = 0.42
	_materials[key] = m
	return m


## 指南的软膝限幅：发光永远不会把颜色打成死白。
static func soft_knee(energy: float) -> float:
	return energy / (1.0 + energy * 0.62)


## 统一色彩空间：调色板按 sRGB 十六进制书写，shader 的 vec4 uniform 按线性接收。
static func _linear(color: Color) -> Color:
	var linear := color.srgb_to_linear()
	return Color(linear.r, linear.g, linear.b, color.a)


# ── 内部 ───────────────────────────────────────────────────────

static func _metal(params: Dictionary, family: int, key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(SH_METAL)
	for k in params.keys():
		m.set_shader_parameter(k, params[k])
	m.set_shader_parameter("world_seed", _seed_for(key))
	# 程序化网格默认没有顶点色；只有 batch_boxes 这类显式烘焙了近似遮罩的网格
	# 才在 overrides 里传 vertex_mask_valid=true。
	if not params.has("vertex_mask_valid"):
		m.set_shader_parameter("vertex_mask_valid", false)
	_bind_family(m, family, family)
	return m


static func _bind_family(m: ShaderMaterial, family: int, _seed_part: int) -> void:
	var family_name := String(FAMILY_TEX.get(family, "paint"))
	var base := TEX_SAMPLE
	if family_name == "bio":
		base = TEX_RUIN
	var nt := _tex(base + family_name + "_normal.png")
	var rt := _tex(base + family_name + "_rough.png")
	var mt := _tex(base + family_name + "_mask.png")
	if nt != null:
		m.set_shader_parameter("detail_normal", nt)
		m.set_shader_parameter("use_detail", true)
	if rt != null:
		m.set_shader_parameter("detail_rough", rt)
	if mt != null:
		m.set_shader_parameter("detail_mask", mt)
		m.set_shader_parameter("use_detail_mask", true)


static func _tex(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	else:
		push_warning("RuinSurfaceLib: 缺少贴图 " + path)
	_textures[path] = texture
	return texture


static func _shader(path: String) -> Shader:
	if _shaders.has(path):
		return _shaders[path] as Shader
	var shader := load(path) as Shader
	if shader == null:
		push_error("RuinSurfaceLib: 缺少 shader " + path)
	_shaders[path] = shader
	return shader


## 确定性 seed：同一颜色/家族/参数永远得到同一张世界噪声偏移。
static func _seed_for(key: String) -> float:
	var h := 2166136261
	for index in key.length():
		h = int((h ^ key.unicode_at(index)) * 16777619) & 0x7fffffff
	return float(h % 9973) * 0.01
