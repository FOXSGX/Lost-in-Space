extends SceneTree

# Read-only probe: list what the cropped tunnel actually contains, and whether
# the route corridor has visible floor geometry under it.
func _initialize() -> void:
	var scene: PackedScene = load("res://assets/moving_tunnel.scn") as PackedScene
	var root: Node3D = scene.instantiate() as Node3D
	print("TUNNEL_CHILDREN ", root.get_child_count())
	var total: int = 0
	for node: Node in root.get_children():
		if node is MeshInstance3D:
			var mesh: MeshInstance3D = node as MeshInstance3D
			var arrays: ArrayMesh = mesh.mesh as ArrayMesh
			var tris: int = 0
			for s: int in range(arrays.get_surface_count()):
				var idx: PackedInt32Array = arrays.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				tris += idx.size() / 3
			total += tris
			print("  ", node.name, " surfaces=", arrays.get_surface_count(), " tris=", tris, " pos=", mesh.position)
	print("TUNNEL_TOTAL_TRIS ", total)

	# Sample the route: is there visible geometry beneath the rails?
	var probe: Node3D = (load("res://assets/station_static.glb") as PackedScene).instantiate() as Node3D
	print("SOURCE_CHILDREN ", probe.get_child_count())
	var mesh_names: Array[String] = []
	for node: Node in probe.get_children():
		if node is MeshInstance3D:
			mesh_names.append(str(node.name))
	mesh_names.sort()
	print("SOURCE_MESHES ", mesh_names)
	probe.free()
	root.free()
	quit(0)
