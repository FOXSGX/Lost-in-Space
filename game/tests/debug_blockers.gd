extends SceneTree

## Print which collision shape blocks a capsule at given world points.

var app: Node3D
var level: LevelBuilder


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(80)
	level = app.get("level") as LevelBuilder
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var points: Array[Vector3] = [
		Vector3(10.99, 0.9, 4.41), Vector3(11.3, 0.9, 4.2), Vector3(10.7, 0.9, 2.1),
		Vector3(11.4, 0.9, 1.2), Vector3(11.6, 0.9, 0.0), Vector3(10.9, 0.9, -5.0),
		Vector3(11.0, 0.9, -6.5), Vector3(10.7, 0.9, -7.4),
	]
	for p in points:
		var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var cap: CapsuleShape3D = CapsuleShape3D.new()
		cap.radius = 0.36
		cap.height = 1.7
		q.shape = cap
		q.transform = Transform3D(Basis(), p)
		q.collision_mask = 1 | 8
		var hits: Array[Dictionary] = space.intersect_shape(q, 16)
		print("\nPOINT ", p, " hits=", hits.size())
		for h in hits:
			var collider: Node = h.get("collider") as Node
			var rid: RID = h.get("shape") as RID
			var label: String = "?"
			if collider != null:
				for child in collider.get_children():
					if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
						if (child as CollisionShape3D).shape.get_rid() == rid:
							label = "%s [%s] pos=%s" % [child.name, (child as CollisionShape3D).shape.get_class(), (child as CollisionShape3D).global_position]
			print("  ", collider.get_path() if collider != null else "null", " shape=", label)
	quit()
