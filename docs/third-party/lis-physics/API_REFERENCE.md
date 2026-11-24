# API 参考（API_REFERENCE）

SDK 版本 1.0.0-rc1。全部公共类名以 `LIS` 前缀开头，便于与工程自有类区分。

约定：

* 所有 `Vector3` 单位是米，质量单位是千克，力是牛顿，力矩是牛·米；
* 时间为秒；
* 标「只读」的字段请勿写入；
* 标「必须显式调用」的方法是使用者的责任。

---

## core

### `LISPhysics`（extends RefCounted，纯静态）

全局常量与物理小工具。不持有任何节点、不读写项目设置。

**常量**

| 名称 | 值 | 说明 |
| --- | --- | --- |
| `SDK_VERSION` | `"1.0.0-rc1"` | 版本 |
| `SDK_NAME` / `SDK_ID` | `"LIS Physics"` / `"lis_physics"` | |
| `REQUIRED_GODOT` | `"4.7"` | 建议版本 |
| `REQUIRED_PHYSICS_ENGINE` | `"Jolt Physics"` | |
| `LAYER_WORLD` | `1` | 静态世界 |
| `LAYER_PLAYER` | `2` | 玩家身体 |
| `LAYER_PROP` | `4` | 可交互刚体（默认） |
| `LAYER_MACHINE` | `8` | 机械设备 |
| `LAYER_TRIGGER` | `16` | 触发器 |
| `DEFAULT_BODY_LAYER` | `4` | |
| `DEFAULT_BODY_MASK` | `1\|2\|4` | |
| `DEFAULT_RAY_MASK` | `4\|8` | |

**静态方法**

| 签名 | 说明 |
| --- | --- |
| `layer_bit(index: int) -> int` | 第 index 层（1..32）对应的位值 |
| `layers_in(mask: int) -> Array[int]` | 掩码里包含哪些层序号 |
| `gravity() -> float` | 项目重力（只读） |
| `physics_engine_name() -> String` | 当前 3D 物理引擎名 |
| `physics_ticks_per_second() -> int` | 物理帧率 |
| `mass_from_density(size: Vector3, density: float) -> float` | 由尺寸与密度推质量 |
| `box_inertia(mass: float, size: Vector3) -> Vector3` | 均质长方体主转动惯量 |
| `inertia_about(body: RigidBody3D, axis_world: Vector3, size: Vector3) -> float` | 绕世界轴的转动惯量估算 |
| `extent_along(size: Vector3, dir: Vector3) -> float` | 沿某方向的半展宽 |
| `clamp_length(v: Vector3, limit: float) -> Vector3` | 按最大长度截断向量 |
| `is_finite_vec3(v: Vector3) -> bool` | NaN / INF 检测 |
| `version_string() -> String` | 版本串 |

### `LISBodyProfile`（extends Resource）

一件物体的**全部真实物理参数**。

**导出字段**

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `display_name` | String | `"物理物体"` | 显示名 |
| `tags` | PackedStringArray | 空 | 供使用者自己筛选 |
| `size` | Vector3 | `(0.6,0.6,0.6)` | 外形尺寸（米） |
| `mass_kg` | float | `12.0` | 质量（kg），下限 0.05 |
| `gravity_scale` | float | `1.0` | |
| `liftable` | bool | `true` | false = 只能贴地推/拖 |
| `friction` | float | `0.7` | |
| `bounce` | float | `0.02` | |
| `rough` | bool | `true` | true = 只用本物体摩擦 |
| `linear_damp` / `angular_damp` | float | `0.06` / `0.35` | |
| `can_sleep` | bool | `true` | |
| `continuous_cd` | bool | `true` | |
| `contact_monitor` | bool | `true` | 受阻判定需要它 |
| `max_contacts` | int | `4` | |
| `collision_layer` / `collision_mask` | int（flags） | `4` / `1\|2\|4` | 位值 |
| `use_custom_center_of_mass` | bool | `false` | |
| `center_of_mass` | Vector3 | `ZERO` | |
| `inertia` | Vector3 | `ZERO` | 0 = 交给引擎 |
| `color` / `metallic` / `roughness` | | | 外观 |
| `emission` / `emission_energy` | bool / float | | |
| `grip_handles` | int | `2` | 表面把手数量（纯视觉） |
| `interactable` | bool | `true` | 是否加入交互组 |
| `group_aliases` | PackedStringArray | 空 | 兼容旧工程的组名 |

**方法**

| 签名 | 说明 |
| --- | --- |
| `sanitize() -> PackedStringArray` | 越界参数修正，返回修正说明 |
| `theoretical_inertia() -> Vector3` | 均质理论惯量（对齐用） |
| `describe() -> String` | 一行摘要 |

### `LISBody`（extends RigidBody3D）

通用可抓握刚体。位置全部由 Jolt 积分产生，脚本不写 `transform`（复位除外）。

**信号**

| 信号 | 参数 |
| --- | --- |
| `grabbed_by` | `(body: LISBody, grabber: Node3D)` |
| `released_by` | `(body: LISBody, thrown: bool)` |
| `holder_count_changed` | `(body: LISBody, count: int)` |

**常量**：`MAX_HOLDERS = 4`、`GROUP_INTERACTABLE = "lis_interactable"`、`GROUP_BODY = "lis_body"`

**导出字段**：`profile`、`display_name`、`mass_kg`、`friction`、`bounce`、`liftable`、`body_size`、`auto_build_visual`

**几何**

| 签名 | 说明 |
| --- | --- |
| `apply_profile(p) -> void` | 应用参数并建立几何 |
| `size() -> Vector3` | 现存碰撞体的外形尺寸 |
| `extent_along(dir) -> float` | 沿方向的半展宽 |
| `half_extent() -> float` | 对角线一半 |
| `grab_point_toward(from) -> Vector3` | 从某点看向本物体时表面最近点 |

**多持有者**

| 签名 | 说明 |
| --- | --- |
| `add_holder(grabber, pid=0) -> bool` | 登记持有者；满 4 人返回 false |
| `remove_holder(grabber) -> void` | 只注销这一只手 |
| `holder_count() -> int` / `is_held_by(g)` / `is_held()` | 查询 |
| `live_holders() -> Array[Node3D]` | 仍在树中的持有者 |
| `prune_dead_holders() -> int` | 清理失效持有者，返回清理数 |
| `clear_holders() -> void` | 清空 |

**状态与安全操作**

| 签名 | 说明 |
| --- | --- |
| `note_constrained_force(demand, dir_world=ZERO) -> void` | 上报"有人在施力"（受阻判定的前提） |
| `is_blocked() -> bool` | 受阻：接触法线反对外施力方向且该方向速度被压住 |
| `effective_weight() -> float` | `mass · g · gravity_scale` |
| `contact_count() -> int` | 真实接触数（需 `contact_monitor`） |
| `wake() -> void` | 唤醒（Godot 的 `apply_force` 不会唤醒休眠刚体） |
| `push_force(force, offset=ZERO) -> void` | 施力并唤醒 |
| `push_force_centered(force) -> void` | 中心力并唤醒 |
| `push_impulse(impulse, offset=ZERO) -> void` | 冲量并唤醒 |
| `reset_to(pose) -> void` | **复位**语义：搬回位姿并清速度、清持有者 |
| `despawn() -> void` | 清持有者后 `queue_free()` |
| `describe() -> String` | |

**网络**

| 签名 | 说明 |
| --- | --- |
| `snapshot() -> Dictionary` | `{pos, rot, lin, ang, sleep, held, holders}` |
| `apply_snapshot(data) -> void` | |
| `enable_mirror(enabled) -> void` | 客户端只读镜像（`freeze` + `KINEMATIC`） |

**错误处理**：`profile` 为空时用内联字段；参数越界由 `sanitize()` 修正并 `push_warning`。

### `LISGrabLedger`（extends RefCounted，纯静态）

为**任意** `RigidBody3D` 提供统一的多持有者登记（`LISBody` 走自身 API，其它走 metadata，
不持有强引用）。`MAX_HOLDERS = 4`。

| 签名 | 说明 |
| --- | --- |
| `count(body) -> int` | |
| `is_held_by(body, grabber) -> bool` | |
| `add_holder(body, grabber, pid=0) -> bool` | |
| `remove_holder(body, grabber) -> void` | |
| `prune(body) -> int` / `clear(body) -> void` | |

### `LISContactProbe`（extends RefCounted，纯静态）

接触与穿透测量，不修改任何东西。

| 签名 | 说明 |
| --- | --- |
| `box_obb(node) -> Dictionary` | `{xform, size}`，取第一个 BoxShape3D |
| `shape_size(node) -> Vector3` | 任意碰撞体的外形尺寸 |
| `sat_depth(a, b) -> float` | 两个 OBB 的最小穿透深度（15 轴 SAT） |
| `contacts_of(body) -> Array[Dictionary]` | `{name, position, normal, impulse}` |
| `plane_gap(point, plane_point, plane_normal) -> float` | |
| `probe_penetration(node, space, mask) -> float` | 形状查询检查是否插入静态世界 |

---

## interaction

### `LISGrabber`（extends Node3D）

**第一人称力驱动抓握器 —— SDK 最重要的组件。**

**信号**

| 信号 | 说明 |
| --- | --- |
| `hold_changed(body: RigidBody3D)` | 抓握对象变化（松手时 body 为 null） |
| `grip_slipped(reason: String)` | 打滑脱手；reason ∈ `too_far` / `slip` / `frozen` |
| `force_saturated(body, demand, cap)` | 力被上限截断 |

**可配置参数（导出或运行时）**

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `lift_force` | `1500.0` N | 单手举升力上限 |
| `drag_force` | `950.0` N | 贴地拖推力上限 |
| `max_lift_mass` | `42.0` kg | **单人**可举升质量（团队 = ×人数） |
| `palm_torque_max` | `500.0` N·m | **玩法辅助**掌心力矩上限（人体约 150） |
| `palm_alpha_max` | `100.0` rad/s² | 单手最大角加速度 |
| `hold_stiffness` | `15.0` | 抓握弹簧刚度 |
| `max_follow_speed` | `7.0` m/s | |
| `break_distance` | `3.2` m | 硬脱手距离 |
| `slip_distance` / `slip_distance_drag` | `0.7` / `1.40` m | 打滑判据 |
| `slip_limit` | `0.45` s | 打滑持续时间阈值 |
| `throw_speed` | `4.5` m/s | 抛掷目标出手速度 |
| `throw_max_impulse` | `60.0` N·s | 抛掷冲量上限（**不按质量等比放大**） |
| `throw_lift_ratio` | `0.28` | 抛掷向上分量比例 |

**只读遥测**

`held`、`mode`（`"lift"`/`"drag"`）、`grip_force`（当前模式力上限）、`hold_distance`、
`manual_yaw`、`last_force`、`last_demand`、`last_clamp_distance`、`palm_torque`、`palm_cap`、
`palm_cancel`、`palm_level`、`saturated_frames`、`last_slip_reason`、
`last_throw_impulse`、`last_throw_speed`、`grip_up`、`player_id`、`player`、`camera`、`hand_anchor`

**静态常量**：`PALM_PATCH_RADIUS = 0.10`、`PHYSICAL_PALM_MOMENT = 150.0`、`PALM_TORQUE_MAX = 500.0`、`PALM_REACH_MAX = 0.30`

**方法**

| 签名 | 说明 |
| --- | --- |
| `setup(player, camera, player_id=1) -> void` | 注入玩家与相机 |
| `set_hand_anchor(anchor) -> void` | 设置手部锚点（只影响目标点，不放大受力） |
| `set_capabilities(lift, drag, lift_mass, torque, alpha) -> void` | 覆盖"人"的能力 |
| `try_grab(body) -> bool` | 尝试抓握；失败时写 `last_slip_reason` |
| `release(thrown) -> void` | 松手；`thrown=true` 给冲量 |
| `is_holding() -> bool` | |
| `rotate_held(degrees) -> void` | 旋转持有物 |
| `grip_world() -> Vector3` | 当前物理抓握点世界坐标 |
| `hand_target() -> Vector3` | 手部目标点世界坐标 |
| `on_body_predelete(body) -> void` | 被抓物体被删除时自动松手（由 `LISBody` 调用） |
| `describe() -> String` | |

**行为要点**

* 抓握模式按"质量 vs 团队举升上限"自动选择，持有者变化时实时重算；
* 多人持有时**偏航姿态辅助自动关闭**（否则两只手互相抢朝向、吃掉真实力偶）；
* 多人持有时打滑容差按人数放大；
* `lift` 模式不败坏竖直方向；`drag` 模式不提供升力（只允许向下压）。

---

## first_person

### `LISFirstPersonSource`（extends Node3D）

**自定义第一人称控制器协议（方式 B）。** 全部方法都有安全默认实现。

| 方法 | 默认返回 | 说明 |
| --- | --- | --- |
| `fp_player_id() -> int` | 1 | 玩家身份 |
| `fp_camera() -> Camera3D` | null | **必需** |
| `fp_body() -> Node3D` | null | 玩家身体 |
| `fp_hand_anchor() -> Node3D` | null | 可空 |
| `fp_forward() -> Vector3` | 由相机推 | |
| `fp_eye_position() -> Vector3` | 相机或自身位置 | |
| `fp_is_authority() -> bool` | true | 客户端只读镜像时返回 false |
| `fp_max_lift_force() -> float` | 0（= 用默认） | |
| `fp_max_drag_force() -> float` | 0 | |
| `fp_palm_torque_max() -> float` | 0 | |
| `is_valid_source() -> String` | — | 空串 = 可用 |

### `LISFirstPersonAdapter`（extends Node3D）

**第一人称交互适配器。** 把任意控制器翻译成 SDK 意图；自身不做物理积分。

**导出字段**

| 字段 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `body` | Node3D | null | 方式 A：玩家身体 |
| `camera` | Camera3D | null | 方式 A：第一人称相机 |
| `player_id` | int | 1 | |
| `source` | LISFirstPersonSource | null | 方式 B：协议对象（优先） |
| `reach` | float | 3.2 | 准星射线长度 |
| `ray_mask` | int（flags） | `4\|8` | 射线掩码（世界层会自动并入） |
| `exclude_held_from_ray` | bool | true | |
| `hand_anchor` | Node3D | null | |
| `read_input` | bool | true | 脚本驱动 / 远端代理应设 false |
| `action_grab` / `action_release` / `action_throw` / `action_rotate_left` / `action_rotate_right` | StringName | `&""` | 留空 = 不响应 |
| `action_move_forward` / `_back` / `_left` / `_right` | StringName | `&""` | 身体推挤用 |
| `push_force` | float | 780.0 | 推挤力上限 |
| `enable_body_push` | bool | true | |

**信号**：`target_changed(target)`、`grabbed(body)`、`released(body, thrown)`、`blocked_changed(blocked)`

**只读状态**：`grabber`、`current_target`、`hit_point`、`hit_distance`、`blocked`、`push_events`、`last_push_force`

**方法**

| 签名 | 说明 |
| --- | --- |
| `update_target() -> RigidBody3D` | 打射线、更新准星目标；被非刚体挡住时返回 null |
| `grab_current() -> bool` | 抓当前准星目标 |
| `grab(body) -> bool` | 抓指定刚体 |
| `release_held(thrown=false) -> void` | |
| `rotate_held(degrees) -> void` | |
| `is_holding() -> bool` | |
| `execute_intent(intent) -> bool` | 执行意图（远端 / 网络层调用） |
| `validate_setup() -> PackedStringArray` | 自检；空数组 = 正确 |
| `describe() -> String` | |

**重要语义**

* 一旦填了 `source`，**不再**在节点树里自动找相机 —— 相机必须由协议提供，
  否则会把场景里别人的相机当成自己的。
* 未填 `source` 且 `camera` 为空时，才会在 `body` 子树里找第一个 `Camera3D`。

### `LISFirstPersonIntent`（extends RefCounted）

一次交互意图。把"玩家想做什么"与"物理世界怎么响应"分开。

**枚举** `Kind { GRAB, RELEASE, THROW, ROTATE, PUSH, NONE }`

**字段**：`kind`、`player_id`、`target`、`eye`、`forward`、`strength`、`degrees`、`stamp`

| 方法 | 说明 |
| --- | --- |
| `static make(kind, player_id, target=null) -> LISFirstPersonIntent` | 构造 |
| `describe() -> String` | |

---

## joints

### `LISJointKit`（extends RefCounted，纯静态）

关节创建与**生命周期**工具。存在的首要理由是销毁顺序。

| 签名 | 说明 |
| --- | --- |
| `create_hinge(parent, name, body_a, body_b, world_pos, axis_world, max_deg=0, use_motor=false) -> HingeJoint3D` | 铰链绕自身局部 Z；`axis_world` 为世界轴 |
| `create_pin(parent, name, body_a, body_b, world_pos) -> PinJoint3D` | 球铰（缆绳用） |
| `create_fixed(parent, name, body_a, body_b, world_pos, world_basis=IDENTITY) -> Generic6DOFJoint3D` | 刚性连接 |
| `order_joints_first(parent) -> void` | 把关节排到同父子节点最前 |
| `ensure_constraints_precede(owner, constraint_holder) -> void` | 让支架/轮容器排在刚体之前（同级） |
| `teardown(joint) -> void` | **先 `remove_child`（物理服务器立刻注销约束）再释放** |
| `teardown_all(joints) -> int` | |
| `is_wired(joint) -> bool` | 两端是否可解析 |
| `anchor_gap(a, la, b, lb) -> float` | 真实锚点分离 |
| `collect_joints(root) -> Array[Joint3D]` | 子树里所有关节 |

**常量**：`GROUP_JOINT = "lis_joint"`

**关键约束（务必遵守）**

* 建立关节前必须先 `add_child`，再设 `global_transform`；
* 节点未进树时 `global_transform` 的 setter 等价于写 local transform；
* **不要**用改写 `node_a` / `node_b` 的方式"断开"关节；
* **不要**在 `_exit_tree()` 里 `free()` 子节点 —— 那是在引擎拆除遍历中删除被遍历元素，
  会造成间歇性崩溃；靠子节点顺序解决。

---

## machines

### `LISCart`（extends LISBody）

四轮独立刚体 + 四个真实轮轴铰链的推车。

**常量**：`VERSION_TAG`、`GROUP_CART`、`DECK_W/T/L`、`WHEEL_RADIUS/WIDTH/X/Z`、`AXLE_Y`、
`CHASSIS_MASS = 86.0`、`WHEEL_MASS = 6.0`、`WHEEL_FRICTION = 1.15`、`BEARING_DAMP = 0.18`

**状态**：`wheel_bodies`、`axles`、`wheel_rig`、`wheel_local`、`cart_mirror`、`base_color`

**遥测**：`telemetry_speed`、`telemetry_forward_speed`、`telemetry_wheel_spin`、
`telemetry_grounded_wheels`、`telemetry_tilt`、`telemetry_slip_ratio`

| 方法 | 说明 |
| --- | --- |
| `build_cart() -> void` | 幂等；`_ready` 会延迟调用（等变换生效） |
| `average_wheel_spin() -> float` | 平均角速度，正 = 向前滚 |
| `wheel_spin_list() -> Array[float]` | 四轮各自角速度 |
| `slip_ratio() -> float` | 0 = 纯滚动；负 = 轮不转车身在滑；正 = 空转 |
| `grounded_wheel_count() -> int` / `is_grounded() -> bool` | 射线判触地 |
| `system_center_of_mass(cargo=[]) -> Vector3` | |
| `cargo_on_deck(space=null) -> Array[Node3D]` | 形状查询 |
| `reset_pose(world_pos, yaw=0) -> void` | 车身 + 车轮一起搬 |
| `enable_mirror(enabled) -> void` | 客户端镜像（车轮视觉按主机位移） |
| `despawn() -> void` | 先拆轮轴 → 车轮 → 车身 |
| `snapshot() -> Dictionary` / `describe() -> String` | |

### `LISLever`（extends LISBody）

真实杠杆 + 配重 + 载物台 + 物理支点。

**常量**：`PIVOT_HEIGHT = 1.10`、`LEVER_MASS = 120.0`、`COM_LOCAL = (0,-0.03,-0.21)`、
`INERTIA_TENSOR = (72,34,96)`、`LIMIT_DEG = 14.0`、`PAN_TOP_Y = 0.125`、
`PAN_CENTER_Z = 1.30`、`PAN_LEN = 1.50`、`PAN_WIDTH = 0.80`、`TRIGGER_LOCAL`、`TRIGGER_SIZE`

**状态**：`frame`、`hinge`、`spawn_pose`、`lever_angle_deg`、`lever_omega`、`pan_load_kg`

| 方法 | 说明 |
| --- | --- |
| `build_lever() -> void` | 幂等；`_ready` 延迟调用 |
| `pivot_world() -> Vector3` / `pan_world() -> Vector3` | |
| `arm_length(world_point) -> float` | 到支点的水平力臂 |
| `angle_deg() -> float` | 正 = 载物端抬起 |
| `omega() -> float` | 绕支点角速度 |
| `pan_cargo() -> Array[RigidBody3D]` | 载物台上真实压着的刚体 |
| `gravity_torque() -> float` | 自重对支点的力矩（负 = 抬载物端） |
| `load_torque(cargo) -> float` | 货物力矩（正 = 压载物端） |
| `reset_lever() -> void` / `despawn() -> void` / `snapshot()` | |

### `LISHingeDoor`（extends Node3D）

被动铰链门（真实刚体 + 竖直铰链 + 限位）。

**常量**：`PANEL_W/H/T`、`PANEL_MASS = 21.0`、`OPEN_LIMIT_DEG = 104.0`、`GROUP_DOOR`

**导出**：`push_impulse = 26.0`、`frame_layer`、`panel_layer`、`panel_mask`、`hinge_side = -1.0`

**信号**：`door_pushed(speed)`、`door_state_changed(open)`
**状态**：`panel`、`frame`、`hinge`、`peak_speed`

| 方法 | 说明 |
| --- | --- |
| `build_door() -> void` | 幂等 |
| `push_from(world_point, strength=-1) -> void` | 从某点朝门板推 |
| `push_along(dir_world, strength=-1) -> void` | 沿世界方向推 |
| `get_open_degrees() -> float` / `is_open() -> bool` | |
| `reset_door() -> void` / `enable_mirror(enabled)` / `despawn()` | |
| `snapshot()` / `apply_snapshot(data)` | |

**语义要点**：竖直门轴下重力**不产生**绕轴力矩（门不会自己开合）。

### `LISMotorDoor`（extends Node3D）

电动机械门：铰链马达 + 力矩上限 + 堵转检测 + 断电。

**常量**：`PANEL_W/H/T`、`PANEL_MASS = 55.0`、`PANEL_CENTER_Y`

**导出**：`open_deg = 88.0`、`max_torque = 600.0`、`max_omega = 1.25`、
`open_delay = 0.15`、`close_delay = 1.2`、`free_when_unpowered = true`、层掩码

**信号**：`door_state_changed(open)`、`blocked_changed(blocked)`
**状态**：`frame`、`panel`、`hinge`、`open_requested`、`door_angle_deg`、`door_omega`、
`motor_torque`、`blocked`、`open_count`、`powered`

| 方法 | 说明 |
| --- | --- |
| `build_door() -> void` | 幂等 |
| `angle_deg() -> float` / `is_open() -> bool` | |
| `set_request(open_now) -> void` | 请求开门/关门（带延迟与去抖） |
| `set_powered(on) -> void` | 断电 = 马达立刻停止输出力矩 |
| `reset_door() -> void` | 复位并把控制器与开关状态重新对齐 |
| `rearm(open_now) -> void` | **参数语义：开关是否被压下 → 请求开门** |
| `enable_mirror` / `despawn` / `snapshot` / `apply_snapshot` | |

### `LISLimitSwitch`（extends Node3D）

机械限位开关：顶杆 + 导向井 + 弹簧 + **真实接触判定**。

**常量**：`PRESS_CLOSE = 0.020`、`PRESS_OPEN = 0.008`、`SPRING_K = 600.0`、
`SPRING_C = 8.0`、`PLUNGER_REST_Y = 0.75`、`WELL_HALF = 0.070`

**导出**：`pressed_by_class`（留空 = 任何刚体都能压）、层掩码
**信号**：`state_changed(closed)`
**状态**：`closed`、`compression`、`pressed_by`、`lever`（向后兼容字段）

| 方法 | 说明 |
| --- | --- |
| `setup(lever_body=null) -> void` | 兼容旧接口 |
| `build_switch() -> void` | 幂等 |
| `is_closed() -> bool` / `reset_switch() -> void` | |

### `LISRope`（extends Node3D）

真实多体缆绳：N 个带质量刚体绳段 + PinJoint 球铰。

**常量**：`SEGMENT_RADIUS = 0.021`、`STEEL_FILL_FACTOR = 0.60`、`STEEL_DENSITY = 7850.0`、
`TAUT_RATIO = 0.94`、`COLLISION_LEN_FACTOR = 0.94`、`GROUP_ROPE`

**导出**：`rope_layer`、`rope_mask`、`build_visual`
**信号**：`rope_taut_changed(taut)`
**状态**：`segments`、`joints`、`segment_count`、`segment_length`、`anchor_a`、`anchor_b`、`free_end`

| 方法 | 说明 |
| --- | --- |
| `build(seg_count, seg_length, from_world, dir, with_free_end=true, bend_deg=0.0) -> void` | 建绳（幂等） |
| `segment_mass_for(length_m) -> float` | 由材料推段质量 |
| `anchor_first_to(body, at=INF) -> void` | 绳头锚定 |
| `tie_last_to(body, at=INF) -> void` | 绳尾绑扎 |
| `get_free_end() -> LISRopeEnd` / `get_tied_body() -> Node3D` | |
| `max_joint_gap() / max_attach_gap() / max_any_gap() -> float` | **真实锚点**分离 |
| `current_length() -> float` | 相邻段**质心距**之和（链长） |
| `stretch_ratio() -> float` | 链长 / 材质长度 − 1 |
| `worst_link_stretch() -> float` | 单节最大拉伸 |
| `taut_ratio() -> float` / `is_taut() -> bool` | |
| `span_distance() / rest_length() / total_mass() / linear_density()` | |
| `reset_rope() -> void` | 复位（**不拆散关节**） |
| `enable_mirror(enabled) -> void` | 只冻结绳段，**不改写关节接线** |
| `teardown_joints_safely() -> void` | 拆约束 + 注销持有关系 + 置 `_shutting_down` |
| `despawn() -> void` | **推荐**：按"清持有 → 拆约束 → 放刚体"顺序销毁 |
| `apply_mirror_end(target) -> void` | 客户端绳端镜像（纯视觉） |
| `wiring_report() -> Dictionary` | `{joints, broken, links, segments, rest_length}` |
| `snapshot()` / `apply_snapshot(_data)` | |

### `LISRopeEnd`（extends LISBody）

缆绳自由端（可抓握）。`effective_load_mass()` 给出等效载荷质量
（绳段 + 另一端货物），`grip_span_distance(camera_pos)` 用于持握距离。

### `LISPulley`（extends Node3D）

真实滑轮。**必须在 `add_child` 之前设置 `want_movable`**。

**常量**：`WHEEL_RADIUS = 0.16`、`WHEEL_WIDTH = 0.09`、`WHEEL_MASS = 6.0`、`ROPE_FRICTION = 0.35`

| 方法 | 说明 |
| --- | --- |
| `build_pulley(movable=false) -> void` | 幂等 |
| `axis_world() -> Vector3` / `radius() -> float` | |
| `apply_rope_friction(rope_v, tension, delta) -> void` | 绳摩擦驱动（上限 μTR） |
| `reset_pulley() -> void` / `despawn() -> void` | |

### `LISWinchDrum`（extends LISBody）

真实绞盘卷筒（电机 + 制动 + 绳反作用力矩 + 能量账本）。

**常量**：`DRUM_RADIUS = 0.22`、`DRUM_WIDTH = 0.30`、`DRUM_MASS = 38.0`、
`MOTOR_TORQUE = 70.0`、`MOTOR_OMEGA = 2.0`、`BRAKE_TORQUE = 320.0`、`CRANK_ARM`、`AXLE_HEIGHT`

**状态**：`frame`、`axle`、`angle_rad`、`omega`、`motor_on`、`brake_on`、`motor_target_omega`、
`wind_sign`、`torque_limit`、`motor_output_torque`、`brake_output_torque`、`motor_work`、
`brake_work`、`manual_work`

| 方法 | 说明 |
| --- | --- |
| `build_drum() -> void` | 幂等 |
| `axis_world() -> Vector3` / `axis_angle() -> float` | |
| `update_telemetry() -> void` | 展开多圈角度与角速度 |
| `set_motor(on, target_omega=MOTOR_OMEGA) -> void` | |
| `set_brake(on) -> void` | |
| `drive(delta, load_torque=0.0) -> void` | **每物理帧由场景调用**（在 `LISCable.solve` 之后） |
| `brake_limit() -> float` / `reset_work() -> void` | |
| `reset_drum() -> void` / `despawn() -> void` | |

### `LISCable`（extends Node3D）

卷扬缆绳（**近似**模型，边界见 [PHYSICS_LIMITATIONS.md](PHYSICS_LIMITATIONS.md) 第 3 节）。

**常量**：`MAX_TENSION = 4000.0`、`K_STIFFNESS = 24000.0`、`K_DAMPING = 260.0`、
`BETA = 0.45`、`ROPE_WIDTH = 0.026`

**状态**：`nodes`、`drum`、`length0`、`length_allowed`、`path_length`、`tension`、
`peak_tension`、`reaction_torque`、`taut`、`take_in`、`wind_sign`、`theta_total`、`L_wound`、
`L_rest`、`L_path`、`elongation`、`damp_work`、`rope_work_on_drum`、`cut_flag`

| 方法 | 说明 |
| --- | --- |
| `setup(drum) -> void` | 必须最先调用 |
| `add_pulley(p)` / `add_load(body, local=ZERO)` / `add_anchor(anchor)` | 按路径顺序 |
| `finalize(wind=0.0) -> void` | 记录初始绳长、自动判定收绳方向 |
| `solve(delta) -> void` | **每物理帧调用** |
| `rope_speed() -> float` | 绳沿自身速度 |
| `cut() -> void` / `reset_cable() -> void` | |
| `wiring_report() -> Dictionary` | |

### `LISBrake`（extends Node）

通用有限制动力机械制动器。**不冻结物体**。

**导出**：`max_torque = 320.0`、`max_force = 2000.0`、`engage_time = 0.08`、
`release_time = 0.12`、`stop_omega_floor = 0.02`、`fade_omega = 0.0`、`fade_ratio = 0.5`、
`heat_per_joule = 0.0`、`cool_per_second = 0.35`、`hot_capacity_ratio = 0.5`

**信号**：`engaged_changed(engaged)`、`overheated(heat)`
**状态**：`target_engage`、`engage`、`heat`、`dissipated_joules`、`last_torque`、
`last_force`、`powered`

| 方法 | 说明 |
| --- | --- |
| `bind_body_axis(body, axis_world) -> void` | 绑定绕轴转动的刚体 |
| `bind_hinge(joint) -> void` | 绑定铰链（轴取自关节局部 Z） |
| `set_engaged(on) -> void` / `set_powered(on) -> void` | |
| `is_engaged() -> bool` | |
| `apply_linear_brake(delta) -> void` | 线性制动（推车式） |
| `telemetry() -> Dictionary` | `{engaged, engage, torque, force, heat, dissipated_j, powered}` |

---

## adapters

### `LISPhysicsHost`（extends Node）

主机权威物理桥（**可选**适配层）。不实现网络传输。

**导出**：`is_host = true`、`max_proxies = 8`、`proxy_reach = 3.2`、`mirror_registered_bodies = true`

**信号**：`proxy_created(pid, adapter)`、`proxy_removed(pid)`、`intent_applied(pid, kind, ok)`
**状态**：`registered`、`proxies`、`applied_intents`、`rejected_intents`

| 方法 | 说明 |
| --- | --- |
| `register_body(node)` / `unregister_body(node)` | |
| `ensure_proxy(pid) -> LISFirstPersonAdapter` | 为远端玩家建代理 |
| `update_proxy_pose(pid, eye, forward, body_pos=INF)` | |
| `apply_intent(intent) -> bool` | 走与本地玩家**相同**的施力路径 |
| `remove_player(pid) -> void` | 释放持有关系并销毁代理 |
| `enter_mirror_mode()` / `exit_mirror_mode()` | 客户端只读镜像 |
| `stats() -> Dictionary` | |

---

## tools

### `lis_project_check.gd`（SceneTree 脚本）

```bash
godot --headless --path <工程> --script res://addons/lis_physics/tools/lis_project_check.gd
```

检查 Godot 版本、物理引擎、必需资源、`class_name` 冲突、输入动作、碰撞层、可选网络适配。
**只报告，不修改任何项目设置。** 退出码 0 = 无错误，1 = 有错误。

输出行：`LIS_CHECK errors=N warnings=N infos=N verdict=OK|OK-WITH-WARNINGS|FAIL`

### `LISPerfBench`（extends Node3D，`tools/lis_perf_bench.tscn`）

可复跑的性能基准。10 个场景：20/50/100/200 刚体、多层堆叠、高频接触、
多关节机械组合、绳索与滑轮、推车载重、多人共同施力。

**先做计时器自检**（`OS.delay_usec` 校准），不可信则退出码 3 并打印
`LIS_PERF_TIMER_UNTRUSTED`，**不继续产假数据**。

记录：GPU/CPU/OS/Godot 版本/物理引擎、每物理步 CPU 耗时（avg/p95/p99/max）、
帧间隔、物理预算占比、活跃刚体数、接触数、峰值内存、异常计数。

**只产数据，不产 GO。**

---

## 错误处理约定

| 情况 | 行为 |
| --- | --- |
| 参数越界（质量 ≤ 0、尺寸非正、层为 0） | `sanitize()` 修正并 `push_warning`，不中断 |
| 抓握失败 | 返回 `false`，原因写入 `last_slip_reason` |
| 相机缺失 | 抓握返回 `false`（`no_camera`），不崩溃 |
| 协议不完整 | `validate_setup()` 返回问题列表；抓握安全失败 |
| 持有上限（4 人） | `add_holder` / `try_grab` 返回 `false`（`occupied`） |
| 被抓物体被删除 | `LISBody` 通知抓握器立刻松手 |
| 关节两端失效 | `LISJointKit.is_wired()` 返回 `false`；`wiring_report().broken` 计数 |

---

## 版本与兼容

* SDK 版本写在 `LISPhysics.SDK_VERSION`、`plugin.cfg`、`VERSION.json`，三处需一致；
* 全部类名以 `LIS` 前缀开头，便于与工程自有类区分；
* 检查工具会报告与引擎内置类的重名；
* 本版本为 **1.0.0-rc1 候选版本**，公共 API 在正式 V1.0.0 前仍可能微调。
