extends SceneTree

## Verifies that the Blender hero asset is a valid Godot PackedScene before it is
## wired into the live ResonanceStage module list.

const MODEL_PATH := "res://assets/resonance/models/resonance_module_hero.glb"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	print("RESONANCE_MODEL_IMPORT: start")
	check(ResourceLoader.exists(MODEL_PATH), "GLB 路径不存在：%s" % MODEL_PATH)
	var loaded := ResourceLoader.load(MODEL_PATH)
	check(loaded != null, "GLB ResourceLoader.load 返回空对象")
	check(loaded is PackedScene, "GLB 没有导入为 PackedScene")
	if loaded is PackedScene:
		var scene := loaded as PackedScene
		var instance: Node = scene.instantiate()
		check(instance != null, "GLB PackedScene 实例化失败")
		if instance != null:
			root.add_child(instance)
			await process_frame
			var meshes := instance.find_children("*", "MeshInstance3D", true, false)
			var materials := {}
			for node in meshes:
				var mesh_node := node as MeshInstance3D
				if mesh_node != null and mesh_node.mesh != null:
					for surface in mesh_node.mesh.get_surface_count():
						var surface_material := mesh_node.get_active_material(surface)
						if surface_material != null:
							materials[str(surface_material.resource_name)] = true
			print("MODEL nodes=%d meshes=%d materials=%d" % [instance.get_child_count(), meshes.size(), materials.size()])
			print("MODEL collisions=%d bodies=%d scripts=%d" % [instance.find_children("*", "CollisionObject3D", true, false).size(), instance.find_children("*", "PhysicsBody3D", true, false).size(), instance.find_children("*", "Script", true, false).size()])
			check(meshes.size() >= 100, "英雄资产网格数量过少，可能导出不完整：%d" % meshes.size())
			check(materials.size() >= 5, "英雄资产材质数量过少：%d" % materials.size())
			check(instance.get_node_or_null("RES_Module_Hero") != null or instance.name == "RES_Module_Hero", "英雄资产根节点缺失")
			instance.queue_free()
	print("RESONANCE_MODEL_IMPORT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
