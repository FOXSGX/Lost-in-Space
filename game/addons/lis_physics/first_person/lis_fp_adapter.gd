class_name LISFirstPersonAdapter
extends Node3D
## LIS Physics SDK · 第一人称交互适配器
##
## 这是"接入层"。它把**任意**第一人称控制器翻译成 SDK 的交互意图，
## 然后把意图交给 LISGrabber 施真实力。它自己不做任何物理积分。
##
## 两种接入方式（同一份抓握实现，不复制）：
##
##   方式 A —— CharacterBody3D 第一人称玩家（当前主要应用方式）
##     把本节点加为玩家子节点，填 body / camera 两个导出字段即可。
##
##   方式 B —— 自定义第一人称控制器（不同节点树 / 输入封装）
##     写一个 extends LISFirstPersonSource 的脚本，赋给 source 字段。
##     SDK 只调用协议方法，不知道你的节点树长什么样。
##
## 输入：默认**不读任何固定 InputMap 动作**。若给了动作名且工程里存在该动作，
## 才会响应；不存在就静默跳过（不报错、不篡改 InputMap）。

signal target_changed(target: Node3D)
signal grabbed(body: RigidBody3D)
signal released(body: RigidBody3D, thrown: bool)
signal blocked_changed(blocked: bool)

# --- 接入（方式 A）--------------------------------------------------------
## 玩家身体（CharacterBody3D 或任意 Node3D）。为空时用本节点的父节点。
@export var body: Node3D
## 第一人称相机。为空时在 body 子树里自动找第一个 Camera3D。
@export var camera: Camera3D
## 玩家唯一身份。1 = 主机 / 单人。
@export var player_id: int = 1

# --- 接入（方式 B）--------------------------------------------------------
## 自定义控制器协议节点。填写后优先于 body / camera 导出字段。
@export var source: LISFirstPersonSource

# --- 交互参数 -------------------------------------------------------------
## 准星射线长度（m）。
@export var reach: float = 3.2
## 交互射线碰撞掩码。默认只选可交互刚体层与机械层。
@export_flags_3d_physics var ray_mask: int = LISPhysics.DEFAULT_RAY_MASK
## 射线是否穿透玩家自身与持有物（必须排除，否则一抓就撞到自己）。
@export var exclude_held_from_ray: bool = true
## 世界空间手部锚点（可选，用于第一人称手部视觉模型）。
@export var hand_anchor: Node3D
## 是否由本节点采样输入。脚本驱动的测试 / 远端代理应设为 false。
@export var read_input: bool = true

# --- 输入动作名（可留空；留空 = 不响应）------------------------------------
@export var action_grab: StringName = &""
@export var action_release: StringName = &""
@export var action_throw: StringName = &""
@export var action_rotate_left: StringName = &""
@export var action_rotate_right: StringName = &""
## 推挤方向用的移动动作（两项一对）。留空 = 不施加身体推力。
@export var action_move_forward: StringName = &""
@export var action_move_back: StringName = &""
@export var action_move_left: StringName = &""
@export var action_move_right: StringName = &""

# --- 身体推挤 -------------------------------------------------------------
## 玩家用身体顶住物体时施加的力上限（N）。
@export var push_force: float = 780.0
## 是否启用身体推挤（把角色挡住的接触转成真实推力）。
@export var enable_body_push: bool = true
## 推挤需要的最小输入强度。
@export var push_min_input: float = 0.12

# --- 运行时 ---------------------------------------------------------------
var grabber: LISGrabber
## 准星当前指向的可交互刚体。
var current_target: RigidBody3D = null
## 最近一次射线命中的世界坐标（供准星 HUD 显示）。
var hit_point: Vector3 = Vector3.ZERO
var hit_distance: float = 0.0
var blocked: bool = false
var push_events: int = 0
var last_push_force: float = 0.0

var _ray: PhysicsRayQueryParameters3D
var _last_target_name: String = ""


func _ready() -> void:
	_resolve_endpoints()
	if grabber == null:
		grabber = LISGrabber.new()
		grabber.name = "LISGrabber"
		add_child(grabber)
	_apply_capabilities()
	grabber.setup(_player_body(), _fp_camera(), player_id)
	grabber.set_hand_anchor(_hand_anchor())
	grabber.hold_changed.connect(_on_hold_changed)
	grabber.grip_slipped.connect(_on_grip_slipped)


func _resolve_endpoints() -> void:
	if source != null and is_instance_valid(source):
		var cam: Camera3D = source.fp_camera()
		if cam != null:
			camera = cam
		var b: Node3D = source.fp_body()
		if b != null:
			body = b
		player_id = source.fp_player_id()
	if body == null:
		body = get_parent() as Node3D
	# 只有在**没有自定义控制器协议**时，才允许"在玩家子树里自动找相机"。
	#
	# 这条限制很重要：一旦使用者显式提供了 source，就应该由协议回答
	# "我的相机是哪个"。若协议返回 null 却去子树里搜索，会把场景里
	# **别人的相机**（或任意一个碰巧存在的 Camera3D）当成自己的，
	# 于是"协议不完整"的自检照样报告可用，抓握用错视角 —— 实测就是这么发生的。
	if camera == null and source == null and body != null:
		camera = _find_camera(body)


func _find_camera(root: Node) -> Camera3D:
	if root is Camera3D:
		return root as Camera3D
	for c: Node in root.get_children():
		var found: Camera3D = _find_camera(c)
		if found != null:
			return found
	return null


func _player_body() -> Node3D:
	if source != null and is_instance_valid(source):
		var b: Node3D = source.fp_body()
		if b != null:
			return b
	return body


func _fp_camera() -> Camera3D:
	if source != null and is_instance_valid(source):
		var c: Camera3D = source.fp_camera()
		if c != null:
			return c
	return camera


func _hand_anchor() -> Node3D:
	if hand_anchor != null and is_instance_valid(hand_anchor):
		return hand_anchor
	if source != null and is_instance_valid(source):
		return source.fp_hand_anchor()
	return null


func _apply_capabilities() -> void:
	if grabber == null or source == null or not is_instance_valid(source):
		return
	var lift: float = source.fp_max_lift_force()
	var drag: float = source.fp_max_drag_force()
	var torque: float = source.fp_palm_torque_max()
	var lift_ok: float = lift if lift > 0.0 else grabber.lift_force
	var drag_ok: float = drag if drag > 0.0 else grabber.drag_force
	var torque_ok: float = torque if torque > 0.0 else grabber.palm_torque_max
	grabber.set_capabilities(lift_ok, drag_ok, grabber.max_lift_mass, torque_ok, grabber.palm_alpha_max)


# ---------------------------------------------------------------------------
# 准星选择
# ---------------------------------------------------------------------------

## 从相机沿前向打一条射线，返回射中的可交互刚体（没有则 null）。
##
## 语义：**射线被任何东西挡住就选不中**。挡住射线的不一定是刚体
## （墙是 StaticBody3D），所以这里对"命中了但不是刚体"的情况返回 null ——
## 否则准星会"穿过墙"选中后面的箱子，这正是第一人称交互最常见的错误。
func update_target() -> RigidBody3D:
	current_target = null
	hit_distance = 0.0
	blocked = false
	var cam: Camera3D = _fp_camera()
	if cam == null or not is_instance_valid(cam):
		_emit_target_if_changed()
		return null
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	if space == null:
		_emit_target_if_changed()
		return null
	var from: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_transform.basis.z
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
	_ray.from = from
	_ray.to = from + dir * reach
	# 射线掩码必须包含世界层，否则墙挡不住准星（会"穿墙选中"）。
	_ray.collision_mask = ray_mask | LISPhysics.LAYER_WORLD
	var exclusions: Array[RID] = []
	var b: Node3D = _player_body()
	if b is CollisionObject3D:
		exclusions.append((b as CollisionObject3D).get_rid())
	if exclude_held_from_ray and grabber != null and grabber.is_holding():
		exclusions.append(grabber.held.get_rid())
	_ray.exclude = exclusions
	var res: Dictionary = space.intersect_ray(_ray)
	if not res.is_empty():
		hit_point = res.get("position", from) as Vector3
		hit_distance = from.distance_to(hit_point)
		var col: Object = res.get("collider")
		var rb: RigidBody3D = col as RigidBody3D
		if rb != null:
			current_target = rb
			blocked = _is_blocked_body(rb)
	_emit_target_if_changed()
	return current_target


func _is_blocked_body(rb: RigidBody3D) -> bool:
	var lm: LISBody = rb as LISBody
	if lm != null:
		return lm.is_blocked()
	return false


func _emit_target_if_changed() -> void:
	var nm: String = "" if current_target == null else str(current_target.name)
	if nm != _last_target_name:
		_last_target_name = nm
		target_changed.emit(current_target)


# ---------------------------------------------------------------------------
# 意图执行（本地输入与远端代理共用同一入口）
# ---------------------------------------------------------------------------

## 抓握当前准星目标。返回是否成功。
func grab_current() -> bool:
	if grabber == null:
		return false
	var tgt: RigidBody3D = current_target
	if tgt == null:
		tgt = update_target()
	if tgt == null:
		return false
	var ok: bool = grabber.try_grab(tgt)
	if ok:
		grabbed.emit(tgt)
	return ok


## 抓握指定刚体（供远端意图 / 脚本调用）。
func grab(body_to_grab: RigidBody3D) -> bool:
	if grabber == null or body_to_grab == null:
		return false
	var ok: bool = grabber.try_grab(body_to_grab)
	if ok:
		grabbed.emit(body_to_grab)
	return ok


func release_held(thrown: bool = false) -> void:
	if grabber == null:
		return
	var b: RigidBody3D = grabber.held
	grabber.release(thrown)
	if b != null:
		released.emit(b, thrown)


func rotate_held(degrees: float) -> void:
	if grabber != null:
		grabber.rotate_held(degrees)


func is_holding() -> bool:
	return grabber != null and grabber.is_holding()


## 执行一个意图（远端代理 / 网络层调用）。
func execute_intent(intent: LISFirstPersonIntent) -> bool:
	if intent == null or grabber == null:
		return false
	match intent.kind:
		LISFirstPersonIntent.Kind.GRAB:
			var rb: RigidBody3D = intent.target as RigidBody3D
			if rb == null:
				return false
			return grab(rb)
		LISFirstPersonIntent.Kind.RELEASE:
			release_held(false)
			return true
		LISFirstPersonIntent.Kind.THROW:
			release_held(true)
			return true
		LISFirstPersonIntent.Kind.ROTATE:
			rotate_held(intent.degrees)
			return true
		_:
			return false


# ---------------------------------------------------------------------------
# 每帧
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if grabber == null:
		return
	if get_tree().paused:
		return
	update_target()
	if read_input:
		_handle_input()
	if enable_body_push:
		_apply_body_push(delta)
	blocked = grabber.is_holding() and (grabber.saturated_frames > 6)


func _handle_input() -> void:
	if action_grab != &"" and _just(action_grab):
		if is_holding():
			release_held(false)
		else:
			grab_current()
	if action_release != &"" and _just(action_release):
		release_held(false)
	if action_throw != &"" and _just(action_throw):
		release_held(true)
	if action_rotate_left != &"" and _just(action_rotate_left):
		rotate_held(-30.0)
	if action_rotate_right != &"" and _just(action_rotate_right):
		rotate_held(30.0)


## 只在动作**存在**时读取，不向 InputMap 写任何东西。
func _just(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	return Input.is_action_just_pressed(action)


func _move_vector() -> Vector2:
	if not (InputMap.has_action(action_move_forward) and InputMap.has_action(action_move_back)
			and InputMap.has_action(action_move_left) and InputMap.has_action(action_move_right)):
		return Vector2.ZERO
	return Input.get_vector(action_move_left, action_move_right, action_move_forward, action_move_back)


## 把"角色被刚体挡住"转成作用在真实接触点上的推力。
## 站着不动不会凭空推动任何东西；两股力在物理引擎里自然相加。
func _apply_body_push(delta: float) -> void:
	if not read_input:
		return
	var b: Node3D = _player_body()
	var cb: CharacterBody3D = b as CharacterBody3D
	if cb == null or not cb.is_on_floor():
		return
	var input: Vector2 = _move_vector()
	if input.length() < push_min_input:
		return
	var wish: Vector3 = cb.transform.basis * Vector3(input.x, 0.0, input.y)
	wish.y = 0.0
	if wish.length() < 0.05:
		return
	wish = wish.normalized()
	var strength: float = push_force * clampf(input.length(), 0.0, 1.0)
	var count: int = cb.get_slide_collision_count()
	for i in range(count):
		var collision: KinematicCollision3D = cb.get_slide_collision(i)
		var obj: Object = collision.get_collider()
		var rb: RigidBody3D = obj as RigidBody3D
		if rb == null or rb.freeze:
			continue
		var normal: Vector3 = collision.get_normal()
		if normal.dot(wish) > -0.12:
			continue
		var point: Vector3 = collision.get_position()
		rb.apply_force(wish * strength, point - rb.global_position)
		push_events += 1
		last_push_force = strength
		var _unused: float = delta


# ---------------------------------------------------------------------------
# 信号转发
# ---------------------------------------------------------------------------

func _on_hold_changed(_body: RigidBody3D) -> void:
	pass


func _on_grip_slipped(_reason: String) -> void:
	pass


# ---------------------------------------------------------------------------
# 自检（安装检查工具调用）
# ---------------------------------------------------------------------------

## 返回问题列表；空数组 = 接入正确。
func validate_setup() -> PackedStringArray:
	var problems := PackedStringArray()
	if source != null and is_instance_valid(source):
		var why: String = source.is_valid_source()
		if why != "":
			problems.append("自定义控制器协议不完整：%s" % why)
	var cam: Camera3D = _fp_camera()
	if cam == null:
		problems.append("找不到第一人称 Camera3D：请填 camera 字段或实现 fp_camera()")
	if _player_body() == null:
		problems.append("找不到玩家身体：请填 body 字段或实现 fp_body()")
	if grabber == null:
		problems.append("抓握器未初始化（_ready 未执行）")
	if reach <= 0.0:
		problems.append("reach 必须 > 0")
	if ray_mask == 0:
		problems.append("ray_mask 为 0：准星射线选不中任何物体")
	return problems


func describe() -> String:
	var who: String = "source" if (source != null and is_instance_valid(source)) else "direct"
	return "LISFirstPersonAdapter pid=%d (%s) · held=%s · target=%s" % [
		player_id, who,
		grabber.describe() if grabber != null else "n/a",
		"none" if current_target == null else str(current_target.name)]
