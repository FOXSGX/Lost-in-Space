extends SceneTree

## Act4 bell-hammer impact geometry (audit R-15).
##
## The hammer used to stop with its head 0.22 m ABOVE the strike plate, so the
## "impact" frame showed a visible gap and `struck` reported a hard-coded
## position that never touched anything. This probe builds the rig standalone,
## puts it exactly at IMPACT_ANGLE and compares the real AABBs.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("HAMMER ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	var rig: HammerRig = HammerRig.new()
	root.add_child(rig)
	rig.build()
	await physics_frame
	await physics_frame

	var head: Node3D = rig.get("_head") as Node3D
	check(head != null, "hammer head resolved")
	if head == null:
		quit(1)
		return

	var plate: MeshInstance3D = rig.get_node_or_null("StrikePlate") as MeshInstance3D
	check(plate != null, "strike plate resolved")
	if plate == null:
		quit(1)
		return

	# Freeze the rig at the frame the strike would happen.
	rig.set("angle", HammerRig.IMPACT_ANGLE)
	rig.set("mode", "idle")
	rig.call("_update_visuals")
	await physics_frame

	var head_box: AABB = _world_aabb(head)
	var plate_box: AABB = _world_aabb(plate)
	var gap: float = head_box.position.y - (plate_box.position.y + plate_box.size.y)
	# 撞击帧的正确几何是"接触"：锤头底面与砧面贴合或轻微咬入。
	# 悬空（gap > 0）说明锤子停在半空打空；咬入过深说明实体穿模。
	# 实测重叠 0.133 m，这条留 0.25 m 上限只拦真正的穿模。
	check(gap <= 0.02, "hammer head reaches the strike plate at impact angle", {
		"head_bottom": snappedf(head_box.position.y, 0.001),
		"plate_top": snappedf(plate_box.position.y + plate_box.size.y, 0.001),
		"gap": snappedf(gap, 0.001),
	})
	check(gap >= -0.25, "hammer head does not sink through the plate", {
		"gap": snappedf(gap, 0.001),
	})
	# Head must actually be over the plate in plan view, not beside it.
	var head_center: Vector3 = head_box.get_center()
	var plate_center: Vector3 = plate_box.get_center()
	var plan_offset: float = Vector2(head_center.x - plate_center.x, head_center.z - plate_center.z).length()
	check(plan_offset < 0.45, "hammer head is above the plate in plan view", {
		"plan_offset": snappedf(plan_offset, 0.001),
	})

	print("ACT4_HAMMER_REPORT ", JSON.stringify({"checks": checks, "failures": failures, "ok": failures == 0}))
	quit(0 if failures == 0 else 1)


func _world_aabb(node: Node3D) -> AABB:
	var total: AABB = AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		total = box if first else total.merge(box)
		first = false
	if first and node is MeshInstance3D:
		var self_mesh: MeshInstance3D = node as MeshInstance3D
		if self_mesh.mesh != null:
			total = self_mesh.global_transform * self_mesh.mesh.get_aabb()
	return total
