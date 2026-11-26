extends "res://tests/test_moving_cart.gd"

# Diagnose the dark patch: what actually renders under the player near the dock.
func run() -> void:
	await boot()
	await travel(Vector3(1, 0, 1.55))
	await frames(20)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for offset: Vector3 in [Vector3(0,0,0), Vector3(1.2,0,0), Vector3(-1.2,0,0), Vector3(0,0,1.4), Vector3(0,0,-1.4), Vector3(2.2,0,0.6)]:
		var from: Vector3 = player.global_position + offset + Vector3.UP * 1.2
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * 4.0, 0xFFFFFFFF)
		var hit: Dictionary = space.intersect_ray(query)
		print("RAY offset=", offset, " hit=", hit.get("collider"), " pos=", hit.get("position"), " normal=", hit.get("normal"))
	# Enumerate visible meshes near the player's feet and report their materials.
	var near: Array = []
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.global_position.distance_to(player.global_position) > 9.0: continue
		var mat: Material = mesh.material_override
		if mat == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
			mat = mesh.mesh.surface_get_material(0)
		var albedo: String = "?"
		if mat is StandardMaterial3D:
			albedo = str((mat as StandardMaterial3D).albedo_color) + " metallic=" + str((mat as StandardMaterial3D).metallic)
		elif mat is ShaderMaterial:
			albedo = "shader"
		near.append({"name": str(mesh.name), "mat": albedo, "pos": str(mesh.global_position), "aabb": str(mesh.get_aabb().size)})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	for entry: Dictionary in near:
		print("MESH ", entry)
	await finish()
