# MECHANICS-004C 第四幕真实升降出口门最终报告

**项目**：《迷失太空》（Lost in Space）· 第四幕「共振矿区」
**工程**：`C:\Users\ASUS\Desktop\迷失太空\game\`
**引擎**：Godot 4.7.2.stable.official.ed1daf0bf · 物理 Jolt Physics · 60 Hz
**执行窗口**：**窗口 A（双窗口并行开发）**
**日期**：2026-11-06

> ⚠️ **本轮为双窗口并行开发的窗口 A。**
> 另一个全新窗口正在独立执行 **MECHANICS-005A（第五幕核心稳定机关改造）**。
> 本报告的一切结论**仅覆盖第四幕出口门**。最终整幕联合验收必须等窗口 B 完成后进行。
> 本轮未修改窗口 B 负责的任何文件（详见第 9 节哈希证据）。

---

## 0. 结论先行

**判定：GO（限定于第四幕出口门本身）**

| 验收项 | 结果 |
|---|---|
| MECHANICS-004C 专项 | **24 / 24 通过**，退出码 0 |
| MECHANICS-004A 回归 | **18 / 18 通过**，退出码 0 |
| MECHANICS-004B 回归 | **24 / 24 通过**，退出码 0 |
| MECHANICS-004B 支架附加 | **3 / 3 通过**，退出码 0 |
| 第四幕入口加载 | 通过 |
| 第四幕→第五幕真实切场 | 通过（`Mech004CHandoff` → `Main`，3103 节点，chapter=act05） |
| 真实窗口截图 | 6 张，1280×720 |

原有 Tween 已彻底删除；门现在是 850 kg 真实刚体，靠 `apply_central_force()` 沿 `SliderJoint3D` 竖直导轨运动，会被真实障碍挡住，顶部靠实体承接梁保持。

---

## 1. 原有代码审计

### 1.1 审计对象与事实

| 文件 | 审计结论 |
|---|---|
| `AGENTS.md` | 用户偏好：中文沟通；**不新增漂浮 3D 文字提示**（本轮未新增任何悬浮文字） |
| `game/project.godot` | `3d/physics_engine="Jolt Physics"`，`physics_ticks_per_second=60`；层定义 world/player/interactable/machine/trigger |
| `game/scripts/act4/exit_gate.gd` | **185 行，门体是 `StaticBody3D`** |
| `game/scripts/act4/game.gd` | 1771 行；`gate.open()` 在 `_on_memory_finished(3)` 中调用 |
| `game/scripts/act4/level_builder.gd` | 1168 行；`EXIT_GATE_POSITION = Vector3(3.2, 0.0, -25.0)` |
| `game/scenes/act4.tscn` | 6 行，仅挂 `game.gd`，场景内容全部由代码构建 |
| `memory_director.gd` | 第三段记忆演出在 `elapsed > 13.2` 时也会 `gate.open()` |

### 1.2 逐项核实（任务书第三节 10 问）

**1. 门体真实节点类型**
```gdscript
_panel_body = StaticBody3D.new()      # ← 静态体，无质量、无惯量
_panel_shape.collision_layer = 1
_panel_body.collision_mask = 0
```

**2. 关闭 / 开启时的实际位置**
- 关闭：`_panel_root.position.y = 0.0`，碰撞盒中心 y=2.1，高 4.2 → 门底 y=0，门顶 y=4.2。
- 开启：Tween 把 `_panel_root.position.y` 插值到 **4.35**。

**3. 门尺寸与升降行程**
- 碰撞盒 `Vector3(0.45, 4.2, 4.3)`；视觉 0.40×4.2×4.3。
- 行程 4.35 m（Tween 目标值）。

**4. 门框与门体碰撞体**
- 门框：`GatePillar0/1`（0.55×5.2×0.65，z=±2.35）、`GateLintel`（0.7×0.8×5.3，y=4.95）、岩壁 `GateWallTop`（0.7×2.6×5.4，y=5.9）——**整块封死门上方**。
- 门体：单个 `BoxShape3D`。

**5. Tween 当前修改什么**
```gdscript
_open_tween.tween_property(_panel_root, "position:y", 4.35, 2.6)
```
改的是 `Node3D` 的 `position.y`——纯视觉节点位移，物理世界不受影响。

**6. 开门的剧情条件**
`game.gd::_on_memory_finished(3)`（`seen_memories[3]`）+ `memory_director.gd` 第三段演出 13.2 s 处。

**7. 中继与参与度判定**
`_relay_ready("b1")` / `_relay_ready("b3")` 要求支架 `aligned` 且 `occupied != null`；合作模式另有 `ParticipationLedger.PHASE_04` 校验。

**8. 玩家通过出口的方式**
`ExitTrigger`（Area3D，layer 32，mask 2）位于 `(3.0, 1.8, 0.0)`，尺寸 4.0×3.6×4.2 → `player_entered` → `_on_exit_entered()`。

**9. 第四幕→第五幕切换条件**
`completed = true` 且 `gate.is_open` 且 `seen_memories[3]` → `SessionHub.request_scene_switch("res://scenes/main.tscn", spawn)`。

**10. 复位时如何恢复门**
`reset_level()` **完全没有碰 gate**——这是原有缺陷（复位后门仍开着）。

### 1.3 审计发现的 4 个真实缺陷

| # | 缺陷 | 严重度 |
|---|---|---|
| A1 | **开门第一件事就关掉碰撞**：`_panel_shape.set_deferred("disabled", true)` | 致命——门一开就物理消失 |
| A2 | **门没有质量/惯量/重力/导向/止挡**，是 Tween 曲线 | 致命——任务书核心问题 |
| A3 | **岩壁 `GateWallTop` 整块封死门上方**，门实际是"升进岩体" | 严重——旧实现靠穿墙 |
| A4 | **`reset_level()` 不恢复门**，复位后门保持开启 | 严重——重复游玩状态泄漏 |

---

## 2. 机械节点树（改造后）

```
ExitGate (Node3D, 世界 (3.2, 0, -25))
├── GatePillar0/1 (StaticBody3D)          立柱，内表面 z=±2.15，门洞净宽 4.30
├── GateGuideRail0/1 (StaticBody3D)       导向轨，真实碰撞
├── GateSill (StaticBody3D)               下止挡钢梁
├── PocketWestPlate (StaticBody3D)        门袋西封板（朝最终矿室）
├── PocketEastPlate (StaticBody3D)        门袋东封板（走廊侧，让出承接梁滑槽）
├── PocketCheek0/1 (StaticBody3D)         门袋南北颊板
├── PocketRoof (StaticBody3D)             门袋顶板 = 第二道上止挡
├── GatePanel (RigidBody3D)               ★ 850 kg 真实门体
│   ├── PanelShape (CollisionShape3D)      BoxShape3D 0.36 × 4.20 × 4.08
│   ├── Panel / PanelRib0-2 / PanelStripe  视觉
│   ├── PanelWheel / PanelAxle / WheelSpoke0-1 / WheelHub
│   ├── PanelSeam / PanelRivet0-13 / Hazard0-4
│   └── PanelStatus (状态灯带：红/琥珀/青)
├── GateAnchor (StaticBody3D)             关节 A 端（无碰撞层）
├── GateSlider (SliderJoint3D)            ★ 竖直滑动约束，轴 = 世界 +Y
├── GateCatchBeam (StaticBody3D)          ★ 顶部机械承接梁（可滑动）
├── CatchHousing / CatchTrack0-1 / CatchBracket0-1   承接梁外壳与导轨
├── ExitTrigger (Area3D)                  出口触发
└── DoorwaySensor (Area3D)                门口占用（安全，禁止夹人）
```

### 2.1 关键：滑动轴方向的实测确定

**Godot 4.7.2 + Jolt 实测结论：`SliderJoint3D` 的滑动轴是关节局部 X 轴。**

`game/tests/mech004c_joint_probe.gd` 三组实验（identity 关节基，沿 +X/+Y/+Z 施力）：

| 施力方向 | 位移 |
|---|---|
| +X | `(4.35, 0, 0)` ← **只有 X 动** |
| +Y | `(0, 0, 0)` |
| +Z | `(0, 0, 0)` |

**关键副作用**：当滑动轴水平时，重力垂直于轴，关节把重力完全吸收——门"受重力"是假的。

因此关节设 `rotation_degrees = (0, 0, 90)`，使局部 X → 世界 **+Y**：

```
joint_axis_world = (0.0, 1.0, 0.0)   dot_up = 1.0000
```

这样 `M·g` 就沿滑动轴真实参与运动——电机必须真的托住门。

另实测：Jolt **不支持** `linear_limit/restitution`（引擎警告），已不依赖该参数。

---

## 3. 质量、惯量、驱动力与重力关系

### 3.1 运动方程

```
M · dv/dt = F_motor − M·g − F_resistance + F_contact
```

### 3.2 各项实测值

| 符号 | 含义 | 值 | 来源 |
|---|---|---|---|
| `M` | 门体质量 | **850.0 kg** | `RigidBody3D.mass` |
| `I` | 惯量（Jolt 按 BoxShape 求解） | **(2428.6, 1188.3, 1258.7) kg·m²** | `get_diagnostics().inertia_diagonal` |
| `M·g` | 重力 | **8330.0 N** | `gravity_scale = 1.0`，从不关闭 |
| `F_MOTOR_MAX` | 电机推力上限 | **12500.0 N** | 硬钳制，实测峰值 12500.0 |
| `K_SPEED` | 速度环增益 | 12000 N/(m/s) | |
| `M_NOMINAL` | 前馈用额定质量 | 850.0 kg | 等于实际质量（见 3.4 注） |
| `F_RESIST_STATIC` | 库仑阻力 | 1800 N | 脚本施加，永远反向 |
| `F_RESIST_VISCOUS` | 粘滞阻力 | 500 N·s/m | 同上 |
| `V_OPEN` / `V_CLOSE` | 开/关目标速度 | 1.6 / 0.9 m/s | |

**推力余量只有 12500 / 8330 ≈ 1.5 倍**——这正是"电机真的在托着门"的量级，不是随便写的巨大数字。

### 3.3 控制律（唯一执行手段是施力）

```gdscript
f_requested = (M_NOMINAL * G + F_RESIST_STATIC) + K_SPEED * (v_target - v)
f_requested = clampf(f_requested, -motor_force_limit, motor_force_limit)
_panel.apply_central_force(_axis * f_requested)   # ← 唯一执行手段
_panel.apply_central_force(_axis * resistance_force)
```

**代码中不存在**：写 `linear_velocity`、写 `global_position`、`freeze = true`、`can_sleep = true`、`shape.disabled = true`。
（`reset_gate()` 里的单次位置恢复是关卡复位语义，不是持续约束。）

### 3.4 重力真实参与的直接证据（E8）

把电机上限压到 **3000 N**（远低于自重 8330 N）后开门：

```
gravity_force = 8330 N   gravity_scale = 1.00   欠功率高度 = 0.000 m
```

门**纹丝不动**——重力真的在起作用，不是被关节或脚本抵消。

### 3.5 负载差异（E23）

| 负载 | 升到 1.5 m 用时 |
|---|---|
| 850 kg | **1.30 s** |
| 2400 kg | **20.00 s**（超时未达标） |

同样推力下比值 **15.4 倍**——质量真的改变加速度。

---

## 4. 关节、止挡与保持机构

### 4.1 关节

| 参数 | 值 |
|---|---|
| 类型 | `SliderJoint3D` |
| 局部旋转 | `(0, 0, 90°)` → 滑动轴 = 世界 +Y |
| `lower_distance` | 0.0（关闭位） |
| `upper_distance` | 4.75 |
| 横向误差实测 | **0.0000 m** |
| 角误差实测 | **0.000°** |

关节锁死另外 2 个平移自由度和全部 3 个转动自由度 → 门只能竖直走。

### 4.2 止挡（每端两道）

| 位置 | 主限位 | 真实碰撞备份 |
|---|---|---|
| 下 | 关节 `lower_distance = 0` | `GateSill` 门槛钢梁 |
| 上 | 关节 `upper_distance = 4.75` | `PocketRoof` 门袋顶板 |

实测最高 **4.754 m**，不超关节上限（+0.004 m 求解器容差）。

### 4.3 顶部保持：两级，都可验证

**第一级 —— 机械承接梁（真实 StaticBody）**

`GateCatchBeam`（0.60 × 0.28 × 4.00）从走廊侧 `x = 1.16` 滑到门底下方 `x = 0.00`：

```
梁体 y 4.46 … 4.74    ← 完全开启时门底 4.75
```

门**真的坐在钢梁上**，落座量 0.01 m。

**第二级 —— 限力保持电机**

承接梁收回或未伸出时，速度环以 `F_motor ≤ 12500 N` 托住门。

**实测（E14）**：门到顶后 `hold_mode = "catch"`，`catch_engaged = true`，**电机推力 `motor_force = 0.0`**（承接后按设计断电）。随后把 `powered = false` 完全失电 **5 秒**：

```
失电 5 秒最大下沉 = 0.0000 m
```

**门不动**——机械保持真实有效。

### 4.4 失电行为（E12）

中途失电：

```
h 1.428 → 峰值 1.535 → 回落    v0 = 1.54 m/s → v_min = -4.25 m/s
```

门先靠惯性继续上升 0.107 m，随后被真实重力拉回**自由下落**（-4.25 m/s）。这说明"顶部不掉"完全是承接梁的功劳，不是脚本锁死。

### 4.5 防夹人 / 防卡关

`DoorwaySensor`（Area3D，3.20 m 高）检测玩家：

```gdscript
func close_gate() -> void:
    if _doorway_occupied():
        _state = "open" if height > 0.05 else "closed"
        _retract_catch()
        gate_notice.emit("门口有人，升降门保持开启")
        return   # ← 绝不硬关
```

并且 `_update_catch()` 中，门口有人只阻止**伸出**承接梁，**绝不因此收回**已承重的梁——否则门会砸在通行中的玩家身上。

---

## 5. 固定障碍与可动刚体实验

### 5.1 A：固定障碍（E17 / E18 / E19）

真实 `StaticBody3D`（1.40 × 0.50 × 5.40，y = 5.30）放进升降路径：

| 指标 | 实测 |
|---|---|
| 门最高点 | **0.845 m**（理论极限 5.05 − 4.20 = 0.85 m） |
| 峰值穿透 | **0.0050 m**（5 mm 求解器接触容差） |
| `exit_allowed` | **false**（净空不足，正确拒绝） |
| 接触点 | 8 |

**门无法穿过障碍，也没有弹飞。**

**堵转保护（E18）**：判据是「一个 0.8 s 窗口内门是否真的朝目标前进 ≥ 0.08 m」——不用瞬时速度（接触抖动会让速度反复穿过 0），也不用绝对位移（断电后重力回弹会假装成"有进度"而误清保护）。

```
stall = true
平均推力 = 8582 N（额定的 69%）
断电帧占比 = 31%
```

电机不会无限强推。

**移走障碍后恢复（E19）**：同一台电机继续把门推到 **4.750 m**，`exit_allowed = true`，`obstruction = false`。

### 5.2 B：可动刚体（E20）

独立 `RigidBody3D` 箱子，**mass 40 kg**，放进升降路径：

```
crate_rise = 0.530 m    door_rise = 0.554 m    有接触帧 = 420 / 420
```

箱子被门**真实顶起**，全程 420 帧都有接触。**脚本从未写过箱子的位置或速度**，它上升只可能来自门体接触。

### 5.3 玩家碰撞（E21）

| 场景 | 实测 |
|---|---|
| 门关闭时玩家向前走 | 停在 x = **2.64**，门在 x = 3.20 → 被门板真实挡住 |
| 门上升时玩家在门洞内 | y = **0.00** → 没有被挤进地面或墙壁 |

---

## 6. 剧情状态完全来自门体实际位置

### 6.1 状态机

```
closed ──open()──> opening ──到顶──> open ──close_gate()──> releasing ──梁收回──> closing ──到底──> closed
```

### 6.2 逐条对应任务书第七节 9 项要求

| # | 要求 | 实现 | 验证 |
|---|---|---|---|
| 1 | 剧情条件不足时电机不能启动 | `open()` 首行 `if not unlocked: return` | **E5**：`motor_peak = 0.0` |
| 2 | 条件满足时仅授予驱动许可 | `unlock()` 只设 `unlocked/drive_enabled`，不碰门 | **E6**：`height 0.000 → 0.000` |
| 3 | 门开始运动 ≠ 已打开 | `is_open` 由 `_update_travel_state()` 依实际净空设置 | **E15**：2.017 m 时 `is_open = false` |
| 4 | 净空不足不能通行 | `exit_allowed` 要求 `height ≥ 4.20` | **E15** |
| 5 | 被卡住时不能假报成功 | `stable` 条件含 `not obstruction` | **E17**：`exit_allowed = false` |
| 6 | 净空达标且稳定后出口才可用 | `_stable_clock ≥ 0.35 s` + `hold_mode != "none"` | **E16** |
| 7 | 玩家实际进入出口才完成 | `ExitTrigger.body_entered` → `player_entered` | **E24** |
| 8 | 原有参与度检查仍有效 | `_on_exit_entered()` 中 `PHASE_04` 校验**原样保留** | 代码未动 |
| 9 | 第四幕→第五幕真实切换仍可运行 | `SessionHub.request_scene_switch` | **H3b** |

### 6.3 `game.gd` 的改动（最小必要）

```gdscript
# 1. _on_memory_finished(3)
if gate != null:
    gate.unlock("memory_3")   # ← 新增：只授予许可
    gate.open()

# 2. _on_exit_entered()
if gate == null or not gate.exit_allowed or not gate.is_open:   # ← 净空判定
    return

# 3. reset_level()  —— 修复缺陷 A4
if gate != null:
    gate.reset_gate()

# 4. 网络快照/事件中的 gate.open() 前补 gate.unlock(...)
```

**`_on_exit_entered()` 中的参与度校验、`completed` 权威判定、`SessionHub` 交接 payload 全部原样保留，未削弱任何故事完成门槛。**

---

## 7. 实际高度、速度与推力数据

### 7.1 正常开门全过程（E7）

高度采样（每 20 帧）：

```
[0.00, 0.15, 0.56, 1.07, 1.58, 2.09, 2.61, 3.12, 3.63, 4.14, 4.65, 4.75]
```

**单调上升**——是力积分的结果，不是预设时间表。
推力峰值 **12500 N**，运动帧数 206，最终高度 **4.735 m**。

### 7.2 典型工况汇总

| 工况 | height | velocity | motor_force | hold_mode |
|---|---|---|---|---|
| 初始关闭 | 0.000 | 0.000 | 0 | none |
| 电机启动 | 0.288 | 1.14 | 12500 | none |
| 上升中 | 2.32 | 1.54 | — | none |
| 被障碍挡住 | 0.41（峰值 0.845） | ~0 | 0（堵转断电帧） | none |
| 顶部承接 | 4.73 | 0.000 | **0** | **catch** |
| 完全开启 | 4.750 | 0.000 | 0 | catch |

### 7.3 关节稳定性（E11 / E22）

连续 **5 轮** 复位→开门→开启：

```
R1 h=4.75 err=0.0000 ang=0.00
R2 h=4.75 err=0.0000 ang=0.00
R3 h=4.75 err=0.0000 ang=0.00
R4 h=4.75 err=0.0000 ang=0.00
R5 h=4.75 err=0.0000 ang=0.00
```

横向误差始终 **0.0000 m**，角误差 **0.00°**——关节从不失稳。

---

## 8. 修改文件清单与 SHA-256

### 8.1 修改的正式代码（4 个）

| SHA-256 | 文件 |
|---|---|
| `8259958209C5B8BCB65BC087E4E50A4F2AD302B307C147D6AC7E319DE6DBF115` | `game/scripts/act4/exit_gate.gd` |
| `5CED167FC8428B0B30529A28A8CD6C138AD8861B72902A7AB44D0D4F5A982526` | `game/scripts/act4/game.gd` |
| `D064C2978851C638EA9E532623C0F4761997808CE995D09186C71EA0F4484109` | `game/scripts/act4/level_builder.gd` |
| `BFBA18972CDEA7856D56C3E1E81C19E4812E9CCD958C70143A45E8F39674B3DD` | `game/scripts/act4/memory_director.gd` |

**`level_builder.gd` 的唯一改动**（第 340 行附近）：把整块 `GateWallTop`（0.7×2.6×5.4）切成南北两段并加岩帽，留出 4.60 m × 5.20 m 真实门袋槽——修复缺陷 A3。其余 1100+ 行未动。

**`memory_director.gd` 的唯一改动**（第 504 行附近）：`gate.open()` 前补 `gate.unlock("memory_3_setpiece")`。其余未动。

### 8.2 新增测试（全部在 `game/tests/mech004c_*`）

| SHA-256 | 文件 |
|---|---|
| `404AF7FA1757B74F2251E2C24FD6CE96B28C9D9331E675ADEB29E851162AA78C` | `mech004c_gate.gd` |
| `47D5BEE252FD2874F5DFC73C6BC48F52F7B4F5F4478F9B3DD506EC0D47DF53FC` | `mech004c_gate.tscn` |
| `966E965B5A1F1275B869EA430A8CBC7613A8C57A2A83CB98ECEC3FFB94B2116F` | `mech004c_handoff.gd` |
| `375E7A93DA5C041792E0933003015FD48B629B7D46A28F63E7CD32739297317B` | `mech004c_handoff.tscn` |
| `6C4A45FC74715DAB549C95A09D43F9F98A3DB941D9B7C3F002D5AD49B6F557FF` | `mech004c_handoff_observer.gd` |
| `0B96648A4176D7AF92777F22456DAC67B1038C09FBB062F24D95EDF79D991EF2` | `mech004c_capture.gd` |
| `16F5E39893DBFA0EFCCD5A4262822405685DC0D9D6AC230E8A9AFA952D2C32B3` | `mech004c_capture.tscn` |
| `70EDCA1D75030939D1E88B22969B3BCB208F8F7674F882F823E041C525F89DAF` | `mech004c_joint_probe.gd` |
| `EF16271FA3989E3AEF2A44B2647817EDA94620CD255D0EFA77123A02B436B982` | `mech004c_joint_probe.tscn` |
| `5ADDA947609EBC6971B0A66B8B471B8EDA48A3AA6FEDB0B44C37DCC26C9E8AD5` | `mech004c_joint_probe2.gd` |
| `C30DF9AE8BD666DC8435DD60972DFEBD4780B37414F8C93F6A54C41D09B41AB9` | `mech004c_joint_probe2.tscn` |
| `E2858B3864494557910EFEBCF04E56A3A79AEB8838F7ED295BB220B38C2411DE` | `mech004c_smoke.gd` |
| `D1BBA497605275BF488A32C979E5938B1809E424BECC152E25EF99D433A5A692` | `mech004c_smoke.tscn` |
| `33D35B06E2C0CA71857929C3288D2C8912A70743EECA6939A0D34947D2DC8BF1` | `mech004c_tree_probe.gd` |
| `27F392F3C7AFE5F4EB900FF003B48B08E59DA113CAC5C3BB8E6675451516547B` | `mech004c_tree_probe.tscn` |

### 8.3 确认未改动（004A / 004B 已验收文件）

| SHA-256（与 004B 基线**完全一致**） | 文件 |
|---|---|
| `A59E2CE83D329F370D8A14F2DCF5CDFFCE996D122F252EE0574C61F08F92F30B` | `game/scripts/act4/freight_platform.gd` |
| `C9385A1FD89814676428483210081C3FF679D7A4E6FB587350809DB4396887DF` | `game/scripts/act4/portable_crystal.gd` |
| `71BC3FBCE157F164215C28831A1EE41D20E3CE6233A25AC2DCA7F36165CA484C` | `game/scripts/act4/cradle.gd` |
| `3EBA645DB2D5925A6E635CF2FE8FDF900AFEC20536F7A13F948554A7ECC5E3EA` | `game/scenes/act4.tscn` |

### 8.4 窗口 B 文件：确认未被本窗口修改

哈希差异扫描发现 `app.gd`、`core_rig.gd`、`stabilizer_rig.gd` 与我的基线快照不同。**时间戳证明这是窗口 B 的改动**：

| 文件 | 最后修改 | 归属 |
|---|---|---|
| `game/scripts/core/app.gd` | 20:16:40 | **窗口 B** |
| `game/scripts/machines/core_rig.gd` | 20:26:03 | **窗口 B** |
| `game/scripts/machines/stabilizer_rig.gd` | 20:29:18 | **窗口 B** |
| （我的基线快照） | 20:13:29 | 窗口 A |
| `game/scripts/act4/exit_gate.gd` | 20:48:19 | **窗口 A** |
| `game/scripts/act4/game.gd` | 20:36:21 | **窗口 A** |

我的第一处编辑在 **20:36**，晚于窗口 B 的全部改动。同目录还出现 `mech005a_flow.gd`、`mech005a_stabilizer.gd`、`mech005a_capture.gd`（窗口 B 的测试），本轮从未创建或修改它们。

**结论：窗口 A 未修改窗口 B 负责的任何文件。**

### 8.5 备份与安全

- 基线备份：`work/parallel-mechanics004c/accepted_baseline/`（含 `scripts_act4/`、`tests/`、`act4.tscn`、`SHA256_before_all.txt`）
- 实验与日志：`work/parallel-mechanics004c/logs/`、`experiments/`
- 截图：`game/captures/mech004c/`
- 未执行任何 `git reset --hard` / `git clean` / 批量覆盖 / 自动提交

---

## 9. 自主修复的 Bug

| # | Bug | 现象 | 定位方法 | 修复 |
|---|---|---|---|---|
| **B1** | 滑动轴方向误判 | 首次探针沿 +Y 施力门不动，重力被关节完全吸收 | `mech004c_joint_probe.gd` 三轴对照实验 | 关节绕 Z 旋转 90°，局部 X → 世界 +Y |
| **B2** | 门升到 0.795 m 被卡死 | 走廊天花板（世界 x ≥ 3.50）挡住门板（半厚 0.225，中心 x = 3.34） | 冒烟测试 `GATE stall height=0.795 contacts=4` | 门板厚度 0.45 → 0.36，中心移到局部 x = 0.00 |
| **B3** | 门袋无处可去 | 原 `GateWallTop` 整块封死门上方 | 审计 + B2 现象 | `level_builder.gd` 切成南北两段 + 岩帽，留 4.60×5.20 槽 |
| **B4** | 顶部承接梁抽走时砸门 | 门口有人时 `_update_catch` 会收回已承重的梁 | 代码走查 | 改为「只阻止伸出，绝不收回」 |
| **B5** | 堵转判定误清 | 用瞬时速度 `< 0.03` 判据，接触抖动导致 `stall=false`，平均推力 91% | E18 首次失败（`stall=false avg=11354`） | 改为**有符号行程进度**：0.8 s 窗口内朝目标前进 < 0.08 m |
| **B6** | E17 穿透量误算 | 堵转断电后门被重力拉回，用瞬时高度算穿透 = 0.1525 m | E17 首次失败 | 改用**最高点**计算峰值穿透 = 0.0050 m |
| **B7** | `reset_level()` 不恢复门 | 复位后门保持开启（原有缺陷 A4） | 审计 | `game.gd::reset_level()` 增加 `gate.reset_gate()` |
| **B8** | 交接测试观察者失效 | 观察者要求 Act4 成为 `current_scene`，但它只是子节点 | `mech004c_tree_probe.gd` 打印场景树 | 改为惰性捕获初始场景名，检测变化 |
| **B9** | 探针运行默认抑制切场 | `game.gd` 见 `suppress_act5` 就不切场，H3 超时 90 s | 日志 `ACT4 completed but scene switch suppressed (probe mode)` | 测试显式 `remove_meta("suppress_act5")` |
| **B10** | E20 箱子进不了门袋 | 0.70 m 箱子 > 门袋内腔 0.72 m 且撞到立柱 | E20 首次 `crate_rise=0.199` | 箱子改 0.40 m，`can_sleep=false` + `contact_monitor` |

---

## 10. 专项与回归结果

### 10.1 MECHANICS-004C 专项（24/24，退出码 0）

```
E1  正式第四幕场景正常加载                      PASS  gate=true player=true cradles=4
E2  门体质量/碰撞/关节真实存在                  PASS  RigidBody3D 850kg layer=4 mask=15 sleep=false
E3  初始门关闭                                  PASS  height=0.000 state=closed
E4  原有剧情条件保留                            PASS  memory_3/relay_a/freight 文案与阶段机
E5  未满足条件时电机不能启动                    PASS  motor_peak=0.0
E6  满足条件后仅授予驱动许可                    PASS  height 0.000→0.000 is_open=false
E7  真实施力使门开始上升                        PASS  单调 [0.00…4.75] force_peak=12500
E8  门受真实重力影响                            PASS  Mg=8330N，3000N 托不动
E9  电机推力不超过上限                          PASS  peak=12500.0 limit=12500.0
E10 升降约束方向正确                            PASS  axis=(0,1,0) dot_up=1.0000 横向=0.0000
E11 门不横向漂移也不旋转                        PASS  err=0.0000m ang=0.000°
E12 松开动力后运动合理                          PASS  peak 1.535 v_min=-4.25
E13 顶部限位真实有效                            PASS  max=4.754 upper=4.75
E14 顶部机械保持真实有效                        PASS  hold=catch motor=0.0 失电5s下沉=0.0000m
E15 通行净空不足时不允许过幕                    PASS  2.017m exit_allowed=false
E16 完全开启后允许正常通行                      PASS  clearance=4.750 玩家站进门洞
E17 固定障碍真实阻挡门体                        PASS  峰值穿透=0.0050m
E18 有障碍时电机不会无限强推                    PASS  avg=69% 断电帧31%
E19 移走障碍后机构恢复                          PASS  0.005→4.750m
E20 可动刚体受到门体真实接触                    PASS  crate_rise=0.530 接触帧420/420
E21 玩家与门的碰撞正常                          PASS  停在 x=2.64
E22 重复开关或复位后关节稳定                    PASS  5 轮 err=0.0000
E23 不同负载下加速度具有合理差异                PASS  1.30s vs 20.00s（15.4×）
E24 实际完成第四幕                              PASS  b1/b3 落座 2/2 completed=true
MECH004C_DONE checks=24 passed=24 failures=0
```

**关键工况重复次数**：E22 连续 5 轮、E11/E13/E14 各 300+ 帧、E20 420 帧接触监测。

### 10.2 回归

| 专项 | 结果 |
|---|---|
| MECHANICS-004A | `MECH004A_DONE checks=18 passed=18 failures=0` |
| MECHANICS-004B | `MECH004B_DONE checks=24 passed=24 failures=0` |
| MECHANICS-004B 支架附加 | `MECH004B_RELAY_DONE checks=3 passed=3 failures=0` |

第二、三幕代码未修改，哈希未变（见 8.3）。网络专项按任务书暂停。

### 10.3 无头模式 `mouse_captured` 环境限制（真实记录）

沿用 004A / 004B 的既有记录，**本轮不宣称该项通过**：

> 第四幕内置 smoke-play 14 项中 13 过；唯一失败 `mouse_captured` 是无头模式没有真实鼠标捕获，属**环境限制**（同一项在窗口模式为 true）。

本轮未重新运行 smoke-play，该限制状态与 004A/004B 报告一致。

---

## 11. 第四幕→第五幕交接结果

```
HANDOFF_OBSERVER start current_scene=Mech004CHandoff
HANDOFF_OBSERVER baseline=Mech004CHandoff
HANDOFF_OBSERVER switch_detected to=Main
  root_children=["SessionHub", "Mech004CHandoffObserver", "Main"]

PASS  H3b 第四幕→第五幕真实场景切换
  from=Mech004CHandoff  to=Main  nodes=3103  chapter=act05
  gate_open=true  completed=true  elapsed=9.1s
```

| 项 | 结果 |
|---|---|
| 第四幕入口 `res://scenes/act4.tscn` | PASS（门是 RigidBody3D，玩家在线） |
| 第五幕入口 `res://scenes/main.tscn` | PASS（3103 节点，初始化完成） |
| 真实切场 | PASS（`request_scene_switch` → `change_scene_to_file`） |
| 交接 payload | `chapter=resonance_04`, `completed=true`, `gate_open=true`（来自门体实际状态） |
| `SessionHub.current_chapter` | `act05` |

**未直接设置第五幕完成状态**；第五幕任何文件未修改。

---

## 12. 真实窗口截图

目录：`game/captures/mech004c/`　分辨率 1280×720　**全部第一人称真实玩家视角**

| 文件 | 内容 | 现场读数 |
|---|---|---|
| `01_gate_closed.png` | 门关闭 | height=0.00 state=closed exit_allowed=false |
| `02_motor_start.png` | 电机启动 | motor_force=12500 N，height=0.288，v=1.14 |
| `03_gate_rising.png` | 门上升中 | height=2.32 m，v=1.54 m/s，joint_err=0.0000 |
| `04_blocked_by_obstacle.png` | 固定障碍挡门 | height=0.41 m（峰值 0.845），obstruction=true |
| `05_top_hold.png` | 顶部限位与保持 | height=4.73 m，hold=catch，motor=0 N |
| `06_player_passing.png` | 玩家通过出口 | 玩家 x=5.00（门 x=3.20），clearance=4.73 m |

**取证方式声明**：
- 门只靠 `apply_central_force()` 上升——**无传送、无冻结、无关闭碰撞**。
- 障碍是真实 `StaticBody3D`。
- 玩家只按真实 `Input.action_press("move_forward")` 行走，只在截图前用 `teleport` 摆到**玩家本来会站的观察位置**（等价于玩家自己走过去），**从不传送进门洞或触发区**。
- 截图进程在门口临时补一盏灯（仅截图用，不改正式场景）。

---

## 13. 可试玩入口

```
引擎：C:\Users\ASUS\Desktop\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe
工程：C:\Users\ASUS\Desktop\迷失太空\game\
场景：res://scenes/act4.tscn
```

命令行：

```powershell
& "C:\Users\ASUS\Desktop\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe" `
  --path "C:\Users\ASUS\Desktop\迷失太空\game" "res://scenes/act4.tscn"
```

**试玩路径**：撞钟 → 三段记忆 → 晶体运输 → b1/b3 中继 → 第三段记忆后门自动受力升起 → 走到门洞等净空达标 → 穿门进入走廊。

**专项复跑**：

```powershell
& $godot --headless --path "C:\Users\ASUS\Desktop\迷失太空\game" "res://tests/mech004c_gate.tscn"
& $godot --headless --path "C:\Users\ASUS\Desktop\迷失太空\game" "res://tests/mech004c_handoff.tscn"
```

---

## 14. 尚存限制

1. **窗口 B 尚未完成**：第五幕正在被另一个窗口改造。本轮只验证了第五幕**入口能加载并初始化**，未验证整幕玩法。整幕联合验收必须等窗口 B 完成后进行。

2. **`mouse_captured` 无头模式限制**：沿用 004A/004B 记录，无头模式该项为 false（环境限制，非回归）。

3. **门袋是"岩体开槽 + 钢制内衬"**：为了让门真的升进去，`level_builder.gd` 把 `GateWallTop` 切开了。这是本轮唯一的场景几何改动，需在整幕联合验收时确认与窗口 B 的第五幕入口视觉不冲突。

4. **关节 restitution 不受支持**：Jolt 忽略 `linear_limit/restitution`（引擎警告）。本轮不依赖该参数，止挡由关节硬限位 + 真实碰撞双保险实现。

5. **堵转保护是占空比式**：不是真实的电机热模型，而是「断电 0.55 s / 通电 0.45 s」的工程近似，平均推力降到额定 69%。对玩法足够，但不是电气仿真。

6. **未做网络同步的多人门测试**：网络专项按任务书暂停。代码中 host 快照路径已补 `gate.unlock()`，但未跑双进程验证。

---

## 15. GO / CONDITIONAL GO / NO-GO

### 判定：**GO（限定于第四幕出口门本身）**

对照任务书第十二节 16 条 GO 标准：

| # | 标准 | 结果 | 证据 |
|---|---|---|---|
| 1 | 原有 Tween 不再驱动门体主运动 | ✅ | `exit_gate.gd` 中 `create_tween` 已完全删除 |
| 2 | 门具有真实质量、惯性和重力响应 | ✅ | 850 kg，I=(2428.6,1188.3,1258.7)，E8 |
| 3 | 真实关节限制门体运动方向 | ✅ | SliderJoint3D，err=0.0000 m，E10/E11 |
| 4 | 电机有有限推力 | ✅ | 硬钳制 12500 N，E9 |
| 5 | 障碍能够真实阻挡门 | ✅ | E17 峰值穿透 5 mm |
| 6 | 门不会穿透障碍 | ✅ | E17 |
| 7 | 可动刚体能受到门体接触作用 | ✅ | E20 箱子被顶起 0.53 m |
| 8 | 顶部保持机制真实有效 | ✅ | E14 失电 5 s 下沉 0.0000 m |
| 9 | 门体实际净空决定能否通行 | ✅ | E15/E16 |
| 10 | 玩家能够完成第四幕出口操作 | ✅ | E24 |
| 11 | 004A、004B 无回归 | ✅ | 18/18、24/24、3/3 |
| 12 | 第五幕正式入口仍可加载 | ✅ | H2（3103 节点） |
| 13 | 全部新增测试通过 | ✅ | 24/24，退出码 0 |
| 14 | 有真实窗口证据 | ✅ | 6 张 1280×720 第一人称截图 |
| 15 | 有明确安全回退方法 | ✅ | 见下 |
| 16 | 未修改窗口 B 所负责的文件 | ✅ | 见 8.4 时间戳证据 |

### 安全回退方法

```powershell
$g = "C:\Users\ASUS\Desktop\迷失太空"
$b = "$g\work\parallel-mechanics004c\accepted_baseline"

# 只回退窗口 A 拥有的 4 个文件
Copy-Item "$b\scripts_act4\exit_gate.gd"       "$g\game\scripts\act4\" -Force
Copy-Item "$b\scripts_act4\game.gd"            "$g\game\scripts\act4\" -Force
Copy-Item "$b\scripts_act4\level_builder.gd"   "$g\game\scripts\act4\" -Force
Copy-Item "$b\scripts_act4\memory_director.gd" "$g\game\scripts\act4\" -Force

# 新增的 mech004c 测试与截图可保留（不影响正式玩法）
```

**回退前请确认窗口 B 未同时修改这 4 个文件**（它们属于 `scripts/act4/`，不在窗口 B 的范围内）。

---

## 16. 窗口 A 声明

> **这是双窗口并行开发的窗口 A。**
> 本轮唯一任务是第四幕出口门的真实物理化，已完成并自验通过。
> **最终整幕联合验收必须等窗口 B（MECHANICS-005A 第五幕核心稳定机关）完成后进行。**
>
> 本窗口**立即停止**，不自动开发第五幕。

**最高原则达成确认**：
> 出口门现在是真正受力运动、会被障碍阻挡的机械设备——850 kg 真实刚体，靠 `apply_central_force()` 沿竖直滑动关节运动，受真实重力、真实阻力、真实接触反作用支配，顶部靠实体钢梁承接。**它不是沿 Tween 曲线移动的模型。**
