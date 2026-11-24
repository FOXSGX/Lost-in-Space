class_name CatwalkStation
extends Node3D

## Small interaction marker for one function of the maintenance catwalk
## (repair lock, rescue winch, emergency ladder). It owns the prompt text so the
## player always reads what the physical station is for.
##
## R1: each station also carries a small physics area on the interactable layer.
## Before this, the station was an intangible point: a ray aimed at the visible
## ladder/rail/console hit the catwalk structure behind it and resolved to the
## broad CatwalkRig fallback instead of the station the player was looking at.
## The area makes the aimed station the first ray hit, exactly like the other
## machines in the hall.

const STATION_LAYER := 8

var rig: CatwalkRig
var mode: String = "lock"
var area: Area3D


func setup(p_rig: CatwalkRig, p_mode: String) -> void:
	rig = p_rig
	mode = p_mode
	add_to_group("interactable")
	_build_area()


func _build_area() -> void:
	if area != null:
		return
	area = Area3D.new()
	area.name = "StationArea"
	area.collision_layer = STATION_LAYER
	area.collision_mask = 0
	area.monitorable = true
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.42 if mode != "ladder" else 0.60
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sphere
	area.add_child(col)
	add_child(area)


func get_prompt() -> String:
	if rig == null:
		return ""
	if not rig.station_zone_ok(mode, rig.player):
		return ""
	match mode:
		"lock":
			if rig.pins_seated < 2:
				return "E 在维修锁处重新固定安全销"
			if rig.preload_state < 0.99:
				return "E 预紧维修保险（收紧栈桥限位）"
			return "维修保险已预紧"
		"winch":
			if rig.has_downed_near_pad():
				return "E 操作救援卷扬机 · W 收绳把队友拉回栈桥"
			return "E 操作救援卷扬机（落点没有人需要救援）"
		"ladder":
			return "E 沿维修爬梯上到栈桥（受伤时无法攀爬）"
	return ""


func interact(p: PlayerController) -> void:
	if rig == null:
		return
	rig.station_interact(mode, p)
