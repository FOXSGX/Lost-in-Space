extends SceneTree

func _initialize() -> void:
	var source: Node3D = (load("res://assets/station_static.glb") as PackedScene).instantiate() as Node3D
	var result: Node3D = Node3D.new()
	result.name = "ApprovedV23Cart"
	var pivots: Array[Node3D] = []
	for x: float in [-2.7, 2.7]:
		for z: float in [1.03, 3.37]:
			var pivot: Node3D = Node3D.new()
			pivot.name = "Wheel%d" % pivots.size()
			pivot.position = Vector3(x, 1.1046444, z)
			result.add_child(pivot)
			pivot.owner = result
			pivots.append(pivot)
	for node: Node in source.get_children():
		if not node is MeshInstance3D or not str(node.name).begins_with("STATIC_cart"): continue
		var source_mesh: MeshInstance3D = node as MeshInstance3D
		var mesh: ArrayMesh = source_mesh.mesh as ArrayMesh
		for surf: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surf)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var buckets: Array[PackedInt32Array] = []
			for _i: int in range(5): buckets.append(PackedInt32Array())
			if indices.is_empty():
				for i: int in range(vertices.size()): indices.append(i)
			for i: int in range(0, indices.size(), 3):
				var center: Vector3 = (vertices[indices[i]] + vertices[indices[i + 1]] + vertices[indices[i + 2]]) / 3.0
				var bucket: int = 0
				for w: int in range(pivots.size()):
					var d: Vector3 = center - pivots[w].position
					if Vector2(d.x, d.y).length() < 0.801 and absf(d.z) < 0.235:
						bucket = w + 1
						break
				buckets[bucket].append_array(indices.slice(i, i + 3))
			for bucket: int in range(5):
				if buckets[bucket].is_empty(): continue
				var copy_arrays: Array = arrays.duplicate()
				copy_arrays[Mesh.ARRAY_INDEX] = buckets[bucket]
				var new_mesh: ArrayMesh = ArrayMesh.new()
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy_arrays)
				new_mesh.surface_set_material(0, mesh.surface_get_material(surf))
				var visual: MeshInstance3D = MeshInstance3D.new()
				visual.mesh = new_mesh
				visual.name = str(source_mesh.name) + "_%d" % bucket
				var parent: Node3D = result if bucket == 0 else pivots[bucket - 1]
				parent.add_child(visual)
				if bucket > 0: visual.position = -parent.position
				visual.owner = result
	var packed: PackedScene = PackedScene.new()
	packed.pack(result)
	var error: Error = ResourceSaver.save(packed, "res://assets/moving_cart_visual.scn")
	print("CART_DERIVATIVE ", error, " wheels=", pivots.size())
	source.free()
	result.free()
	quit(error)
