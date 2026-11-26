extends Node

## 手柄泵：只在暂停时仍然需要读 Start 键，所以单独挂在 PROCESS_MODE_ALWAYS 的节点上。
## 主场景（GuluPlanetPreview）保持可暂停，物理/计时/AI 的冻结逻辑完全不变。
## 不持有任何玩法状态，只把轮询转交给 GuluApp._poll_pad_actions()。

var target: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if target != null and is_instance_valid(target):
		target.call("_poll_pad_actions")
