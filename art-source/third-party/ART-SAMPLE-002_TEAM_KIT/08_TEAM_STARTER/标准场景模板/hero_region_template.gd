extends Node3D
## ART-SAMPLE-002 · 标准英雄区场景模板
##
## 用途：**开一个新星球**时，把这个脚本挂到空场景根节点上，改下面 3 处常量即可：
##   1. MODELS —— 你的 GLB 清单（文件、节点名、位置）
##   2. ANCHOR —— 英雄区中心（灯光与相机都以它为准）
##   3. SWING  —— 若有关节机器（摆锤/门/起重机），填轴心与臂长；没有就留空
##
## 它会自动：
##   * 挂载 GLB 并按材质名套用 `materials/hero_lib.gd` 的材质
##   * 按 ANCHOR 生成标准光位（主光 / 副光 / 轮廓光 / 观者侧柔光 / 洞厅反弹 / 岩壁掠射）
##   * 可选地驱动一个摆锤（同一套积分参数：重力 8.8 / 臂长 / 阻尼 0.32 / 打击角 -30°）
##
## 这样新星球不需要从零搭灯光与材质映射，只要准备资产。

const LIB := preload("res://materials/hero_lib.gd")

# ---------------- 1) 你的资产清单 ----------------
const MODELS := [
	# {"file": "res://assets/models/你的星球/xxx.glb", "name": "主机械", "pos": Vector3(0, 0, 0)},
]

# ---------------- 2) 英雄区中心与规模 ----------------
const ANCHOR := Vector3(0.0, 1.8, 0.0)
const SCALE := 1.0          # 整体灯距/灯强度的参考尺度（相对本样例）

# ---------------- 3) 关节机器（没有就留 null） ----------------
const SWING := {
	"enabled": false,
	"pivot_height": 4.30,   # 轴心高度
	"arm_length": 3.50,     # 摆臂长度
	"rest_angle": 2.5,      # 静止角（度）
	"max_pull": 74.0,       # 最大拉起角（度）
	"impact_angle": -30.0,  # 打击角（度）
	"gravity": 8.8,
	"damping": 0.32,
	"post_impact_damping": 1.35,
	"arm_glb": "",          # 摆臂 GLB（可空）
	"head_glb": "",         # 锤头 GLB（可空）
}

var _lib: Dictionary = {}
var _pivot: Node3D


func _ready() -> void:
	_lib = LIB.new().build()
	_build_models()
	_build_lights()
	if bool(SWING.get("enabled", false)):
		_build_swing()


func _build_models() -> void:
	for spec in MODELS:
		var path := str(spec.get("file", ""))
		if path == "" or not ResourceLoader.exists(path):
			push_warning("hero_template: missing " + path)
			continue
		var holder := Node3D.new()
		holder.name = str(spec.get("name", "Model"))
		holder.position = spec.get("pos", Vector3.ZERO) as Vector3
		add_child(holder)
		holder.add_child((load(path) as PackedScene).instantiate())
		_apply_materials(holder)


func _apply_materials(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in range(m.mesh.get_surface_count()):
			var src: Material = m.mesh.surface_get_material(s)
			var key := "" if src == null else src.resource_name
			var target: Material = _lib.get(key) as Material
			if target != null:
				m.set_surface_override_material(s, target)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_lights() -> void:
	var k := SCALE
	# 主光（对应"机装工作灯"的位置；换星球时按你的灯具位置改）
	var key := SpotLight3D.new()
	key.name = "Key"
	key.position = ANCHOR + Vector3(-1.5, 2.8, 1.0) * k
	key.light_color = Color(1.0, 0.855, 0.70)
	key.light_energy = 9.0 * k
	key.spot_range = 13.0 * k
	key.spot_angle = 46.0
	key.shadow_enabled = true
	key.shadow_bias = 0.055
	key.light_size = 0.55
	add_child(key)
	key.look_at(ANCHOR + Vector3(-0.25, -0.85, -0.45) * k, Vector3.UP)

	var fill := SpotLight3D.new()
	fill.name = "Fill"
	fill.position = ANCHOR + Vector3(1.6, 2.9, -0.5) * k
	fill.light_color = Color(1.0, 0.80, 0.62)
	fill.light_energy = 5.0 * k
	fill.spot_range = 10.0 * k
	fill.spot_angle = 46.0
	add_child(fill)
	fill.look_at(ANCHOR + Vector3(0.2, -0.65, -1.5) * k, Vector3.UP)

	var rim := SpotLight3D.new()
	rim.name = "Rim"
	rim.position = ANCHOR + Vector3(-2.3, 3.5, -5.9) * k
	rim.light_color = Color(0.46, 0.68, 1.0)
	rim.light_energy = 6.0 * k      # 只做分离，不要用它照亮主体
	rim.spot_range = 20.0 * k
	rim.spot_angle = 36.0
	add_child(rim)
	rim.look_at(ANCHOR, Vector3.UP)

	var front := OmniLight3D.new()
	front.position = ANCHOR + Vector3(1.4, 0.15, 2.95) * k
	front.light_color = Color(0.86, 0.88, 0.95)
	front.light_energy = 4.2 * k
	front.omni_range = 8.5 * k
	add_child(front)

	var bounce := OmniLight3D.new()
	bounce.position = ANCHOR + Vector3(0.0, 4.8, -3.0) * k
	bounce.light_color = Color(0.30, 0.42, 0.60)
	bounce.light_energy = 6.0 * k
	bounce.omni_range = 44.0 * k
	add_child(bounce)

	# 岩壁掠射（没有自然岩壁的星球可删）
	for spec in [[Vector3(-3.55, 1.3, 1.95), Vector3(-4.35, -1.45, -2.15), 7.5],
			[Vector3(3.45, 1.05, 2.35), Vector3(4.05, -1.5, -1.35), 6.0]]:
		var lamp := SpotLight3D.new()
		lamp.position = ANCHOR + (spec[0] as Vector3) * k
		lamp.light_color = Color(0.86, 0.90, 1.0)
		lamp.light_energy = float(spec[2]) * k
		lamp.spot_range = 9.0 * k
		lamp.spot_angle = 34.0
		add_child(lamp)
		lamp.look_at(ANCHOR + (spec[1] as Vector3) * k, Vector3.UP)


func _build_swing() -> void:
	var ph := float(SWING.get("pivot_height", 4.30))
	_pivot = Node3D.new()
	_pivot.name = "PendulumPivot"
	_pivot.position = ANCHOR + Vector3(0.0, ph, 0.0)
	add_child(_pivot)
	for key in ["arm_glb", "head_glb"]:
		var f := str(SWING.get(key, ""))
		if f == "" or not ResourceLoader.exists(f):
			continue
		var holder := Node3D.new()
		holder.name = "Arm" if key == "arm_glb" else "Head"
		_pivot.add_child(holder)
		holder.add_child((load(f) as PackedScene).instantiate())
		_apply_materials(holder)
	# 静止姿态
	_pivot.rotation.x = -deg_to_rad(float(SWING.get("rest_angle", 2.5)))

