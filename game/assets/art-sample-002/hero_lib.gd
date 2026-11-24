extends RefCounted
## ART-SAMPLE-002 · 可复用材质库（Godot 侧唯一入口）
##
## 用法（三行）：
##     const LIB := preload("res://materials/hero_lib.gd")
##     var lib := LIB.new()
##     var mats: Dictionary = lib.build()          # {材质名: Material}
##
## 约定：**GLB 里材质的 resource_name 就是这里的键**。装配时按名字覆盖即可：
##     for mi in root.find_children("*", "MeshInstance3D", true, false):
##         for s in mi.mesh.get_surface_count():
##             var key = mi.mesh.surface_get_material(s).resource_name
##             if mats.has(key): mi.set_surface_override_material(s, mats[key])
##
## 顶点色约定（Blender `bake_masks()` 写入 COLOR_0）：
##     R = 凸棱磨损   G = 自遮挡   B = 起皮斑   A = 朝上程度
## **没有顶点色的网格必须给材质设置 `vertex_mask_valid = false`**，
## 否则 COLOR 恒为 1，会被当成"整件都磨损 + 整件都被遮蔽"（本项目踩过这个坑）。

const SH_METAL := "res://assets/art-sample-002/shaders/aqs2_metal.gdshader"
const SH_ROCK := "res://assets/art-sample-002/shaders/aqs2_rock.gdshader"
const SH_CRYSTAL := "res://assets/art-sample-002/shaders/aqs2_crystal.gdshader"
const TEX := "res://assets/art-sample-002/textures/"
const TEXTURES_2K := "res://assets/art-sample-002/textures/"

## 全局配比：一次把整套材质的"脏/磨/锈/棱光"调到同一档
const BAL := {
	"dust_amount": 0.50, "grime_amount": 0.70, "streak_amount": 0.70,
	"rust_amount": 0.80, "chip_gain": 0.85, "wear_gain": 0.90, "edge_rim": 0.60,
}

var _cache: Dictionary = {}
var _tex: Dictionary = {}


func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name] as Texture2D
	var path := TEXTURES_2K + name
	if not ResourceLoader.exists(path):
		push_warning("hero_lib: missing texture " + path)
		_tex[name] = null
		return null
	var t := load(path) as Texture2D
	_tex[name] = t
	return t


func surf(p: Dictionary, family: String = "") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH_METAL)
	for k in p.keys():
		var v: Variant = p[k]
		if v is float and BAL.has(k):
			v = float(v) * float(BAL[k])
		m.set_shader_parameter(k, v)
	m.set_shader_parameter("world_seed", randf() * 43.0)
	if family != "":
		var nt := tex(family + "_normal.png")
		var rt := tex(family + "_rough.png")
		var mt := tex(family + "_mask.png")
		if nt != null:
			m.set_shader_parameter("detail_normal", nt)
			m.set_shader_parameter("use_detail", true)
		if rt != null:
			m.set_shader_parameter("detail_rough", rt)
		if mt != null:
			m.set_shader_parameter("detail_mask", mt)
			m.set_shader_parameter("use_detail_mask", true)
	return m


func rock(a: Color, b: Color, c: Color, strata: float, crack: float,
		ambient: float = 0.42) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH_ROCK)
	m.set_shader_parameter("stone_a", a)
	m.set_shader_parameter("stone_b", b)
	m.set_shader_parameter("stone_c", c)
	m.set_shader_parameter("strata_period", clampf(1.0 / maxf(0.3, strata), 0.08, 1.2))
	m.set_shader_parameter("patch_gain", clampf(crack, 0.0, 1.0))
	m.set_shader_parameter("ambient_fill", ambient * 0.25)
	m.set_shader_parameter("world_seed", randf() * 29.0)
	var nt := tex("rock_normal.png")
	var rt := tex("rock_rough.png")
	var mt := tex("rock_mask.png")
	if nt != null:
		m.set_shader_parameter("detail_normal", nt)
		m.set_shader_parameter("use_detail", true)
	if rt != null:
		m.set_shader_parameter("detail_rough", rt)
	if mt != null:
		m.set_shader_parameter("detail_mask", mt)
		m.set_shader_parameter("use_detail_mask", true)
	m.set_shader_parameter("detail_scale", 3.8)
	m.set_shader_parameter("detail_strength", 0.7)
	m.set_shader_parameter("cleft_scale", 0.5)
	return m


func crystal(deep: Color, body: Color, tip: Color, vein: Color,
		energy: float, vein_strength: float, core: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH_CRYSTAL)
	m.set_shader_parameter("deep_color", deep)
	m.set_shader_parameter("body_color", body)
	m.set_shader_parameter("tip_color", tip)
	m.set_shader_parameter("vein_color", vein)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("vein_strength", vein_strength)
	m.set_shader_parameter("core_strength", core)
	m.set_shader_parameter("world_seed", randf() * 17.0)
	return m


func build() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	# ---------------- 喷漆钢结构 ----------------
	_cache["M_PaintCream"] = surf({
		"paint_color": Color(0.615, 0.578, 0.488),
		"primer_color": Color(0.520, 0.300, 0.240),
		"bare_color": Color(0.560, 0.575, 0.585),
		"rough_paint": 0.44, "metallic_paint": 0.10,
		"wear_gain": 1.10, "chip_threshold": 0.58,
		"detail_scale": 3.4, "detail_strength": 0.55,
	}, "paint")
	_cache["M_PaintOrange"] = surf({
		"paint_color": Color(0.700, 0.268, 0.062),
		"primer_color": Color(0.430, 0.230, 0.180),
		"rough_paint": 0.48, "metallic_paint": 0.10,
		"wear_gain": 1.15, "chip_threshold": 0.56,
		"detail_scale": 3.6, "detail_strength": 0.55,
	}, "paint")
	_cache["M_PaintYellow"] = surf({
		"paint_color": Color(0.800, 0.560, 0.090),
		"primer_color": Color(0.480, 0.330, 0.190),
		"rough_paint": 0.46, "metallic_paint": 0.08,
		"wear_gain": 1.25, "chip_threshold": 0.52,
		"detail_scale": 3.8, "detail_strength": 0.55,
	}, "paint")
	_cache["M_PaintTeal"] = surf({
		"paint_color": Color(0.145, 0.330, 0.330),
		"rough_paint": 0.42, "metallic_paint": 0.12,
		"wear_gain": 1.0, "chip_threshold": 0.62,
		"detail_scale": 3.4, "detail_strength": 0.5,
	}, "paint")
	_cache["M_PaintGrey"] = surf({
		"paint_color": Color(0.300, 0.318, 0.330),
		"rough_paint": 0.50, "metallic_paint": 0.16,
		"wear_gain": 1.05, "chip_threshold": 0.60,
		"detail_scale": 3.2, "detail_strength": 0.5,
	}, "paint")
	# ---------------- 铸铁 / 深钢 ----------------
	_cache["M_SteelDeep"] = surf({
		"paint_color": Color(0.098, 0.108, 0.118),
		"rough_paint": 0.46, "metallic_paint": 0.45,
		"wear_gain": 0.85, "chip_threshold": 0.68,
		"detail_scale": 3.6, "detail_strength": 0.7,
	}, "cast")
	_cache["M_DarkSteel"] = surf({
		"paint_color": Color(0.085, 0.095, 0.105),
		"rough_paint": 0.48, "metallic_paint": 0.5,
		"wear_gain": 0.8, "chip_threshold": 0.70,
		"detail_scale": 3.6, "detail_strength": 0.7,
	}, "cast")
	_cache["M_CastSteel"] = surf({
		"paint_color": Color(0.300, 0.312, 0.322),
		"rough_paint": 0.62, "metallic_paint": 0.5,
		"wear_gain": 0.85, "chip_threshold": 0.66,
		"detail_scale": 4.0, "detail_strength": 0.8,
	}, "cast")
	# ---------------- 裸金属 / 机加工 ----------------
	_cache["M_BareSteel"] = surf({
		"paint_color": Color(0.450, 0.470, 0.490),
		"bare_color": Color(0.600, 0.615, 0.625),
		"rough_paint": 0.30, "metallic_paint": 0.85,
		"wear_gain": 0.35, "chip_threshold": 1.60,
		"detail_scale": 4.6, "detail_strength": 0.5,
	}, "mach")
	_cache["M_MachinedSteel"] = surf({
		"paint_color": Color(0.560, 0.575, 0.585),
		"bare_color": Color(0.660, 0.672, 0.680),
		"rough_paint": 0.18, "metallic_paint": 0.95,
		"wear_gain": 0.25, "chip_threshold": 1.60,
		"detail_scale": 6.0, "detail_strength": 0.35,
	}, "mach")
	_cache["M_WornSteel"] = surf({
		"paint_color": Color(0.470, 0.455, 0.425),
		"rough_paint": 0.34, "metallic_paint": 0.7,
		"wear_gain": 1.5, "chip_threshold": 0.50,
		"detail_scale": 5.0, "detail_strength": 0.5,
	}, "mach")
	_cache["M_Bronze"] = surf({
		"paint_color": Color(0.520, 0.372, 0.150),
		"rust_color": Color(0.190, 0.360, 0.280),
		"rough_paint": 0.34, "metallic_paint": 0.85,
		"wear_gain": 0.6, "chip_threshold": 0.72, "rust_amount": 0.35,
		"detail_scale": 5.5, "detail_strength": 0.5,
	}, "cast")
	_cache["M_Copper"] = surf({
		"paint_color": Color(0.470, 0.245, 0.135),
		"rust_color": Color(0.180, 0.380, 0.310),
		"rough_paint": 0.32, "metallic_paint": 0.85,
		"wear_gain": 0.6, "chip_threshold": 0.74, "rust_amount": 0.40,
		"detail_scale": 5.5, "detail_strength": 0.5,
	}, "cast")
	# ---------------- 混凝土 ----------------
	_cache["M_Concrete"] = surf({
		"paint_color": Color(0.205, 0.205, 0.197),
		"primer_color": Color(0.360, 0.330, 0.300),
		"bare_color": Color(0.400, 0.388, 0.370),
		"rough_paint": 0.86, "metallic_paint": 0.0,
		"wear_gain": 0.55, "chip_threshold": 0.88,
		"rust_amount": 0.0, "grime_amount": 0.55, "streak_amount": 0.5,
		"dust_amount": 0.5, "cavity_amount": 0.85, "edge_rim": 0.08,
		"detail_scale": 1.8, "detail_strength": 0.9,
		"concrete_mode": 1.0,
	}, "conc")
	_cache["M_Grout"] = surf({
		"paint_color": Color(0.300, 0.294, 0.276),
		"rough_paint": 0.80, "metallic_paint": 0.0,
		"wear_gain": 0.8, "chip_threshold": 0.80,
		"rust_amount": 0.0, "grime_amount": 0.6, "dust_amount": 0.5,
		"concrete_mode": 1.0,
		"detail_scale": 2.2, "detail_strength": 0.9,
	}, "conc")
	_cache["M_Foundation"] = _cache["M_Grout"]
	_cache["M_Rubber"] = surf({
		"paint_color": Color(0.048, 0.050, 0.054),
		"rough_paint": 0.92, "metallic_paint": 0.0,
		"wear_gain": 0.4, "chip_threshold": 1.60,
		"rust_amount": 0.0, "grime_amount": 0.35, "dust_amount": 0.65,
		"detail_scale": 4.0, "detail_strength": 0.5,
	}, "cast")
	# ---------------- 高模烘焙的锤头（本包的核心样例）----------------
	var head := surf({
		"paint_color": Color(0.355, 0.365, 0.375),
		"bare_color": Color(0.520, 0.532, 0.540),
		"rough_paint": 0.68, "metallic_paint": 0.16,
		"wear_gain": 0.95, "chip_threshold": 0.60,
		"rust_amount": 0.45, "grime_amount": 0.38, "dust_amount": 0.40,
		"cavity_amount": 0.80, "edge_rim": 0.30,
		"detail_scale": 5.5, "detail_strength": 0.55,
		"use_uv_baked": true, "vertex_mask_valid": false,
		"uv_normal_strength": 1.55, "uv_mask_wear": 1.20, "uv_mask_cavity": 1.0,
		"uv_micro_scale": 5.0, "uv_micro_strength": 0.32,
	}, "cast")
	var hn := tex("aqs002_head_normal.png")
	var hm := tex("aqs002_head_mask.png")
	if hn != null:
		head.set_shader_parameter("uv_normal", hn)
	if hm != null:
		head.set_shader_parameter("uv_mask", hm)
	_cache["M_CastSteelBaked"] = head
	# ---------------- 玻璃 / 晶体 ----------------
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.95, 0.88, 0.72)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.86, 0.62)
	glass.emission_energy_multiplier = 1.5
	_cache["M_Glass"] = glass
	_cache["M_CrystalShell"] = crystal(
		Color(0.014, 0.075, 0.105), Color(0.075, 0.330, 0.430),
		Color(0.560, 0.860, 0.960), Color(0.360, 0.220, 0.780), 0.55, 0.30, 0.40)
	_cache["M_CrystalCore"] = crystal(
		Color(0.030, 0.140, 0.190), Color(0.180, 0.560, 0.700),
		Color(0.760, 0.940, 1.000), Color(0.460, 0.280, 0.880), 0.85, 0.45, 0.65)
	_cache["M_CrystalVein"] = crystal(
		Color(0.070, 0.040, 0.170), Color(0.320, 0.190, 0.700),
		Color(0.560, 0.420, 0.960), Color(0.520, 0.300, 0.920), 0.75, 0.40, 0.45)
	for key in ["M_Mid", "M_Axial", "M_Deep", "M_Exposed", "M_Violet"]:
		_cache[key] = crystal(Color(0.012, 0.060, 0.090), Color(0.055, 0.250, 0.340),
			Color(0.470, 0.760, 0.900), Color(0.300, 0.180, 0.680), 0.55, 0.22, 0.30)
	# ---------------- 岩石 ----------------
	_cache["M_RootRock"] = rock(Color(0.300, 0.252, 0.206), Color(0.150, 0.126, 0.106),
		Color(0.398, 0.336, 0.274), 2.2, 0.30, 0.55)
	_cache["M_Bedrock"] = rock(Color(0.285, 0.238, 0.194), Color(0.145, 0.122, 0.102),
		Color(0.380, 0.322, 0.264), 2.6, 0.34, 0.52)
	_cache["M_BedrockDark"] = rock(Color(0.205, 0.172, 0.144), Color(0.098, 0.084, 0.072),
		Color(0.290, 0.246, 0.204), 3.2, 0.32, 0.50)
	_cache["M_Talus"] = rock(Color(0.268, 0.228, 0.188), Color(0.132, 0.112, 0.094),
		Color(0.352, 0.298, 0.244), 3.6, 0.40, 0.55)
	var ground := rock(Color(0.205, 0.176, 0.145), Color(0.108, 0.092, 0.077),
		Color(0.288, 0.247, 0.203), 2.6, 0.26, 0.42)
	ground.set_shader_parameter("ground_mode", 1.0)
	ground.set_shader_parameter("strata_period", 1.05)
	ground.set_shader_parameter("cleft_scale", 0.85)
	_cache["M_GroundRock"] = ground
	_cache["M_Flagstone"] = ground
	_cache["M_StairRock"] = _cache["M_Bedrock"]
	_cache["M_RockSocket"] = _cache["M_Bedrock"]
	_cache["M_CradleRock"] = _cache["M_Bedrock"]
	return _cache
