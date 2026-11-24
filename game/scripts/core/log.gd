extends RefCounted
## 极小的调试日志开关。
##
## 用法（不要加 `class_name`，用 preload 常量引用，避免依赖全局类注册）：
##     const Log := preload("res://scripts/core/log.gd")
##     Log.d("GATE", "open start height=%.2f" % height)
##
## 发布构建里 `enabled` 为 false，所有调用退化为一次静态布尔判断，
## 不再产生 stdout 写入（Windows 上重定向到日志文件时这些写入是同步落盘的，
## 在联机/低配机器上会变成可见的卡顿，也会淹没真正的错误）。

static var enabled: bool = OS.is_debug_build()


static func d(tag: String, message: String) -> void:
	if enabled:
		print("[", tag, "] ", message)


static func w(tag: String, message: String) -> void:
	if enabled:
		push_warning("[" + tag + "] " + message)
