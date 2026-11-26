class_name LISDemoPlayer
extends CharacterBody3D
## LIS Physics SDK · 示例用第一人称玩家（方式 A：CharacterBody3D）
##
## 这是**示例**，不是 SDK 核心。它演示"如何把一个普通 CharacterBody3D 第一人称
## 玩家接到 SDK 上"：整个接入只有三行（见 _ready 的 LISFirstPersonAdapter 部分）。
##
## 各星球自己的控制器不需要用这个脚本 —— 用你自己的，只要把
## LISFirstPersonAdapter 的 body / camera 填对，或实现 LISFirstPersonSource。
##
## 操作：WASD 移动 · Shift 加速 · 空格跳 · 鼠标环视
##       左键抓握/松手 · 右键松手 · X 抛掷 · Q/E 旋转持有物
##       R 复位场景
##
## 提示文字一律走 HUD，不用漂浮在空中的 3D 文字。

signal reset_requested()
signal interact_pressed()

const WALK_SPEED := 4.3
const SPRINT_SPEED := 6.2
const ACCELERATION := 26.0
const AIR_ACCELERATION := 6.0
const FRICTION := 14.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 5.4
const EYE_HEIGHT := 1.62
const MOUSE_SENSITIVITY := 0.0021
const PITCH_MIN := -1.35
const PITCH_MAX := 1.35

var camera: Camera3D
var yaw: float = 0.0
var pitch: float = 0.0
## SDK 接入点。
var adapter: LISFirstPersonAdapter
## 输入开关（脚本驱动 / 自动化测试时关掉）。
var input_enabled: bool = true

var _pitch_node: Node3D
var _head: Node3D


func _ready() -> void:
	collision_layer = LISPhysics.LAYER_PLAYER
	collision_mask = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PROP | LISPhysics.LAYER_MACHINE
	_build_body()
	_build_camera()
	_build_adapter()
	add_to_group("player")


func _build_body() -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0.0, 0.12, 0.0)
	add_child(cs)


func _build_camera() -> void:
	_pitch_node = Node3D.new()
	_pitch_node.name = "PitchPivot"
	_pitch_node.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(_pitch_node)
	_head = Node3D.new()
	_head.name = "Head"
	_pitch_node.add_child(_head)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 72.0
	camera.near = 0.05
	camera.current = true
	_head.add_child(camera)


## === SDK 接入（方式 A）—— 这就是全部 ===
func _build_adapter() -> void:
	adapter = LISFirstPersonAdapter.new()
	adapter.name = "PhysicsAdapter"
	adapter.body = self
	adapter.camera = camera
	adapter.player_id = 1
	adapter.reach = 3.2
	adapter.action_grab = &"lis_grab"
	adapter.action_release = &"lis_release"
	adapter.action_throw = &"lis_throw"
	adapter.action_rotate_left = &"lis_rotate_left"
	adapter.action_rotate_right = &"lis_rotate_right"
	adapter.action_move_forward = &"move_forward"
	adapter.action_move_back = &"move_back"
	adapter.action_move_left = &"move_left"
	adapter.action_move_right = &"move_right"
	add_child(adapter)
	# 手部锚点：纯视觉。真实受力仍由抓握弹簧在物体表面产生。
	var hand: Node3D = Node3D.new()
	hand.name = "HandAnchor"
	hand.position = Vector3(0.0, -0.12, -0.42)
	camera.add_child(hand)
	adapter.hand_anchor = null   # 设 null 时抓握目标点 = 相机前方 hold_distance
	# 若想让手部视觉跟随，把下面这行换成 adapter.hand_anchor = hand：
	#   adapter.hand_anchor = hand


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		yaw -= mm.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - mm.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		_apply_look()
	elif InputMap.has_action("lis_reset") and event.is_action_pressed("lis_reset"):
		reset_requested.emit()


func _apply_look() -> void:
	rotation.y = yaw
	if _pitch_node != null:
		_pitch_node.rotation.x = pitch


func _physics_process(delta: float) -> void:
	if input_enabled and _has_move_actions():
		_move(delta)
	else:
		# 让重力仍然生效，避免关输入后悬空
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = 0.0
		move_and_slide()


## 只在动作确实存在时才读输入：SDK 及其示例绝不假设使用者的 InputMap 结构，
## 也绝不向 InputMap 写任何东西。
func _has_move_actions() -> bool:
	return InputMap.has_action("move_left") and InputMap.has_action("move_right") \
		and InputMap.has_action("move_forward") and InputMap.has_action("move_back")


func _move(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	if not on_floor:
		velocity.y -= GRAVITY * delta
	elif InputMap.has_action("jump") and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish: Vector3 = transform.basis * Vector3(input.x, 0.0, input.y)
	wish.y = 0.0
	var sprinting: bool = InputMap.has_action("sprint") and Input.is_action_pressed("sprint")
	var speed: float = SPRINT_SPEED if sprinting else WALK_SPEED
	var accel: float = ACCELERATION if on_floor else AIR_ACCELERATION
	if wish.length() > 0.05:
		wish = wish.normalized()
		velocity.x = move_toward(velocity.x, wish.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, wish.z * speed, accel * delta)
	elif on_floor:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
	move_and_slide()


## 传送（示例的复位按钮 / 自动化脚本用）。
func teleport(pos: Vector3, new_yaw: float = 0.0, new_pitch: float = -0.08) -> void:
	global_position = pos
	yaw = new_yaw
	pitch = new_pitch
	_apply_look()
	velocity = Vector3.ZERO
