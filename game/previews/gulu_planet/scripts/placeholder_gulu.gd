extends Node3D

## 占位咕噜。本轮没有发现、追逐、叼走或声音行为，只提供可替换的视觉与碰撞占位。

var display_name := "占位咕噜"
var state := "待机"
var body_color := Color("#67b98d")


func get_debug_text() -> String:
	return "%s · %s" % [display_name, state]
