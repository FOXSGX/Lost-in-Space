extends StaticBody3D

## 占位燃料：可拾取、携带、放下；不做真实物理咬合或吞噬。
## 携带时只跟随玩家，不改 first-person controller；被扑中时由 gulu_app 调用掉落。

var display_name := "占位燃料"
var fuel_amount := 1
var carried := false

var _home_parent: Node
var _home_position := Vector3.ZERO
var _home_rotation := Vector3.ZERO
var _carry_target: Node3D
var _base_collision_layer := 1
var _base_collision_mask := 1

# 相对玩家脚底的位置：右前方、低于视线，避免完全挡住第一人称视角。
const CARRY_OFFSET := Vector3(0.42, 0.92, -0.62)


func _ready() -> void:
	_home_parent = get_parent()
	_home_position = global_position
	_home_rotation = global_rotation
	_base_collision_layer = collision_layer
	_base_collision_mask = collision_mask
	set_process(true)


func can_pick_up(player: CharacterBody3D, max_distance: float = 2.2) -> bool:
	if carried or player == null:
		return false
	return global_position.distance_to(player.global_position) <= max_distance


func pick_up(player: CharacterBody3D) -> void:
	if carried or player == null:
		return
	carried = true
	_carry_target = player
	collision_layer = 0
	collision_mask = 0


func drop_from_player(player: CharacterBody3D, forward_offset: float = 1.15) -> void:
	if not carried:
		return
	carried = false
	_carry_target = null
	if player != null:
		var forward := -player.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		forward = forward.normalized()
		global_position = player.global_position + forward * forward_offset
		global_position.y = player.global_position.y + 0.02
		global_rotation = Vector3(0.0, player.global_rotation.y, 0.0)
	collision_layer = _base_collision_layer
	collision_mask = _base_collision_mask


func reset_to_home() -> void:
	carried = false
	_carry_target = null
	global_position = _home_position
	global_rotation = _home_rotation
	collision_layer = _base_collision_layer
	collision_mask = _base_collision_mask


func _process(_delta: float) -> void:
	if not carried or not is_instance_valid(_carry_target):
		return
	global_position = _carry_target.to_global(CARRY_OFFSET)
	global_rotation = Vector3(0.0, _carry_target.global_rotation.y - 0.25, 0.0)


func get_debug_text() -> String:
	var suffix := " · 携带中" if carried else ""
	return "%s ×%d%s" % [display_name, fuel_amount, suffix]
