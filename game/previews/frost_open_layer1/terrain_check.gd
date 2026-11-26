extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var map: Main3D = load("res://previews/frost_open_layer1/preview.tscn").instantiate() as Main3D
	root.add_child(map)
	for index: int in 20:
		await physics_frame
	var arrays: Array = map.terrain_mesh.surface_get_arrays(0)
	print("normal0=",arrays[Mesh.ARRAY_NORMAL][0])
	var ok: bool = (arrays[Mesh.ARRAY_NORMAL][0] as Vector3).y > 0
	for p: Vector2 in [Vector2(0,39),Vector2(0,0),Vector2(45,10),Vector2(-46,10),Vector2(0,48)]:
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(p.x,20,p.y),Vector3(p.x,-5,p.y),2)
		var result: Dictionary = map.get_world_3d().direct_space_state.intersect_ray(ray)
		print("terrain ray ",p," = ",result)
		ok = ok and not result.is_empty() and (result.normal as Vector3).y>0
	print("FROST_TERRAIN_PASSED" if ok else "FROST_TERRAIN_FAILED")
	quit(0 if ok else 1)
