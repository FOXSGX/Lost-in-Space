# 第一人称 API 专项（FIRST_PERSON_API）

本文只讲第一人称相关的设计约束与用法。全游戏统一第一人称是本项目最高级设计决定。

---

## 0. 一条必须记住的分工

```text
第一人称手部模型  = 视觉表现          （可以跟丢、可以摆动、可以没有）
LISGrabber        = 真实受力的唯一来源 （力有上限、作用在接触点上、由 Jolt 积分）
```

**不允许**因为"玩家看见手贴在箱子上"就把箱子设置到手上。
真正的抓握链是：

```text
抓握位置（物体表面） → 目标位置（相机前方 或 手部锚点） → 有上限的力 → RigidBody3D
```

---

## 1. Camera3D

适配器需要一台第一人称相机，它决定三件事：

1. **交互射线的原点与方向**（准星选物）；
2. **抓握目标点**（默认 = 相机位置 + 前向 × 持握距离）；
3. **抛掷方向**（沿相机前向 + 少量向上）。

```gdscript
adapter.camera = $Head/Camera3D
```

相机应当：

* `near` 足够小（建议 0.05），否则近距离物体被裁掉；
* `current = true`；
* 每帧跟随玩家朝向（俯仰放在相机或它的父节点上，**不要**把俯仰加到玩家身体上，
  否则移动方向会跟着俯仰倾斜）。

---

## 2. 第一人称交互射线

```gdscript
adapter.reach = 3.2       # 射线长度（米）
adapter.ray_mask = LISPhysics.LAYER_PROP | LISPhysics.LAYER_MACHINE
adapter.exclude_held_from_ray = true    # 排除自己正持有的物体
```

每物理帧调用：

```gdscript
var target: RigidBody3D = adapter.update_target()   # 返回准星指着的刚体
adapter.current_target    # 同上，缓存值
adapter.hit_point         # 命中点世界坐标（准星标记用）
adapter.hit_distance      # 命中距离
```

**准星不会穿墙。** 适配器会自动把世界层并入射线掩码：
若命中了一个非刚体（墙、门框、地形），`update_target()` 返回 `null`。
这条修复来自实测缺陷 —— 早期版本会"穿过墙选中后面的箱子"。

排除项（自动）：

* 玩家自己的身体碰撞体（否则射线永远打在自己身上）；
* 自己正在持有的物体（可选，默认开）。

---

## 3. 手部锚点

第一人称手部模型（view model）需要一个"手在哪"的参考点。

```gdscript
adapter.set_hand_anchor(hand_node)     # 一个 Node3D，世界空间位置
```

行为差异：

| `hand_anchor` | 抓握目标点 |
| --- | --- |
| 未设置（null） | 相机位置 + 前向 × `hold_distance` |
| 已设置 | 该节点的世界位置 |

> **手部锚点只移动目标点，不放大作用力。** 力的上限始终是 `grip_force`。
> 这条由自动化测试守着：给抓握器挂一个锚点后，力不得超过上限。

推荐做法：把手部模型挂在相机下，用 `hand_anchor` 指向它。
这样"手跟着物体动"是视觉表现，而物体是被力拉过去的。

**SDK 不要求制作正式手部动画。** 但接口支持后续美术接入：
`LISGrabber` 会发射状态信号，你可以据此切换手的姿态。

---

## 4. 抓握距离

```gdscript
grabber.hold_distance    # 手到抓握点的距离（米），抓握时确定
grabber.hand_target()    # 当前帧的手部目标世界坐标
grabber.grip_world()     # 当前帧的真实物理抓握点世界坐标
```

抓握距离在 `try_grab()` 时按物体表面抓握点确定，并夹在 `1.05 ~ 2.30 m`。
两种模式算法不同：

| 模式 | 距离算法 | 原因 |
| --- | --- | --- |
| `lift`（举升） | 相机到抓握点的**直线距离** | 举起来时物体就在眼前 |
| `drag`（拖推） | 抓握点在**相机前向轴上的投影** | 拖推时相机与抓握点有竖直高差（眼高 1.62 m vs 货台 0.68 m），用直线距离会让目标点一抓住就冲过物体，几十帧内必误判脱手 |

模式由**质量与当前持有者人数**自动决定：

```text
团队举升上限 = max_lift_mass（默认 42 kg） × 持有者人数
若 物体可举起 且 质量 ≤ 团队上限 → lift
否则                            → drag
```

所以：**第二个人上来一起抬，第一个人会自动从拖推切到举升。**
这是"双人合力"在代码里的落点。

---

## 5. 视角改变对抓握目标的影响

目标点每帧重算：

```gdscript
target = camera.global_position + (-camera.global_transform.basis.z) * hold_distance
```

因此低头、抬头、转身都会让**手的目标点**跟着动。但物体是被**力**拉过去的：

* 转得太快时力会饱和 → 物体跟不上手（真实手感）；
* 手-物几何误差持续超过阈值 → 打滑脱手（`grip_slipped` 信号）；
* 误差超过 `break_distance`（默认 3.2 m）→ 立刻脱手。

自动化测试覆盖：转身 120°、抬头/低头 ±25° 时抓握仍然稳定。

---

## 6. 第一人称与远程角色视觉的一致性

多人联机时：

* **每名玩家用自己的第一人称相机操作**；
* **其他玩家能看到他的身体、动作、手部与持有物体**；
* 这些远程角色表现**不属于**第三人称玩家控制模式。

SDK 的保证是：**力的作用点一致**。

远端玩家不走"另一套简化物理"，而是把意图送到权威端，由权威端的
`LISFirstPersonAdapter`（代理）用**同一个 `LISGrabber`** 施同一个力：

```gdscript
# 远端 → 意图
var it := LISFirstPersonIntent.make(LISFirstPersonIntent.Kind.GRAB, pid, crate)
it.eye = eye_pos
it.forward = forward_dir
it.strength = 1.0

# 权威端 → 应用
host.update_proxy_pose(pid, it.eye, it.forward)
host.apply_intent(it)
```

因此"第一人称交互力的实际作用点，和多人世界中物体受到的力保持一致"。

> ⚠ SDK **不提供**第三人称摄像机、跟随控制器、抓握适配器、示例或测试，
> 也不提供第一/第三人称切换。

---

## 7. 玩家与持有物的碰撞例外

默认行为：

* 玩家的 `CharacterBody3D` 与所有刚体层碰撞（能推箱子、被推车挡住）；
* 玩家**不会**与自己持有的物体发生"把自己顶飞"的情况 —— 因为抓握力作用在
  物体上、反作用由物理解算，且射线与部分查询会排除自己的身体与持有物。

若你的玩家与持有物出现互相顶撞，检查：

1. 玩家碰撞层是否包含了刚体层（应为 `WORLD | PROP`）；
2. 是否把持有物错误地加到了玩家子节点下（**不要**这样做，
   Node3D 层级会让两个刚体争夺 transform）。

身体推挤（把角色接触转成真实推力）：

```gdscript
adapter.enable_body_push = true
adapter.push_force = 780.0            # 力上限（N）
adapter.action_move_forward = &"move_forward"    # 可选：用移动输入判断推力方向
adapter.action_move_back = &"move_back"
adapter.action_move_left = &"move_left"
adapter.action_move_right = &"move_right"
```

只有玩家**确实朝物体压过去**时才施力；站着不动不会凭空推动任何东西。

---

## 8. 物体靠近镜头时的遮挡与受阻

第一人称特有的两个问题：

### 8.1 物体挡住视线

抓握 `drag` 模式刻意不控制竖直方向 —— 物体可能垂在画面下方。
这符合真实（你拖着一个箱子走路时它就在你腿边），但必要时可以：

* 提高相机的 `near` 裁剪距离并不能解决（那是裁掉物体）；
* 用手部锚点把目标点抬高，让物体离镜头远一些；
* 或者给持有物做一个"半透明"表现（纯视觉，不影响物理）。

### 8.2 手持物体撞墙受阻

物体与墙真实碰撞，力的求解会让它停下。此时：

```gdscript
grabber.saturated_frames     # > 6 表示力持续饱和
grabber.last_clamp_distance  # 手-物几何误差
adapter.blocked              # 是否处于受阻
```

`LISBody.is_blocked()` 的语义是**"有人在施力、但被接触挡住了"**：

* 静止在地面的箱子有接触、速度为 0，但**不算受阻**（没有人在推它）；
* 只有当接触法线**反对外施力方向**、且该方向速度被压住时才算受阻。

---

## 9. 鼠标操作与物理旋转控制

持有物体时的旋转有两套输入：

```gdscript
# 1) 按键旋转（离散，每次 ±度）
adapter.rotate_held(30.0)     # 或 -30.0

# 2) 归位（由玩家身体朝向驱动，自动）
```

内部实现：

* `manual_yaw` 累加按键旋转量；
* 目标偏航 = `玩家朝向 + manual_yaw`；
* 通过**掌心力矩预算**内的力矩把物体拧过去（有上限，不是瞬移角度）。

> ⚠ **多人持有时偏航辅助会自动关闭。**
> 原因：两只手抓同一根杆时，杆的朝向应当由两人的相对位置与施力决定，
> 不该由谁的肩膀朝向决定。若每只手都坚持"把物体拧到我身体的朝向"，
> 两人朝向不同就会各出约 250 N·m 的归位力矩，把真实力偶整个吃掉
> （实测：两人在横杆两端反向拉，偏航变化 0.00°）。
> 关闭后同样的操作产生 27.7° 的真实偏航。

---

## 10. 手部状态接口（供美术接入）

`LISGrabber` 提供的信号与只读状态：

| 信号 / 字段 | 含义 |
| --- | --- |
| `hold_changed(body)` | 抓握对象变化（含松手时的 null） |
| `grip_slipped(reason)` | 打滑脱手，reason ∈ `too_far` / `slip` / `frozen` |
| `force_saturated(body, demand, cap)` | 力被上限截断（力不足） |
| `last_force` / `last_demand` / `grip_force` | 实际力 / 需求力 / 上限 |
| `mode` | `lift` 或 `drag` |
| `saturated_frames` | 连续饱和帧数 |
| `palm_torque` / `palm_cap` | 姿态辅助实际值 / 上限 |
| `last_slip_reason` | 最近一次失败原因 |

据此可以驱动手部姿态：

| 状态 | 判据 |
| --- | --- |
| 抓稳 | `is_holding()` 且 `saturated_frames == 0` |
| 受阻 | `saturated_frames > 6` |
| 力不足 | `last_demand > grip_force * 1.5` |
| 拖行 | `mode == "drag"` |
| 松手 / 抛出 | `hold_changed(null)` |

---

## 11. 不要做的事

| ❌ 反模式 | 为什么 |
| --- | --- |
| 每帧 `body.global_position = hand.global_position` | 传送式持有，物体不再参与碰撞，丢失全部物理真实性 |
| 抓握时 `body.freeze = true` | 冻结的物体不参与碰撞，抓着的箱子会穿墙 |
| 把持有物设为玩家子节点 | 两个刚体争夺同一 transform，互相拉扯 |
| 把俯仰加到玩家身体上 | 移动方向会跟着倾斜 |
| 让第三人称控制器共用这套适配器 | 本项目统一第一人称；远程角色表现是另一回事 |
| 用提高姿态辅助上限来"让示例通过" | 那会把游戏化辅助伪装成人体力学，见 [PHYSICS_LIMITATIONS.md](PHYSICS_LIMITATIONS.md) |
