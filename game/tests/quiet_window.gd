class_name QuietCaptureWindow
extends RefCounted

## 截图/取证脚本专用：把 Godot 窗口放到屏幕外并禁止抢焦点。
## 不用于需要真实键鼠输入的测试（那些测试仍需要前台窗口）。


static func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-3200, -3200))
