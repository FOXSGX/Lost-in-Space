extends Node
## MECHANICS-004C · 冒烟：正式第四幕加载 + 门体真实节点结构

var stage: Node
var gate: Node3D


func _ready() -> void:
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	for _i in range(180):
		await get_tree().physics_frame
	gate = stage.get("gate") as Node3D
	if gate == null:
		print("FAIL gate missing")
		get_tree().quit(1)
		return
	var panel: Node = gate.get("_panel")
	var joint: Node = gate.get("_joint")
	var catch_beam: Node = gate.get("_catch")
	print("GATE panel=", panel, " class=", panel.get_class() if panel != null else "-")
	print("GATE joint=", joint, " class=", joint.get_class() if joint != null else "-")
	print("GATE catch=", catch_beam, " class=", catch_beam.get_class() if catch_beam != null else "-")
	var diag: Dictionary = gate.call("get_diagnostics")
	print("DIAG ", JSON.stringify(_clean(diag)))
	# 门静止 3 秒后应当仍在关闭位（重力沿滑动轴被关节 + 门槛托住）
	for _i in range(180):
		await get_tree().physics_frame
	var diag2: Dictionary = gate.call("get_diagnostics")
	print("DIAG_REST ", JSON.stringify(_clean(diag2)))
	# 未解锁时 open() 必须被拒绝
	gate.call("open")
	for _i in range(90):
		await get_tree().physics_frame
	var diag3: Dictionary = gate.call("get_diagnostics")
	print("DIAG_AFTER_REFUSED ", JSON.stringify(_clean(diag3)))
	# 解锁并开门
	gate.call("unlock", "smoke")
	gate.call("open")
	var peak_motor := 0.0
	var peak_v := 0.0
	for _i in range(600):
		await get_tree().physics_frame
		peak_motor = maxf(peak_motor, absf(float(gate.get("motor_force"))))
		peak_v = maxf(peak_v, absf(float(gate.get("velocity"))))
	var diag4: Dictionary = gate.call("get_diagnostics")
	print("DIAG_OPEN ", JSON.stringify(_clean(diag4)))
	print("PEAKS motor=%.1f v=%.3f" % [peak_motor, peak_v])
	# 失电测试：电机断电后门是否掉落
	gate.set("powered", false)
	for _i in range(240):
		await get_tree().physics_frame
	var diag5: Dictionary = gate.call("get_diagnostics")
	print("DIAG_UNPOWERED ", JSON.stringify(_clean(diag5)))
	print("SMOKE_DONE")
	get_tree().quit(0)


func _clean(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d.keys():
		var v: Variant = d[k]
		if v is Vector3:
			out[str(k)] = str((v as Vector3).snapped(Vector3(0.001, 0.001, 0.001)))
		elif v is float:
			out[str(k)] = snappedf(float(v), 0.001)
		else:
			out[str(k)] = v
	return out
