extends SceneTree

## What blocks the floor lane west of the left ramp foot? Dump every collider the
## player capsule would hit at a few sample points between x=-4.4 and x=-8.

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	var space: PhysicsDirectSpaceState3D = (app as Node3D).get_world_3d().direct_space_state
	for x in [-4.6, -5.2, -5.8, -6.4, -7.0, -7.6]:
		var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var shape: CapsuleShape3D = CapsuleShape3D.new()
		shape.radius = 0.30
		shape.height = 1.70
		params.shape = shape
		params.transform = Transform3D(Basis(), Vector3(x, 0.95, 2.2))
		params.collision_mask = 1
		var hits: Array[Dictionary] = space.intersect_shape(params, 8)
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
			names.append("%s#%s [%s]" % [path, shape_name, str(hit.get("shape"))])
		print("BLOCK x=%.1f hits=%d %s" % [x, hits.size(), str(names)])
	quit(0)
