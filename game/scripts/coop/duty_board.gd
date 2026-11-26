class_name DutyBoard
extends Node3D

## Physical crew duty board in the hall. It shows, for every effective player,
## whether they have already done real work in phase A / B / C. This is the
## in-world version of the participation record - it exists so the team can see
## who still owes which station, instead of failing on an invisible score.

const MAX_ROWS := 4

var session: CoopSession
var kit: WorldKit
var header: Label3D
var rows: Array[Dictionary] = []
var _refresh: float = 0.0
var _built: bool = false


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	var dark: Material = MatLib.dark_steel()
	var steel: Material = MatLib.painted_steel(Color(0.22, 0.28, 0.30))
	# stand
	for sx in [-1.05, 1.05]:
		kit.box("BoardLeg", Vector3(0.12, 2.2, 0.12), Vector3(sx, 1.1, 0), steel, Vector3.ZERO, true)
		kit.box("BoardFoot", Vector3(0.44, 0.12, 0.60), Vector3(sx, 0.06, 0), dark, Vector3.ZERO, true)
	kit.box("BoardFrame", Vector3(2.5, 1.55, 0.14), Vector3(0, 2.35, 0), MatLib.metal(Color(0.14, 0.18, 0.19), 0.5, 0.6, 0.7), Vector3.ZERO, true)
	kit.box("BoardFace", Vector3(2.34, 1.40, 0.04), Vector3(0, 2.35, 0.09), MatLib.holo(Color(0.18, 0.42, 0.50), 0.30), Vector3.ZERO, false)
	kit.box("BoardHeader", Vector3(2.34, 0.10, 0.05), Vector3(0, 3.00, 0.10), MatLib.emissive(Color(0.35, 0.9, 1.0), 1.2), Vector3.ZERO, false)
	header = kit.label3d("全员参与 · 职责看板", Vector3(0, 2.90, 0.12), 0.0024, Color(0.85, 0.98, 1.0), 30)
	kit.label3d("A 稳定   B 事故   C 隔离", Vector3(0, 2.72, 0.12), 0.0018, Color(0.62, 0.86, 0.92), 20)
	for i in range(MAX_ROWS):
		var y: float = 2.47 - float(i) * 0.21
		var name_label: Label3D = kit.label3d("", Vector3(-1.05, y, 0.12), 0.0019, Color(0.88, 0.95, 1.0), 22)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var lamps: Array[MeshInstance3D] = []
		for k in range(3):
			var lamp: MeshInstance3D = MeshInstance3D.new()
			var sm: SphereMesh = SphereMesh.new()
			sm.radius = 0.055
			sm.height = 0.11
			sm.radial_segments = 10
			lamp.mesh = sm
			lamp.material_override = MatLib.emissive(Color(0.25, 0.3, 0.32), 0.5)
			lamp.position = Vector3(0.32 + float(k) * 0.30, y, 0.14)
			add_child(lamp)
			lamps.append(lamp)
		rows.append({"label": name_label, "lamps": lamps})
	kit.omni(Vector3(0, 2.6, 0.8), Color(0.45, 0.85, 1.0), 0.9, 3.4, false, "BoardLight")


func setup(p_session: CoopSession) -> void:
	session = p_session
	refresh_now()


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.35
	refresh_now()


func refresh_now() -> void:
	if session == null:
		return
	var ids: Array[int] = session.ledger.player_ids()
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var label: Label3D = row["label"] as Label3D
		var lamps: Array[MeshInstance3D] = row["lamps"] as Array[MeshInstance3D]
		if i >= ids.size():
			label.text = ""
			for lamp in lamps:
				lamp.visible = false
			continue
		for lamp in lamps:
			lamp.visible = true
		var pid: int = ids[i]
		var status: String = session.status_of(pid)
		var name: String = session.ledger.display_name(pid)
		var suffix: String = ""
		if status != "active":
			suffix = "（观战）" if status == "spectator" else "（离线）" if status == "disconnected" else "（暂离）"
		elif session.ledger.is_ready(pid):
			suffix = " 就绪"
		label.text = "P%d %s%s" % [pid, name, suffix]
		var phases: Array[String] = ["A", "B", "C"]
		for k in range(3):
			var done: bool = session.ledger.ready_for_phase(pid, phases[k])
			var col: Color = Color(0.25, 0.32, 0.34)
			if done:
				col = Color(0.18, 1.0, 0.55)
			elif status == "active":
				col = Color(1.0, 0.62, 0.12)
			lamps[k].material_override = MatLib.emissive(col, 2.0 if done else 1.0)
