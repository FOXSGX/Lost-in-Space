extends SceneTree

# Rig inspection for the grip hand problem: what the arm/elbow/glove nodes
# actually are, whether the gloves are skinned or rigid, and whether rotating
# the arm bone moves them.

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	var app: Node = (load("resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	var scene: Node3D = app.get("stage") as Node3D
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	await _frames(20)
	var visual: Node3D = player.get("visual") as Node3D
	for node: Node in visual.find_children("*", "", true, false):
		var name_lower: String = str(node.name).to_lower()
		if name_lower.contains("skeleton") or name_lower.contains("glove") or name_lower.contains("hand") \
				or name_lower.contains("arm") or name_lower.contains("elbow") or name_lower.contains("skin"):
			var path: String = str(visual.get_path_to(node))
			var extra: String = ""
			if node is MeshInstance3D:
				var mi: MeshInstance3D = node as MeshInstance3D
				extra = " mesh=%s skin=%s surfaces=%d" % [
					str(mi.mesh.resource_name) if mi.mesh else "null",
					"yes" if mi.skin != null else "no",
					mi.mesh.get_surface_count() if mi.mesh else 0]
			if node is Skeleton3D:
				var sk: Skeleton3D = node as Skeleton3D
				extra = " bones=%d" % sk.get_bone_count()
			print("NODE ", path, " [", node.get_class(), "]", extra,
				" parent=", str(visual.get_path_to(node.get_parent())))
	print("PROBE_RIG_DONE")
	current_scene = null
	app.queue_free()
	await _frames(3)
	quit(0)
