extends SceneTree

## 临时验收工具：进场景后量每个导入模型的 world AABB，
## 检查 1) 底部是否贴地 2) 是否侵入球路走廊 3) 是否压住出生点。
## 用法：godot --headless --path . --script res://tools/probe_dressing.gd

var _frames := 0
var _scene: Node


func _initialize() -> void:
	_scene = (load("res://gulu_planet.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var dressing := _scene.find_child("ImportedDressing", true, false)
	if dressing == null:
		print("DRESS no dressing node")
		return true
	for child in dressing.get_children():
		if not (child is Node3D) or child is Light3D or child is StaticBody3D:
			continue
		var box := _aabb(child as Node3D)
		var name := str(child.name)
		var bottom := box.position.y
		var overlaps_lane := box.intersects(AABB(Vector3(-6.0, -0.2, -2.4), Vector3(19.0, 4.0, 4.8)))
		var overlaps_spawn := box.intersects(AABB(Vector3(-11.6, -0.2, 4.4), Vector3(1.2, 2.0, 1.2)))
		print("DRESS %-16s bottom=%.2f top=%.2f x=[%.1f,%.1f] z=[%.1f,%.1f] lane=%s spawn=%s" % [
			name, bottom, box.end.y,
			box.position.x, box.end.x, box.position.z, box.end.z,
			str(overlaps_lane), str(overlaps_spawn)])
	return true


func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		var world: AABB = mi.global_transform * mi.get_aabb()
		if first:
			box = world
			first = false
		else:
			box = box.merge(world)
	return box


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
