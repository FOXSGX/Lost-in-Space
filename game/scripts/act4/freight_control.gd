class_name FreightControl
extends Node3D
## One physical control on the suspended freight platform or its docks.
##
## The node itself is the interaction point. It is deliberately small and its
## `get_interaction_reach()` is tighter than the global 3.1 m reach, so the
## driver really has to walk from the drive console to the brake or the cargo
## clamp. That distance is the solo/co-op tension the platform is built around.
##
## `platform` is intentionally typed as Node: FreightPlatform creates this
## class, and a typed back-reference would make the two scripts a cyclic
## class_name dependency.

var platform: Node
var kind: String = "drive"
var dock_id: String = ""
var reach: float = 1.65
var label: String = ""


func setup(platform_value: Node, kind_value: String, dock_value: String = "", reach_value: float = 1.65) -> void:
	platform = platform_value
	kind = kind_value
	dock_id = dock_value
	reach = reach_value
	label = kind_value + (":" + dock_id if not dock_id.is_empty() else "")
	add_to_group("interactable")


func get_interaction_position() -> Vector3:
	return global_position


func get_interaction_reach() -> float:
	return reach


func get_interaction_prompt(player: Node) -> String:
	if platform == null:
		return ""
	return str(platform.call("control_prompt", kind, player, dock_id))


func interact(player: Node) -> void:
	if platform == null:
		return
	platform.call("handle_control", kind, player, dock_id)
