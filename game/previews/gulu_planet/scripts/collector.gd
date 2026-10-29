extends Node3D
class_name FuelCollector

## 飞船装货口：喇叭形接货斜面 + 吸入式收集仓。
## 判定用固定 AABB（有容错），不依赖高速物理碰撞；入仓只计一次。

signal fuel_collected(total: int, target: int)

const HULL := Color("#9aa9a6")
const HULL_DARK := Color("#7f8f8c")
const TRIM := Color("#375967")
const GLASS := Color("#8fe3ff")
const AMBER := Color("#ffb347")
const CYAN := Color("#3fd8ff")
const INTAKE := Color("#0d1a20")

## 接货口在世界坐标中的容错范围（比视觉开口略大，避免像素级瞄准）。
const CATCH_MIN := Vector3(12.45, 0.0, -2.40)
const CATCH_MAX := Vector3(15.90, 2.30, 2.40)
const INTAKE_POINT := Vector3(15.15, 1.05, 0.0)

var target_count := 3
var loaded_count := 0
## 最后一次入仓的搬运者 peer（单人时 1；保留给以后多人算贡献）
var last_credit_peer := 0

var _pips: Array[MeshInstance3D] = []
var _pulse := 0.0
var _intake_material: StandardMaterial3D
var _flash := 0.0


func _ready() -> void:
	_build_hull()
	_build_scoop()
	_build_intake()
	_build_pips()
	_update_pips()
	set_process(true)


func contains_point(point: Vector3) -> bool:
	return (
		point.x >= CATCH_MIN.x and point.x <= CATCH_MAX.x
		and point.y >= CATCH_MIN.y - 0.6 and point.y <= CATCH_MAX.y
		and point.z >= CATCH_MIN.z and point.z <= CATCH_MAX.z
	)


func consume(fuel: Node3D) -> void:
	if fuel == null or not is_instance_valid(fuel):
		return
	if bool(fuel.get("collected")):
		return
	fuel.call("collect")
	last_credit_peer = int(fuel.get("credit_peer"))
	loaded_count += 1
	_flash = 1.0
	_update_pips()
	_animate_intake(fuel)
	fuel_collected.emit(loaded_count, target_count)


func reset_state() -> void:
	loaded_count = 0
	last_credit_peer = 0
	_flash = 0.0
	_update_pips()


func _animate_intake(fuel: Node3D) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(fuel, "global_position", INTAKE_POINT, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(fuel, "scale", Vector3.ONE * 0.15, 0.45)
	tween.chain().tween_callback(func() -> void: fuel.visible = false)
	# 重开时由燃料自己 kill，避免动画把已重置的燃料又拉回仓里。
	fuel.set_meta("intake_tween", tween)


# ------------------------------------------------------------------ 几何

func _build_hull() -> void:
	# 船体：左右两侧船身夹出中间的装货口，口朝 -X。
	for side in [-1.0, 1.0]:
		_box(Vector3(6.0, 5.0, 3.6), Vector3(16.9, 2.5, side * 4.7), HULL, true)
		_box(Vector3(0.9, 0.5, 3.7), Vector3(13.55, 4.55, side * 4.7), TRIM, false)
		_box(Vector3(3.2, 0.22, 3.4), Vector3(16.4, 5.05, side * 4.7), HULL_DARK, false)
		for index in range(3):
			_box(Vector3(0.16, 1.0, 1.3), Vector3(13.88, 3.15, side * 4.7 - 1.15 + float(index) * 1.15), GLASS, false, 1.0)
		# 侧鳍：让船在远景里有方向感
		_box(Vector3(2.4, 0.9, 0.18), Vector3(17.9, 3.0, side * 6.55), TRIM, false, 0.0, Vector3(side * 0.3, 0.0, 0.0))
	# 背板与顶部
	_box(Vector3(3.2, 5.0, 13.0), Vector3(18.4, 2.5, 0.0), HULL, true)
	_box(Vector3(6.0, 1.4, 13.0), Vector3(16.9, 4.7, 0.0), HULL, true)
	_box(Vector3(0.24, 0.16, 12.6), Vector3(13.9, 4.02, 0.0), CYAN, false, 1.0)
	_box(Vector3(0.6, 0.7, 13.4), Vector3(17.0, 5.6, 0.0), TRIM, false)
	# 尾部引擎
	_box(Vector3(0.3, 2.6, 9.0), Vector3(19.9, 2.4, 0.0), HULL_DARK, false)
	for side in [-1.0, 1.0]:
		var nozzle := CylinderMesh.new()
		nozzle.top_radius = 0.85
		nozzle.bottom_radius = 1.05
		nozzle.height = 1.5
		var nozzle_node := MeshInstance3D.new()
		nozzle_node.mesh = nozzle
		nozzle_node.position = Vector3(20.1, 2.2, side * 3.4)
		nozzle_node.rotation.z = PI * 0.5
		nozzle_node.material_override = _material(TRIM, 0.0)
		add_child(nozzle_node)
		_box(Vector3(0.10, 1.5, 1.5), Vector3(20.78, 2.2, side * 3.4), CYAN, false, 1.4)
	# 起落架
	for side in [-1.0, 1.0]:
		for x in [15.4, 18.8]:
			_leg(Vector3(x, 0.5, side * 5.6))


func _build_scoop() -> void:
	# 接货平台（与地面齐平，可走进去）
	_box(Vector3(4.6, 0.3, 5.8), Vector3(13.55, -0.15, 0.0), HULL_DARK, true)
	# 入口门槛：0.22 m，步进辅助可跨过，但能挡住滚出去的燃料
	_box(Vector3(0.42, 0.22, 5.8), Vector3(11.5, 0.11, 0.0), TRIM, true)
	# 地面导引条
	for side in [-1.0, 1.0]:
		_box(Vector3(4.2, 0.02, 0.20), Vector3(13.6, 0.015, side * 1.45), AMBER, false, 0.5, Vector3(0, side * 0.10, 0))
	# 两侧接货斜面（漏斗），碰撞跟着一起旋转
	for side in [-1.0, 1.0]:
		_box(Vector3(3.9, 1.10, 0.34), Vector3(13.5, 0.55, side * 2.45), HULL, true, 0.0, Vector3(0, side * 0.42, 0))
		_box(Vector3(3.9, 0.14, 0.44), Vector3(13.5, 1.16, side * 2.45), AMBER, false, 0.7, Vector3(0, side * 0.42, 0))
	# 平台边缘灯
	_box(Vector3(0.12, 0.10, 5.6), Vector3(11.36, 0.03, 0.0), AMBER, false, 1.0)


func _build_intake() -> void:
	_box(Vector3(1.2, 2.2, 3.2), Vector3(15.5, 1.1, 0.0), INTAKE, false)
	_intake_material = _material(CYAN, 1.6)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.16, 2.3, 0.16), Vector3(15.05, 1.15, side * 1.65), CYAN, false, 1.6, Vector3.ZERO, _intake_material)
	_box(Vector3(0.16, 0.16, 3.5), Vector3(15.05, 2.28, 0.0), CYAN, false, 1.6, Vector3.ZERO, _intake_material)
	_box(Vector3(0.16, 0.16, 3.5), Vector3(15.05, 0.08, 0.0), CYAN, false, 1.6, Vector3.ZERO, _intake_material)
	var glow := OmniLight3D.new()
	glow.position = Vector3(14.6, 1.2, 0.0)
	glow.light_color = CYAN
	glow.light_energy = 1.5
	glow.omni_range = 5.5
	add_child(glow)
	var amber := OmniLight3D.new()
	amber.position = Vector3(12.6, 0.9, 0.0)
	amber.light_color = AMBER
	amber.light_energy = 0.9
	amber.omni_range = 5.0
	add_child(amber)


func _build_pips() -> void:
	for index in range(3):
		_pips.append(_box(Vector3(0.10, 0.24, 0.52), Vector3(13.94, 2.05, -1.5 + float(index) * 1.5), TRIM, false))


func _update_pips() -> void:
	for index in range(_pips.size()):
		var lit: bool = index < loaded_count
		var mat := StandardMaterial3D.new()
		mat.albedo_color = AMBER if lit else TRIM
		mat.roughness = 0.7
		if lit:
			mat.emission_enabled = true
			mat.emission = AMBER
			mat.emission_energy_multiplier = 1.8
		_pips[index].material_override = mat


func _process(delta: float) -> void:
	_pulse += delta
	_flash = maxf(0.0, _flash - delta * 2.2)
	if _intake_material != null:
		_intake_material.emission_energy_multiplier = 1.2 + 0.35 * sin(_pulse * 2.4) + _flash * 3.2


func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = 0.05
	material.metallic_specular = 0.22
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _leg(at: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.26
	mesh.bottom_radius = 0.34
	mesh.height = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(Color("#8fa3a1"), 0.0)
	add_child(instance)


func _box(size: Vector3, at: Vector3, color: Color, solid: bool, emission: float = 0.0, rotation: Vector3 = Vector3.ZERO, material: StandardMaterial3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rotation
	instance.material_override = material if material != null else _material(color, emission)
	add_child(instance)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		body.position = at
		body.rotation = rotation
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)
	return instance
