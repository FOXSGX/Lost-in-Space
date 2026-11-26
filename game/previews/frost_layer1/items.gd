extends CrewItems3D

func _refresh_held() -> void:
	super._refresh_held()
	var record: Dictionary = _held.get(1,{})
	var model: Node3D = record.get("node") as Node3D
	var player: SpacePlayer3D = controller.players.get(1) as SpacePlayer3D
	if model != null and player != null and model.get_parent() != player._camera:
		model.reparent(player._camera)
		model.position = Vector3(0.32,-0.42,-0.72)
		model.rotation = Vector3.ZERO
		model.scale = Vector3.ONE * 0.65
