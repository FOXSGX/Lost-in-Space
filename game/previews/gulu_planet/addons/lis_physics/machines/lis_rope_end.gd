class_name LISRopeEnd
extends LISBody
## LIS Physics SDK · 缆绳自由端（可抓握）
##
## 一个小的可抓刚体，通过球铰连在最后一节绳段上。玩家用准星抓住它，
## 靠移动身体产生牵引 —— 牵引力完全由弹簧力经绳段关节链传递到被牵引物体。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_rope_end.gd
## 解耦改动：继承 SDK 的 LISBody（原为 PhysProp），接口与抓握点几何保持一致。

## 所属缆绳。
var rope: LISRope = null
var _pending_pos: Vector3 = Vector3.ZERO
var _has_pending: bool = false


## 建链时先指定位置，configure() 之后再摆回去。
func set_pending_position(p: Vector3) -> void:
	_pending_pos = p
	_has_pending = true
	if _built:
		global_position = p
		rotation = Vector3.ZERO


func _ready() -> void:
	if profile == null:
		var p: LISBodyProfile = LISBodyProfile.new()
		p.display_name = "缆绳自由端"
		p.size = Vector3.ONE * 0.15
		p.mass_kg = 0.8
		p.friction = 0.55
		p.bounce = 0.05
		p.grip_handles = 0
		p.color = Color(0.92, 0.78, 0.30)
		p.liftable = true
		p.linear_damp = 0.15
		p.angular_damp = 1.5
		p.group_aliases = PackedStringArray()
		profile = p
	super()
	if _has_pending and _pending_pos != Vector3.ZERO:
		global_position = _pending_pos
		rotation = Vector3.ZERO


## 等效载荷质量：手抓这根绳时实际要对抗的重量（绳段 + 另一端货物）。
func effective_load_mass() -> float:
	var total: float = mass
	if rope == null:
		return total
	for s: RigidBody3D in rope.segments:
		if is_instance_valid(s):
			total += s.mass
	var load: Node3D = rope.get_tied_body()
	if load != null and is_instance_valid(load):
		var rb: RigidBody3D = load as RigidBody3D
		if rb != null:
			total += rb.mass
	return total


## 手持这根绳时"手到货箱"的距离（用于持握距离）。
func grip_span_distance(camera_pos: Vector3) -> float:
	var span: float = camera_pos.distance_to(global_position)
	if rope != null:
		span = maxf(span, rope.rest_length() * 0.85)
		var load: Node3D = rope.get_tied_body()
		if load != null and is_instance_valid(load):
			var rb: RigidBody3D = load as RigidBody3D
			if rb != null:
				span += LISPhysics.extent_along(LISContactProbe.shape_size(rb), Vector3.ONE)
	return span
