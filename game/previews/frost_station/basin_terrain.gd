extends Node3D
class_name FrostBasinTerrain

## 霜烬星 2.5 · 1040×1160m 超大极地盆地程序化地形（容纳 16 座大型建筑群 + 四向远征地标）
## - 中心极地科考城平场（X ∈ [-195..195], Z ∈ [-192..78]）完全平整，承载 15 栋大型建筑 + 飞船 + 宽阔极地车大道。
## - 东线盘山公路爬升至 +16m 气象雷达高地（X=325, Z=-75），西线跨越大冰缝钢桥（X=-255）直抵坠毁探测舱（X=-340, Z=-90）。
## - 南线延伸至极地空投雪原（X=-185, Z=165），北线深入远古巨兽骨骸峡谷（Z=-180..-660）。

const SNOW_SHADER: Shader = preload("res://shaders/frost_snow.gdshader")
const ROCK_SHADER: Shader = preload("res://shaders/frost_rock.gdshader")

const MIN_X: float = -520.0
const MAX_X: float = 520.0
const MIN_Z: float = -780.0
const MAX_Z: float = 380.0
const STEP: float = 20.0

static func sample_height(x: float, z: float) -> float:
	# 1. 超大极地科考城平场（容纳 16 座大型建筑）+ 遗迹主走廊保持 0.0 平地
	var station_dist: float = _box_sdf(Vector2(x, z), Vector2(0.0, -57.0), Vector2(195.0, 136.0))
	var ruins_dist: float = _box_sdf(Vector2(x, z), Vector2(0.0, -420.0), Vector2(48.0, 270.0))
	var flat_mask: float = clampf(minf(station_dist, ruins_dist) / 36.0, 0.0, 1.0)
	flat_mask = flat_mask * flat_mask * (3.0 - 2.0 * flat_mask)

	# 2. 外围雪原自然起伏
	var wave: float = sin(x * 0.014) * cos(z * 0.013) * 4.8 + sin(x * 0.036 + z * 0.028) * 1.85
	var h: float = wave * flat_mask

	# 3. 盆地外圈宏伟冰川山脉围合
	var rim_x: float = maxf(0.0, (absf(x) - 385.0) / 135.0)
	var rim_z_south: float = maxf(0.0, (z - 240.0) / 140.0)
	var rim_z_north: float = maxf(0.0, (-z - 670.0) / 110.0)
	var rim: float = maxf(rim_x, maxf(rim_z_south, rim_z_north))
	if rim > 0.0:
		var crag: float = 0.75 + 0.25 * sin(x * 0.055 + z * 0.048) + 0.15 * cos(x * 0.11 - z * 0.08)
		h += pow(rim, 1.65) * 56.0 * crag * flat_mask

	# 4. 东线 · 气象雷达高地（(325, -75)，海拔 +16m）+ 盘山公路缓坡
	var radar_d: float = Vector2(x - 325.0, z + 75.0).length()
	if radar_d < 105.0:
		var t: float = clampf(1.0 - (radar_d - 32.0) / 73.0, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		h = lerpf(h, 16.0, t)

	var east_road_t: Vector2 = _segment_factor(Vector2(x, z), Vector2(198.0, -40.0), Vector2(325.0, -75.0), 18.0)
	if east_road_t.x > 0.0:
		var target_h: float = lerpf(0.0, 16.0, clampf(east_road_t.y, 0.0, 1.0))
		h = lerpf(h, target_h, east_road_t.x)

	# 5. 西线 · 冻裂冰缝（X ≈ -255, 下陷 -8.5m）与坠毁轨道探测舱（(-340, -90), 海拔 +2.0m）
	var crevasse_x: float = absf(x + 255.0)
	if crevasse_x < 24.0 and z > -180.0 and z < 15.0:
		var ct: float = clampf(1.0 - crevasse_x / 24.0, 0.0, 1.0)
		ct = ct * ct * (3.0 - 2.0 * ct)
		h -= 8.5 * ct

	var pod_d: float = Vector2(x + 340.0, z + 90.0).length()
	if pod_d < 56.0:
		var pt: float = clampf(1.0 - (pod_d - 24.0) / 32.0, 0.0, 1.0)
		pt = pt * pt * (3.0 - 2.0 * pt)
		h = lerpf(h, 2.0, pt)

	if crevasse_x >= 20.0:
		var west_road_t: Vector2 = _segment_factor(Vector2(x, z), Vector2(-196.0, -68.0), Vector2(-340.0, -90.0), 16.0)
		if west_road_t.x > 0.0:
			var target_wh: float = lerpf(0.0, 2.0, clampf(west_road_t.y, 0.0, 1.0))
			h = lerpf(h, target_wh, west_road_t.x)

	# 6. 南线 · 极地补给空投雪原（(-185, 165)，海拔 +2.5m）
	var drop_d: float = Vector2(x + 185.0, z - 165.0).length()
	if drop_d < 54.0:
		var dt: float = clampf(1.0 - (drop_d - 22.0) / 32.0, 0.0, 1.0)
		dt = dt * dt * (3.0 - 2.0 * dt)
		h = lerpf(h, 2.5, dt)

	return h

static func _box_sdf(p: Vector2, center: Vector2, half_ext: Vector2) -> float:
	var d: Vector2 = (p - center).abs() - half_ext
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)

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
			var xm: float = x0 + STEP * 0.5
			var zm: float = z0 + STEP * 0.5
			# 跳过中心 16 座大型建筑科考城平地（由平整基础地坪承托，杜绝 Z-fighting）
			if absf(xm) < 194.0 and zm > -196.0 and zm < 80.0:
				continue
			if absf(xm) < 40.0 and zm < -180.0:
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
			var target_st: SurfaceTool = st_rock if (max_h > 19.0 or slope > 0.42) else st_snow

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
