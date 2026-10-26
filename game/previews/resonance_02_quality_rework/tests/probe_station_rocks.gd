extends SceneTree

# Lists the reusable rock meshes inside the approved station diorama that the
# cart project already imports, so the cave can be rebuilt from approved rock
# volumes instead of a smooth procedural tube.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var packed: PackedScene = load("res://assets/station_static.glb") as PackedScene
	var root_node: Node3D = packed.instantiate() as Node3D
	root.add_child(root_node)
	var count: int = 0
	for node: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.get_aabb()
		var mat: Material = mesh.mesh.surface_get_material(0)
		var albedo: String = ""
		if mat is StandardMaterial3D:
			albedo = str((mat as StandardMaterial3D).albedo_color)
		var faces: int = mesh.mesh.get_faces().size() / 3 if mesh.mesh is ArrayMesh else 0
		print("MESH ", mesh.name, " tris=", faces, " size=(%.2f,%.2f,%.2f)" % [box.size.x, box.size.y, box.size.z],
			" centre=(%.1f,%.1f,%.1f)" % [box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.5, box.position.z + box.size.z * 0.5],
			" albedo=", albedo, " mat=", mat.resource_name if mat else "null")
		count += 1
		if count > 60:
			break
	print("STATION_MESHES ", count)
	print("PROBE_STATION_DONE")
	root_node.queue_free()
	await process_frame
	quit(0)
