extends ShipSession3D
# Isolated preview: no hub UI, persistence, stock writes or network session.
func _ready() -> void:
	controller = get_parent() as Main3D
	persistence_enabled = false

func _process(_delta: float) -> void:
	pass

func broadcast() -> void:
	# Apply the host's local item snapshot to invalidate physical prop visuals,
	# exactly as the hub broadcast does, without hub UI, RPCs or save writes.
	if controller._items != null:
		controller._items.apply_state(controller._items.snapshot())

func has_panel() -> bool:
	return false

func _notify(_peer_id: int, message: String) -> void:
	get_parent().show_notice(message)
