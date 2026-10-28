extends StaticBody3D

## 占位燃料。本轮不实现拾取、叼走、吞噬或任务结算，只作为可碰撞的场景对象。

var display_name := "占位燃料"
var fuel_amount := 1


func get_debug_text() -> String:
	return "%s ×%d" % [display_name, fuel_amount]
