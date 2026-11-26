class_name GrabPoint
extends Node3D

## A physical grab rail on the maintenance catwalk. Press E to hold on; while
## holding, the deck carries the player and no amount of tilt slides them off.

var rig: CatwalkRig
var index: int = 0
var holder: PlayerController = null
var _mesh: MeshInstance3D
var area: Area3D


func build() -> void:
	add_to_group("interactable")
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.16, 0.10, 0.10)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Grip"
	_mesh.mesh = mesh
	_mesh.material_override = MatLib.grip()
	_mesh.position = Vector3(0, 0, -0.06)
	add_child(_mesh)
	var bar: BoxMesh = BoxMesh.new()
	bar.size = Vector3(0.5, 0.075, 0.075)
	var bar_mi: MeshInstance3D = MeshInstance3D.new()
	bar_mi.name = "GripBar"
	bar_mi.mesh = bar
	bar_mi.material_override = MatLib.painted_steel(Color(0.85, 0.62, 0.16))
	bar_mi.position = Vector3(0, 0, 0.04)
	add_child(bar_mi)
	# marker that can be seen from the deck without a HUD
	var marker: SphereMesh = SphereMesh.new()
	marker.radius = 0.045
	marker.height = 0.09
	marker.radial_segments = 8
	var marker_mi: MeshInstance3D = MeshInstance3D.new()
	marker_mi.name = "GripLamp"
	marker_mi.mesh = marker
	marker_mi.material_override = MatLib.emissive(Color(0.35, 0.95, 1.0), 1.4)
	marker_mi.position = Vector3(0, 0.12, 0.05)
	add_child(marker_mi)
	# R1: a real interaction area on the rail. Without it a ray aimed at the
	# rail passed through the (collisionless) grip and hit the deck behind it,
	# where the broad catwalk fallback could start the maintenance lock.
	area = Area3D.new()
	area.name = "GrabArea"
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitorable = true
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.34
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sphere
	area.add_child(col)
	add_child(area)


func _in_reach(p: PlayerController) -> bool:
	return p != null and p.global_position.distance_to(global_position) < 2.5


func get_prompt() -> String:
	if rig != null and not _in_reach(rig.player):
		return ""
	if holder != null and is_instance_valid(holder):
		if holder.grabbing and holder.grab_anchor == self:
			return "E 松开抓扶横杆"
		return "横杆已被 %s 抓住" % holder.name
	return "E 抓住抓扶横杆（冲击时不会被甩下）"


func interact(p: PlayerController) -> void:
	if rig == null:
		return
	if not _in_reach(p):
		return
	if holder != null and is_instance_valid(holder) and holder != p:
		return
	if p.grabbing and p.grab_anchor == self:
		rig.clear_grab(p)
		holder = null
		return
	if p.grabbing:
		p.stop_grab()
	if rig.set_grab(p, self, index):
		holder = p
