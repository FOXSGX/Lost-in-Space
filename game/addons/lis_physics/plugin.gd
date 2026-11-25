@tool
extends EditorPlugin
## LIS Physics SDK · 编辑器插件入口
##
## 设计约束（任务书 §15）：SDK 导入后**不得**自动修改使用者工程。
## 所以本插件在启用/禁用时不做任何写操作：
##   * 不改主场景、不改玩家控制器、不改全局重力、不改物理帧率；
##   * 不改 Jolt 求解器参数、不改 InputMap、不改碰撞层名称；
##   * 不注册 autoload、不碰会话系统、不改渲染设置。
##
## 唯一行为是往输出面板打印一行提示，告诉使用者下一步该做什么。
## 真正的工程体检在 `addons/lis_physics/tools/lis_project_check.gd`，
## 它只报告与给建议，绝不覆盖用户配置。

const SDK_VERSION := "1.0.0-rc1"


func _enter_tree() -> void:
	print("[LIS Physics] SDK %s 已启用。本插件不会修改项目配置。" % SDK_VERSION)
	print("[LIS Physics] 工程体检：godot --headless --path . --script res://addons/lis_physics/tools/lis_project_check.gd")


func _exit_tree() -> void:
	print("[LIS Physics] SDK 已禁用（项目配置未被改动）。")
