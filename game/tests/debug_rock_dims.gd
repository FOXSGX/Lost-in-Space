extends SceneTree

func _initialize() -> void:
	var names: Array[String] = ["rock_wall_a", "rock_wall_b", "rock_vault_a", "rock_shoulder_a", "rock_outcrop_a", "rock_stalactite_a", "crystal_cluster_a"]
	for n in names:
		var path: String = "res://assets/rocks/%s.glb" % n
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			print(n, " MISSING")
			continue
		var inst: Node3D = packed.instantiate() as Node3D
		root.add_child(inst)
		var box: AABB = AABB()
		var first: bool = true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi as MeshInstance3D
			if m.mesh == null:
				continue
			var a: AABB = m.global_transform * m.get_aabb()
			if first:
				box = a
				first = false
			else:
				box = box.merge(a)
		print(n, " size=", box.size, " center=", box.get_center())
		inst.queue_free()
	quit()
