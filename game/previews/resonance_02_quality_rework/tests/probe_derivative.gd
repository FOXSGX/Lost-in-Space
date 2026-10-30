extends SceneTree

# Inspect the generated corridor derivative. The suspicion is that the source
# cave is ONE ~43 m diorama whose west/middle/east groups are material groups,
# not separate bays, so offsetting four copies by 0/30/60/90 overlaps them.

const CART := preload("res://scripts/moving_cart.gd")

func _initialize() -> void:
	var scene: Node3D = (load("res://assets/moving_tunnel.scn") as PackedScene).instantiate() as Node3D
	var rows: Array = []
	for node: Node in scene.get_children():
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null: continue
		var tris: int = 0
		for s: int in range(mesh.mesh.get_surface_count()):
			var arr: Array = (mesh.mesh as ArrayMesh).surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
		rows.append({"name": str(mesh.name), "pos": mesh.position, "tris": tris})
	print("DERIVATIVE_CHILDREN ", rows.size())
	# Group by bay suffix and print the world X span each bay covers.
	var per_bay: Dictionary = {}
	for row: Dictionary in rows:
		var n: String = str(row["name"])
		var bay: int = int(n.get_slice("_bay", 1))
		var arr: Array = per_bay.get(bay, [])
		arr.append(row)
		per_bay[bay] = arr
	var bays: Array = per_bay.keys()
	bays.sort()
	for bay: int in bays:
		var list: Array = per_bay[bay]
		var min_x: float = 1e9
		var max_x: float = -1e9
		var tris: int = 0
		for row: Dictionary in list:
			var mesh: MeshInstance3D = row["name"] as MeshInstance3D if row["name"] is MeshInstance3D else null
			tris += int(row["tris"])
		print("BAY %d meshes=%d tris=%d" % [bay, list.size(), tris])
	# Precise X span per bay using real geometry.
	print("=== BAY WORLD X SPANS ===")
	for bay: int in bays:
		var lo: float = 1e9
		var hi: float = -1e9
		for node: Node in scene.get_children():
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh == null: continue
			if not str(mesh.name).ends_with("_bay%d" % bay): continue
			var box: AABB = mesh.mesh.get_aabb()
			lo = minf(lo, box.position.x + mesh.position.x)
			hi = maxf(hi, box.end.x + mesh.position.x)
		print("  bay %d  x %.1f .. %.1f   (width %.1f)" % [bay, lo, hi, hi - lo])
	scene.free()

	# Source: same measurement, un-tiled.
	var source: Node3D = (load("res://assets/station_static.glb") as PackedScene).instantiate() as Node3D
	var slo: float = 1e9
	var shi: float = -1e9
	var szlo: float = 1e9
	var szhi: float = -1e9
	var ylo: float = 1e9
	var yhi: float = -1e9
	for node: Node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null or mesh.mesh == null: continue
		var box: AABB = mesh.mesh.get_aabb()
		slo = minf(slo, box.position.x + mesh.position.x)
		shi = maxf(shi, box.end.x + mesh.position.x)
		szlo = minf(szlo, box.position.z + mesh.position.z)
		szhi = maxf(szhi, box.end.z + mesh.position.z)
		ylo = minf(ylo, box.position.y + mesh.position.y)
		yhi = maxf(yhi, box.end.y + mesh.position.y)
	print("SOURCE_EXTENT x %.1f..%.1f (%.1f)  z %.1f..%.1f (%.1f)  y %.1f..%.1f (%.1f)" % [slo, shi, shi - slo, szlo, szhi, szhi - szlo, ylo, yhi, yhi - ylo])
	source.free()
	quit(0)
