# 接入指南（INTEGRATION_GUIDE）

面向要把 SDK 装进自己星球工程的开发人员。本文假定你已读过 [QUICKSTART.md](QUICKSTART.md)。

---

## 1. 在现有星球工程安装

1. 备份你的工程（或至少确认在版本控制下）。
2. 把 `addons/lis_physics` 复制到你工程的 `addons/` 下。
3. 打开 Godot，等待资源导入完成。
4. 运行检查工具确认环境：

```bash
godot --headless --path <你的工程> --script res://addons/lis_physics/tools/lis_project_check.gd
```

**安装不会做这些事**（这是设计约束，不是"暂时没做"）：

* 不改主场景
* 不改你现有的玩家控制器
* 不改全局重力
* 不改物理帧率
* 不改 Jolt 求解器参数
* 不改 InputMap
* 不改碰撞层名称
* 不新增或覆盖网络自动加载单例（SessionHub / CoopNet 等）
* 不碰会话系统、存档、背包、任务系统
* 不改项目渲染设置

检查工具**只报告与给建议**，绝不覆盖你的配置。

---

## 2. 适配已有的第一人称控制器

### 2.1 先判断你属于哪种情况

| 你的控制器 | 用哪种方式 |
| --- | --- |
| `CharacterBody3D` + 一个 `Camera3D` 子节点 | **方式 A**：填两个导出字段 |
| 不是 CharacterBody3D，或相机在深层节点、输入自成一派 | **方式 B**：实现 `LISFirstPersonSource` 协议 |

两种方式**共用同一份抓握实现**（同一个 `LISGrabber`），不存在功能差异。

### 2.2 方式 A：填字段

```gdscript
var adapter := LISFirstPersonAdapter.new()
adapter.body = self          # 你的玩家节点（CharacterBody3D 或任何 Node3D）
adapter.camera = $Head/Cam   # 第一人称相机
adapter.player_id = 1
adapter.reach = 3.2          # 交互距离（米）
add_child(adapter)
```

若 `body` / `camera` 留空，适配器会依次尝试：父节点作为身体 → 在身体子树里找第一个 `Camera3D`。
**建议显式填写**，别依赖自动查找。

### 2.3 方式 B：实现协议

新建脚本继承 `LISFirstPersonSource`，覆写你需要的协议方法：

```gdscript
class_name MyPlanetSource
extends LISFirstPersonSource

func fp_player_id() -> int: return 3
func fp_camera() -> Camera3D: return cam
func fp_body() -> Node3D: return body_root
func fp_forward() -> Vector3: return -cam.global_transform.basis.z
func fp_eye_position() -> Vector3: return cam.global_position
func fp_hand_anchor() -> Node3D: return hand_node      # 可返回 null
func fp_is_authority() -> bool: return true             # 客户端只读镜像时返回 false
func fp_max_lift_force() -> float: return 1500.0        # 可选：自定义玩家力气
func fp_max_drag_force() -> float: return 950.0
func fp_palm_torque_max() -> float: return 500.0
```

然后：

```gdscript
adapter.source = my_source
adapter.read_input = false    # 输入由你自己的控制器采样
add_child(adapter)
```

> ⚠ **重要**：一旦填了 `source`，适配器**不再**自动在节点树里找相机。
> 相机必须由 `fp_camera()` 提供 —— 否则它会抓到场景里**别人的**相机。

### 2.4 自检

```gdscript
var problems := adapter.validate_setup()
if not problems.is_empty():
    for p in problems:
        push_warning(p)
```

---

## 3. 添加可抓握物品

参数写在 `LISBodyProfile` 里 —— 这是"真实物理参数"的唯一定义处：

```gdscript
var prof := LISBodyProfile.new()
prof.display_name = "钢制工具箱"
prof.size = Vector3(0.7, 0.45, 0.4)    # 米
prof.mass_kg = 28.0                    # 千克
prof.friction = 0.55
prof.bounce = 0.0
prof.liftable = true                   # false = 只能贴地推/拖
prof.linear_damp = 0.05
prof.angular_damp = 0.4
prof.continuous_cd = true              # 快速抛掷物建议开
prof.collision_layer = 4               # 位值，默认第 3 层
prof.collision_mask = 1 | 2 | 4
prof.grip_handles = 2                  # 表面把手数量（纯视觉）
prof.color = Color(0.5, 0.55, 0.6)

var box := LISBody.new()
box.name = "Toolbox"
box.profile = prof
box.position = Vector3(2, 0.3, -3)
add_child(bb)
```

### 质量怎么填

| 物体 | 参考质量 |
| --- | --- |
| 小工具 / 手持件 | 0.5 – 5 kg |
| 木箱 / 标准货箱 | 8 – 25 kg |
| 大货箱 / 长箱 | 30 – 80 kg |
| 机柜 / 重型设备 | 120 – 400 kg |
| 推车（车身 + 四轮） | 见 `LISCart` 常量（车身 86 kg + 4×6 kg） |

也可以用密度推算：

```gdscript
prof.mass_kg = LISPhysics.mass_from_density(prof.size, 180.0)   # 中空木箱
prof.mass_kg = LISPhysics.mass_from_density(prof.size, 1200.0)  # 实心塑料/木料
```

### 不要硬编码同一套质量

任务要求明确规定：**不得让所有物体都使用同一套硬编码质量和摩擦**。
请按物体的真实材质与体积填写。

### 用美术资源代替程序生成盒体

```gdscript
box.auto_build_visual = false    # 不生成盒体网格与把手
```

然后在编辑器里给这个节点挂上你自己的 `MeshInstance3D`。
**注意：关掉视觉不会关掉碰撞体** —— 碰撞体总会生成（物理必需品）。
若你自带 `CollisionShape3D` 子节点，SDK 不会重复添加。

---

## 4. 添加物理门

### 4.1 被动铰链门（人推 / 抓握拉开）

```gdscript
var door := LISHingeDoor.new()
door.position = Vector3(0, 0, -6)
door.hinge_side = -1.0      # 门轴在 −X 边
add_child(door)
```

* 门板是真实 `RigidBody3D`，通过 `HingeJoint3D` 挂在门框上；
* 用身体顶、或用抓握拽，门会**真的转开**；
* 开度限位默认 ±104°（`OPEN_LIMIT_DEG`）。

代码推动：

```gdscript
door.push_along(Vector3.RIGHT, 26.0)    # 世界方向 + 冲量大小（N·s）
door.push_from(player_point)            # 从某点朝门板方向推
```

> **竖直门轴不会因为重力自己开合。** 重力与门轴平行，绕轴力矩为零。
> 这条是 SDK 明确处理的：历史实现曾把重力误算成开门力矩。

### 4.2 电动门（马达驱动 + 限矩 + 堵转）

```gdscript
var door := LISMotorDoor.new()
door.max_torque = 600.0     # 马达力矩上限（N·m）
door.open_deg = 88.0        # 最大开度
door.position = Vector3(0, 0, -8)
add_child(door)

door.set_request(true)      # 请求开门（有 0.15 s 建立延迟）
door.set_request(false)     # 请求关门（有 1.2 s 延迟，留出通过时间）
door.set_powered(false)     # 断电：马达立即停止输出力矩
```

* 门被挡住时马达只能顶到 `max_torque`，门停下并报告 `blocked`；
* **不会**把门推穿障碍；
* 检查堵转：`door.blocked`（有 0.7 s 去抖）。

配合限位开关做完整电控链：

```gdscript
var sw := LISLimitSwitch.new()
sw.position = Vector3(...)           # 放在触发杆正下方
add_child(sw)
sw.state_changed.connect(func(closed: bool): door.set_request(closed))
```

> `rearm(open_now)` 的参数语义是"**开关是否被压下 → 请求开门**"。
> 复位后应调用 `door.reset_door()` 再 `door.rearm(false)`，否则门可能停在半开位。

---

## 5. 制作真实轮轴（推车）

```gdscript
var cart := LISCart.new()
cart.position = Vector3(5, 0.60, 0)   # 车身中心高度 0.60 → 四轮刚好触地
add_child(cart)
```

结构（全部运行时生成）：

```
Station
├── Cart（车身刚体，可抓握/推挤）
└── CartWheelRig
    ├── WheelFL/FR/RL/RR（RigidBody3D 圆柱车轮）
    └── AxleFL/FR/RL/RR（HingeJoint3D，轴沿车身 X）
```

关键点：

* 车轮是**独立刚体**，滚动来自接触摩擦，**没有**按车速播放的动画；
* 车轮不能是车身的子节点（两个刚体争夺同一 transform 会互相拉扯）；
* 铰链挂在静态容器下，复位时整体平移，约束几何不变。

遥测（HUD 与测试用）：

```gdscript
cart.telemetry_forward_speed     # 车身前向速度 m/s
cart.average_wheel_spin()        # 平均角速度 rad/s（正 = 向前滚）
cart.slip_ratio()                # 0 = 纯滚动；负 = 车轮未转车身在滑；正 = 空转
cart.grounded_wheel_count()      # 触地轮数
cart.cargo_on_deck()             # 货台上有哪些刚体
cart.telemetry_tilt              # 车身倾角
```

复位：

```gdscript
cart.reset_pose(Vector3(5, 0.60, 0), yaw)
```

**做别的轮式载具**：直接参考 `LISCart` 的搭建顺序，或只用 SDK 的关节工具自己搭：

```gdscript
var axle := LISJointKit.create_hinge(wheel_rig, "Axle", body, wheel,
    wheel.global_position, Vector3.RIGHT)
```

> 顺序要求：必须**先 `add_child`、再设 `global_transform`**。
> 节点未进树时 `global_transform` 的 setter 等价于写 local transform，
> 会把"轮心世界坐标"当成局部坐标，轮子直接埋进地里。

---

## 6. 杠杆与配重

```gdscript
var lever := LISLever.new()
lever.position = Vector3(0, LISLever.PIVOT_HEIGHT, 0)   # 支点高度 1.10 m
add_child(lever)
```

* 杠杆是 120 kg 刚体，重心与惯量显式给定（`COM_LOCAL` / `INERTIA_TENSOR`）；
* 支点是真实 `HingeJoint3D`，机械限位 ±14°；
* 载物台顶面高度 `LISLever.PAN_TOP_Y`，中心在局部 `+PAN_CENTER_Z`。

读数：

```gdscript
lever.angle_deg()            # 正 = 载物端抬起
lever.pan_load_kg            # 载物台上真实压着多少 kg
lever.gravity_torque()       # 自重对支点的力矩（负 = 把载物端抬起）
lever.load_torque(cargo)     # 货物力矩（正 = 把载物端压下）
lever.arm_length(point)      # 某点到支点的水平力臂
```

**力臂决定结果**：同一个 24 kg 箱子放在远端（力臂 ≈1.55 m）能压下杠杆，
放在近端（力臂 ≈0.68 m）压不动。这是真实力矩，不是脚本判定。

`reset_lever()` 把杠杆搬回初始位姿。

---

## 7. 缆绳

SDK 提供两套绳索，用途不同：

| | `LISRope` | `LISCable` |
| --- | --- | --- |
| 模型 | N 个带质量刚体绳段 + 球铰 | 无质量不可伸长线 + 卷筒/滑轮切点 |
| 真实度 | **高**：能下垂、能弯曲、能拖地、绳段间有碰撞 | **近似**：张力瞬时传递，无几何缠绕 |
| 适用 | 拖拽、牵引、绳索形状可见 | 绞盘收放、滑轮组、卷扬机 |
| 成本 | 每段一个刚体（10 段 = 10 刚体） | 只算路径长度，很便宜 |

### 7.1 多体缆绳

```gdscript
var rope := LISRope.new()
add_child(rope)
await get_tree().physics_frame          # 等节点进树，位置生效

rope.build(10, 0.34, from_world, Vector3.RIGHT, true, 0.0)
#         段数  段长   起点        方向            带自由端  初始弯曲角

await get_tree().physics_frame
rope.anchor_first_to(post, post.global_position + Vector3(0, 3, 0))  # 绳头锚定
rope.tie_last_to(crate, crate.global_position + Vector3(-0.45, 0, 0)) # 绳尾绑货
```

读数：

```gdscript
rope.tension_estimate()      # 见下
rope.stretch_ratio()         # 链长 / 材质长度 − 1
rope.max_joint_gap()         # 段间真实锚点分离（理想 0）
rope.is_taut()               # 是否绷紧
rope.rest_length()           # 材质总长
rope.wiring_report()         # 结构自检（关节数 / 破损数）
```

复位：

```gdscript
rope.reset_rope()
```

> **复位不会拆散绳索。** 历史 Bug 是"复位调用 `enable_mirror(false)`，
> 而那一版 `enable_mirror` 无条件清空关节接线"，于是每次复位都把绳子永久断开，
> 而结构检查仍报告连接正常。现在 `enable_mirror` 只冻结绳段、不改接线。

安全拆卸（销毁前必须调用，或直接用 `despawn()` 语义）：

```gdscript
rope.teardown_joints_safely()
rope.queue_free()
```

### 7.2 绞盘 + 滑轮

```gdscript
var winch := LISWinchDrum.new()
add_child(winch)
winch.position = Vector3(...)

var pulley := LISPulley.new()
pulley.want_movable = false     # 必须在 add_child **之前**设置
add_child(pulley)

var cable := LISCable.new()
add_child(cable)
await get_tree().physics_frame
cable.setup(winch)
cable.add_pulley(pulley)
cable.add_load(load_body, Vector3(0, 0.3, 0))
cable.add_anchor(anchor_node)          # 或 add_load
cable.finalize()                        # 记录初始绳长、自动判定收绳方向
```

每物理帧驱动（**顺序不能反**）：

```gdscript
func _physics_process(delta: float) -> void:
    cable.solve(delta)                        # 先解绳约束
    winch.drive(delta, cable.reaction_torque) # 再驱动卷筒（电机 + 制动）
```

控制卷筒：

```gdscript
winch.set_motor(true, LISWinchDrum.MOTOR_OMEGA)   # 开电机
winch.set_brake(true)                              # 合闸
```

> ⚠ **模型边界**：`LISCable` 的路径按**圆心连线折线**计算，不是严格外公切线。
> 详见 [PHYSICS_LIMITATIONS.md](PHYSICS_LIMITATIONS.md)。

---

## 8. 配置碰撞层

SDK 的层常量在 `LISPhysics`：

| 常量 | 位值 | 建议层名 |
| --- | --- | --- |
| `LAYER_WORLD` | 1 | world |
| `LAYER_PLAYER` | 2 | player |
| `LAYER_PROP` | 4 | interactable |
| `LAYER_MACHINE` | 8 | machine |
| `LAYER_TRIGGER` | 16 | trigger |

默认：刚体在 `LAYER_PROP`（4），掩码 `WORLD | PLAYER | PROP`（1|2|4）。

> ⚠ **历史工程注意**：旧代码里 `phys_prop.gd` 用的是 `collision_layer = 8`（第 4 层）。
> SDK **不会**自动跟随你的旧设置。迁移时二选一：
> * 把旧物体的层改成 4；或
> * 在 `LISBodyProfile` 里显式写 `collision_layer = 8`、`collision_mask = 1|2|8`。

交互射线掩码：

```gdscript
adapter.ray_mask = LISPhysics.LAYER_PROP | LISPhysics.LAYER_MACHINE
adapter.reach = 3.2
```

> 适配器会**自动把世界层并入射线掩码**，否则准星会穿过墙选中后面的箱子。

---

## 9. 安全销毁

这是本项目最容易踩的坑，也是 SDK 专门做了修正的地方。

### 9.1 规则

**释放刚体之前，必须先处理引用它的约束。**

Godot 按子节点顺序销毁节点。若刚体先被释放、引用它的关节后释放，
Jolt 的约束对象会指向已释放内存 → `0xC0000005` 访问冲突。

### 9.2 正确做法

优先用组件自带的销毁方法（内部已处理顺序）：

```gdscript
body.despawn()
cart.despawn()
lever.despawn()
door.despawn()
winch.despawn()
rope.teardown_joints_safely(); rope.queue_free()
```

自己搭的关节：

```gdscript
LISJointKit.teardown(joint)          # 先摘出树，再 free；不改 node_a/node_b
LISJointKit.teardown_all(joints)
```

**不要**这么做：

```gdscript
# ❌ 在 _exit_tree() 里 free() 关节 —— 等于在引擎拆除遍历中删除被遍历的子节点
func _exit_tree() -> void:
    for j in joints: j.free()

# ❌ 改写 node_a / node_b 来"断开关节"
joint.node_a = NodePath()   # 让 Jolt 在运行期重建约束，反复执行会留下半断开对象

# ❌ 直接把刚体 queue_free()，不管关节
```

### 9.3 让销毁顺序天然安全

组件在搭建时会自动调用：

```gdscript
LISJointKit.order_joints_first(parent)                        # 关节排到同父的子节点最前
LISJointKit.ensure_constraints_precede(owner, holder)         # 支架/轮容器排到刚体之前
```

自己搭机械时请照做。

### 9.4 玩家离场

```gdscript
# 抓握器退出树时会自动注销自己的持有关系；
# 若你手动销毁玩家节点，建议显式松手：
player_adapter.release_held(false)
player.queue_free()
```

`LISBody.prune_dead_holders()` 可清理失效持有者。

---

## 10. 让多人共享权威物理

SDK **不实现网络传输**。ENet、SessionHub、CoopNet、玩家身份、存档、背包、任务系统
都是各星球自己的东西，SDK 绝不自动安装或覆盖。

SDK 提供的是**边界**：

```gdscript
var host := LISPhysicsHost.new()
host.is_host = true                 # 主机
host.register_body(crate)           # 登记要同步的物理物体
add_child(host)

# 客户端：把登记的物体切到只读镜像（本地不积分）
host.enter_mirror_mode()
```

远端玩家的意图：

```gdscript
# 客户端：打包意图（不要直接施力）
var it := LISFirstPersonIntent.make(LISFirstPersonIntent.Kind.GRAB, pid, crate)
it.eye = eye_position
it.forward = forward_dir
rpc_id(1, "_intent", it.serialize())    # 传输你自己实现

# 主机：应用意图 —— 走的是与本地玩家**完全相同**的施力路径
host.update_proxy_pose(pid, eye, forward)
host.apply_intent(it)
```

玩家退出：

```gdscript
host.remove_player(pid)     # 释放他的持有关系并销毁代理
```

**权威模型**：

| 模式 | 谁积分物理 |
| --- | --- |
| 单人 | 本地 |
| 主机权威 | 只有主机 |
| 客户端只读镜像 | 没有人（`freeze` + `KINEMATIC`，只接受快照） |

> ⚠ **已集成 ≠ 已稳定**。本轮只做了双进程基础冒烟（能连上、意图能变成真实抓握）。
> 高延迟、丢包、断线重连**未验证**。
