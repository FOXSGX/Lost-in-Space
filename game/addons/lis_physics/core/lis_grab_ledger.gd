class_name LISGrabLedger
extends RefCounted
## LIS Physics SDK · 多持有者登记表
##
## "谁正在抓这件物体"必须只有一处真相，否则两名玩家同时松手时会互相踩。
## 本类为**任意** RigidBody3D 提供统一的持有者登记：
##   * 若物体是 LISBody，转调它自己的 holders 数组（保持信号与类型安全）；
##   * 否则把持有者的 instance_id 写进物体 metadata，不持有强引用，
##     因此不会阻止持有者被释放（"玩家离开场景时清理抓握引用"）。
##
## 上限固定 4（任务书：单人 / 双人 / 四人共同施力）。

const MAX_HOLDERS := 4
const META_KEY := "lis_holder_ids"


static func count(body: Node3D) -> int:
	if body == null or not is_instance_valid(body):
		return 0
	var lis: LISBody = body as LISBody
	if lis != null:
		return lis.holder_count()
	var ids: Array = body.get_meta(META_KEY, [])
	return ids.size()


static func is_held_by(body: Node3D, grabber: Node3D) -> bool:
	if body == null or grabber == null:
		return false
	var lis: LISBody = body as LISBody
	if lis != null:
		return lis.is_held_by(grabber)
	var ids: Array = body.get_meta(META_KEY, [])
	return ids.has(grabber.get_instance_id())


## 登记一个持有者。返回 false = 已达上限或参数非法。
static func add_holder(body: Node3D, grabber: Node3D, pid: int = 0) -> bool:
	if body == null or grabber == null or not is_instance_valid(body) or not is_instance_valid(grabber):
		return false
	var lis: LISBody = body as LISBody
	if lis != null:
		return lis.add_holder(grabber, pid)
	var ids: Array = (body.get_meta(META_KEY, []) as Array).duplicate()
	if ids.has(grabber.get_instance_id()):
		return true
	if ids.size() >= MAX_HOLDERS:
		return false
	ids.append(grabber.get_instance_id())
	body.set_meta(META_KEY, ids)
	var rb: RigidBody3D = body as RigidBody3D
	if rb != null:
		rb.sleeping = false
	return true


static func remove_holder(body: Node3D, grabber: Node3D) -> void:
	if body == null or grabber == null or not is_instance_valid(body):
		return
	var lis: LISBody = body as LISBody
	if lis != null:
		lis.remove_holder(grabber)
		return
	var ids: Array = body.get_meta(META_KEY, [])
	var id: int = grabber.get_instance_id()
	if not ids.has(id):
		return
	ids.erase(id)
	body.set_meta(META_KEY, ids)


## 清理已失效的持有者（instance_id 已无法解析）。返回清理数量。
static func prune(body: Node3D) -> int:
	if body == null or not is_instance_valid(body):
		return 0
	var lis: LISBody = body as LISBody
	if lis != null:
		return lis.prune_dead_holders()
	var ids: Array = body.get_meta(META_KEY, [])
	var keep: Array = []
	var removed: int = 0
	for raw: Variant in ids:
		var obj: Object = instance_from_id(int(raw))
		if obj == null or not is_instance_valid(obj):
			removed += 1
		else:
			keep.append(int(raw))
	if removed > 0:
		body.set_meta(META_KEY, keep)
	return removed


static func clear(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var lis: LISBody = body as LISBody
	if lis != null:
		lis.clear_holders()
		return
	body.set_meta(META_KEY, [])
