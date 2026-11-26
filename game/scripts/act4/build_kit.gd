class_name BuildKit
extends RefCounted
## Small static builders used by the level, hammer rig and memory set pieces.
## Everything returns the visual node so callers can animate it.

static func box_visual(parent: Node3D, name_value: String, size: Vector3, position_value: Vector3, material: Material, rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.rotation_degrees = rotation_degrees_value
	instance.material_override = material
	parent.add_child(instance)
	return instance


static func cylinder_visual(parent: Node3D, name_value: String, radius: float, height: float, position_value: Vector3, material: Material, rotation_degrees_value: Vector3 = Vector3.ZERO, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.rotation_degrees = rotation_degrees_value
	instance.material_override = material
	parent.add_child(instance)
	return instance


static func sphere_visual(parent: Node3D, name_value: String, radius: float, position_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
	return instance


static func static_box(parent: Node3D, name_value: String, size: Vector3, position_value: Vector3, material: Material, rotation_degrees_value: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = name_value
	body.position = position_value
	body.rotation_degrees = rotation_degrees_value
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Collision"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var visual: MeshInstance3D = box_visual(body, "Mesh", size, Vector3.ZERO, material)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return body


static func static_cylinder(parent: Node3D, name_value: String, radius: float, height: float, position_value: Vector3, material: Material, rotation_degrees_value: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = name_value
	body.position = position_value
	body.rotation_degrees = rotation_degrees_value
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Collision"
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	body.add_child(shape)
	var visual: MeshInstance3D = cylinder_visual(body, "Mesh", radius, height, Vector3.ZERO, material)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return body


## A sloped walkable slab. `rise` is positive; the slab's low edge is at
## `low_edge`, the high edge at `low_edge + forward * length`.
static func ramp(parent: Node3D, name_value: String, width: float, length: float, rise: float, low_edge: Vector3, yaw_degrees: float, material: Material) -> StaticBody3D:
	var angle: float = atan2(rise, length)
	var slab_length: float = sqrt(length * length + rise * rise)
	var yaw: float = deg_to_rad(yaw_degrees)
	var forward: Vector3 = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = name_value
	body.position = low_edge + Vector3(0.0, rise * 0.5, 0.0) + forward * (length * 0.5)
	body.rotation = Vector3(angle, yaw, 0.0)
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Collision"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(width, 0.30, slab_length)
	shape.shape = box
	body.add_child(shape)
	var visual: MeshInstance3D = box_visual(body, "Mesh", Vector3(width, 0.30, slab_length), Vector3.ZERO, material)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return body


static func omni_light(parent: Node3D, name_value: String, position_value: Vector3, color: Color, energy: float, range_value: float, shadows: bool = false) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = name_value
	light.position = position_value
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.omni_attenuation = 1.25
	light.shadow_enabled = shadows
	light.shadow_bias = 0.08
	parent.add_child(light)
	return light


static func spot_light(parent: Node3D, name_value: String, position_value: Vector3, look_target: Vector3, color: Color, energy: float, range_value: float, angle_degrees: float = 35.0, shadows: bool = false) -> SpotLight3D:
	var light: SpotLight3D = SpotLight3D.new()
	light.name = name_value
	light.position = position_value
	light.light_color = color
	light.light_energy = energy
	light.spot_range = range_value
	light.spot_angle = angle_degrees
	light.spot_angle_attenuation = 1.4
	light.shadow_enabled = shadows
	parent.add_child(light)
	light.look_at(look_target, Vector3.UP)
	return light
