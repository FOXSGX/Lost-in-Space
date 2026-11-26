extends SceneTree

## Probe the exact station-approach lane west of the left ramp foot with the
## real capsule (r=0.36) and print the blocking collider names, including the
## shape owners (so we can tell RampPost vs TrestleFoot apart by name).

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var app: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	for _i in range(30):
		await physics_frame
	var level: Node = app.get("level")
	for z in [2.2, 2.4, 2.6, 1.9]:
		for x in [-4.4, -4.8, -5.0, -5.2, -5.4, -5.6, -5.8, -6.0, -6.2]:
			var space: PhysicsDirectSpaceState3D = (app as Node3D).get_world_3d().direct_space_state
			var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			var shape: CapsuleShape3D = CapsuleShape3D.new()
			shape.radius = 0.36
			shape.height = 1.78
			params.shape = shape
			params.transform = Transform3D(Basis(), Vector3(x, 0.89, z))
			params.collision_mask = 1
			var hits: Array[Dictionary] = space.intersect_shape(params, 20)
			if hits.is_empty():
				print("Z=%.1f X=%.1f CLEAR" % [z, x])
				continue
			var names: Array[String] = []
			for hit in hits:
				var collider: Object = hit.get("collider")
				var path: String = str(collider.get_path()) if collider is Node else "?"
				var shape_name: String = "?"
				if collider is CollisionObject3D:
					var body: CollisionObject3D = collider as CollisionObject3D
					var sidx: int = int(hit.get("shape", -1))
					var owner_id: int = body.shape_find_owner(sidx)
					if owner_id >= 0:
						var owner_node: Node = body.shape_owner_get_owner(owner_id)
						if owner_node != null:
							shape_name = owner_node.name
				names.append("%s#%s" % [path, shape_name])
			print("Z=%.1f X=%.1f hit=%d %s" % [z, x, hits.size(), "; ".join(names)])
	quit(0)