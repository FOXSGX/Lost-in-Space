extends SceneTree

## 一次性检查：奶龙星三件 Blender 中景资产（维修棚 / 集装箱 / 观测台）
## 能否导入、三角面数、材质名、包围盒（Godot 语义：x 宽 / y 高 / z 深）、脚底是否贴地。
## 用法： godot --headless --path <preview> --script tools/check_nailong_assets.gd

const ASSETS := [
	["service_shed", "res://assets/models/nailong/service_shed.glb"],
	["container_a", "res://assets/models/nailong/container_a.glb"],
	["container_b", "res://assets/models/nailong/container_b.glb"],
	["observation_deck", "res://assets/models/nailong/observation_deck.glb"],
]


func _initialize() -> void:
	var bad := 0
	for entry in ASSETS:
		var label: String = entry[0]
		var path: String = entry[1]
		if not ResourceLoader.exists(path):
			print("ASSET %s MISSING %s" % [label, path])
			bad += 1
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			print("ASSET %s load failed" % label)
			bad += 1
			continue
		var root := packed.instantiate() as Node3D
		var triangles := 0
		var verts := 0
		var materials := {}
		var box := AABB()
		var first := true
		var has_color := false
		var has_uv := false
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				verts += v.size()
				triangles += (idx.size() if idx.size() > 0 else v.size()) / 3
				if arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() > 0:
					has_color = true
				if arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV].size() > 0:
					has_uv = true
				var mat := mi.mesh.surface_get_material(s)
				if mat != null:
					materials[mat.resource_name] = true
			var local := mi.transform * mi.get_aabb()
			box = local if first else box.merge(local)
			first = false
		print("ASSET %s tris=%d verts=%d color=%s uv=%s mats=%s" % [
			label, triangles, verts, str(has_color), str(has_uv), str(materials.keys())])
		print("ASSET %s aabb pos=%s size=%s feet_on_ground=%s" % [
			label, str(box.position.snapped(Vector3(0.001, 0.001, 0.001))),
			str(box.size.snapped(Vector3(0.001, 0.001, 0.001))),
			str(absf(box.position.y) < 0.02)])
		if triangles < 2000 or triangles > 15000:
			print("ASSET %s TRI_BUDGET_FAIL %d" % [label, triangles])
			bad += 1
		if not has_color:
			print("ASSET %s MISSING_VERTEX_COLOR" % label)
			bad += 1
		root.free()
	print("ASSET CHECK %s" % ("ok" if bad == 0 else "failures=%d" % bad))
	quit(0 if bad == 0 else 1)
