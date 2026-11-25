extends Node3D
class_name FrostBasinTerrain

## 霜烬星 · 720×920m 立体极地盆地程序化地形与不规则岩脊
## - 中心科考站（[-82..82, -155..45]）与遗迹主轴保持平整可建造，无缝过渡到起伏雪原、冰峡谷与层理山脊。
## - 同步生成精确 ConcavePolygonShape3D 碰撞，支持极地运输车真实爬坡与跨盆地驾驶。
## - 东线盘山公路直达 +14m 气象雷达高地，西线跨越冻裂冰缝通往坠毁探测舱。

const SNOW_SHADER: Shader = preload("res://shaders/frost_snow.gdshader")
const ROCK_SHADER: Shader = preload("res://shaders/frost_rock.gdshader")

const MIN_X: float = -360.0
const MAX_X: float = 360.0
const MIN_Z: float = -660.0
const MAX_Z: float = 220.0
const STEP: float = 16.0

## 计算世界坐标 (x, z) 处的基准地表高度（确保站区、主路与地标平台平滑衔接）
static func sample_height(x: float, z: float) -> float:
	# 1. 中心科考城镇（11 栋建筑群）+ 降落坪 + 遗迹主走廊保持 0.0 平地
	var station_dist: float = _box_sdf(Vector2(x, z), Vector2(0.0, -64.0), Vector2(110.0, 112.0))
	var ruins_dist: float = _box_sdf(Vector2(x, z), Vector2(0.0, -400.0), Vector2(46.0, 260.0))
	var flat_mask: float = clampf(minf(station_dist, ruins_dist) / 28.0, 0.0, 1.0)
	flat_mask = flat_mask * flat_mask * (3.0 - 2.0 * flat_mask)

	# 2. 自然雪原波浪起伏
	var wave: float = sin(x * 0.017) * cos(z * 0.015) * 4.2 + sin(x * 0.043 + z * 0.031) * 1.65
	var h: float = wave * flat_mask

	# 3. 盆地外围天然冰川山脊围合（替代旧版旋转方盒）
	var rim_x: float = maxf(0.0, (absf(x) - 245.0) / 115.0)
	var rim_z_south: float = maxf(0.0, (z - 125.0) / 95.0)
	var rim_z_north: float = maxf(0.0, (-z - 595.0) / 65.0)
	var rim: float = maxf(rim_x, maxf(rim_z_south, rim_z_north))
	if rim > 0.0:
		var crag: float = 0.75 + 0.25 * sin(x * 0.065 + z * 0.052) + 0.15 * cos(x * 0.13 - z * 0.09)
		h += pow(rim, 1.65) * 48.0 * crag * flat_mask

	# 4. 东线 · 气象雷达高地（中心 (215, -75)，平台高度 +14m）
	var radar_d: float = Vector2(x - 215.0, z + 75.0).length()
	if radar_d < 95.0:
		var t: float = clampf(1.0 - (radar_d - 28.0) / 67.0, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		h = lerpf(h, 14.0, t)

	# 东线盘山公路缓坡平滑插值（从 (112, -32) 爬升至 (215, -75)，避开通讯塔平地）
	var east_road_t: Vector2 = _segment_factor(Vector2(x, z), Vector2(112.0, -32.0), Vector2(215.0, -75.0), 16.0)
	if east_road_t.x > 0.0:
		var target_h: float = lerpf(0.0, 14.0, clampf(east_road_t.y, 0.0, 1.0))
		h = lerpf(h, target_h, east_road_t.x)

	# 5. 西线 · 冻裂冰缝（X ≈ -135, Z ∈ [-150, -35] 下陷 -7.5m，桥面跨越）与坠毁探测舱盆地（(-210, -90), 高度 +1.5m）
	var crevasse_x: float = absf(x + 135.0)
	if crevasse_x < 22.0 and z > -165.0 and z < -25.0:
		var ct: float = clampf(1.0 - crevasse_x / 22.0, 0.0, 1.0)
		ct = ct * ct * (3.0 - 2.0 * ct)
		h -= 7.5 * ct

	var pod_d: float = Vector2(x + 210.0, z + 90.0).length()
	if pod_d < 52.0:
		var pt: float = clampf(1.0 - (pod_d - 20.0) / 32.0, 0.0, 1.0)
		pt = pt * pt * (3.0 - 2.0 * pt)
		h = lerpf(h, 1.5, pt)

	# 西线公路平滑（从 (-72, -55) 至 (-210, -90)，避开冰缝深沟由钢桥承托）
	if crevasse_x >= 18.0:
		var west_road_t: Vector2 = _segment_factor(Vector2(x, z), Vector2(-72.0, -55.0), Vector2(-210.0, -90.0), 14.0)
		if west_road_t.x > 0.0:
			var target_wh: float = lerpf(0.0, 1.5, clampf(west_road_t.y, 0.0, 1.0))
			h = lerpf(h, target_wh, west_road_t.x)

	# 6. 南线 · 补给空投雪原（(-115, 85)，平缓 +2.5m）
	var drop_d: float = Vector2(x + 115.0, z - 85.0).length()
	if drop_d < 48.0:
		var dt: float = clampf(1.0 - (drop_d - 18.0) / 30.0, 0.0, 1.0)
		dt = dt * dt * (3.0 - 2.0 * dt)
		h = lerpf(h, 2.5, dt)

	return h

static func _box_sdf(p: Vector2, center: Vector2, half_ext: Vector2) -> float:
	var d: Vector2 = (p - center).abs() - half_ext
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)

## 返回 Vector2(平滑权重 0..1, 沿线段进度 0..1)
static func _segment_factor(p: Vector2, a: Vector2, b: Vector2, half_width: float) -> Vector2:
	var ab: Vector2 = b - a
	var len_sq: float = maxf(ab.length_squared(), 0.001)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var proj: Vector2 = a + ab * t
	var dist: float = p.distance_to(proj)
	if dist >= half_width * 1.8:
		return Vector2(0.0, t)
	var w: float = clampf(1.0 - (dist - half_width * 0.5) / (half_width * 1.3), 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	return Vector2(w, t)

func build() -> void:
	name = "PolarBasinTerrain"
	var cols: int = int((MAX_X - MIN_X) / STEP)
	var rows: int = int((MAX_Z - MIN_Z) / STEP)

	var st_snow: SurfaceTool = SurfaceTool.new()
	st_snow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_rock: SurfaceTool = SurfaceTool.new()
	st_rock.begin(Mesh.PRIMITIVE_TRIANGLES)

	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize((cols + 1) * (rows + 1))
	for iz: int in range(rows + 1):
		var z: float = MIN_Z + float(iz) * STEP
		for ix: int in range(cols + 1):
			var x: float = MIN_X + float(ix) * STEP
			heights[iz * (cols + 1) + ix] = sample_height(x, z)

	for iz: int in range(rows):
		for ix: int in range(cols):
			var x0: float = MIN_X + float(ix) * STEP
			var z0: float = MIN_Z + float(iz) * STEP
			# 跳过中心平地内部（覆盖 11 栋站区建筑群，保留精细地面与碰撞，避免 Z-fighting）
			if absf(x0 + STEP * 0.5) < 108.0 and z0 + STEP * 0.5 > -168.0 and z0 + STEP * 0.5 < 36.0:
				continue
			# 跳过遗迹洞厅内部正下方
			if absf(x0 + STEP * 0.5) < 38.0 and z0 + STEP * 0.5 < -180.0:
				continue

			var h00: float = heights[iz * (cols + 1) + ix]
			var h10: float = heights[iz * (cols + 1) + ix + 1]
			var h01: float = heights[(iz + 1) * (cols + 1) + ix]
			var h11: float = heights[(iz + 1) * (cols + 1) + ix + 1]

			var v00: Vector3 = Vector3(x0, h00, z0)
			var v10: Vector3 = Vector3(x0 + STEP, h10, z0)
			var v01: Vector3 = Vector3(x0, h01, z0 + STEP)
			var v11: Vector3 = Vector3(x0 + STEP, h11, z0 + STEP)

			var max_h: float = maxf(maxf(h00, h10), maxf(h01, h11))
			var slope: float = maxf(absf(h10 - h00), absf(h01 - h00)) / STEP
			var target_st: SurfaceTool = st_rock if (max_h > 17.5 or slope > 0.42) else st_snow

			target_st.add_vertex(v00)
			target_st.add_vertex(v10)
			target_st.add_vertex(v11)

			target_st.add_vertex(v00)
			target_st.add_vertex(v11)
			target_st.add_vertex(v01)

	_commit_surface("BasinSnowSurface", st_snow, _snow_material())
	_commit_surface("BasinRockRidges", st_rock, _rock_material())

func _commit_surface(node_name: String, st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	var arr_mesh: ArrayMesh = st.commit()
	if arr_mesh == null or arr_mesh.get_surface_count() == 0:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = arr_mesh
	mi.material_override = mat
	add_child(mi)

	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name + "Collision"
	body.collision_layer = 2
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = arr_mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)

func _snow_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SNOW_SHADER
	return mat

func _rock_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	return mat
