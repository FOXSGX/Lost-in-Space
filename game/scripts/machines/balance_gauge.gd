class_name BalanceGauge
extends Node3D

## Physical analog deviation gauge. The needle is driven by the actual net
## moment of the two counterweight carts, never by a scripted "success" value.

var needle: Node3D
var _target_angle: float = 0.0
var _green_arc: Array[MeshInstance3D] = []


func build(radius: float = 0.46) -> void:
	var face_mat: StandardMaterial3D = MatLib.flat(Color(0.07, 0.08, 0.085), 0.55, 0.35)
	var rim_mat: Material = MatLib.dark_steel()
	var ring_mesh: CylinderMesh = CylinderMesh.new()
	ring_mesh.top_radius = radius
	ring_mesh.bottom_radius = radius
	ring_mesh.height = 0.06
	ring_mesh.radial_segments = 40
	var face: MeshInstance3D = MeshInstance3D.new()
	face.mesh = ring_mesh
	face.material_override = rim_mat
	face.rotation_degrees = Vector3(90, 0, 0)
	add_child(face)
	var inner_mesh: CylinderMesh = CylinderMesh.new()
	inner_mesh.top_radius = radius * 0.86
	inner_mesh.bottom_radius = radius * 0.86
	inner_mesh.height = 0.02
	inner_mesh.radial_segments = 40
	var inner: MeshInstance3D = MeshInstance3D.new()
	inner.mesh = inner_mesh
	inner.material_override = face_mat
	inner.position = Vector3(0, 0, 0.045)
	inner.rotation_degrees = Vector3(90, 0, 0)
	add_child(inner)
	# green capture arc at the top
	for i in range(9):
		var a: float = -0.26 + float(i) * 0.065
		var seg: MeshInstance3D = MeshInstance3D.new()
		var sm: BoxMesh = BoxMesh.new()
		sm.size = Vector3(0.035, radius * 0.16, 0.012)
		seg.mesh = sm
		seg.material_override = MatLib.emissive(Color(0.18, 0.95, 0.55), 0.9)
		seg.position = Vector3(sin(a) * radius * 0.74, cos(a) * radius * 0.74, 0.062)
		seg.rotation.z = a
		add_child(seg)
		_green_arc.append(seg)
	# red danger arcs
	for side in [-1.0, 1.0]:
		for i in range(5):
			var a2: float = side * (0.55 + float(i) * 0.11)
			var seg2: MeshInstance3D = MeshInstance3D.new()
			var sm2: BoxMesh = BoxMesh.new()
			sm2.size = Vector3(0.035, radius * 0.16, 0.012)
			seg2.mesh = sm2
			seg2.material_override = MatLib.emissive(Color(0.95, 0.24, 0.12), 0.8)
			seg2.position = Vector3(sin(a2) * radius * 0.74, cos(a2) * radius * 0.74, 0.062)
			seg2.rotation.z = a2
			add_child(seg2)
	# needle
	needle = Node3D.new()
	needle.name = "Needle"
	needle.position = Vector3(0, 0, 0.075)
	add_child(needle)
	var nm: BoxMesh = BoxMesh.new()
	nm.size = Vector3(0.026, radius * 0.72, 0.014)
	var needle_mesh: MeshInstance3D = MeshInstance3D.new()
	needle_mesh.mesh = nm
	needle_mesh.material_override = MatLib.emissive(Color(1.0, 0.78, 0.25), 1.1)
	needle_mesh.position = Vector3(0, radius * 0.33, 0)
	needle.add_child(needle_mesh)
	var hub_mesh: CylinderMesh = CylinderMesh.new()
	hub_mesh.top_radius = 0.055
	hub_mesh.bottom_radius = 0.055
	hub_mesh.height = 0.03
	hub_mesh.radial_segments = 12
	var hub: MeshInstance3D = MeshInstance3D.new()
	hub.mesh = hub_mesh
	hub.material_override = MatLib.steel()
	hub.rotation_degrees = Vector3(90, 0, 0)
	hub.position = Vector3(0, 0, 0.09)
	add_child(hub)


func update_net(net: float, capturable: bool) -> void:
	_target_angle = clampf(-net * 1.15, -1.05, 1.05)
	if needle != null:
		needle.rotation.z = lerpf(needle.rotation.z, _target_angle, 0.18)
	for seg in _green_arc:
		var mat: StandardMaterial3D = MatLib.emissive(Color(0.18, 1.0, 0.6) if capturable else Color(0.12, 0.5, 0.35), 1.3 if capturable else 0.45)
		seg.material_override = mat
