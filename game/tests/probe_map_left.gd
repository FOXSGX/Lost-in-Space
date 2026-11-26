extends SceneTree

## Walkability map of the floor between the left ramp foot and the left
## counterweight console. A cell is "clear" when the player capsule fits there.

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	var space: PhysicsDirectSpaceState3D = app.get_world_3d().direct_space_state
	var zs: Array[float] = [-0.4, 0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4]
	var xs: Array[float] = [-4.0, -4.4, -4.8, -5.2, -5.6, -6.0, -6.4, -7.2, -8.0]
	print("MAP      " + " ".join(zs.map(func(z: float) -> String: return "%5.1f" % z)))
	for x in xs:
		var row: Array[String] = []
		for z in zs:
			var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			var shape: CapsuleShape3D = CapsuleShape3D.new()
			shape.radius = 0.30
			shape.height = 1.70
			params.shape = shape
			params.transform = Transform3D(Basis(), Vector3(x, 0.90, z))
			params.collision_mask = 1
			var hits: Array[Dictionary] = space.intersect_shape(params, 4)
			row.append("  .. " if hits.is_empty() else "  XX ")
		print("MAP x=%5.1f %s" % [x, "".join(row)])
	quit(0)
