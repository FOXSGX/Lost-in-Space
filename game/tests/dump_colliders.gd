extends SceneTree

## Dump every box/cylinder/capsule shape under WorldCollision with its world
## AABB so we can map the blocker shapes (24/156/160/253/254) to geometry.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var app: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	for _i in range(30):
		await physics_frame
	var wc: Node = app.find_child("WorldCollision", true, false)
	if wc == null:
		print("NO_WORLDCOLLISION")
		quit(1)
		return
	var idx: int = 0
	for child: Node in wc.get_children():
		if not child is CollisionShape3D:
			continue
		var cs: CollisionShape3D = child as CollisionShape3D
		var shape: Shape3D = cs.shape
		if shape == null:
			idx += 1
			continue
		var kind: String = shape.get_class()
		var dims: Vector3 = Vector3.ZERO
		if shape is BoxShape3D:
			dims = (shape as BoxShape3D).size
		elif shape is CylinderShape3D:
			var cyl: CylinderShape3D = shape as CylinderShape3D
			dims = Vector3(cyl.radius, cyl.height, cyl.radius)
		elif shape is CapsuleShape3D:
			var cap: CapsuleShape3D = shape as CapsuleShape3D
			dims = Vector3(cap.radius, cap.height, cap.radius)
		var center: Vector3 = cs.global_transform.origin
		if absf(center.x) < 12.0 and center.z > -1.0 and center.z < 5.0 and center.y < 3.0:
			print("SHAPE idx=%d name=%s kind=%s dims=%s pos=%s" % [idx, cs.name, kind, dims, center])
		idx += 1
	quit(0)