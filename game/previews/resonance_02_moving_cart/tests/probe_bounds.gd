extends SceneTree

# Read-only measurement of the visual cart bounds and the cave floor band along
# the route, so the corridor crop can keep the floor and clear only headroom.
func _initialize() -> void:
	var visual: Node3D = (load("res://assets/moving_cart_visual.scn") as PackedScene).instantiate() as Node3D
	var bounds: AABB = AABB()
	var first: bool = true
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var box: AABB = mesh.get_aabb()
		var world: AABB = AABB(mesh.transform * box.position, box.size)
		if first:
			bounds = world
			first = false
		else:
			bounds = bounds.merge(world)
	print("CART_VISUAL_AABB pos=", bounds.position, " end=", bounds.end, " size=", bounds.size)
	var wheels: Array[String] = []
	for node: Node in visual.get_children():
		if str(node.name).begins_with("Wheel"):
			wheels.append(str(node.name))
	print("CART_WHEEL_NODES ", wheels)
	visual.free()

	# Cave floor band: histogram of triangle-centre heights near the route.
	var source: Node3D = (load("res://assets/station_static.glb") as PackedScene).instantiate() as Node3D
	var bands: Dictionary = {}
	var near_route: int = 0
	for node: Node in source.get_children():
		if not node is MeshInstance3D: continue
		var label: String = str(node.name).to_lower()
		if not ("bedrock" in label or "ballast" in label or "schist" in label or "feldspar" in label): continue
		var mesh: MeshInstance3D = node as MeshInstance3D
		var arrays: ArrayMesh = mesh.mesh as ArrayMesh
		for s: int in range(arrays.get_surface_count()):
			var data: Array = arrays.surface_get_arrays(s)
			var verts: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = data[Mesh.ARRAY_INDEX]
			var step: int = maxi(3, idx.size() / 3 / 400 * 3)
			for i: int in range(0, idx.size(), step):
				if i + 2 >= idx.size(): break
				var c: Vector3 = (verts[idx[i]] + verts[idx[i+1]] + verts[idx[i+2]]) / 3.0
				if c.x < -6.0 or c.x > 96.0: continue
				var route_z: float = 2.2 + (5.8 * smoothstep(23.0, 49.0, c.x) - 3.2 * smoothstep(61.0, 83.0, c.x))
				if absf(c.z - route_z) > 4.0: continue
				near_route += 1
				var band: int = int(floor(c.y * 4.0)) / 4
				bands[band] = int(bands.get(band, 0)) + 1
	print("FLOOR_SAMPLES_NEAR_ROUTE ", near_route)
	var keys: Array = bands.keys()
	keys.sort()
	for k: float in keys:
		print("  y~", k, " count=", bands[k])
	source.free()
	quit(0)
