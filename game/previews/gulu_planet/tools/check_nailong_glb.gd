extends SceneTree

## 一次性检查：nailong.glb 能否导入、有多少网格、脚底是否贴地、包围盒尺寸。
## 用法： godot --headless --path <preview> --script tools/check_nailong_glb.gd

func _initialize() -> void:
	var path := "res://assets/characters/nailong.glb"
	if not ResourceLoader.exists(path):
		print("NAILONG_GLB missing: %s" % path)
		quit(2)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("NAILONG_GLB load failed")
		quit(2)
		return
	var root := packed.instantiate() as Node3D
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var materials: Array = []
	var box := AABB()
	var first := true
	for entry in meshes:
		var mi := entry as MeshInstance3D
		if mi.mesh == null:
			continue
		triangles += mi.mesh.get_faces().size() / 3
		for surface in mi.mesh.get_surface_count():
			var material := mi.mesh.surface_get_material(surface)
			if material != null:
				materials.append(material.resource_name)
		var local := mi.transform * mi.get_aabb()
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	print("NAILONG_GLB meshes=%d triangles=%d materials=%s" % [meshes.size(), triangles, str(materials)])
	print("NAILONG_GLB bounds min=%s max=%s size=%s" % [str(box.position), str(box.end), str(box.size)])
	print("NAILONG_GLB feet_on_ground=%s" % str(absf(box.position.y) < 0.02))
	root.free()
	quit(0)
