class_name LISPhysicsHost
extends Node
## LIS Physics SDK · 主机权威物理桥（可选适配层）
##
## 本层是**可选的**。SDK 不需要它也能跑单人物理。
## 它的作用是给多人工程一个明确的接入边界：
##
##   客户端：只发**意图**（谁是哪个玩家、想抓哪件东西、想松手/抛掷、朝向与位置）
##   主机  ：为每个远端玩家建一个代理适配器（LISFirstPersonAdapter），
##           用与本地玩家**完全同一条施力代码路径**把意图变成真实力
##
## 这样"第一人称交互力的实际作用点与多人世界中物体受到的力一致"才成立。
##
## ⚠ 本 SDK **不实现**网络传输本身。
##   ENet / SessionHub / CoopNet / 玩家身份 / 存档 / 背包 / 任务系统
##   都归各星球工程自己所有，SDK 绝不自动安装或覆盖它们。
##   本类只定义"意图进来之后物理世界该怎么响应"。
##
## ⚠ 已验证范围：双进程基础冒烟（成对启动 + 意图往返 + 力一致）。
##   高延迟、丢包、断线重连**未验证**（任务书 §12 明确不做专项研发）。

signal proxy_created(pid: int, adapter: LISFirstPersonAdapter)
signal proxy_removed(pid: int)
signal intent_applied(pid: int, kind: int, ok: bool)

## 主机权威（true）还是客户端只读镜像（false）。
@export var is_host: bool = true
## 远端代理的最大数量。
@export var max_proxies: int = 8
## 代理的交互射线长度。
@export var proxy_reach: float = 3.2
## 是否把登记的刚体切换到镜像模式（客户端）。
@export var mirror_registered_bodies: bool = true

## 登记的物理物体（主机广播 / 客户端镜像的对象）。
var registered: Array[Node3D] = []
## pid -> LISFirstPersonAdapter
var proxies: Dictionary = {}
var applied_intents: int = 0
var rejected_intents: int = 0


func register_body(node: Node3D) -> void:
	if node == null or registered.has(node):
		return
	registered.append(node)


func unregister_body(node: Node3D) -> void:
	registered.erase(node)


## 主机侧：为远端玩家准备一个代理（身体 + 相机 + 适配器）。
## 代理的相机位置与朝向由网络层每帧写入（这里只提供容器）。
func ensure_proxy(pid: int) -> LISFirstPersonAdapter:
	if proxies.has(pid):
		return proxies[pid] as LISFirstPersonAdapter
	if proxies.size() >= max_proxies:
		return null
	var root: Node3D = Node3D.new()
	root.name = "RemoteProxy_%d" % pid
	add_child(root)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = LISPhysics.LAYER_PLAYER
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.70
	cs.shape = cap
	body.add_child(cs)
	body.position = Vector3(0.0, -0.86, 0.0)
	root.add_child(body)
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	cam.current = false
	root.add_child(cam)
	var ad: LISFirstPersonAdapter = LISFirstPersonAdapter.new()
	ad.name = "Adapter"
	ad.read_input = false
	ad.player_id = pid
	ad.reach = proxy_reach
	root.add_child(ad)
	ad.body = root
	ad.camera = cam
	proxies[pid] = ad
	proxy_created.emit(pid, ad)
	return ad


## 网络层每帧调用：更新远端玩家的身体位置与相机朝向（这是"别的玩家看见他"的唯一来源）。
func update_proxy_pose(pid: int, eye: Vector3, forward: Vector3, body_pos: Vector3 = Vector3.INF) -> void:
	var ad: LISFirstPersonAdapter = proxies.get(pid) as LISFirstPersonAdapter
	if ad == null:
		ad = ensure_proxy(pid)
		if ad == null:
			return
	var root: Node3D = ad.get_parent() as Node3D
	if root != null:
		var bp: Vector3 = body_pos
		if not is_finite(bp.x) or not is_finite(bp.y) or not is_finite(bp.z):
			bp = eye - Vector3(0.0, 1.62, 0.0)
		root.global_position = bp
	if ad.camera != null:
		ad.camera.global_position = eye
		var d: Vector3 = forward.normalized()
		if d.length() > 0.01 and absf(d.dot(Vector3.UP)) < 0.98:
			ad.camera.look_at(eye + d, Vector3.UP)


## 主机侧：应用一个远端意图。返回是否成功。
func apply_intent(intent: LISFirstPersonIntent) -> bool:
	if not is_host or intent == null:
		rejected_intents += 1
		return false
	var ad: LISFirstPersonAdapter = proxies.get(intent.player_id) as LISFirstPersonAdapter
	if ad == null:
		ad = ensure_proxy(intent.player_id)
		if ad == null:
			rejected_intents += 1
			return false
	# 意图里的眼位 / 前向优先于本地代理位姿（网络传过来的是权威采样）。
	if intent.eye != Vector3.ZERO:
		update_proxy_pose(intent.player_id, intent.eye, intent.forward)
	var ok: bool = ad.execute_intent(intent)
	if ok:
		applied_intents += 1
	else:
		rejected_intents += 1
	intent_applied.emit(intent.player_id, intent.kind, ok)
	return ok


## 玩家退出：清掉他的持有关系与代理（不留下悬空引用）。
func remove_player(pid: int) -> void:
	var ad: LISFirstPersonAdapter = proxies.get(pid) as LISFirstPersonAdapter
	if ad == null:
		return
	if ad.grabber != null:
		ad.grabber.release(false)
	var root: Node3D = ad.get_parent() as Node3D
	if root != null:
		root.queue_free()
	proxies.erase(pid)
	proxy_removed.emit(pid)


## 客户端：把登记的物体切到只读镜像（本地不积分，避免第二个物理权威）。
func enter_mirror_mode() -> void:
	is_host = false
	if not mirror_registered_bodies:
		return
	for n: Node3D in registered:
		if n != null and is_instance_valid(n) and n.has_method("enable_mirror"):
			n.call("enable_mirror", true)


func exit_mirror_mode() -> void:
	if not mirror_registered_bodies:
		return
	for n: Node3D in registered:
		if n != null and is_instance_valid(n) and n.has_method("enable_mirror"):
			n.call("enable_mirror", false)


## 清理：所有远端退出时把他们的持有关系一并释放。
func _exit_tree() -> void:
	for pid: int in proxies.keys():
		var ad: LISFirstPersonAdapter = proxies[pid] as LISFirstPersonAdapter
		if ad != null and is_instance_valid(ad) and ad.grabber != null:
			ad.grabber.release(false)
	proxies.clear()


func stats() -> Dictionary:
	return {
		"is_host": is_host,
		"registered": registered.size(),
		"proxies": proxies.size(),
		"applied": applied_intents,
		"rejected": rejected_intents,
	}
