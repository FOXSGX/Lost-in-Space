extends Node3D

## 腐墟星医院内部：独立于城市外景的 4 层室内。
##
## B1 太平间 / 1F 急诊大厅 / 2F 住院病房 / 3F 手术与 ICU。
## 中央走廊 + 两排房间，西侧折返楼梯，东侧停用电梯。
## 全部沿用腐墟星的倒角方块和低饱和配色，靠灯光、床位、血迹和杂物读空间。

const ART := preload("res://scripts/ruin_cartoon_art.gd")
const SURFACE := preload("res://scripts/ruin_surface_lib.gd")
const STAIR_TEMPLATE := preload("res://scripts/ruin_stair_template.gd")

const LEVELS := 4
const FLOOR_HEIGHT := 3.0
const BASE_Y := 197.0
const W := 24.0
const D := 17.0
const HALF_W := 12.0
const HALF_D := 8.5
const STAIR_X0 := -11.0
const STAIR_X1 := -7.0
const STAIR_Z := 5.0
const CORRIDOR := 1.3

const FLOOR_TILE := Color("#626c70")
const FLOOR_GROUT := Color("#4b5450")
const WALL := Color("#9aa6a8")
const WALL_LOW := Color("#29464d")
const CEILING := Color("#b6bdc0")
const METAL := Color("#3a4c54")
const RUST := Color("#7d4632")
const BLOOD := Color("#702e2a")
const LINEN := Color("#d3d4ca")
const WOOD := Color("#6b5846")
const GLASS := Color("#557f80")
const GREEN := Color("#4f8a7a")
const RED := Color("#a8453a")
const DARK := Color("#172729")
const LAMP := Color("#d6ded8")
const AMBER := Color("#c58a3e")
const STEEL_DARK := Color("#2b3b3d")
const CREAM_TRIM := Color("#c9c0aa")

const LEVEL_NAMES := ["B1 地下药库与太平间", "1F 大厅/药房/保安室", "2F 门诊/检查/观察室", "3F 住院病房"]

var controller: Main3D
var _flicker_lights: Array[OmniLight3D] = []
var _flicker_phase := 0.0
var locked_door_points: Array[Vector3] = []
var ward_door_pivot: Node3D
var ward_door_collider: StaticBody3D
var ward_door_open := false
var _ward_door_local := Vector3.ZERO
var _task_items: Dictionary = {}
var _task_points: Dictionary = {}
var _floor_y := 0.0


func build(owner: Main3D, parent: Node3D) -> void:
	controller = owner
	name = "RuinHospitalInterior"
	position = Vector3(0.0, BASE_Y, 0.0)
	parent.add_child(self)
	for level: int in LEVELS:
		_build_level(level)
	_build_stairs()
	_build_elevator()
	set_process(true)


func spawn_position() -> Vector3:
	return global_position + Vector3(0.0, FLOOR_HEIGHT + 0.15, 6.9)


func exit_position() -> Vector3:
	return global_position + Vector3(0.0, FLOOR_HEIGHT, 7.9)


func level_position(level: int) -> Vector3:
	return global_position + Vector3(0.0, float(level) * FLOOR_HEIGHT, 0.0)


func level_count() -> int:
	return LEVELS


func task_item_positions() -> Dictionary:
	var points: Dictionary = {}
	for id: String in _task_points.keys():
		points[id] = global_position + _task_points[id]
	return points


func collect_task_item(item_id: String) -> void:
	if not _task_items.has(item_id):
		return
	var node := _task_items[item_id] as Node3D
	if node != null:
		node.visible = false


func locked_door_positions() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for point: Vector3 in locked_door_points:
		points.append(global_position + point)
	return points


func ward_door_position() -> Vector3:
	return global_position + _ward_door_local


func is_ward_door_open() -> bool:
	return ward_door_open


func open_ward_door() -> void:
	if ward_door_open or ward_door_pivot == null:
		return
	ward_door_open = true
	if ward_door_collider != null:
		ward_door_collider.collision_layer = 0
	var tween := create_tween()
	var target := ward_door_pivot.rotation
	target.y = deg_to_rad(-102.0)
	tween.tween_property(ward_door_pivot, "rotation", target, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func is_inside(point: Vector3) -> bool:
	var local := point - global_position
	return local.y > -1.0 and local.y < FLOOR_HEIGHT * float(LEVELS) + 1.0 and absf(local.x) <= HALF_W + 2.0 and absf(local.z) <= HALF_D + 2.0


func _process(delta: float) -> void:
	_flicker_phase += delta
	for index: int in _flicker_lights.size():
		var light := _flicker_lights[index]
		if not is_instance_valid(light):
			continue
		var flicker := 0.82 + 0.18 * sin(_flicker_phase * (7.0 + float(index)) + float(index))
		if sin(_flicker_phase * 0.37 + float(index) * 2.1) > 0.92:
			flicker *= 0.18
		light.light_energy = light.get_meta("base_energy", 0.85) * flicker


# ── 楼层 ─────────────────────────────────────────────────────

func _build_level(level: int) -> void:
	var y := float(level) * FLOOR_HEIGHT
	_floor_y = y
	_floor_slabs(y)
	_ceiling_slabs(y)
	_walls(y, level)
	if level == 3:
		_build_ward_doors(y)
	_lights(y, level)
	_furnish(level, y)
	_floor_dressing(level, y)
	if level == 1:
		_build_entrance_door(y)
	_stairwell_soffit(y)


func _floor_slabs(y: float) -> void:
	_floor_piece(Vector2(-7.0, HALF_W), Vector2(-HALF_D, HALF_D), y)
	_floor_piece(Vector2(-HALF_W, -7.0), Vector2(-HALF_D, -STAIR_Z), y)
	_floor_piece(Vector2(-HALF_W, -7.0), Vector2(STAIR_Z, HALF_D), y)
	if is_zero_approx(y):
		# B1 楼梯底部必须是一整块可站立地面，不能再是窄封边之间的空洞。
		_floor_piece(Vector2(-HALF_W, -7.0), Vector2(-STAIR_Z, STAIR_Z), y)


func _floor_piece(bounds_x: Vector2, bounds_z: Vector2, y: float) -> void:
	var size := Vector3(bounds_x.y - bounds_x.x, 0.22, bounds_z.y - bounds_z.x)
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.11, (bounds_z.x + bounds_z.y) * 0.5)
	var slab := ART.block(self, "HospitalFloor", size, center, FLOOR_TILE, 0.04)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = load("res://assets/ruin/textures/floor_concrete.png") as Texture2D
	floor_mat.albedo_color = Color.WHITE
	floor_mat.roughness = 0.92
	floor_mat.metallic = 0.0
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_world_triplanar = true
	floor_mat.uv1_scale = Vector3.ONE / 2.4
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slab.material_override = floor_mat
	var floor_overlay := MeshInstance3D.new()
	floor_overlay.name = "HospitalFloorTexture_%d_%d_%d" % [int(y * 10.0), int(bounds_x.x * 10.0), int(bounds_z.x * 10.0)]
	var overlay_mesh := BoxMesh.new()
	overlay_mesh.size = Vector3(size.x, 0.012, size.z)
	floor_overlay.mesh = overlay_mesh
	var overlay_mat := StandardMaterial3D.new()
	overlay_mat.albedo_texture = floor_mat.albedo_texture
	overlay_mat.albedo_color = Color.WHITE
	overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay_mat.uv1_scale = Vector3(maxf(size.x / 2.4, 1.0), maxf(size.z / 2.4, 1.0), 1.0)
	floor_overlay.material_override = overlay_mat
	floor_overlay.position = Vector3(center.x, y + 0.012, center.z)
	floor_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_overlay)
	# 实体砖缝：即使纹理在兼容渲染下被洗淡，地面仍然有可见的尺度与分格。
	var step := 1.2
	var gx := bounds_x.x + step
	while gx < bounds_x.y:
		ART.block(self, "FloorGrout_X_%d_%d" % [int(gx * 10.0), int(y * 10.0)], Vector3(0.085, 0.010, size.z), Vector3(gx, y + 0.042, center.z), Color("#2f3a39"), 0.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gx += step
	var gz := bounds_z.x + step
	while gz < bounds_z.y:
		ART.block(self, "FloorGrout_Z_%d_%d" % [int(gz * 10.0), int(y * 10.0)], Vector3(size.x, 0.010, 0.085), Vector3(center.x, y + 0.042, gz), Color("#2f3a39"), 0.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gz += step
	_collider(size, center)


func _ceiling_slabs(y: float) -> void:
	var ceiling_y := y + FLOOR_HEIGHT
	_ceiling_piece(Vector2(-7.0, HALF_W), Vector2(-HALF_D, HALF_D), ceiling_y)
	_ceiling_piece(Vector2(-HALF_W, -7.0), Vector2(-HALF_D, -STAIR_Z), ceiling_y)
	_ceiling_piece(Vector2(-HALF_W, -7.0), Vector2(STAIR_Z, HALF_D), ceiling_y)


func _ceiling_piece(bounds_x: Vector2, bounds_z: Vector2, y: float) -> void:
	var size := Vector3(bounds_x.y - bounds_x.x, 0.16, bounds_z.y - bounds_z.x)
	# 楼上的地板底面比顶板低约 0.22 m，会在下方盖住顶板；把可读顶面下移到地板底面以下。
	# 顶面使用与墙面同一套灰泥色/脏污纹理，但用无光照材质保证亮度稳定、略暗。
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_texture = load("res://assets/ruin/textures/ceiling_plaster.png") as Texture2D
	skin_mat.albedo_color = Color.WHITE
	skin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin_mat.uv1_scale = Vector3(maxf(size.x / 2.0, 1.0), maxf(size.z / 2.0, 1.0), 1.0)
	var skin := MeshInstance3D.new()
	skin.name = "HospitalCeiling"
	var skin_mesh := BoxMesh.new()
	skin_mesh.size = Vector3(size.x, 0.05, size.z)
	skin.mesh = skin_mesh
	skin.material_override = skin_mat
	skin.position = Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.28, (bounds_z.x + bounds_z.y) * 0.5)
	skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skin)

	# 顶板四周做 soffit 收边；即使下方是楼梯井，也读成结构开口而不是黑块。
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.32, (bounds_z.x + bounds_z.y) * 0.5)
	var trim := 0.16
	ART.block(self, "CeilingSoffit", Vector3(size.x + trim * 2.0, 0.20, trim), Vector3(center.x, y - 0.32, bounds_z.x - trim * 0.5), CREAM_TRIM, 0.02)
	ART.block(self, "CeilingSoffit", Vector3(size.x + trim * 2.0, 0.20, trim), Vector3(center.x, y - 0.32, bounds_z.y + trim * 0.5), CREAM_TRIM, 0.02)
	ART.block(self, "CeilingSoffit", Vector3(trim, 0.20, size.z), Vector3(bounds_x.x - trim * 0.5, y - 0.32, center.z), CREAM_TRIM, 0.02)
	ART.block(self, "CeilingSoffit", Vector3(trim, 0.20, size.z), Vector3(bounds_x.y + trim * 0.5, y - 0.32, center.z), CREAM_TRIM, 0.02)


# ── 墙与门洞 ─────────────────────────────────────────────────

func _walls(y: float, level: int) -> void:
	var h := FLOOR_HEIGHT
	# 南墙：一层留大门，其他楼层封死。
	if level == 1:
		_wall(Vector3(10.9, h, 0.25), Vector3(-6.45, y + h * 0.5, HALF_D))
		_wall(Vector3(10.9, h, 0.25), Vector3(6.45, y + h * 0.5, HALF_D))
		_door_frame(Vector3(0.0, y, HALF_D), 2.2, 2.8, GREEN)
	else:
		_wall(Vector3(W, h, 0.25), Vector3(0.0, y + h * 0.5, HALF_D))
	_wall(Vector3(W, h, 0.25), Vector3(0.0, y + h * 0.5, -HALF_D))
	_wall(Vector3(0.25, h, D), Vector3(-HALF_W, y + h * 0.5, 0.0))
	_wall(Vector3(0.25, h, D), Vector3(HALF_W, y + h * 0.5, 0.0))

	# 每层只在楼梯抵达的一侧留一个 2.4 m 入口，楼层之间交错：
	# B1 南、1F 北、2F 南、3F 北。另一侧是完整墙体，不再开第二个门。
	var entrance_z := 6.0 if level % 2 == 0 else -6.0
	if entrance_z > 0.0:
		_wall(Vector3(0.25, h, 13.3), Vector3(STAIR_X1, y + h * 0.5, -1.85))
		_wall(Vector3(0.25, h, 1.3), Vector3(STAIR_X1, y + h * 0.5, 7.85))
	else:
		_wall(Vector3(0.25, h, 1.3), Vector3(STAIR_X1, y + h * 0.5, -7.85))
		_wall(Vector3(0.25, h, 13.3), Vector3(STAIR_X1, y + h * 0.5, 1.85))
	STAIR_TEMPLATE.build_door_frame(self, Vector3(STAIR_X1, y, entrance_z), 2.4, 2.4, TEAL_LOW())

	# 中央走廊两侧房间墙，每侧三扇门。
	if level == 1:
		# 一层急诊大厅：楼梯口西侧完全开放，不再用墙段封住唯一入口。
		_wall(Vector3(7.0, h, 0.20), Vector3(8.5, y + h * 0.5, CORRIDOR))
		for side: float in [-1.0, 1.0]:
			ART.block(self, "LobbyColumn", Vector3(0.42, h, 0.42), Vector3(side * 5.0, y + h * 0.5, CORRIDOR), TEAL_LOW(), 0.03)
			_collider(Vector3(0.42, h, 0.42), Vector3(side * 5.0, y + h * 0.5, CORRIDOR))
		# 北侧也打开中央 9 m，让入口—大厅—走廊连成一条完整视线。
		_wall(Vector3(7.5, h, 0.20), Vector3(8.25, y + h * 0.5, -CORRIDOR))
		for side: float in [-1.0, 1.0]:
			ART.block(self, "LobbyColumn", Vector3(0.42, h, 0.42), Vector3(side * 4.5, y + h * 0.5, -CORRIDOR), TEAL_LOW(), 0.03)
			_collider(Vector3(0.42, h, 0.42), Vector3(side * 4.5, y + h * 0.5, -CORRIDOR))
	else:
		_wall_line_x(CORRIDOR, y, h, [-4.6, 3.4, 7.4], 1.2)
		_wall_line_x(-CORRIDOR, y, h, [-4.6, 3.4, 7.4], 1.2)
	# 病房隔墙。1F 大厅中央和南侧不隔断，否则大门正对一堵墙。
	for x: float in [-5.0, 0.0, 5.0]:
		if not (level == 1 and is_zero_approx(x)):
			_wall(Vector3(0.22, h, 7.1), Vector3(x, y + h * 0.5, -5.05))
		if level == 1:
			continue
		_wall(Vector3(0.22, h, 7.1), Vector3(x, y + h * 0.5, 5.05))

	# 走廊下部青色护墙和踢脚线。
	for side: float in [-1.0, 1.0]:
		# 只保留贴地踢脚线；原先 0.92 m 高的连续深色墙裙会横穿门洞/柜台，已取消。
		ART.block(self, "Baseboard", Vector3(19.0, 0.10, 0.06), Vector3(2.5, y + 0.05, side * (CORRIDOR - 0.12)), DARK, 0.02)


## 1F 入口：关着的对开木框玻璃门。玩家进门后回头看到的就是这扇门；
## 门板带碰撞，不能从门洞走出去掉下室内高台。离开仍走入口 E 交互。
func _build_entrance_door(y: float) -> void:
	var door_z := HALF_D - 0.12
	var door_w := 2.2
	for side: float in [-1.0, 1.0]:
		ART.block(self, "InteriorEntranceDoorLeaf", Vector3(door_w * 0.5 - 0.03, 2.72, 0.10), Vector3(side * door_w * 0.25, y + 1.36, door_z), WOOD, 0.03)
		ART.block(self, "InteriorEntranceDoorGlass", Vector3(door_w * 0.40, 0.78, 0.04), Vector3(side * door_w * 0.25, y + 2.06, door_z - 0.06), GLASS, 0.01, true, 0.08)
		ART.block(self, "InteriorEntranceDoorHandle", Vector3(0.06, 0.26, 0.07), Vector3(side * 0.10, y + 1.18, door_z - 0.10), METAL, 0.01, false, 0.0, SURFACE.Family.MACH)
	ART.block(self, "InteriorEntranceDoorKick", Vector3(door_w - 0.10, 0.24, 0.05), Vector3(0.0, y + 0.20, door_z - 0.08), METAL, 0.01, false, 0.0, SURFACE.Family.MACH)
	var body := StaticBody3D.new()
	body.name = "InteriorEntranceDoorCollision"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = Vector3(0.0, y + 1.4, door_z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(door_w, 2.8, 0.14)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _build_ward_doors(_y: float) -> void:
	# 病房门全部删除：门洞保持敞开，玩家直接进入病房。
	locked_door_points.clear()


func _wall(size: Vector3, center: Vector3) -> void:
	var mesh := ART.block(self, "HospitalWall", size, center, WALL, 0.05)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(size, center)
	ART.block(self, "WallCap", Vector3(size.x + 0.03, 0.07, size.z + 0.03), center + Vector3(0.0, size.y * 0.5 - 0.035, 0.0), CREAM_TRIM, 0.012)
	# 统一踢脚线，避免整面墙从地板直接长出来。
	ART.block(self, "WallBase", Vector3(size.x + 0.02, 0.14, size.z + 0.02), center + Vector3(0.0, -size.y * 0.5 + 0.07, 0.0), DARK, 0.02)


func _wall_line_x(z: float, y: float, h: float, door_starts: Array, door_width: float) -> void:
	var x_start := STAIR_X1
	var x_end := HALF_W
	var cursor := x_start
	# 楼梯平台到走廊的常开通道。没有这个开口，楼梯门后是一间封闭房间，
	# 玩家会以为整层都被墙封死。
	var west_open_start := -6.6
	var west_open_end := -5.2
	_wall(Vector3(west_open_start - cursor, h, 0.22), Vector3((cursor + west_open_start) * 0.5, y + h * 0.5, z))
	_door_frame(Vector3((west_open_start + west_open_end) * 0.5, y, z), west_open_end - west_open_start, 2.4, TEAL_LOW(), false)
	cursor = west_open_end
	for start: float in door_starts:
		if start > cursor:
			var length := start - cursor
			_wall(Vector3(length, h, 0.22), Vector3((cursor + start) * 0.5, y + h * 0.5, z))
		_door_frame(Vector3(start + door_width * 0.5, y, z), door_width, 2.4, TEAL_LOW(), false)
		cursor = start + door_width
	if x_end > cursor:
		_wall(Vector3(x_end - cursor, h, 0.22), Vector3((cursor + x_end) * 0.5, y + h * 0.5, z))


func _door_frame(at: Vector3, width: float, height: float, color: Color, with_panel := true) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DoorPost", Vector3(0.14, height, 0.34), at + Vector3(side * width * 0.5, height * 0.5, 0.0), color, 0.03)
	ART.block(self, "DoorHeader", Vector3(width + 0.28, 0.18, 0.34), at + Vector3(0.0, height, 0.0), color, 0.03)
	# 半开的门板：只做视觉，不挡交互。病房门保持打开，让走廊能看见病床。
	if not with_panel:
		return
	var panel := ART.block(self, "DoorPanel", Vector3(width * 0.92, height * 0.93, 0.07), at + Vector3(-width * 0.42, height * 0.46, 0.22), Color("#6f7f7c"), 0.03)
	panel.rotation_degrees.y = 104.0


## 沿 X 方向墙面的门框（门洞沿 Z 展开），用于西侧楼梯间。
func _door_frame_z(at: Vector3, width: float, height: float, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DoorPost", Vector3(0.34, height, 0.14), at + Vector3(0.0, height * 0.5, side * width * 0.5), color, 0.03)
	ART.block(self, "DoorHeader", Vector3(0.34, 0.18, width + 0.28), at + Vector3(0.0, height, 0.0), color, 0.03)


func TEAL_LOW() -> Color:
	return WALL_LOW


# ── 楼梯 ─────────────────────────────────────────────────────

func _stairwell_soffit(y: float) -> void:
	# 楼梯井上方的楼板边缘做浅色收边，避免从下方看是黑色尖片。
	var edge_y := y + FLOOR_HEIGHT - 0.06
	ART.block(self, "StairSoffit", Vector3(5.2, 0.20, 0.16), Vector3(-9.5, edge_y, -STAIR_Z), CREAM_TRIM, 0.02)
	ART.block(self, "StairSoffit", Vector3(5.2, 0.20, 0.16), Vector3(-9.5, edge_y, STAIR_Z), CREAM_TRIM, 0.02)
	ART.block(self, "StairSoffit", Vector3(0.16, 0.20, 10.2), Vector3(-12.0, edge_y, 0.0), CREAM_TRIM, 0.02)
	ART.block(self, "StairSoffit", Vector3(0.16, 0.20, 10.2), Vector3(-7.0, edge_y, 0.0), CREAM_TRIM, 0.02)


func _build_stairs() -> void:
	STAIR_TEMPLATE.build(self, {
		"levels": LEVELS,
		"floor_height": FLOOR_HEIGHT,
		"x0": -12.0,
		"x1": -7.0,
		"stair_z": 5.0,
		"tread_color": Color("#aeb6b3"),
		"fill_color": Color("#778487"),
		"rail_color": Color("#7f8a8c"),
	})


# ── 灯光 ─────────────────────────────────────────────────────

func _lights(y: float, level: int) -> void:
	var positions: Array[Vector2] = [
		Vector2(-4.0, 4.8), Vector2(3.0, 4.8), Vector2(-4.0, -4.8), Vector2(3.0, -4.8), Vector2(3.0, 0.0)
	]
	var color := Color("#d4ddd7")
	if level == 0:
		color = Color("#c9d2cb")
	elif level == 2:
		color = Color("#c2d4cd")
	elif level == 3:
		color = Color("#d2d8d3")
	for index: int in positions.size():
		var point := positions[index]
		_light_panel(Vector3(point.x, y + 2.86, point.y), color, 0.55, 7.2)
	if level == 1:
		# 大厅入口单独补三盏宽角灯，避免玩家一进门只剩出口灯。
		_light_panel(Vector3(-3.0, y + 2.86, 6.8), color, 0.70, 7.0)
		_light_panel(Vector3(3.0, y + 2.86, 6.8), color, 0.70, 7.0)
		_light_panel(Vector3(0.0, y + 2.86, 3.6), color, 0.80, 8.5)
		_light_panel(Vector3(0.0, y + 2.86, -6.8), color, 0.75, 8.0)
		_light_panel(Vector3(0.0, y + 2.80, -7.9), Color("#e8e0cc"), 1.15, 7.0)
	ART.block(self, "FarWallCove", Vector3(21.0, 0.05, 0.05), Vector3(2.0, y + 2.82, -8.36), Color("#b9ad93"), 0.01, true, 0.18)
	for side: float in [-1.0, 1.0]:
		ART.block(self, "FarWallLightHousing", Vector3(1.2, 0.18, 0.10), Vector3(side * 4.5, y + 1.88, -8.38), STEEL_DARK, 0.02)
		ART.block(self, "FarWallLightTube", Vector3(1.0, 0.05, 0.04), Vector3(side * 4.5, y + 1.88, -8.31), Color("#bdb5a2"), 0.01, true, 0.16)
		var wall_light := OmniLight3D.new()
		wall_light.light_color = Color("#bdb5a2")
		wall_light.light_energy = 0.28
		wall_light.omni_range = 4.5
		wall_light.position = Vector3(side * 4.5, y + 1.8, -7.9)
		wall_light.shadow_enabled = false
		add_child(wall_light)
	_light_panel(Vector3(0.0, y + 2.86, 7.9), GREEN, 0.45, 4.0)
	_exit_sign(Vector3(0.0, y + 2.95, HALF_D - 0.20), GREEN)
	# 楼梯间补光：壁灯固定在楼梯间东墙，不悬在井口上方。
	_wall_light(Vector3(-7.12, y + 1.92, 6.2), Color("#bfe8e0"), 0.82, 5.4)
	_wall_light(Vector3(-7.12, y + 1.92, -6.2), Color("#bfe8e0"), 0.82, 5.4)
	_wall_light(Vector3(-7.12, y + 1.92, 0.0), Color("#d7e5e1"), 0.62, 4.8)
	_stair_floor_sign(level, y)
	var stair_entrance_side := 1.0 if level % 2 == 0 else -1.0
	ART.block(self, "StairLevelPlate", Vector3(0.06, 0.62, 1.1), Vector3(-6.86, y + 1.55, stair_entrance_side * 7.35), [RED, Color("#6ba7b8"), Color("#78a88a"), Color("#d59a5b")][level], 0.02, true, 0.22)
	if level == 0:
		var flicker := OmniLight3D.new()
		flicker.name = "MorgueFlicker"
		flicker.light_color = Color("#e8a86a")
		flicker.light_energy = 0.85
		flicker.omni_range = 7.5
		flicker.position = Vector3(-4.0, y + 2.3, 5.0)
		flicker.shadow_enabled = false
		flicker.set_meta("base_energy", 0.85)
		add_child(flicker)
		_flicker_lights.append(flicker)


func _light_panel(at: Vector3, color: Color, energy: float, range_value: float) -> void:
	# 吸顶底座与扩散板连在一起，灯不再悬在天花板下方；跟随下移后的顶面。
	var fixed_at := Vector3(at.x, _floor_y + 2.78, at.z)
	# 底座从灯板一直顶到天花板，避免吸顶灯看起来悬空。
	ART.block(self, "CeilingLightMount", Vector3(1.72, 0.24, 0.50), fixed_at + Vector3(0.0, 0.12, 0.0), CREAM_TRIM, 0.02)
	var panel := ART.block(self, "CeilingLight", Vector3(1.5, 0.05, 0.34), fixed_at, color, 0.02, true, 0.55)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.position = fixed_at + Vector3(0.0, -0.20, 0.0)
	light.shadow_enabled = false
	light.set_meta("fixture", "ceiling")
	add_child(light)


func _wall_light(at: Vector3, color: Color, energy: float, range_value: float) -> void:
	# 固定在楼梯间东墙上的壁灯，避免灯板悬在无顶板的井口上方。
	ART.block(self, "WallLightBracket", Vector3(0.18, 0.08, 0.18), at + Vector3(0.10, 0.0, 0.0), STEEL_DARK, 0.012)
	ART.block(self, "WallLightHousing", Vector3(0.10, 0.24, 1.05), at + Vector3(0.04, 0.0, 0.0), STEEL_DARK, 0.02)
	var tube := ART.block(self, "WallLightTube", Vector3(0.035, 0.10, 0.86), at + Vector3(-0.02, 0.0, 0.0), color, 0.01, true, 0.55)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.position = at + Vector3(-0.20, -0.04, 0.0)
	light.shadow_enabled = false
	light.set_meta("fixture", "wall")
	add_child(light)


func _sign_plate(texture_path: String, at: Vector3, size: Vector2, yaw: float) -> MeshInstance3D:
	var texture := load(texture_path) as Texture2D
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = size
	var sign := MeshInstance3D.new()
	sign.name = "WallSign_%s_%d" % [texture_path.get_file().get_basename(), get_child_count()]
	sign.mesh = quad
	sign.material_override = material
	sign.position = at
	sign.rotation.y = yaw
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sign)
	return sign


func _stair_floor_sign(level: int, y: float) -> void:
	var names := ["b1", "1f", "2f", "3f"]
	var colors := [RED, Color("#6ba7b8"), Color("#78a88a"), Color("#d59a5b")]
	# 只在唯一入口的一侧放楼层牌和目录，避免把封闭侧误读成入口。
	var side := 1.0 if level % 2 == 0 else -1.0
	_sign_plate("res://assets/ruin/signs/hospital_floor_%s.png" % names[level], Vector3(-6.80, y + 1.78, side * 7.25), Vector2(0.56, 0.28), PI * 0.5)
	_sign_plate("res://assets/ruin/signs/hospital_dir_%s.png" % names[level], Vector3(-9.0, y + 1.62, side * 8.34), Vector2(1.65, 0.62), PI if side > 0.0 else 0.0)


func _exit_sign(at: Vector3, color: Color) -> void:
	var sign := ART.block(self, "ExitSign", Vector3(0.62, 0.22, 0.08), at, color, 0.02, true, 0.45)
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ART.block(self, "ExitArrow", Vector3(0.22, 0.08, 0.04), at + Vector3(0.0, 0.0, -0.06), Color("#d7f0e0"), 0.01, true, 0.35)


# ── 陈设 ─────────────────────────────────────────────────────

func _furnish(level: int, y: float) -> void:
	match level:
		0:
			_morgue(y)
			_basement_pharmacy(y)
			_archive_room(y)
		1:
			_lobby(y)
			_pharmacy(y)
			_security_office(y)
		2:
			_outpatient(y)
			_exam_rooms(y)
			_imaging(y)
			_nurse_station(y)
			_sedation_room(y)
		3:
			_wards(y)
			_nurse_station(y)
	# 每层都有的零碎
	_corridor_details(y, level)
	_debris(y, level)


func _corridor_details(y: float, level: int) -> void:
	# 走廊导向牌：纯色块，不写悬浮字。
	var colors := [RED, Color("#6ba7b8"), Color("#78a88a"), Color("#d59a5b")]
	var color: Color = colors[level]
	for x: float in [-3.0, 2.0, 7.0]:
		for side: float in [-1.0, 1.0]:
			var z := side * (CORRIDOR - 0.13)
			ART.block(self, "CorridorSign", Vector3(0.78, 0.34, 0.05), Vector3(x, y + 1.95, z), color, 0.02, true, 0.22)
			ART.block(self, "CorridorSignMark", Vector3(0.24, 0.12, 0.03), Vector3(x + 0.18, y + 1.95, z - side * 0.03), Color("#f1e4c8"), 0.01)
			# 墙上的旧水渍/血迹
			var stain := ART.plane(self, "WallStain", Vector2(1.1, 0.62), Vector3(x - 1.1, y + 1.2, z - side * 0.02), Color("#6b5b48"), true, 0.02)
			stain.rotation_degrees.x = 90.0
	# 走廊吊顶只保留结构梁；18 m 长管线会穿过门楣/楼梯口，已移除。
	for x: float in [-4.0, 0.0, 4.0, 8.0]:
		ART.block(self, "CeilingBeam", Vector3(0.18, 0.16, 2.5), Vector3(x, y + 2.92, 0.0), Color("#b9ae98"), 0.02)
	# 走廊保持净空：担架/轮椅/输液架移进房间，不再横在走廊中间。


func _lobby(y: float) -> void:
	# 接待台保留，但取消其后方半身高黑色挡板，避免遮挡和误穿。
	_desk(Vector3(-3.2, y, 4.0), 0.0)
	# 进门左手（西墙）楼梯间导向牌：楼梯入口在 1F 北侧。
	_sign_plate("res://assets/ruin/signs/hospital_stairs.png", Vector3(-11.60, y + 1.55, 6.9), Vector2(2.8, 0.79), PI * 0.5)
	# 候诊椅
	for index: int in 4:
		_chair(Vector3(-4.5 + float(index) * 1.2, y, 6.2), PI)
		_chair(Vector3(-4.5 + float(index) * 1.2, y, 7.0), PI)
	for index: int in 3:
		_chair(Vector3(1.0 + float(index) * 1.2, y, 6.4), 0.0)
	# 轮椅、担架和地上的血迹
	ART.block(self, "LobbyGuide", Vector3(0.42, 0.012, 6.2), Vector3(0.0, y + 0.02, 4.8), Color("#3f514c"), 0.0)
	_wheelchair(Vector3(5.8, y, 5.2), 20.0)
	_gurney(Vector3(5.2, y, 3.0), -8.0)
	_blood_trail(Vector3(0.2, y + 0.012, 7.8), Vector3(0.0, y + 0.012, 2.0), 8, 1.0)
	ART.block(self, "LobbyBench", Vector3(4.2, 0.18, 0.7), Vector3(4.8, y + 0.45, 8.0), COLOR_BENCH(), 0.04)
	ART.block(self, "LobbyBenchBack", Vector3(4.2, 0.7, 0.16), Vector3(4.8, y + 0.8, 8.27), COLOR_BENCH(), 0.04)
	_collider(Vector3(4.2, 0.8, 0.7), Vector3(4.8, y + 0.4, 8.0))
	# 入口导视：先告诉玩家各科室和楼梯在哪，而不是只给一句“去配电间”。
	ART.block(self, "HospitalDirectoryPost", Vector3(0.12, 1.35, 0.12), Vector3(6.0, y + 0.68, 6.35), STEEL_DARK, 0.02)
	_sign_plate("res://assets/ruin/signs/hospital_directory.png", Vector3(6.0, y + 1.55, 6.40), Vector2(1.9, 0.78), PI)


func COLOR_BENCH() -> Color:
	return Color("#3f6f72")


func _emergency_rooms(y: float) -> void:
	_gurney(Vector3(-3.0, y, 5.0), 0.0)
	_gurney(Vector3(2.0, y, 5.0), 8.0)
	_cabinet(Vector3(8.4, y, 7.1), 1.0)
	_iv(Vector3(-1.0, y, 4.2))
	_iv(Vector3(4.6, y, 4.2))


func _pharmacy(y: float) -> void:
	# 1F 中南角药房：铁栅窗口、药架、处方台和绿十字。
	var room_x := 2.0
	_light_panel(Vector3(2.0, y + 2.86, -5.4), Color("#d4ddd7"), 0.82, 5.4)
	_light_panel(Vector3(2.0, y + 2.86, -7.2), Color("#d4ddd7"), 0.68, 4.4)
	# 药房不再做半身高铁栅挡板，保留完全开放的柜台。
	_desk(Vector3(room_x, y, -3.6), 0.0)
	ART.block(self, "PharmacyCounter", Vector3(3.4, 1.0, 0.85), Vector3(room_x, y + 0.5, -3.55), WOOD, 0.04)
	_collider(Vector3(3.4, 1.0, 0.85), Vector3(room_x, y + 0.5, -3.55))
	ART.block(self, "PharmacySign", Vector3(1.5, 0.42, 0.07), Vector3(room_x, y + 2.65, -3.10), Color("#4f7458"), 0.02, true, 0.45)
	ART.block(self, "PharmacyCrossV", Vector3(0.16, 0.64, 0.05), Vector3(room_x, y + 2.65, -3.16), Color("#a8c9a8"), 0.01, true, 0.35)
	ART.block(self, "PharmacyCrossH", Vector3(0.52, 0.16, 0.05), Vector3(room_x, y + 2.65, -3.15), Color("#a8c9a8"), 0.01, true, 0.35)
	# 药架：三层小盒子，颜色分化但整体脏。
	var colors := [Color("#8a6b4b"), Color("#6b8071"), Color("#9a5a4d"), Color("#6c7c88")]
	for row: int in 3:
		ART.block(self, "PharmacyShelf_%d" % row, Vector3(3.9, 0.10, 0.55), Vector3(room_x, y + 1.1 + float(row) * 0.55, -7.7), METAL, 0.03)
		for col: int in 6:
			var color: Color = colors[(row + col) % colors.size()]
			ART.block(self, "MedicineBox", Vector3(0.42, 0.30, 0.36), Vector3(0.55 + float(col) * 0.6, y + 1.34 + float(row) * 0.55, -7.7), color, 0.02)
	ART.block(self, "PharmacyFridge", Vector3(1.2, 1.8, 0.8), Vector3(4.2, y + 0.9, -6.8), Color("#6c8382"), 0.04)
	ART.block(self, "PharmacyFridgeDoor", Vector3(0.95, 1.5, 0.05), Vector3(4.2, y + 0.9, -6.38), GLASS, 0.02, true, 0.12)
	_chair(Vector3(0.9, y, -2.3), PI)
	_chair(Vector3(1.7, y, -2.3), PI)


func _basement_pharmacy(y: float) -> void:
	# B1 地下药库：不做门/铁笼，冷柜和低温稳定剂直接可达。
	_light_panel(Vector3(2.0, y + 2.86, -5.4), Color("#c6d9d5"), 0.85, 5.4)
	ART.block(self, "ColdStorage", Vector3(1.8, 2.15, 1.0), Vector3(2.0, y + 1.08, -7.65), Color("#526b69"), 0.05)
	_collider(Vector3(1.8, 2.15, 1.0), Vector3(2.0, y + 1.08, -7.65))
	ART.block(self, "ColdStorageGlass", Vector3(1.4, 1.55, 0.05), Vector3(2.0, y + 1.12, -7.11), GLASS, 0.02, true, 0.18)
	_sign_plate("res://assets/ruin/signs/hospital_pharmacy.png", Vector3(2.0, y + 1.95, -8.34), Vector2(1.5, 0.52), 0.0)
	ART.block(self, "ColdStorageShelf", Vector3(1.3, 0.04, 0.1), Vector3(2.0, y + 0.72, -7.08), Color("#aabbb6"), 0.01)
	for index: int in 3:
		ART.cylinder(self, "ColdVial", 0.07, 0.28, Vector3(1.55 + float(index) * 0.45, y + 0.9, -7.08), Color("#9ad8d2"), true, 0.35)
	ART.block(self, "PharmacyCounter", Vector3(2.8, 0.92, 0.9), Vector3(2.0, y + 0.46, -5.55), WOOD, 0.04)
	_collider(Vector3(2.8, 1.0, 0.9), Vector3(2.0, y + 0.5, -5.55))

	# 任务物：低温稳定剂，放在柜台前缘的独立处置盒里，避免嵌进柜台碰撞体。
	var stabilizer := _register_task_item("coolant_stabilizer", Vector3(2.0, y + 1.0, -4.7), Color("#8fe0d4"))
	ART.block(stabilizer, "StabilizerCase", Vector3(0.45, 0.22, 0.32), Vector3(0.0, 0.0, 0.0), Color("#536b69"), 0.03)
	ART.cylinder(stabilizer, "StabilizerVial", 0.085, 0.34, Vector3(0.0, 0.25, 0.0), Color("#b9ece5"), true, 0.45)
	ART.block(stabilizer, "StabilizerCap", Vector3(0.14, 0.07, 0.14), Vector3(0.0, 0.44, 0.0), AMBER, 0.01)
	ART.block(stabilizer, "StabilizerTag", Vector3(0.20, 0.10, 0.03), Vector3(0.24, 0.08, 0.0), Color("#d9d2be"), 0.01)


func _archive_room(y: float) -> void:
	# B1 档案室：补充医院沦陷前的行政记录，和 2F 镇静观察室互相呼应。
	_light_panel(Vector3(-2.5, y + 2.86, -5.2), Color("#c9d7d2"), 0.72, 4.8)
	for index: int in 4:
		ART.block(self, "ArchiveCabinet_%d" % index, Vector3(1.0, 2.0, 0.55), Vector3(-4.2 + float(index) * 1.1, y + 1.0, -8.1), Color("#4e6663"), 0.04)
		_collider(Vector3(1.0, 2.0, 0.55), Vector3(-4.2 + float(index) * 1.1, y + 1.0, -8.1))
		for drawer: int in 3:
			ART.block(self, "ArchiveDrawer", Vector3(0.82, 0.52, 0.04), Vector3(-4.2 + float(index) * 1.1, y + 0.42 + float(drawer) * 0.58, -7.80), Color("#647b74"), 0.02)
			ART.block(self, "ArchiveHandle", Vector3(0.20, 0.04, 0.04), Vector3(-4.2 + float(index) * 1.1, y + 0.42 + float(drawer) * 0.58, -7.76), AMBER, 0.01)
	_desk(Vector3(-2.6, y, -4.4), 0.0)
	# 档案室桌面监视器会正对入口、近距离占满视野，已取消。
	for index: int in 12:
		var paper := ART.plane(self, "ArchivePaper", Vector2(0.28, 0.20), Vector3(-4.2 + float(index % 4) * 1.1, y + 0.02, -6.2 + float(index / 4) * 0.35), Color("#b6ae9a"))
		paper.rotation_degrees.y = float(index * 29) + 8.0
	ART.block(self, "ArchiveWallChart", Vector3(2.2, 1.0, 0.05), Vector3(-2.6, y + 1.8, -7.72), Color("#8a8170"), 0.02)
	ART.block(self, "ArchiveRedMark", Vector3(0.8, 0.16, 0.02), Vector3(-2.6, y + 1.8, -7.67), Color("#8e4238"), 0.01)


func _security_office(y: float) -> void:
	# 1F 保安/行政室：门禁卡任务物。
	_light_panel(Vector3(8.0, y + 2.86, 5.0), Color("#d4ddd7"), 0.78, 5.2)
	_desk(Vector3(8.0, y, 4.0), 0.0)
	ART.block(self, "SecurityMonitor", Vector3(1.2, 0.75, 0.10), Vector3(8.0, y + 1.42, 4.35), DARK, 0.03)
	for index: int in 3:
		ART.block(self, "SecurityScreen", Vector3(0.52, 0.34, 0.03), Vector3(7.4 + float(index) * 0.6, y + 1.45, 4.28), Color("#4e8f86"), 0.01, true, 0.3)
	ART.block(self, "KeyRack", Vector3(2.4, 1.4, 0.08), Vector3(8.0, y + 1.8, 7.8), STEEL_DARK, 0.03)
	for index: int in 5:
		ART.block(self, "KeyHook", Vector3(0.06, 0.15, 0.05), Vector3(7.1 + float(index) * 0.42, y + 1.55, 7.73), AMBER, 0.01)
	ART.block(self, "SecurityRadio", Vector3(0.42, 0.20, 0.18), Vector3(9.2, y + 1.10, 4.3), DARK, 0.02)
	var card := _register_task_item("energy_access_card", Vector3(8.0, y + 1.05, 4.45), AMBER)
	ART.block(card, "AccessCard", Vector3(0.32, 0.025, 0.20), Vector3.ZERO, Color("#d8d2c0"), 0.01)
	ART.block(card, "AccessCardStripe", Vector3(0.20, 0.006, 0.04), Vector3(0.0, 0.015, -0.04), AMBER, 0.005, true, 0.3)
	ART.block(card, "AccessCardChip", Vector3(0.08, 0.008, 0.06), Vector3(-0.07, 0.018, 0.04), Color("#6f9e95"), 0.003, true, 0.25)


func _sedation_room(y: float) -> void:
	# 2F 镇静实验观察室：病床、重复打针的护士和散落病历。任务物 2。
	_light_panel(Vector3(8.0, y + 2.86, 5.0), Color("#c7d8d2"), 0.78, 5.4)
	_bed(Vector3(8.0, y, 5.2), 0.0)
	_iv(Vector3(6.6, y, 4.5))
	ART.block(self, "SedationGlass", Vector3(0.06, 1.7, 2.6), Vector3(5.08, y + 1.65, 5.0), GLASS, 0.02, true, 0.10)
	_collider(Vector3(0.06, 1.7, 2.6), Vector3(5.08, y + 1.65, 5.0))
	for index: int in 4:
		ART.block(self, "SedationGlassFrame", Vector3(0.05, 1.8, 0.08), Vector3(5.03, y + 1.65, 3.7 + float(index) * 0.87), METAL, 0.01)
	# 观察室只保留病历/托盘等可对话取物线索，不放任何护士 NPC 实体。
	ART.block(self, "SedationTray", Vector3(0.7, 0.08, 0.35), Vector3(7.0, y + 1.25, 5.0), METAL, 0.02)
	ART.block(self, "SedationMonitor", Vector3(0.55, 0.44, 0.10), Vector3(9.7, y + 1.5, 6.8), DARK, 0.02)
	ART.block(self, "SedationMonitorGlow", Vector3(0.40, 0.28, 0.04), Vector3(9.7, y + 1.5, 6.73), Color("#6fbfb2"), 0.01, true, 0.32)
	_desk(Vector3(9.8, y, 2.7), 0.0)
	for index: int in 8:
		var paper := ART.plane(self, "SedationPaper", Vector2(0.30, 0.22), Vector3(6.2 + float(index % 4) * 0.7, y + 0.02, 3.0 + float(index / 4) * 0.45), Color("#b9b09b"))
		paper.rotation_degrees.y = float(index * 37) + 12.0
	var records := _register_task_item("patient_records", Vector3(9.8, y + 1.0, 2.7), Color("#d8cfb8"))
	ART.block(records, "RecordsFolder", Vector3(0.42, 0.06, 0.30), Vector3.ZERO, Color("#b8aa8d"), 0.01)
	ART.block(records, "RecordsPaper", Vector3(0.34, 0.015, 0.24), Vector3(0.03, 0.04, 0.0), Color("#ded5c0"), 0.005)
	ART.block(records, "RecordsTab", Vector3(0.12, 0.02, 0.05), Vector3(0.14, 0.05, 0.0), Color("#8e4e42"), 0.005)


func _register_task_item(item_id: String, point: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "HospitalTask_" + item_id
	root.position = point
	add_child(root)
	_task_items[item_id] = root
	_task_points[item_id] = point
	var glow := ART.sphere(root, "TaskGlow", Vector3(0.10, 0.10, 0.10), Vector3(0.0, 0.28, 0.0), color, true, 0.55)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func _outpatient(y: float) -> void:
	# 2F 门诊：签到台、候诊椅、导诊牌和分诊秤。
	_light_panel(Vector3(2.0, y + 2.86, 6.2), Color("#c9d8cd"), 0.76, 5.2)
	_desk(Vector3(2.0, y, 3.9), 0.0)
	ART.block(self, "OutpatientSign", Vector3(1.7, 0.38, 0.06), Vector3(2.0, y + 2.45, 3.34), Color("#4f6f7b"), 0.02, true, 0.28)
	for index: int in 3:
		_chair(Vector3(1.0 + float(index) * 1.2, y, 6.3), 0.0)
	ART.block(self, "TriageScale", Vector3(0.62, 0.10, 0.62), Vector3(4.2, y + 0.12, 3.2), METAL, 0.02)
	ART.block(self, "TriageColumn", Vector3(0.14, 1.5, 0.14), Vector3(4.2, y + 0.85, 3.2), METAL, 0.02)
	ART.block(self, "TriageDial", Vector3(0.42, 0.22, 0.08), Vector3(4.2, y + 1.55, 3.15), DARK, 0.01)
	ART.block(self, "OutpatientBoard", Vector3(2.2, 1.0, 0.06), Vector3(8.0, y + 1.75, 1.48), Color("#6f7c72"), 0.02)
	for index: int in 3:
		ART.block(self, "OutpatientNotice", Vector3(0.52, 0.34, 0.02), Vector3(7.3 + float(index) * 0.7, y + 1.8, 1.44), Color("#b8ad96"), 0.01)


func _exam_rooms(y: float) -> void:
	# 门诊检查室：检查床、隔帘、器械柜、洗手池和监护仪。
	_light_panel(Vector3(2.0, y + 2.86, 5.0), Color("#c9d8cd"), 0.76, 5.2)
	_light_panel(Vector3(7.0, y + 2.86, -5.0), Color("#c9d8cd"), 0.76, 5.2)
	for position: Vector3 in [Vector3(-3.0, y, 5.0), Vector3(2.0, y, 5.0), Vector3(7.0, y, -5.0)]:
		_gurney(position, 0.0)
		_iv(position + Vector3(-1.2, 0.0, 0.5))
		_cabinet(position + Vector3(1.5, 0.0, 1.0), 0.7)
		_curtain(position + Vector3(0.0, 1.9, -1.0), 2.2)
	ART.block(self, "ExamMonitor", Vector3(0.72, 0.52, 0.12), Vector3(3.0, y + 1.35, 7.8), DARK, 0.02)
	ART.block(self, "ExamMonitorGlow", Vector3(0.56, 0.36, 0.04), Vector3(3.0, y + 1.35, 7.73), Color("#6fb8b1"), 0.01, true, 0.28)
	ART.block(self, "ExamSink", Vector3(1.0, 0.18, 0.55), Vector3(-4.2, y + 0.92, 2.1), Color("#b9c4bf"), 0.03)
	ART.cylinder(self, "ExamTap", 0.025, 0.35, Vector3(-4.2, y + 1.15, 2.0), METAL)
	ART.block(self, "ExamScreen", Vector3(1.4, 1.7, 0.06), Vector3(7.8, y + 1.15, 2.2), Color("#4f6a68"), 0.03)
	for index: int in 5:
		ART.plane(self, "ExamPaper", Vector2(0.28, 0.20), Vector3(-1.5 + float(index) * 0.8, y + 0.02, 3.0 + float(index % 2) * 0.3), Color("#b8b09e")).rotation_degrees.y = float(index) * 38.0


func _wards(y: float) -> void:
	var x_positions: Array[float] = [-3.6, 2.0, 8.0]
	for x: float in x_positions:
		_bed(Vector3(x, y, 5.0), 0.0)
		_bed(Vector3(x, y, -5.0), PI)
		_cabinet(Vector3(x + 1.25, y, 6.5), 0.7)
		_iv(Vector3(x - 0.85, y, 4.4))
	for index: int in 2:
		_curtain(Vector3(-4.0 + float(index) * 6.0, y + 1.9, 3.2), 2.4)


func _nurse_station(y: float) -> void:
	# 护士台移到东侧凹位，不再横在中央走廊。
	_desk(Vector3(10.4, y, 0.2), 0.0)
	ART.block(self, "NurseMonitor", Vector3(0.7, 0.55, 0.1), Vector3(10.4, y + 1.25, -0.2), DARK, 0.03)
	ART.block(self, "NurseMonitorGlow", Vector3(0.55, 0.40, 0.04), Vector3(10.4, y + 1.25, -0.26), Color("#67c9b7"), 0.02, true, 0.38)


func _operating_room(y: float) -> void:
	ART.block(self, "ORTileBand", Vector3(8.4, 0.02, 0.32), Vector3(2.0, y + 0.015, 2.6), Color("#5f8f86"), 0.01)
	_surgical_table(Vector3(2.0, y, 5.4))
	_surgical_lamp(Vector3(2.0, y + 2.75, 5.4))
	_cabinet(Vector3(-2.4, y, 7.0), 1.1)
	ART.block(self, "ORMonitor", Vector3(1.1, 0.76, 0.12), Vector3(6.8, y + 1.45, 7.4), DARK, 0.03)
	ART.block(self, "ORMonitorGlow", Vector3(0.86, 0.52, 0.04), Vector3(6.8, y + 1.45, 7.32), Color("#6fd7c3"), 0.02, true, 0.34)
	ART.block(self, "ORTray", Vector3(1.4, 0.10, 0.65), Vector3(-0.8, y + 1.0, 4.1), METAL, 0.03)
	for index: int in 4:
		ART.block(self, "Instrument", Vector3(0.05, 0.04, 0.28), Vector3(-1.25 + float(index) * 0.30, y + 1.08, 4.1), Color("#cdd7d0"), 0.01)


func _icu(y: float) -> void:
	for x: float in [-3.5, 2.0, 7.5]:
		_bed(Vector3(x, y, -5.0), PI)
		_iv(Vector3(x - 1.3, y, -4.3))
		ART.block(self, "ICUMonitor", Vector3(0.5, 0.42, 0.12), Vector3(x + 1.0, y + 1.25, -3.6), DARK, 0.02)
		ART.block(self, "ICUMonitorGlow", Vector3(0.36, 0.26, 0.04), Vector3(x + 1.0, y + 1.25, -3.55), Color("#6fd7c3"), 0.01, true, 0.30)


func _imaging(y: float) -> void:
	ART.block(self, "XRayMachine", Vector3(1.8, 2.2, 0.55), Vector3(-3.0, y + 1.1, -6.8), Color("#7e8c8c"), 0.06)
	_collider(Vector3(1.8, 2.2, 0.55), Vector3(-3.0, y + 1.1, -6.8))
	ART.block(self, "XRayBed", Vector3(2.6, 0.18, 0.9), Vector3(-3.0, y + 0.55, -5.2), METAL, 0.04)
	_collider(Vector3(2.6, 0.8, 0.9), Vector3(-3.0, y + 0.4, -5.2))
	ART.block(self, "XRayPanel", Vector3(1.25, 1.35, 0.08), Vector3(-3.0, y + 1.55, -6.43), GLASS, 0.02, true, 0.18)
	_cabinet(Vector3(3.8, y, -7.0), 0.8)


func _morgue(y: float) -> void:
	# 太平间抽屉墙
	ART.block(self, "MorgueWall", Vector3(6.4, 2.5, 0.35), Vector3(-3.8, y + 1.25, 7.7), Color("#4b5b5b"), 0.05)
	_collider(Vector3(6.4, 2.5, 0.35), Vector3(-3.8, y + 1.25, 7.7))
	for row: int in 3:
		for col: int in 5:
			var drawer := ART.block(self, "MorgueDrawer", Vector3(1.2, 0.64, 0.10), Vector3(-6.4 + float(col) * 1.2, y + 0.55 + float(row) * 0.74, 7.48), Color("#7b8788"), 0.03)
			drawer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ART.block(self, "DrawerHandle", Vector3(0.36, 0.05, 0.05), Vector3(-6.4 + float(col) * 1.2, y + 0.55 + float(row) * 0.74, 7.40), METAL, 0.01)
	_gurney(Vector3(4.0, y, 5.0), 0.0)
	_gurney(Vector3(6.5, y, 5.2), 14.0)
	ART.block(self, "Drain", Vector3(0.45, 0.02, 0.45), Vector3(2.0, y + 0.015, 4.6), DARK, 0.01)
	_blood_trail(Vector3(4.2, y + 0.012, 4.0), Vector3(2.2, y + 0.012, 2.0), 5, 0.8)


func _boiler(y: float) -> void:
	ART.block(self, "Boiler", Vector3(2.4, 2.3, 1.8), Vector3(7.5, y + 1.15, -5.5), Color("#5b6460"), 0.08)
	for index: int in 3:
		ART.cylinder(self, "BoilerPipe", 0.12, 2.0, Vector3(6.2 - float(index) * 0.35, y + 2.3, -5.5), RUST)
	ART.block(self, "BoilerPanel", Vector3(0.7, 0.6, 0.08), Vector3(7.5, y + 1.35, -4.56), DARK, 0.02)
	_cabinet(Vector3(2.5, y, -7.0), 0.8)


# ── 小陈设 ───────────────────────────────────────────────────

func _bed(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "HospitalBed"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Frame", Vector3(1.95, 0.22, 0.92), Vector3(0.0, 0.46, 0.0), METAL, 0.04)
	ART.block(root, "Mattress", Vector3(1.82, 0.18, 0.82), Vector3(0.0, 0.62, 0.0), LINEN, 0.06)
	ART.block(root, "Pillow", Vector3(0.52, 0.14, 0.52), Vector3(0.0, 0.76, 0.26), Color("#f2ecdf"), 0.04)
	ART.block(root, "Headboard", Vector3(1.95, 0.9, 0.10), Vector3(0.0, 0.88, 0.44), Color("#789a95"), 0.04)
	for side: float in [-1.0, 1.0]:
		ART.cylinder(root, "BedLeg", 0.05, 0.36, Vector3(side * 0.78, 0.22, side * 0.34), METAL)
	ART.block(root, "BedRail", Vector3(0.08, 0.08, 0.72), Vector3(-0.88, 0.78, 0.0), METAL, 0.02)
	_collider(Vector3(1.95, 0.55, 0.92), at + Vector3(0.0, 0.30, 0.0), Vector3(0.0, yaw_degrees, 0.0))


func _gurney(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "Gurney"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Frame", Vector3(1.9, 0.12, 0.72), Vector3(0.0, 0.56, 0.0), METAL, 0.03)
	ART.block(root, "Pad", Vector3(1.75, 0.16, 0.62), Vector3(0.0, 0.68, 0.0), Color("#b9c8bf"), 0.04)
	for side: float in [-1.0, 1.0]:
		ART.cylinder(root, "Pole", 0.035, 0.56, Vector3(side * 0.78, 0.28, 0.0), METAL)
		ART.torus(root, "Wheel", 0.09, 0.13, Vector3(side * 0.78, 0.12, 0.18), DARK)
		ART.torus(root, "Wheel", 0.09, 0.13, Vector3(side * 0.78, 0.12, -0.18), DARK)
	_collider(Vector3(1.8, 0.6, 0.72), at + Vector3(0.0, 0.3, 0.0), Vector3(0.0, yaw_degrees, 0.0))


func _chair(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "WaitingChair"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Seat", Vector3(0.56, 0.10, 0.52), Vector3(0.0, 0.45, 0.0), COLOR_BENCH(), 0.03)
	ART.block(root, "Back", Vector3(0.56, 0.52, 0.10), Vector3(0.0, 0.72, 0.24), COLOR_BENCH(), 0.03)
	for side: float in [-1.0, 1.0]:
		ART.cylinder(root, "Leg", 0.025, 0.44, Vector3(side * 0.22, 0.22, 0.18), METAL)


func _wheelchair(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "Wheelchair"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Seat", Vector3(0.55, 0.08, 0.52), Vector3(0.0, 0.48, 0.0), Color("#3f6f72"), 0.03)
	ART.block(root, "Back", Vector3(0.55, 0.62, 0.08), Vector3(0.0, 0.78, 0.24), Color("#3f6f72"), 0.03)
	for side: float in [-1.0, 1.0]:
		ART.torus(root, "Wheel", 0.20, 0.25, Vector3(side * 0.33, 0.26, 0.0), DARK)
		ART.cylinder(root, "Arm", 0.025, 0.5, Vector3(side * 0.30, 0.68, 0.05), METAL)


func _iv(at: Vector3) -> void:
	ART.cylinder(self, "IVPole", 0.025, 1.65, at + Vector3(0.0, 0.82, 0.0), METAL)
	ART.sphere(self, "IVBag", Vector3(0.18, 0.24, 0.12), at + Vector3(0.0, 1.62, 0.0), Color("#a9d7c3"))


func _cabinet(at: Vector3, width: float) -> void:
	ART.block(self, "Cabinet", Vector3(width, 1.65, 0.55), at + Vector3(0.0, 0.82, 0.0), Color("#6f8c86"), 0.04)
	_collider(Vector3(width, 1.65, 0.55), at + Vector3(0.0, 0.82, 0.0))
	ART.block(self, "CabinetDoor", Vector3(width * 0.86, 1.35, 0.05), at + Vector3(0.0, 0.82, -0.30), Color("#4f6e6a"), 0.02)
	ART.block(self, "CabinetHandle", Vector3(0.12, 0.05, 0.05), at + Vector3(width * 0.25, 0.95, -0.34), METAL, 0.01)


func _desk(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "ReceptionDesk"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "DeskTop", Vector3(2.8, 0.14, 0.9), Vector3(0.0, 0.95, 0.0), WOOD, 0.04)
	ART.block(root, "DeskFront", Vector3(2.8, 0.9, 0.18), Vector3(0.0, 0.48, -0.36), Color("#748682"), 0.04)
	ART.block(root, "DeskSide", Vector3(0.18, 0.9, 0.9), Vector3(1.31, 0.48, 0.0), Color("#748682"), 0.04)
	_collider(Vector3(2.8, 1.0, 0.9), at + Vector3(0.0, 0.5, 0.0), Vector3(0.0, yaw_degrees, 0.0))


func _surgical_table(at: Vector3) -> void:
	ART.block(self, "SurgicalBase", Vector3(1.0, 0.55, 0.7), at + Vector3(0.0, 0.28, 0.0), METAL, 0.04)
	ART.block(self, "SurgicalTable", Vector3(2.4, 0.18, 0.9), at + Vector3(0.0, 0.72, 0.0), Color("#c8d2c9"), 0.05)
	ART.block(self, "SurgicalPad", Vector3(2.25, 0.12, 0.78), at + Vector3(0.0, 0.86, 0.0), Color("#c2d6cc"), 0.05)
	_collider(Vector3(2.4, 0.8, 0.9), at + Vector3(0.0, 0.45, 0.0))


func _surgical_lamp(at: Vector3) -> void:
	ART.cylinder(self, "LampArm", 0.045, 0.9, at + Vector3(0.0, 0.45, 0.0), METAL)
	ART.cylinder(self, "LampHead", 0.52, 0.18, at + Vector3(0.0, 0.0, 0.0), Color("#d9e7db"), 0.04)
	ART.cylinder(self, "LampGlow", 0.43, 0.05, at + Vector3(0.0, -0.10, 0.0), Color("#effff4"), true, 0.82)
	var light := OmniLight3D.new()
	light.light_color = Color("#effff4")
	light.light_energy = 1.10
	light.omni_range = 5.0
	light.position = at + Vector3(0.0, -0.25, 0.0)
	light.shadow_enabled = false
	add_child(light)


func _curtain(at: Vector3, width: float) -> void:
	ART.block(self, "Curtain", Vector3(width, 1.6, 0.04), at, Color("#b7cfc4"), 0.02)
	ART.cylinder(self, "CurtainRail", 0.02, width, at + Vector3(0.0, 0.82, 0.0), METAL)


func _debris(y: float, level: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 711 + level * 97
	for index: int in 8:
		var x := rng.randf_range(-6.0, 10.5)
		var z := rng.randf_range(-7.5, 7.5)
		if absf(z) < 1.6:
			continue
		ART.block(self, "Debris", Vector3(rng.randf_range(0.10, 0.26), 0.04, rng.randf_range(0.12, 0.30)), Vector3(x, y + 0.03, z), Color("#b9ad95"), 0.01).rotation_degrees.y = rng.randf_range(0.0, 180.0)
	ART.block(self, "WetFloor", Vector3(1.2, 0.012, 0.7), Vector3(-2.0, y + 0.02, 2.0), Color("#5e7772"), 0.01)


func _blood_trail(from: Vector3, to: Vector3, count: int, scale_value: float) -> void:
	for index: int in count:
		var t := float(index) / float(maxi(count - 1, 1))
		var point := from.lerp(to, t)
		ART.plane(self, "Blood", Vector2(0.55, 0.32) * scale_value, point, BLOOD, true, 0.05).rotation_degrees.y = float(index) * 31.0


func _floor_dressing(level: int, y: float) -> void:
	# 走廊导向色带：每层不同颜色，替代悬浮文字。
	var colors := [RED, Color("#6ba7b8"), Color("#78a88a"), Color("#d59a5b")]
	var color: Color = colors[level]
	ART.block(self, "FloorBand", Vector3(18.6, 0.012, 0.16), Vector3(2.6, y + 0.015, 0.88), color, 0.01)
	ART.block(self, "FloorBand", Vector3(18.6, 0.012, 0.16), Vector3(2.6, y + 0.015, -0.88), color, 0.01)
	for x: float in [-3.0, 0.0, 3.0, 6.0, 9.0]:
		ART.plane(self, "FloorGrout", Vector2(0.035, 17.0), Vector3(x, y + 0.006, 0.0), FLOOR_GROUT).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for z: float in [-6.0, -3.0, 3.0, 6.0]:
		ART.plane(self, "FloorGrout", Vector2(19.0, 0.035), Vector3(2.5, y + 0.006, z), FLOOR_GROUT).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 楼层色块与门牌
	ART.block(self, "FloorPlate", Vector3(1.2, 0.5, 0.05), Vector3(STAIR_X1 + 0.16, y + 2.2, 0.0), color, 0.02, true, 0.22)


func _build_elevator() -> void:
	# 东侧停用电梯：只做门、呼叫灯和警示色，不实现乘坐。
	ART.block(self, "ElevatorFrame", Vector3(2.2, 2.5, 0.22), Vector3(10.5, FLOOR_HEIGHT + 1.25, -7.2), METAL, 0.05)
	ART.block(self, "ElevatorDoorL", Vector3(0.95, 2.2, 0.08), Vector3(10.05, FLOOR_HEIGHT + 1.1, -7.05), Color("#7c8b89"), 0.02)
	ART.block(self, "ElevatorDoorR", Vector3(0.95, 2.2, 0.08), Vector3(10.95, FLOOR_HEIGHT + 1.1, -7.05), Color("#7c8b89"), 0.02)
	ART.block(self, "ElevatorCall", Vector3(0.18, 0.28, 0.06), Vector3(11.8, FLOOR_HEIGHT + 1.2, -6.95), DARK, 0.01)
	ART.sphere(self, "ElevatorLight", Vector3(0.05, 0.05, 0.03), Vector3(11.8, FLOOR_HEIGHT + 1.28, -6.9), RED, true, 0.4)
	ART.block(self, "ElevatorBand", Vector3(2.3, 0.16, 0.24), Vector3(10.5, FLOOR_HEIGHT + 2.55, -7.2), Color("#d9a15b"), 0.02, true, 0.25)


func _collider(size: Vector3, center: Vector3, rotation_degrees_value := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = "HospitalCollision"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = center
	body.rotation_degrees = rotation_degrees_value
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
