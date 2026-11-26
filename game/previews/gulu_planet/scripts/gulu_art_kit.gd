class_name GuluArtKit
extends RefCounted

## 奶龙星环境美术工具（2026-11-18）
##
## 材质方法借鉴 ART-SAMPLE-002 的 aqs2_metal / aqs2_rock（同目录 shaders/），
## 但不使用其 2K 贴图与顶点色烘焙：本项目的几何是运行时代码生成，
## 没有 UV/顶点色，所以一律 `vertex_mask_valid = false`，靠世界坐标噪声做磨损。
##
## 只负责“看得见的东西”：材质、倒角盒、圆角门拱、低多边形岩体。
## 不碰碰撞、玩法、AI。

const SHADER_METAL := preload("res://shaders/aqs2_metal.gdshader")
const SHADER_ROCK := preload("res://shaders/aqs2_rock.gdshader")

## ART-SAMPLE-002 的 2K 材质家族（2026-11-25 按《美术制作与 AI 协作指南》方法二接入）：
## paint / cast / mach / conc / rock 各一套 normal + rough + mask，按家族绑定，
## 不再全场景共用同一张噪声（指南红线 5）。
const TEX_DIR := "res://assets/textures/"
var _fam_cache: Dictionary = {}


func _family_tex(family: String, kind: String) -> Texture2D:
	var key := family + "_" + kind
	if _fam_cache.has(key):
		return _fam_cache[key] as Texture2D
	var path := TEX_DIR + key + ".png"
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_fam_cache[key] = tex
	return tex


## 把一族 2K 细节（法线/粗糙/掩膜）绑到材质上；缺资源时静默退回程序化。
func _apply_family(m: ShaderMaterial, family: String, scale: float = 3.2,
		strength: float = 0.55) -> void:
	var n := _family_tex(family, "normal")
	var r := _family_tex(family, "rough")
	var k := _family_tex(family, "mask")
	if n != null:
		m.set_shader_parameter("detail_normal", n)
		m.set_shader_parameter("use_detail", true)
	if r != null:
		m.set_shader_parameter("detail_rough", r)
	if k != null:
		m.set_shader_parameter("detail_mask", k)
		m.set_shader_parameter("use_detail_mask", true)
	m.set_shader_parameter("detail_scale", scale)
	m.set_shader_parameter("detail_strength", strength)

var _cache: Dictionary = {}


# ------------------------------------------------------------------ 材质

func paint(color: Color, rough: float = 0.46, metallic: float = 0.10,
		wear: float = 0.9, seed: float = 1.0) -> ShaderMaterial:
	var key := "paint:%s:%.2f:%.2f:%.2f:%.2f" % [color.to_html(), rough, metallic, wear, seed]
	if _cache.has(key):
		return _cache[key] as ShaderMaterial
	var m := _metal_base(color, rough, metallic, wear, seed)
	_apply_family(m, "paint", 3.4, 0.55)
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("primer_color", Color(color.r * 0.55, color.g * 0.34, color.b * 0.28))
	m.set_shader_parameter("bare_color", Color("#8e989c"))
	m.set_shader_parameter("chip_threshold", 0.66)
	m.set_shader_parameter("rust_amount", 0.35)
	_cache[key] = m
	return m


## 干净烤漆：大面壳体用。没有高光反射的“塑料白”，避免大面积过曝。
func clean_paint(color: Color, rough: float = 0.62, metallic: float = 0.04) -> StandardMaterial3D:
	var key := "clean:%s:%.2f:%.2f" % [color.to_html(), rough, metallic]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.metallic_specular = 0.0
	_cache[key] = m
	return m


func bare_metal(color: Color = Color("#8b979b"), rough: float = 0.30, seed: float = 2.0) -> ShaderMaterial:
	var key := "bare:%s:%.2f:%.2f" % [color.to_html(), rough, seed]
	if _cache.has(key):
		return _cache[key] as ShaderMaterial
	var m := _metal_base(color, rough, 0.85, 0.35, seed)
	_apply_family(m, "mach", 2.6, 0.60)
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("bare_color", Color("#aab3b6"))
	m.set_shader_parameter("chip_threshold", 1.55)
	m.set_shader_parameter("rust_amount", 0.10)
	m.set_shader_parameter("grime_amount", 0.35)
	_cache[key] = m
	return m


func dark_metal(color: Color = Color("#2b3937"), rough: float = 0.52, seed: float = 3.0) -> ShaderMaterial:
	var key := "dark:%s:%.2f:%.2f" % [color.to_html(), rough, seed]
	if _cache.has(key):
		return _cache[key] as ShaderMaterial
	var m := _metal_base(color, rough, 0.55, 0.55, seed)
	_apply_family(m, "cast", 2.8, 0.55)
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("bare_color", Color("#6f7c7e"))
	m.set_shader_parameter("chip_threshold", 0.92)
	m.set_shader_parameter("rust_amount", 0.25)
	_cache[key] = m
	return m


func concrete(color: Color = Color("#556662"), rough: float = 0.88, seed: float = 4.0) -> ShaderMaterial:
	var key := "conc:%s:%.2f:%.2f" % [color.to_html(), rough, seed]
	if _cache.has(key):
		return _cache[key] as ShaderMaterial
	var m := _metal_base(color, rough, 0.0, 0.35, seed)
	_apply_family(m, "conc", 2.2, 0.50)
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("primer_color", Color(color.r * 0.78, color.g * 0.78, color.b * 0.76))
	m.set_shader_parameter("bare_color", Color("#7a8580"))
	m.set_shader_parameter("chip_threshold", 0.95)
	m.set_shader_parameter("rust_amount", 0.0)
	m.set_shader_parameter("grime_amount", 0.16)
	m.set_shader_parameter("dust_amount", 0.32)
	m.set_shader_parameter("cavity_amount", 0.32)
	m.set_shader_parameter("edge_rim", 0.04)
	_cache[key] = m
	return m


func rock(stone_a: Color, stone_b: Color, stone_c: Color,
		strata: float = 0.34, crack: float = 0.55, seed: float = 5.0) -> ShaderMaterial:
	var key := "rock:%s:%s:%s:%.2f:%.2f:%.2f" % [
		stone_a.to_html(), stone_b.to_html(), stone_c.to_html(), strata, crack, seed]
	if _cache.has(key):
		return _cache[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = SHADER_ROCK
	m.set_shader_parameter("stone_a", stone_a)
	m.set_shader_parameter("stone_b", stone_b)
	m.set_shader_parameter("stone_c", stone_c)
	m.set_shader_parameter("fresh_color", stone_c.lightened(0.12))
	m.set_shader_parameter("dust_color", Color("#a9b4ad"))
	m.set_shader_parameter("strata_period", strata)
	m.set_shader_parameter("strata_strength", 0.62)
	m.set_shader_parameter("strata_warp", 0.35)
	m.set_shader_parameter("facet_contrast", 0.42)
	m.set_shader_parameter("arris_gain", 0.85)
	m.set_shader_parameter("cavity_gain", 0.85)
	m.set_shader_parameter("dust_gain", 0.45)
	m.set_shader_parameter("damp_height", 0.35)
	m.set_shader_parameter("damp_strength", 0.14)
	m.set_shader_parameter("patch_gain", crack)
	m.set_shader_parameter("cleft_gain", 0.8)
	m.set_shader_parameter("cleft_scale", 0.50)
	m.set_shader_parameter("ambient_fill", 0.06)
	m.set_shader_parameter("world_seed", seed)
	_apply_family(m, "rock", 3.6, 0.70)
	_cache[key] = m
	return m


func emissive(color: Color, energy: float = 1.0, rough: float = 0.55,
		metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	m.metallic_specular = 0.25
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func rubber(color: Color = Color("#1e2726")) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	m.metallic = 0.0
	return m


func _metal_base(color: Color, rough: float, metallic: float,
		wear: float, seed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_METAL
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("primer_color", Color(color.r * 0.6, color.g * 0.42, color.b * 0.34))
	m.set_shader_parameter("bare_color", Color("#8e989c"))
	m.set_shader_parameter("rust_color", Color("#6b4a33"))
	m.set_shader_parameter("dust_color", Color("#b9c0b6"))
	m.set_shader_parameter("metallic_paint", metallic)
	m.set_shader_parameter("metallic_bare", 1.0)
	m.set_shader_parameter("rough_paint", rough)
	m.set_shader_parameter("rough_bare", 0.28)
	m.set_shader_parameter("rough_rust", 0.88)
	m.set_shader_parameter("specular_level", 0.36)
	m.set_shader_parameter("wear_gain", wear)
	m.set_shader_parameter("chip_threshold", 0.66)
	m.set_shader_parameter("chip_gain", 0.85)
	m.set_shader_parameter("rust_amount", 0.35)
	m.set_shader_parameter("grime_amount", 0.38)
	m.set_shader_parameter("streak_amount", 0.35)
	m.set_shader_parameter("dust_amount", 0.32)
	m.set_shader_parameter("cavity_amount", 0.60)
	m.set_shader_parameter("edge_rim", 0.22)
	m.set_shader_parameter("detail_scale", 3.2)
	m.set_shader_parameter("detail_strength", 0.55)
	m.set_shader_parameter("rough_variation", 0.14)
	m.set_shader_parameter("use_detail", false)
	m.set_shader_parameter("use_detail_mask", false)
	m.set_shader_parameter("concrete_mode", 0.0)
	m.set_shader_parameter("use_uv_baked", false)
	m.set_shader_parameter("vertex_mask_valid", false)
	m.set_shader_parameter("ambient_fill", 0.05)
	m.set_shader_parameter("world_seed", seed)
	return m


# ------------------------------------------------------------------ 网格

## 倒角盒：6 个内缩面 + 12 条斜边 + 8 个角三角，轮廓比 BoxMesh 圆。
func beveled_box(size: Vector3, bevel: float = 0.035) -> ArrayMesh:
	var h := size * 0.5
	var b := clampf(bevel, 0.001, minf(minf(h.x, h.y), h.z) * 0.45)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 6 面
	_quad(st, Vector3(h.x, -h.y + b, -h.z + b), Vector3(h.x, h.y - b, -h.z + b),
		Vector3(h.x, h.y - b, h.z - b), Vector3(h.x, -h.y + b, h.z - b), Vector3.RIGHT)
	_quad(st, Vector3(-h.x, -h.y + b, h.z - b), Vector3(-h.x, h.y - b, h.z - b),
		Vector3(-h.x, h.y - b, -h.z + b), Vector3(-h.x, -h.y + b, -h.z + b), Vector3.LEFT)
	_quad(st, Vector3(-h.x + b, h.y, -h.z + b), Vector3(h.x - b, h.y, -h.z + b),
		Vector3(h.x - b, h.y, h.z - b), Vector3(-h.x + b, h.y, h.z - b), Vector3.UP)
	_quad(st, Vector3(-h.x + b, -h.y, h.z - b), Vector3(h.x - b, -h.y, h.z - b),
		Vector3(h.x - b, -h.y, -h.z + b), Vector3(-h.x + b, -h.y, -h.z + b), Vector3.DOWN)
	_quad(st, Vector3(-h.x + b, -h.y + b, h.z), Vector3(h.x - b, -h.y + b, h.z),
		Vector3(h.x - b, h.y - b, h.z), Vector3(-h.x + b, h.y - b, h.z), Vector3.BACK)
	_quad(st, Vector3(h.x - b, -h.y + b, -h.z), Vector3(-h.x + b, -h.y + b, -h.z),
		Vector3(-h.x + b, h.y - b, -h.z), Vector3(h.x - b, h.y - b, -h.z), Vector3.FORWARD)

	# 12 条斜边
	for sy in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_quad(st,
				Vector3(-h.x + b, sy * h.y, sz * (h.z - b)),
				Vector3(h.x - b, sy * h.y, sz * (h.z - b)),
				Vector3(h.x - b, sy * (h.y - b), sz * h.z),
				Vector3(-h.x + b, sy * (h.y - b), sz * h.z),
				Vector3(0.0, sy, sz))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_quad(st,
				Vector3(sx * h.x, -h.y + b, sz * (h.z - b)),
				Vector3(sx * h.x, h.y - b, sz * (h.z - b)),
				Vector3(sx * (h.x - b), h.y - b, sz * h.z),
				Vector3(sx * (h.x - b), -h.y + b, sz * h.z),
				Vector3(sx, 0.0, sz))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_quad(st,
				Vector3(sx * h.x, sy * (h.y - b), -h.z + b),
				Vector3(sx * h.x, sy * (h.y - b), h.z - b),
				Vector3(sx * (h.x - b), sy * h.y, h.z - b),
				Vector3(sx * (h.x - b), sy * h.y, -h.z + b),
				Vector3(sx, sy, 0.0))

	# 8 个角
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_tri(st,
					Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b)),
					Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b)),
					Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z),
					Vector3(sx, sy, sz))
	return st.commit()


## 门拱：从地面左端沿顶部到右端，带外/内两层轮廓；没有下门槛。
func arch(outer_w: float, outer_h: float, inner_w: float, inner_h: float,
		depth: float, r_outer: float = 0.42, r_inner: float = 0.16) -> ArrayMesh:
	var outer := _arch_loop(outer_w, outer_h, r_outer)
	var inner := _arch_loop(inner_w, inner_h, r_inner)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_d := depth * 0.5
	for i in range(outer.size() - 1):
		var o0 := outer[i]
		var o1 := outer[i + 1]
		var n0 := inner[i]
		var n1 := inner[i + 1]
		var mid := (o0 + o1) * 0.5
		var outward := Vector3(0.0, mid.y - outer_h * 0.45, mid.x)
		if outward.length_squared() < 0.0001:
			outward = Vector3.UP
		outward = outward.normalized()
		# 前/后环面（玩家在 -X 方向）
		_quad(st, Vector3(-half_d, o0.y, o0.x), Vector3(-half_d, o1.y, o1.x),
			Vector3(-half_d, n1.y, n1.x), Vector3(-half_d, n0.y, n0.x), Vector3.LEFT)
		_quad(st, Vector3(half_d, n0.y, n0.x), Vector3(half_d, n1.y, n1.x),
			Vector3(half_d, o1.y, o1.x), Vector3(half_d, o0.y, o0.x), Vector3.RIGHT)
		# 外壁 / 内壁
		_quad(st, Vector3(-half_d, o0.y, o0.x), Vector3(half_d, o0.y, o0.x),
			Vector3(half_d, o1.y, o1.x), Vector3(-half_d, o1.y, o1.x), outward)
		_quad(st, Vector3(half_d, n0.y, n0.x), Vector3(-half_d, n0.y, n0.x),
			Vector3(-half_d, n1.y, n1.x), Vector3(half_d, n1.y, n1.x), -outward)
	# 两个落地端面（朝下，实际看不到，但避免开口）
	_cap_quad(st, outer[0], inner[0], -half_d, half_d)
	_cap_quad(st, outer[outer.size() - 1], inner[inner.size() - 1], -half_d, half_d)
	return st.commit()


## 低多边形岩体：二十面体细分 + 确定性噪声 + 平面着色 + 顶点色（供 aqs2_rock）。
func rock_mesh(seed: float, size: Vector3, subdiv: int = 2) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var base := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var verts: Array[Vector3] = []
	for v: Vector3 in base:
		verts.append(v.normalized())
	# 去重缓存
	for _level in range(maxi(0, subdiv)):
		var cache: Dictionary = {}
		var next_faces: Array = []
		for f: Array in faces:
			var ia: int = int(f[0])
			var ib: int = int(f[1])
			var ic: int = int(f[2])
			var ab := _midpoint(verts, ia, ib, cache)
			var bc := _midpoint(verts, ib, ic, cache)
			var ca := _midpoint(verts, ic, ia, cache)
			next_faces.append([ia, ab, ca])
			next_faces.append([ib, bc, ab])
			next_faces.append([ic, ca, bc])
			next_faces.append([ab, bc, ca])
		faces = next_faces
	# 位移：确定性多频正弦，不依赖随机数，重复加载一致
	var displaced: Array[Vector3] = []
	var min_y := 1e9
	for v: Vector3 in verts:
		var n := 0.0
		n += sin(v.x * 3.1 + seed) * sin(v.y * 2.3 + seed * 1.7) * sin(v.z * 3.7 + seed * 0.3) * 0.22
		n += sin(v.x * 6.7 - seed) * sin(v.z * 5.9 + seed * 2.1) * 0.08
		n += sin(v.y * 11.0 + seed * 3.3) * 0.035
		var p := v * (1.0 + n)
		p.x *= size.x * 0.5
		p.y *= size.y * 0.52
		p.z *= size.z * 0.5
		min_y = minf(min_y, p.y)
		displaced.append(p)
	for i in range(displaced.size()):
		displaced[i].y -= min_y
		if displaced[i].y < size.y * 0.06:
			displaced[i].y = size.y * 0.06
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		var a := displaced[int(f[0])]
		var b := displaced[int(f[1])]
		var c := displaced[int(f[2])]
		var n := (b - a).cross(c - a).normalized()
		# 保证朝外：少量二十面体面片在位移后可能翻向，直接翻回来。
		if n.dot((a + b + c) / 3.0) < 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		var up := clampf(n.y * 0.5 + 0.5, 0.0, 1.0)
		var arris := clampf(0.18 + 0.82 * (1.0 - absf(n.y)), 0.0, 1.0)
		var cav := clampf(0.45 + (a.y + b.y + c.y) / (size.y * 3.0) * 0.35, 0.0, 1.0)
		var patch := 0.25 + 0.75 * absf(sin((a.x + b.z + c.y) * 2.7 + seed))
		_tri(st, a, b, c, Vector3.ZERO, Color(arris, cav, patch, up), true)
	return st.commit()


# ------------------------------------------------------------------ 内部工具

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		hint: Vector3, color: Color = Color.WHITE, use_color: bool = false) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1.0e-12:
		return
	if n.dot(hint) < 0.0:
		var tmp := b
		b = d
		d = tmp
		n = -n
	n = n.normalized()
	_tri(st, a, b, c, n, color, use_color)
	_tri(st, a, c, d, n, color, use_color)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
		color: Color = Color.WHITE, use_color: bool = false) -> void:
	var n := normal
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
	st.set_normal(n)
	if use_color:
		st.set_color(color)
	st.add_vertex(a)
	st.set_normal(n)
	if use_color:
		st.set_color(color)
	st.add_vertex(b)
	st.set_normal(n)
	if use_color:
		st.set_color(color)
	st.add_vertex(c)


func _cap_quad(st: SurfaceTool, outer: Vector2, inner: Vector2, x0: float, x1: float) -> void:
	_quad(st, Vector3(x0, outer.y, outer.x), Vector3(x0, inner.y, inner.x),
		Vector3(x1, inner.y, inner.x), Vector3(x1, outer.y, outer.x), Vector3.DOWN)


func _arch_loop(w: float, h: float, r: float) -> Array[Vector2]:
	var radius := clampf(r, 0.02, minf(w, h) * 0.28)
	var pts: Array[Vector2] = []
	var straight := 4
	var arc := 6
	var top := 8
	# 左直段（从地面向上，包含两端）
	for i in range(straight + 1):
		var t := float(i) / float(straight)
		pts.append(Vector2(-w * 0.5, lerpf(0.0, h - radius, t)))
	# 左上圆角（不含起点，含终点）
	for i in range(1, arc + 1):
		var t := float(i) / float(arc)
		var ang := PI - t * PI * 0.5
		pts.append(Vector2(-w * 0.5 + radius + cos(ang) * radius, h - radius + sin(ang) * radius))
	# 顶段
	for i in range(1, top + 1):
		var t := float(i) / float(top)
		pts.append(Vector2(lerpf(-w * 0.5 + radius, w * 0.5 - radius, t), h))
	# 右上圆角
	for i in range(1, arc + 1):
		var t := float(i) / float(arc)
		var ang := PI * 0.5 - t * PI * 0.5
		pts.append(Vector2(w * 0.5 - radius + cos(ang) * radius, h - radius + sin(ang) * radius))
	# 右直段（向下，不含起点，含地面端点）
	for i in range(1, straight + 1):
		var t := float(i) / float(straight)
		pts.append(Vector2(w * 0.5, lerpf(h - radius, 0.0, t)))
	return pts


func _midpoint(verts: Array[Vector3], a: int, b: int, cache: Dictionary) -> int:
	var key := "%d_%d" % [mini(a, b), maxi(a, b)]
	if cache.has(key):
		return int(cache[key])
	var v := ((verts[a] + verts[b]) * 0.5).normalized()
	verts.append(v)
	var index := verts.size() - 1
	cache[key] = index
	return index


