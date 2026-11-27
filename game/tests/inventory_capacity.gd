extends SceneTree

## 四格手持栏验收：容量、1–4 输入、HUD 格子数、旧两格快照补齐、满格拒绝。

var main: Main3D
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main.network_port = 28421
	main._ship_session.persistence_enabled = false
	main._create_host()
	await process_frame
	await process_frame

	var items := main._items as CrewItems3D
	check(CrewItems3D.CAPACITY == 4, "手持容量不是 4")
	check(CrewItems3D.EQUIPMENT_CAPACITY == 2, "装备容量被误改")
	check(InputMap.has_action("slot_3") and InputMap.has_action("slot_4"), "缺少 3/4 选格输入")
	check(items._cells.size() == 4, "底部 HUD 没有 4 个手持格")
	check(items._equipment_cells.size() == 2, "装备 HUD 格数被误改")
	check(items._bar.size.x >= 300.0, "四格 HUD 宽度没有扩展")

	# 旧两格快照：补齐到 4，保留原选格，不丢物品。
	items.bags[1] = {"slots": [{"kind": "medical"}, {"kind": "oxygen"}], "selected": 1}
	var bag := items.ensure_bag(1)
	check(bag.slots.size() == 4, "旧两格背包没有补齐到 4")
	check(int(bag.selected) == 1, "旧背包选格被重置")
	check(items.count_kind(1, "medical") == 1 and items.count_kind(1, "oxygen") == 1, "旧背包物品丢失")

	# 网络旧快照同样补齐，并钳制越界选格。
	items.apply_state({"bags": {1: {"slots": [{"kind": "medical"}], "selected": 9}}, "drops": [], "training_saved": {}, "next_uid": items.next_uid})
	bag = items.ensure_bag(1)
	check(bag.slots.size() == 4, "apply_state 没有补齐两格快照")
	check(int(bag.selected) == 3, "越界选格没有被钳制到最后一格")

	# 满 4 格拒绝第 5 件。
	for index: int in 4:
		bag.slots[index] = {"kind": "hologram"}
	var stock_before := int(main._ship_session.stock.medical)
	var added := items.add_item(1, "medical", -1, {}, true)
	check(not added and items.occupied(1) == 4, "满四格仍能放进第 5 件")
	check(int(main._ship_session.stock.medical) == stock_before, "满格失败仍扣了共享库存")

	main.queue_free()
	await process_frame
	print("INVENTORY_CAPACITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
