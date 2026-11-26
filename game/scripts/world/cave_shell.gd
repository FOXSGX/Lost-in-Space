class_name CaveShell
extends RefCounted

## Procedural cavern shells with exact trimesh collision.
## The hall wall/dome and the entrance tunnel are single continuous surfaces, so
## there are no invisible boundary planes and no seams between decorative rocks.

static func hall(kit: WorldKit, center: Vector3, radius: float, wall_height: float, dome_height: float, portal_angle: float, portal_half: float, portal_y_min: float, portal_y_max: float, exit_angle: float, exit_half: float, exit_y_max: float) -> MeshInstance3D:
	var segments: int = 112
	var rows: int = 26
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for row in range(rows + 1):
		var ring: Array[Vector3] = []
		var height_ratio: float = float(row) / float(rows)
		var y: float
		var r: float
		if height_ratio <= 0.62:
			var t: float = height_ratio / 0.62
			y = wall_height * t
			r = radius * (1.0 + 0.055 * sin(t * 2.2 + 0.4))
		else:
			var t2: float = (height_ratio - 0.62) / 0.38
			var theta: float = t2 * PI * 0.5
			y = wall_height + sin(theta) * dome_height
			r = radius * pow(cos(theta), 0.78)
		for s in range(segments + 1):
			var a: float = TAU * float(s) / float(segments)
			# Only displace outwards. The shell is the collision backstop behind
			# the detailed wall panels; inward noise used to poke the smooth
			# shell through the panels and create a hidden wall in front of the
			# visible rock.
			var n: float = (
				0.030 * sin(a * 3.0 + 0.7)
				+ 0.022 * sin(a * 7.0 + 1.9)
				+ 0.012 * sin(a * 13.0 + 3.1)
				+ 0.020 * sin(y * 0.72 + a * 2.0)
				+ 0.012 * sin(y * 1.9 - a * 4.0)
			)
			n = maxf(0.0, n)
			var ledge: float = 0.0
			var band: float = sin(y * 1.15 + sin(a * 3.0) * 0.8)
			if band > 0.72:
				ledge = 0.38 * (band - 0.72) / 0.28
			var rr: float = r * (1.0 + n) + ledge
			if height_ratio > 0.9:
				rr = maxf(rr, radius * 0.09)
			var px: float = cos(a) * rr
			var pz: float = sin(a) * rr
			var py: float = y
			ring.append(Vector3(center.x + px, center.y + py, center.z + pz))
		grid.append(ring)
	for row in range(rows):
		for s in range(segments):
			var a0: float = TAU * float(s) / float(segments)
			var a1: float = TAU * float(s + 1) / float(segments)
			var mid_a: float = (a0 + a1) * 0.5
			var p0: Vector3 = grid[row][s]
			var p1: Vector3 = grid[row][s + 1]
			var p2: Vector3 = grid[row + 1][s + 1]
			var p3: Vector3 = grid[row + 1][s]
			var mid_y: float = (p0.y + p2.y) * 0.5 - center.y
			if _in_portal(mid_a, mid_y, portal_angle, portal_half, portal_y_min, portal_y_max):
				continue
			if _in_portal(mid_a, mid_y, exit_angle, exit_half, -1.0, exit_y_max):
				continue
			_add_tri(st, p0, p1, p3, center)
			_add_tri(st, p1, p2, p3, center)
	# 封顶。最后一圈的半径被 `height_ratio > 0.9` 下限夹在 radius*0.09（约 1.5 m），
	# 若不再补一层扇形，穹顶正中会留一个约 3 m 的洞：背景/天空会漏进大厅，
	# 那块 trimesh 也是“无底洞”。补一个以最后圈为边的 apex 扇形即可闭合。
	var top_ring: Array = grid[rows]
	var apex: Vector3 = Vector3(center.x, (top_ring[0] as Vector3).y, center.z)
	for s in range(segments):
		_add_tri(st, top_ring[s] as Vector3, top_ring[s + 1] as Vector3, apex, center)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "HallShell"
	mi.mesh = mesh
	mi.material_override = MatLib.rock_shell(Color(0.36, 0.335, 0.34), Color(0.10, 0.48, 0.56), 0.34, 0.22)
	mi.position = Vector3.ZERO
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	kit.root.add_child(mi)
	kit.add_trimesh_shape(mesh, Transform3D.IDENTITY)
	kit.stats["meshes"] = int(kit.stats["meshes"]) + 1
	kit.stats["triangles"] = int(kit.stats["triangles"]) + segments * rows * 2 + segments
	return mi


static func _in_portal(angle: float, y: float, center_angle: float, half: float, y_min: float, y_max: float) -> bool:
	var d: float = absf(wrapf(angle - center_angle, -PI, PI))
	return d < half and y >= y_min and y <= y_max


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3) -> void:
	for p in [a, b, c]:
		var h: float = clampf((p.y - center.y) / 20.0, 0.0, 1.0)
		var shade: float = 0.55 + 0.45 * h + 0.16 * sin(p.x * 0.8 + p.z * 0.6)
		st.set_color(Color(shade, shade, shade, 1.0))
		st.add_vertex(p)


static func tunnel(kit: WorldKit, z_start: float, z_end: float, width: float, floor_y: float, height: float, material: Material = null) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments: int = 46
	var steps: int = 38
	var grid: Array = []
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var z: float = lerpf(z_start, z_end, t)
		var ring: Array[Vector3] = []
		for s in range(segments + 1):
			var a: float = PI * float(s) / float(segments)
			var wobble: float = 0.055 * sin(a * 5.0 + t * 3.1) + 0.03 * sin(a * 11.0 - t * 4.3) + 0.025 * sin(t * 9.0 + a * 2.0)
			var x: float = cos(a) * width * (1.0 + wobble)
			var y: float = floor_y + pow(sin(a), 0.72) * height * (1.0 + wobble * 0.6)
			ring.append(Vector3(x, y, z))
		grid.append(ring)
	for i in range(steps):
		for s in range(segments):
			var p0: Vector3 = grid[i][s]
			var p1: Vector3 = grid[i][s + 1]
			var p2: Vector3 = grid[i + 1][s + 1]
			var p3: Vector3 = grid[i + 1][s]
			_add_tri(st, p0, p1, p3, Vector3(0, floor_y + height * 0.5, 0))
			_add_tri(st, p1, p2, p3, Vector3(0, floor_y + height * 0.5, 0))
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "EntranceTunnel"
	mi.mesh = mesh
	mi.material_override = material if material != null else MatLib.rock_shell(Color(0.35, 0.32, 0.30), Color(0.12, 0.42, 0.5), 0.26, 0.22)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	kit.root.add_child(mi)
	kit.add_trimesh_shape(mesh, Transform3D.IDENTITY)
	kit.stats["meshes"] = int(kit.stats["meshes"]) + 1
	kit.stats["triangles"] = int(kit.stats["triangles"]) + steps * segments * 2
	return mi


static func end_cap(kit: WorldKit, z: float, width: float, floor_y: float, height: float) -> void:
	# The spawn end used to be an invisible box behind rubble. It is now a real
	# sealed bulkhead, so the collision the player can touch is the wall they see.
	var steel: Material = MatLib.painted_steel(Color(0.22, 0.26, 0.26))
	var dark: Material = MatLib.dark_steel()
	kit.box("TunnelEndBulkhead", Vector3(width * 2.0 + 0.6, height + 0.4, 0.6), Vector3(0, floor_y + height * 0.5, z + 0.30), steel, Vector3.ZERO, true)
	kit.box("BulkheadRib", Vector3(width * 2.0 + 0.7, 0.18, 0.70), Vector3(0, floor_y + 1.35, z + 0.30), dark, Vector3.ZERO, false)
	kit.box("BulkheadRib", Vector3(width * 2.0 + 0.7, 0.18, 0.70), Vector3(0, floor_y + 3.25, z + 0.30), dark, Vector3.ZERO, false)
	kit.box("BulkheadHazard", Vector3(width * 2.0 + 0.5, 0.22, 0.66), Vector3(0, floor_y + 0.45, z + 0.30), MatLib.hazard_material(), Vector3.ZERO, false)
	for i in range(10):
		kit.cylinder("BulkheadBolt", 0.05, 0.06, Vector3(-3.3 + float(i) * 0.73, floor_y + 3.85, z + 0.62), MatLib.steel(), Vector3(PI * 0.5, 0, 0), false, 8)
	kit.label3d("R-05 · 封闭区", Vector3(0, floor_y + 2.4, z + 0.62), 0.0030, Color(0.78, 0.86, 0.82), 34, Basis(Vector3.UP, PI))
	kit.rock("SpawnRubble", "res://assets/rocks/rock_rubble_a.glb", Vector3(-1.6, floor_y + 0.1, z + 0.2), 20.0, 1.2, MatLib.debris_rock(), true)
	kit.rock("SpawnRubble2", "res://assets/rocks/rock_rubble_b.glb", Vector3(1.8, floor_y + 0.0, z + 0.4), -35.0, 1.3, MatLib.debris_rock(), true)
	kit.rock("SpawnRubble3", "res://assets/rocks/rock_outcrop_b.glb", Vector3(0.0, floor_y - 0.2, z + 0.9), 8.0, 1.0, MatLib.debris_rock(), true)
