extends RefCounted

# Small procedural mesh kit for the industrial test scene.
# Everything is authored from primitives so the prototype needs no new Blender
# work and no external art dependency. Colours sit next to the existing Resonance
# mining-station palette: cold steel, hazard amber, cyan crystal energy.
#
# Used as a preloaded const, e.g.  const Kit := preload("res://scripts/build/mesh_kit.gd")

static func material(color: Color, metallic: float = 0.6, roughness: float = 0.55, emission: Color = Color(0, 0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat

static func box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, mat: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position
	instance.rotation = rotation
	parent.add_child(instance)
	return instance

static func cylinder(parent: Node3D, node_name: String, radius: float, height: float, position: Vector3, mat: Material, axis: String = "y", sides: int = 24) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position
	match axis:
		"x":
			instance.rotation = Vector3(0.0, 0.0, PI * 0.5)
		"z":
			instance.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		_:
			pass
	parent.add_child(instance)
	return instance

static func prism(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, mat: Material, sides: int = 6) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position
	parent.add_child(instance)
	return instance

static func sphere(parent: Node3D, node_name: String, radius: float, position: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position
	parent.add_child(instance)
	return instance

static func static_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, mat: Material, rotation: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = position
	body.rotation = rotation
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var visual: MeshInstance3D = box(body, node_name + "Mesh", size, Vector3.ZERO, mat)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(body)
	return body
