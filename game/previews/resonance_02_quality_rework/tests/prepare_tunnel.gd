extends SceneTree

func _initialize() -> void:
	var source: Node3D = (load("res://assets/station_static.glb") as PackedScene).instantiate() as Node3D
	var result: Node3D = Node3D.new()
	result.name = "ApprovedCaveRouteDerivative"
	var kept: int = 0
	var removed: int = 0
	for bay: int in range(4):
		# Each bay must follow the actual route curve. A flat +5 Z shift put bays
		# 1-3 up to 4 m away from the track, so the corridor crop punched holes
		# through the cave shell and exposed the background colour.
		var bay_x: float = float(bay) * 30.0
		var offset: Vector3 = Vector3(bay_x, 0.0, preload("res://scripts/moving_cart.gd").bend(bay_x))
		for node: Node in source.get_children():
			if not node is MeshInstance3D: continue
			var label: String = str(node.name).to_lower()
			if "static_cart" in label or "access" in label or "rail head" in label or "rail web" in label or "rail clamp" in label or "track sleeper" in label: continue
			var old: MeshInstance3D = node as MeshInstance3D
			var mesh: ArrayMesh = old.mesh as ArrayMesh
			var generated: ArrayMesh = ArrayMesh.new()
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for i: int in range(vertices.size()): indices.append(i)
				var keep: PackedInt32Array = PackedInt32Array()
				for i: int in range(0, indices.size(), 3):
					var a: Vector3 = vertices[indices[i]]
					var b: Vector3 = vertices[indices[i+1]]
					var c: Vector3 = vertices[indices[i+2]]
					var center: Vector3 = (a + b + c) / 3.0 + offset
					var route_z: float = 2.2 + preload("res://scripts/moving_cart.gd").bend(center.x)
					var in_corridor: bool = absf(center.z - route_z) < 3.15 and center.y > 0.35 and center.y < 6.0
					if in_corridor:
						# A face straddling the crop boundary must survive, otherwise
						# the cut leaves an open edge that renders as a black hole.
						var spans: bool = false
						for corner: Vector3 in [a, b, c]:
							var world_corner: Vector3 = corner + offset
							var corner_z: float = 2.2 + preload("res://scripts/moving_cart.gd").bend(world_corner.x)
							if absf(world_corner.z - corner_z) >= 3.15 or world_corner.y <= 0.35 or world_corner.y >= 6.0:
								spans = true
								break
						if not spans:
							removed += 1
							continue
					keep.append_array(indices.slice(i,i+3))
					kept += 1
				if keep.is_empty(): continue
				arrays[Mesh.ARRAY_INDEX] = keep
				generated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				generated.surface_set_material(generated.get_surface_count()-1,mesh.surface_get_material(surface))
			if generated.get_surface_count() == 0: continue
			var visual: MeshInstance3D = MeshInstance3D.new()
			visual.name = str(node.name) + "_bay%d" % bay
			visual.mesh = generated
			visual.position = offset
			result.add_child(visual)
			visual.owner = result
	var packed: PackedScene = PackedScene.new()
	packed.pack(result)
	var error: Error = ResourceSaver.save(packed,"res://assets/moving_tunnel.scn",ResourceSaver.FLAG_COMPRESS)
	print("TUNNEL_DERIVATIVE ",error," kept=",kept," cleared_for_route=",removed)
	result.free()
	source.free()
	quit(error)
