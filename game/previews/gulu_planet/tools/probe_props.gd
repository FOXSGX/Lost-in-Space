extends SceneTree

## 临时工具：打印 props 目录里每个 GLB 在 Godot 里的实际包围盒 / 网格数 / 材质。
## 用法：godot --headless --path . --script res://tools/probe_props.gd

const DIR := "res://assets/props"


func _init() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		print("PROBE no dir")
		quit()
		return
	for file in dir.get_files():
		if not file.ends_with(".glb"):
			continue
		var path := DIR.path_join(file)
		var scene := load(path) as PackedScene
		if scene == null:
			print("PROBE LOAD FAIL ", file)
			continue
		var root := scene.instantiate()
		var aabb := _aabb_of(root, root)
		var meshes := _mesh_list(root)
		var mats := {}
		for mi in meshes:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.get_active_material(s)
				if m:
					mats[m.resource_name if m.resource_name != "" else m.get_class()] = true
		print("PROBE %s size=(%.2f, %.2f, %.2f) center=(%.2f, %.2f, %.2f) meshes=%d mats=%s" % [
			file, aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.get_center().x, aabb.get_center().y, aabb.get_center().z,
			meshes.size(), str(mats.keys())])
		root.free()
	quit()


func _mesh_list(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_mesh_list(child))
	return out


func _aabb_of(node: Node, root: Node) -> AABB:
	var meshes := _mesh_list(node)
	var out := AABB()
	var first := true
	for mi in meshes:
		var xf := _relative(mi, root)
		var box: AABB = xf * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _relative(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
