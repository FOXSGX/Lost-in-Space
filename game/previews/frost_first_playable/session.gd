extends "res://previews/frost_layer1/session.gd"

func broadcast() -> void:
	if controller._items != null:
		controller._items._revision += 1

func _notify(peer_id: int, message: String) -> void:
	controller.tell(peer_id, message)
