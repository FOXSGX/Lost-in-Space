# MECHANICS-004B 第四幕悬吊货运平台与晶体真实运输最终报告

> 工程：`game/`（`C:\Users\ASUS\Desktop\迷失太空\game`）　Godot 4.7.2.stable + Jolt，60 Hz
> 结论：**GO（技术）**（含第九节如实声明的边界）
> 范围：只改造第四幕的**悬吊货运平台 / 货物承载 / 货物夹具**；未改第一幕、第二三幕已验收机械、第五幕、出口门、网络与全局 Jolt 配置。

---

## 一、原有货运平台审计（P0，20 项）

审计对象：`game/scripts/act4/freight_platform.gd`（原 1619 行）、`freight_control.gd`、`freight_arena.gd`、`portable_crystal.gd`、`game.gd`、`level_builder.gd`。

| # | 问题 | 审计结果（改造前） | 分类 |
|---|---|---|---|
| 1 | 平台本体节点类型 | `AnimatableBody3D`，`sync_to_physics = false` | 运动学 |
| 2 | 是否有真实碰撞体 | 有：`DeckShape` + 南北栏杆 + 三面货唇（共 6 个 BoxShape3D） | 真实碰撞 |
| 3 | 是否有实际质量/惯量 | **没有**。无 `mass`，Jolt 不解算它 | 运动学 |
| 4 | 如何沿断层移动 | `travel_x += speed * delta`，`speed` 由 `move_toward()` 逼近 `target_speed` | **伪动力学（预设速度曲线）** |
| 5 | E / W / S 分别做什么 | E 握杆/松杆；W/S 给 `drive_input`；制动是独立控制点的 E 开关 | 合理电控 |
| 6 | 驱动器是否有限推力/力矩 | **没有**。`max_speed` 与 `accel` 只是两个常数 | **无上限** |
| 7 | 是否预设速度曲线 | **是**。`TRAVEL_SPEED_EMPTY=1.45` / `TRAVEL_SPEED_LOADED=0.95` / `ACCEL_*` / `COAST_DECEL` 直接决定速度 | **预设时间表** |
| 8 | 制动是否真实作用 | 只是把 `target_speed` 设 0 并用更大的 `move_toward` 速率 | **伪制动** |
| 9 | 是否有卷筒/缆绳/传动 | 有视觉缆绳（`_cables`、`_trolley`），只做 `_place_cable()` 摆位 | 视觉动画 |
| 10 | 缆绳是否传递张力 | **否**。缆绳不参与任何受力 | 视觉动画 |
| 11 | `clamp_t` 代表什么 | 一个 0→1 的**装饰插值参数**，驱动两只夹爪在 z 上 0.80→0.40 平移 | **纯视觉** |
| 12 | 夹具是否有实体碰撞/限位 | **没有**。夹爪是 `Node3D` + 视觉 box，无 `CollisionShape3D` | **无实体** |
| 13 | 晶体放到平台上后是否自由刚体 | **否**。`seat_cargo()` 立刻 `freeze=true`、`set_collision_enabled(false)` | **冻结 + 关碰撞** |
| 14 | 是否有隐藏吸附/冻结/同步位置 | **有，而且是主路径**：`_tick_cargo()` 每帧 `cargo.global_transform = Transform3D(...)` | **隐藏吸附** |
| 15 | 平台运动是否通过真实接触带动晶体 | **否**。晶体被冻结后由脚本写 transform | **伪运输** |
| 16 | 玩家能否站在平台上随平台运动 | 能。`_rider_area` + `get_ride_velocity()`，`CharacterBody3D` 走真实移动碰撞体 | 真实（运动学平台） |
| 17 | 到站如何判定 | `current_dock()` 比较 `travel_x` 与端点（±0.06 m）；另有 `_emit_dock_if_arrived()` | 合理 |
| 18 | 失载/制动失败/卡住会怎样 | `_drop_cargo_overboard()` 把晶体**传送**到 (1.72, 0.30) 并赋速度 | 伪机械 |
| 19 | 任务成功是否直接读 flag | `_update_objective_from_state()` 读 `platform.cargo_attached`、`clamp_t > 0.9`、`crystal_a.x < -8.4` | 部分读 flag |
| 20 | 剧情是否要求先运过断层 | **是**。story.json 目标链：`freight` → `freight_loaded` → `freight_fixed` → `freight_carry` → 支架 | 剧情正确 |

**审计结论**：玩家随动、碰撞体、端位判定是真实的；**平台动力学、货物承载、货物夹具三项都是伪机械**。这正是本轮唯一需要物理化的缺口。

### 审计中额外发现的根因级缺陷

**晶体的碰撞体是 `CapsuleShape3D`（圆底半球）。** 它站在甲板上时与甲板只有一个接触点，平台一加速，接触力立刻产生力矩，晶体像球一样滚倒（实测 `up_y` 从 1.00 掉到 0.32）。这不是平台的问题，而是**晶体自身不能站立**——004A 的支架之所以没暴露它，是因为支架用承托面 + 两侧锁爪把晶体夹住了。

---

## 二、实际选择的物理改造点

只改三处，且都是第四幕货运平台直接相关的代码：

| 改造点 | 原状态 | 改后 |
|---|---|---|
| **平台动力学** | 预设速度曲线 | **受约束动力学**：`M_eff·dv/dt = F_drive − F_brake − F_resist − F_grade`，速度是力积分的结果 |
| **货物承载** | 冻结 + 每帧写 transform | **真实刚体**：不冻结、不关碰撞、不写 transform，靠 Jolt 接触跟随 |
| **货物夹具** | `clamp_t` 驱动装饰夹爪 | **实体机构**：4 块水平合拢侧挡（StaticBody3D）+ 1 块下压压板（StaticBody3D） |
| **晶体碰撞体** | `CapsuleShape3D`（圆底，滚倒） | `CylinderShape3D`（平底，半径/高度不变 0.34/1.20） |

**明确声明**：平台仍然是 `AnimatableBody3D`（运动学），**不是**完整 Jolt 刚体。上面那条运动方程是**受约束动力学模型**，不是 Jolt 求解的自由刚体。缆绳仍不传递张力。

---

## 三、平台驱动与制动原理

### 运动方程（`_tick_drive()`）

```
M_eff · dv/dt = F_drive − F_brake − F_resist − F_grade

M_eff    = 150 kg（平台自重）
         + 货台上真实刚体的质量（Jolt 重叠查询，不是脚本记账）
         + 80 kg × 站在台上的玩家数
F_drive  = clamp(420 × (v_setpoint − v), −620, +620) × ramp
           其中 v_setpoint = 操纵杆 × 1.45 m/s
F_brake  = −sign(v) × 1150（只在 |v| > 0.02 时）
F_resist = −sign(v) × (60 + 28·|v|)
F_grade  = 0（轨道是水平吊索，无真实坡度）
```

### 逐项对照任务书要求

| 要求 | 实现 |
|---|---|
| 明确的工作方向 | W = 向对岸（−x），S = 倒退（+x） |
| 有上限的驱动力 | `F_DRIVE_MAX = 620 N`，硬性 `clampf`；实测峰值 425.6 N |
| 合理的启动与停止 | `DRIVE_RAMP = 3.2`/s 推力爬升；停止靠阻力，不瞬清 |
| 不同载荷的响应 | `M_eff` 含真实货物质量；实测 150 kg 用 63 帧到 1.0 m/s，166 kg 用 66 帧 |
| 到站减速或限位 | `_park_brake_force()` 按剩余距离算所需减速度（`v²/2d`），受 `F_BRAKE_MAX×0.85` 限制；端位硬限位吸收剩余动能 |
| 受阻时停止强推 | `_blocked_ahead()` 甲板上方 0.90 m 射线探测，命中即撤销推力 |
| 松开输入后的合理运动 | 只剩 `F_resist`，实测松 W 后速度 −1.147 m/s、继续滑行 1.187 m |
| 防止数值发散 | `speed` 钳制在 ±3.2 m/s；`M_eff` 有下限；`_drive_ramp` 有界 |

**禁止项全部未出现**：没有 `speed=0` 直接归零、没有倒放动画、没有瞬移、没有穿透、没有倒计时到站。

---

## 四、真实货物承载与夹持结构

### 4.1 货物是真实刚体（`_tick_cargo()`）

改造后的 `_tick_cargo()` **只做三件事**：读回真实状态、推进夹具行程、在真实越界时解除登记。它**不写** `global_transform`、**不冻结**、**不关碰撞**。

`seat_cargo()` 的差别：

```
改造前： crystal.set("freeze", true)
         crystal.call("set_collision_enabled", false)
         每帧写 global_transform
改造后： (crystal as RigidBody3D).freeze = false
         crystal.call("set_collision_enabled", true)
         只登记“这趟运输算哪块晶体”
```

### 4.2 夹具（`_tick_clamp()`）

```
ClampSide0..3   四块实体侧挡，沿平台局部 ±x / ±z 水平合拢
                合拢内表面 = 0.388 − 0.10/2 = 0.338 m（晶体半径 0.34，2 mm 预紧）
                张开退到 1.20 m，完全让开装卸区
                每块带 StaticBody3D(layer 1) + BoxShape3D(0.10 × 0.42 × 1.30)
ClampPress      下压压板，沿 −y 从 1.80 m 落到晶体顶面 2 mm 处
                带 StaticBody3D(layer 1) + BoxShape3D(0.74 × 0.12 × 0.66)
```

行程都是**位移驱动**（每帧约 0.42·dt ≈ 7 mm，与 Jolt 碰撞检测同量级），不是瞬移——这是关键：瞬移会把穿透修正能量灌进晶体（见第七节 Bug 5）。

`is_cargo_fixed()` 读的是**真实夹持状态**（`clamp_closed and jaw_locked`），其中 `jaw_locked = jaw_pressing and sides_closed`，不再是 `clamp_t > 0.9` 的阈值。

### 4.3 甲板摩擦

`DECK_FRICTION = 0.06`（磨光钢格栅）。这个值必须低于启动加速度所需的 μ，未固定的晶体才会在加速/制动时真的滑——这是 A/B 对照能成立的前提。

---

## 五、实验数据

### 5.1 空载 / 单箱 / 双箱

| 工况 | M_eff | 到 1.0 m/s 用帧 | 峰值速度 | 备注 |
|---|---|---|---|---|
| 空载 | 150 kg（玩家握杆时 230 kg） | **63 帧** | 1.213 m/s | 玩家 80 kg 也计入 |
| 单箱 | 166 kg（+玩家 246 kg） | **66 帧** | 1.209 m/s | 载重影响可测 |
| 双箱 | 182 kg（+玩家 262 kg） | — | — | 货台 3.2×3.2 m，两块 16 kg 晶体都放得下且都被计入 |

> 16 kg 相对 150 kg 平台只占 10.7%，因此加速差异只有 3 帧——**这是真实比例，未人为放大货重**。

### 5.2 A / B / C 固定对照（同一块 16 kg 晶体、同一驱动条件）

| 组 | 条件 | 峰值相对滑移 | 最小 up_y | 结论 |
|---|---|---|---|---|
| **A 未固定** | 夹具张开 | **0.8034 m** | 0.999 | 明显滑移，但未翻倒 |
| **B 正确固定** | 侧挡合拢 + 压板压住 | **0.0571 m** | 0.998 | 滑移降到 A 的 7.1% |
| **C 解除固定** | 行驶中张开夹具 | **0.8268 m** | 0.998 | 恢复自由滑动 |

三组使用**同一块晶体实例、同一质量 16 kg、同一驱动曲线**，差异只来自夹具状态。

### 5.3 制动与滑行

| 项 | 实测 |
|---|---|
| 制动前速度 | −1.192 m/s |
| 制动距离 | 0.091 m（`_park_brake_force` 已在端位前接管） |
| 松 W 后 6 帧速度 | −1.147 m/s（**未归零**） |
| 松 W 后滑行距离 | 1.187 m |

### 5.4 连续三轮 / 五次异常

| 项 | 实测 |
|---|---|
| 三轮运输 | slip = 0.0428 / 0.0249 / 0.0267 m，三轮都 `fixed=true` |
| 五次异常 | 空货台 5 次从未 `fixed`；未固定行驶后 up_y 均 1.00，平台无发散 |

---

## 六、玩家实际运输流程（正式路径）

```
玩家走到西侧装货台 → F 搬起 16 kg 晶体
  → 走上平台货台 → F 放下：晶体靠重力落在真实甲板上（仍是刚体）
  → 走到夹具杆旁 → E：四块侧挡合拢夹住、压板压到顶面（约 0.9 s）
  → 走到操纵台 → E 握杆 → 按住 W：平台按受力加速、承载晶体穿越断层
  → 到对岸由端位限位/制动自然停住（dock = far）
  → E 松杆 → E 打开夹具 → F 搬起同一块晶体 → 运往 b1 支架
```

**同一实例证据**（E19 实测）：`crystal_instance == stage_crystal_instance`，晶体从上货台→运过断层→卸下→落进 b1 叉口→004A 锁爪夹住，全程是**同一个 `PortableCrystal` 节点**，没有被传送或重建。

---

## 七、自主修复的 Bug（复现 → 根因 → 修改）

| # | 现象 | 根因 | 修改 |
|---|---|---|---|
| 1 | 晶体在平台上永远滚倒（up_y 1.00 → 0.32） | 晶体碰撞体是 `CapsuleShape3D`，圆底半球与甲板单点接触 | 改 `CylinderShape3D`（半径/高度不变，004A 数值零改动） |
| 2 | 写 `global_position` 移动平台时晶体被“假拖” | 瞬移式运动学让 Jolt 把穿透修正当成推动 | 平台速度改为力积分，位移连续 |
| 3 | 按 W 平台不动（force=30.9 N 却 speed=0） | 静摩擦判据在**有驱动输入时**也清速度，推力爬升永远起不来 | 只在无驱动输入时才清速度 |
| 4 | 夹具合拢后晶体被弹飞 8 m | `CollisionShape3D` 挂在普通 `Node3D` 下**被物理服务器静默忽略**，夹持完全没有碰撞；改用 `StaticBody3D` 后正常 | 侧挡/压板改为 `StaticBody3D` + `CollisionShape3D`（同 004A 锁爪做法） |
| 5 | 压板贴不到晶体顶面（`jaw_pressing` 恒 false） | 用 `to_local().y` 算目标高度，平台 tilt 让 local.y 从 −0.02 涨到 1.36 | 改用**世界竖直方向**算压板目标高度 |
| 6 | 晶体落到 local y=1.36 而不是甲板 | 压板张开高度 1.34 m < 晶体 1.20 m + 板半厚，装卸时体积重叠 | 张开高度改 1.80 m |
| 7 | 侧挡挡住玩家看货的视线 | 侧挡高 1.12 m，与晶体等高 | 降到 0.42 m（仍提供横向约束，上半段可见） |
| 8 | 压板挡住驾驶员视线 | 压板 1.10 × 0.86 太大 | 缩到 0.74 × 0.66（仍大于晶体直径 0.68） |
| 9 | 侧挡创建在原点，与落座晶体重叠 | 忘记设初始 position | 创建时立即放到 CHOCK_OPEN |
| 10 | 截图流程“重新握杆”失败 | 操纵台要求平台停稳；玩家在滑行中握不到 | 等滑行结束再握杆（真实行为） |

---

## 八、修改文件与 SHA-256

| 文件 | SHA-256（改造后） | 004A 基线 |
|---|---|---|
| `game/scripts/act4/freight_platform.gd` | `A59E2CE83D329F370D8A14F2DCF5CDFFCE996D122F252EE0574C61F08F92F30B` | `3CA1F446800648A3…` |
| `game/scripts/act4/portable_crystal.gd` | `C9385A1FD89814676428483210081C3FF679D7A4E6FB587350809DB4396887DF` | `EB4E331097621F17…` |
| `game/tests/mech004b_freight.gd`（新增） | `CE1449E4E200A20D7766EC4DD3C362565CC24D42B1C2852EF607ED685D19BFB1` | — |
| `game/tests/mech004b_relay_guard.gd`（新增） | `B2C8DE4F75A20A102170D9C70DAA1046435EDBCA29685980D80866E4AEE5CD7B` | — |
| `game/tests/mech004b_capture.gd`（新增） | `295E14DC481C6C9F7EEEFAB64C748B50FBE77E15E58595B2A1DCF7C129FCEFE0` | — |

**未改动（哈希与 004A 基线一致）**：`cradle.gd`、`game.gd`、`level_builder.gd`、`freight_arena.gd`、`freight_control.gd`、`player_controller.gd`、`exit_gate.gd` 及全部第二三幕文件。

---

## 九、新增测试与回归

### MECHANICS-004B 专项：**24 / 24 通过**

`tests-out/mech004b_run.log` 末行：`MECH004B_DONE checks=24 passed=24 failures=0`

覆盖任务书第十一节全部 24 项（逐项对应，见日志原文）。

### 第九节附加核实：**3 / 3 通过**

`MECH004B_RELAY_DONE checks=3 passed=3 failures=0`

| 断言 | 实测 |
|---|---|
| F1 晶体真实落进 b1 叉口 | occupied=true |
| F2 锁定后中继成立 | locked=true relay=true aligned=true |
| **F3 晶体被真实外力推出叉口后，中继不再报告成功** | pushed=true inside=false locked=false **aligned=false relay=false**，位移 0.47 m |

**结论**：`aligned` **不是**锁定瞬间缓存的一次性布尔——`_ensure_still_locked()` 每帧检查 `crystal_inside()`，一旦晶体离开叉口就清 `latched` 与 `aligned`。**没有发现需要修复的缓存缺陷**。

### 回归（本轮实跑）

| 回归项 | 结果 |
|---|---|
| MECHANICS-004A 晶体支架 | **18 / 18** |
| MECHANICS-003A 停靠 | **18 / 18** |
| MECHANICS-003A 章节交接 | **7 / 7**（failures=0） |
| 第四幕正式入口 `act4.tscn` | 加载通过，无脚本错误 |
| 第四幕内置 smoke-play | 14 项中 13 过；唯一失败 `mouse_captured` 是无头模式无真实鼠标捕获（环境限制，窗口模式为 true） |
| 第四幕 → 中继连续流程 | E19 通过（同一实例、真实落座、锁爪锁定） |
| 第四幕后续剧情 | E24 通过（货运/中继/出口目标文案保留，stage 回 0，出口门在线） |
| **第四幕 → 第五幕交接** | **19 / 19**（`test_act05_handoff.gd`：L0–L3 全通过，`passed=true`，`failures=0`） |

---

## 十、实际窗口截图（`game/captures/mech004b/`）

全部 1280×720、**玩家第一人称视角**，由真实按键（F/E/W）驱动：

| 文件 | 内容 | 亮度 | 关键状态 |
|---|---|---|---|
| `01_platform_empty.png` | 平台在断层一侧、货台空着 | 0.504 | x=−8.80 dock=near cargo=false |
| `02_place_on_deck.png` | 玩家把晶体搬到货台上方 | 0.357 | carried=true |
| `02b_seated_on_deck.png` | 晶体靠重力落在甲板上 | 0.359 | cargo=true freeze=false |
| `03_clamping.png` | 夹具合拢中：侧挡夹住、压板下压 | 0.341 | side_inner=0.95 press=1.60 |
| `03b_clamped.png` | 夹具已锁定 | 0.380 | **fixed=true** press=1.19 side=0.34 |
| `04_carry_across.png` | **平台承载晶体穿越断层（运输途中）** | 0.412 | x=−9.93 v=−1.13 相对位移=0.010 fixed=true |
| `05_arrived_braked.png` | 平台制动并到达对岸 | 0.440 | **dock=far x=−14.70 v=0.000 arrived=true** |
| `06_pickup_from_deck.png` | 玩家取下同一块晶体 | 0.366 | 夹具已开=true carrying=true |

**未作弊**：没有冻结货物、没有关碰撞、没有传送晶体、没有直接设到站状态、没有直接完成剧情。行驶途中只转视角，不 teleport（teleport 会松开操纵杆，那不是玩家行为）。

> 第四幕正式洞穴较暗：截图进程在货运区临时补一盏灯（仅截图场景，未写入正式关卡）。

---

## 十一、可试玩入口

```
引擎：C:\Users\ASUS\Desktop\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe
工程：C:\Users\ASUS\Desktop\迷失太空\game
场景：res://scenes/act4.tscn
```

试玩路线：出生 → 敲钟 → 记忆回声 → 走到西侧装货台 → F 搬晶体 → 上平台 → F 放下 → 夹具杆 E 固定 → 操纵台 E 握杆 → 按住 W 过断层 → 到岸松杆 → E 开夹具 → F 取晶体 → 装 b1 支架。

---

## 十二、尚存限制（如实声明）

1. **平台不是完整 Jolt 刚体**。它是 `AnimatableBody3D` + 一条显式的 1 自由度运动方程。Jolt 不解算它的惯量，横向/旋转方向由轨道与 tilt 弹簧约束。这是任务书第四节点名允许的“受约束动力学”。
2. **缆绳仍不传递张力**。`_cables` 只做视觉摆位；平台与吊车（`_trolley`）通过 `travel_x` 同步，不是绳索动力学。
3. **夹具是位移驱动的实体机构，不是柔性夹具**。侧挡与压板都是 `StaticBody3D`，靠几何接触约束晶体；没有螺纹/弹簧扭矩求解。
4. **`F_grade = 0`**。轨道是水平吊索，实测吊车与吊点同一 y，没有真实坡度项。
5. **载重差异只有 3 帧**（63 → 66 帧到 1.0 m/s）。16 kg 对 150 kg 平台只占 10.7%，这是真实比例，未人为放大。
6. **双箱工况只验证“放得下且计入 M_eff”**，没有做双箱全程运输实验（正式关卡只要求运一块晶体过断层）。
7. **出口门仍是 Tween 抬升**（004A 已确认，属后续独立候选，本轮未动）。
8. **联机未验证**。`snapshot()`/`apply_net_state()` 已同步新增的 `jaw_locked`/`press_y`/`chock` 字段，但网络专项仍暂停。
9. **真人手感验收未做**。

---

## 十三、安全回退

**备份**：`work/mechanics004b-r1/accepted_mechanics004a/`（54 个文件，含 `.gdignore` 防止 Godot 扫描）

已核实备份内容确为 **004A 状态**（不含 004B 标记，`TRAVEL_SPEED_EMPTY` 与 `CapsuleShape3D` 都在）。

**回退脚本**：`work/mechanics004b-r1/rollback_to_004a.ps1`

```
pwsh -File work/mechanics004b-r1/rollback_to_004a.ps1
```

脚本会：恢复 `freight_platform.gd` / `portable_crystal.gd` 到 004A、删除 004B 专项与截图、打印恢复后的哈希供比对。

**Git 状态**：`game/scripts/act4/`、`game/act1/`、`game/act23/` 均**未纳入 Git 跟踪**（`git ls-files` 计数 0，`.gitignore` 未匹配到它们）。本轮未改 `.gitignore`、未提交、未推送。

---

## 十四、结论：**GO（技术）**

| # | 验收标准 | 结果 |
|---|---|---|
| 1 | 货运平台原有结构已核实 | ✅ 第一节 20 项审计表 |
| 2 | 实际存在需要物理化的核心缺口 | ✅ 动力学/承载/夹具三项皆伪机械，且晶体圆底不能站立 |
| 3 | 对应机械已在正式第四幕改造完成 | ✅ `freight_platform.gd` 在 `act4.tscn` 里真实构建 |
| 4 | 平台运动来自实际动力学或合理受约束动力学 | ✅ 力积分，实测 63 帧到 1.0 m/s、松 W 滑行 1.187 m |
| 5 | 驱动与制动具有明确上限 | ✅ `F_DRIVE_MAX=620`（峰值 425.6）、`F_BRAKE_MAX=1150` |
| 6 | 晶体运输过程不依赖传送 | ✅ `_tick_cargo` 不写 transform；同一实例 E19 |
| 7 | 货物通过真实接触或受力约束保持在平台上 | ✅ 甲板摩擦 + 4 侧挡 + 压板，全部 Jolt 接触 |
| 8 | 载重对运动具有合理影响 | ✅ 150→166 kg，63→66 帧 |
| 9 | 夹具具有实际机械作用 | ✅ A 0.8034 m vs B 0.0571 m（7.1%） |
| 10 | 受阻、松脱、误操作与复位合理 | ✅ E16 越界 0、E21 复位正确、五次异常稳定 |
| 11 | 玩家可通过正常控制完成跨断层运输 | ✅ 截图 01–06 全真实按键，dock=far |
| 12 | 004A 真实晶体支架无回归 | ✅ 18/18 + 附加 3/3 |
| 13 | 新增专项全部通过 | ✅ 24/24 |
| 14 | 货运平台到晶体中继的连续流程通过 | ✅ E19/E20 |
| 15 | 后续剧情没有退化 | ✅ E24 |
| 16 | 真实图形窗口可以试玩 | ✅ 8 张 1280×720 真实窗口截图 |
| 17 | 有可靠安全回退方法 | ✅ 54 文件备份 + 一键回退脚本 |
| 18 | 不虚报完整刚体、绳索或联机能力 | ✅ 第十二节 1–3、8 |

**最高原则复核**：晶体是被玩家 F 搬上货台的，平台是靠受力积分真的把它载过断层的（相对滑移 0.057 m），玩家又把**同一块晶体**取下来装进了 004A 支架、锁爪夹住、中继成立。机械操作改变真实世界，剧情只确认已经发生的结果。**GO。**

---

## 十五、本轮之后的状态

按任务书要求，**完成后立即停止**：未开始出口门物理化，未开始第五幕研发，网络专项仍暂停。
