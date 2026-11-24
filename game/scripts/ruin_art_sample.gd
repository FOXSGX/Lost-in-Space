extends RefCounted

## ART-SAMPLE-002 的游戏可用 GLB 接入小工具。
## 原包位于 art-source/third-party/ART-SAMPLE-002_TEAM_KIT；
## 游戏内只放需要的 GLB/贴图/shader，材质统一走项目内的 hero_lib。

const HERO_LIB := preload("res://assets/art-sample-002/hero_lib.gd")

static var _materials: Dictionary = {}


static func materials() -> Dictionary:
	if _materials.is_empty():
		_materials = HERO_LIB.new().build()
	return _materials


static func attach(parent: Node3D, path: String, position_value: Vector3, rotation_degrees_value: Vector3, scale_value: Vector3) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("ART-SAMPLE model missing: " + path)
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		return null
	root.name = path.get_file().get_basename()
	parent.add_child(root)
	root.position = position_value
	root.rotation_degrees = rotation_degrees_value
	root.scale = scale_value
	_apply_materials(root)
	return root


static func _apply_materials(root: Node3D) -> void:
	var library := materials()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface) as Material
			if source == null:
				continue
			var material_name := source.resource_name
			if library.has(material_name):
				mesh_instance.set_surface_override_material(surface, library[material_name])
