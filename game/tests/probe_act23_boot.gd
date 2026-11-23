extends SceneTree

func _initialize() -> void:
	print("PROBE_ACT23_START")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > 3000:
		var root_node: Node = current_scene
		if root_node == null:
			push_error("PROBE current_scene null")
			quit()
			return false
		var slice: Node = root_node.get_node_or_null("MovingCartSlice")
		var world: Node = slice if slice != null else root_node
		var player_node: Node = world.get_node_or_null("Player1")
		var cart_node: Node = world.get_node_or_null("MovingCart")
		var flow: Node = world.get_node_or_null("LevelFlow")
		var coop: Node = world.get_node_or_null("CoopNet")
		var yard: Node = world.get_node_or_null("RepairYard")
		var hud: Node = null
		for child in world.get_children():
			if child is CanvasLayer:
				hud = child
				break
		print("PROBE_ACT23 scene=", root_node.name, " slice=", slice != null,
			" player=", player_node != null, " cart=", cart_node != null,
			" flow=", flow != null, " coop=", coop != null, " yard=", yard != null,
			" hud=", hud != null)
		if slice != null and player_node != null and cart_node != null and flow != null and coop != null and yard != null and hud != null:
			print("PROBE_ACT23_OK")
		else:
			push_error("PROBE_ACT23_MISSING")
		quit()
	return false
