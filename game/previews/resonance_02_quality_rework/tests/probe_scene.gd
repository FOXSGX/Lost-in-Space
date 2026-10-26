extends SceneTree

# Read-only structural dump of the approved cave source. Answers the questions
# the previous round never answered: which meshes exist, what their real world
# bounds are, and how the floor is distributed along the cart route.

const CART := preload("res://scripts/moving_cart.gd")

func _initialize() -> void:
	var source: Node3D = (load("res://assets/station_static.glb") as PackedScene).instantiate() as Node3D
	print("=== MESH INVENTORY ===")
	var total_tris: int = 0
	var rows: Array = []
	for node: Node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null: continue
		var aabb: AABB = mesh.mesh.get_aabb()
		var tris: int = 0
		for s: int in range(mesh.mesh.get_surface_count()):
			var arr: Array = (mesh.mesh as ArrayMesh).surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() / 3) if not idx.is_empty() else ((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		total_tris += tris
		var mat: Material = mesh.get_active_material(0)
		rows.append({
			"name": str(mesh.name),
			"tris": tris,
			"pos": aabb.position,
			"size": aabb.size,
			"mat": mat.resource_name if mat != null else "<none>",
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	for row: Dictionary in rows:
		print("MESH %-46s tris=%-7d aabb_pos=%s size=%s mat=%s" % [
			str(row["name"]), int(row["tris"]),
			_v(str(row["pos"])), _v(str(row["size"])), str(row["mat"])])
	print("TOTAL_TRIS ", total_tris, " meshes=", rows.size())

	# Height histogram of triangles that sit inside the swept route corridor.
	print("=== CORRIDOR HEIGHT HISTOGRAM (|z-route|<3.2, -4<x<96) ===")
	var bands: Dictionary = {}
	var per_mesh: Dictionary = {}
	for node: Node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null: continue
		var mesh_tris: int = 0
		for s: int in range(mesh.mesh.get_surface_count()):
			var arr: Array = (mesh.mesh as ArrayMesh).surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array()
				for i: int in range(verts.size()): idx.append(i)
			var step: int = maxi(3, (idx.size() / 3 / 3000) * 3)
			for i: int in range(0, idx.size(), step):
				if i + 2 >= idx.size(): break
				var c: Vector3 = (verts[idx[i]] + verts[idx[i+1]] + verts[idx[i+2]]) / 3.0
				if c.x < -4.0 or c.x > 96.0: continue
				var route_z: float = 2.2 + CART.bend(c.x)
				if absf(c.z - route_z) > 3.2: continue
				mesh_tris += 1
				var band: float = snappedf(c.y, 0.5)
				bands[band] = int(bands.get(band, 0)) + 1
		if mesh_tris > 0: per_mesh[str(mesh.name)] = mesh_tris
	print("CORRIDOR_SAMPLED ", int(per_mesh.values().reduce(func(a, b): return a + b, 0)))
	var keys: Array = bands.keys()
	keys.sort()
	for k: float in keys:
		var bar: String = "#".repeat(int(minf(60.0, float(bands[k]) / 40.0)))
		print("  y=%6.1f  n=%-6d %s" % [k, int(bands[k]), bar])
	var names: Array = per_mesh.keys()
	names.sort_custom(func(a, b) -> bool: return int(per_mesh[a]) > int(per_mesh[b]))
	print("--- corridor triangles by mesh ---")
	for n: String in names:
		print("  %-46s %d" % [n, int(per_mesh[n])])

	# Floor height directly under the rail centreline.
	print("=== FLOOR PROBE (raycast-free: nearest triangle centre per station) ===")
	for s: float in [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0]:
		var target: Vector3 = Vector3(s, 0.0, 2.2 + CART.bend(s))
		var best: float = 999.0
		var best_mesh: String = ""
		for node: Node in source.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh.mesh == null: continue
			for si: int in range(mesh.mesh.get_surface_count()):
				var arr: Array = (mesh.mesh as ArrayMesh).surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				if idx.is_empty(): continue
				var step: int = maxi(3, (idx.size() / 3 / 400) * 3)
				for i: int in range(0, idx.size(), step):
					if i + 2 >= idx.size(): break
					var c: Vector3 = (verts[idx[i]] + verts[idx[i+1]] + verts[idx[i+2]]) / 3.0
					var flat: float = Vector2(c.x - target.x, c.z - target.z).length()
					if flat > 2.6: continue
					var d: float = absf(c.y)
					if d < best:
						best = d
						best_mesh = str(mesh.name)
		print("  s=%5.1f  nearest_floor_y=%7.3f  from=%s" % [s, best, best_mesh])
	source.free()
	quit(0)

func _v(text: String) -> String:
	return text.replace("(", "[").replace(")", "]")
