# MECHANICS-001F 共振星第一幕真实货舱固定带与载重约束最终报告

> 工程：`game/`（`C:\Users\ASUS\Desktop\迷失太空\game`）　Godot 4.7.2.stable + Jolt，60 Hz　日期：2026-11-05
> 结论：**GO**（含 8 条如实声明的边界，见第十一节）
> 范围：只改造第一幕 departure 阶段的货舱固定带；未触碰其他四幕、其他星球、归航号与核心网络架构；网络专项继续暂停。

---

## 一、开工前补齐的 001E 有限验证（双向制动）

不另开 R4，直接在既有 `mech001e_brake.gd` 上追加 E13–E19，全部在正式 `act01.tscn` 内执行，
**关掉组件自带的演示力矩（`drive_torque=0`）**，只施加测试力矩，方向 +12 N·m 与 −12 N·m 各自从
`reset_brake()` 的同一初始条件开始。

### 1.1 三态实测（累积角位移 / 角速度 / 销爪行程 / 实际接触）

| 方向 | 状态 | 累积角位移 | 末角速度 | 销爪行程 | 实际接触 |
|---|---|---|---|---|---|
| +12 N·m | 锁止 | **0.4533 rad** | **0.000 rad/s** | −0.0025 m | BrakeDrum + 两导槽 |
| +12 N·m | 解除 | 0.950 rad | 10.297 rad/s（第 12 帧脱开） | −0.2750 m | — |
| +12 N·m | 重新锁止 | 1.392 rad | **0.000 rad/s**（第 5 帧重锁） | +0.0015 m | BrakeDrum + 下导槽 |
| −12 N·m | 锁止 | **0.4605 rad** | **0.000 rad/s** | −0.0006 m | BrakeDrum + **PinInStop** |
| −12 N·m | 解除 | 0.949 rad | 10.290 rad/s（第 12 帧脱开） | −0.2750 m | — |
| −12 N·m | 重新锁止 | 1.390 rad | **0.000 rad/s**（第 5 帧重锁） | +0.0015 m | BrakeDrum + 上导槽 + **PinInStop** |

**双向都能被齿圈—销爪几何挡住**：两个方向的锁止段角位移都只有 ~0.45 rad（一个齿距内的齿隙），
随后角速度收敛到 **0.000**，不是"只把 27.9 降到 6.08"。

### 1.2 负载下持续稳定

锁止状态连续施加 12 N·m 达 240 帧（4 s），末角速度 **0.000 rad/s**，累积角位移 **< 1.60 rad**
（阈值取一个齿距）。判定条件写在测试里：`ω_end < 0.35 且 cum < 1.60`。

### 1.3 R2 台架 0.021 m 越位的处理（用最终结构解决，不虚报旧台架）

R3 当时的做法是"入位即停 + **清速度**"。本轮把这套做法**删除**，改成真正的机械边界：

* 新增 **`PinInStop`** 支承座（静态实体，5×12×9 cm），销爪的**肩部**正面顶在它上面；
* 支承座刻意放在**齿圈平面之外**（z 0.075–0.165），与鼓体（z ±0.05）和鼓齿（z ±0.05）都不接触，
  所以不会像"塞进齿圈内侧"那样把鼓卡死（该坑本轮实测踩到过：塞进去之后鼓永远转不动）；
* 销爪改为**棱柱副**（三个转动自由度锁死 + 两片导槽限制 y/z），否则鼓齿的切向冲量会把销爪拧歪。

结果：重锁后行程停在 **+0.0015 m**（旧机制可被推入 0.021–0.067 m），且 `PinInStop` 真的进入接触表。
R2 旧台架（`wip_mechanics001e_r2/mech001e_r2_bench.gd`）对应的是**旧结构**，本轮不再重跑，
标记为**历史测试**；其等价断言（越位 ≤ 0.005 m、实体止挡承载）已由正式场景 E13–E15/E19 取代。

### 1.4 "入位即停并清速度"的代码审计

`mech001e_brake.gd` 的 E19 直接读脚本源码做审计（不是空话）：

```
AUDIT .../act1_parking_brake_r2.gd：运行路径 437 字符；直接写速度 = 0 次；
      限力执行器 apply_central_force = 1 次；伸入端止挡 PinInStop = 1 次
```

审计范围是 `_physics_process … reset_brake` 之间的**运行路径**：其中没有任何
`linear_velocity =` / `angular_velocity =` 赋值；复位函数里清速度仍然保留（安全规范允许）。

**001E 专项：25/25 通过（原 12 项全部保留，新增 13 项）。**

---

## 二、原有货舱与货物结构审计（先核实，再设计）

| # | 审计项 | 改造前的真实情况 |
|---|---|---|
| 1 | `cargo` 按 E 执行什么 | `act1_app.gd` 里 `flags["cargo_secured"] = true` + 一条 HUD 提示；**没有任何机械** |
| 2 | `cargo_secured` 如何影响发车 | `_launch_conditions_ok()` 直接读这个布尔值；`mine_cart._launch_prompt()` 同 |
| 3 | 货物是什么节点类型 | **不存在货物**。只有 `act1_station_builder.gd` 里两个装饰网格：`CargoStrapBox`（0.75×0.65×0.55）与 `CargoStrap`（0.10×0.10×2.0 的细条） |
| 4 | 是否有质量/碰撞 | **都没有**。`kit.box()` 是纯视觉几何，`_hazard`/`_paint` 材质，无 CollisionShape |
| 5 | 是否跟随矿车 | 不跟随。网格固定在站台世界坐标 (6.4, 1.85, −43.9)，而矿车在 (0,0,−47) 且会开走 |
| 6 | 矿车货台有无真实碰撞 | 有。`Act1MineCartRig._build_collision()`：DeckFloor 9.0×0.22×9.2（台面 y=1.51）等 5 块 |
| 7 | 货物与货台之间有无接触 | **没有**（货物不在车上，也没有碰撞体） |
| 8 | 现有固定带是否只是装饰 | 是。一根悬空细条，唯一作用是给交互点做视觉参照 |
| 9 | 矿车加速度/最大速度 | `MAX_SPEED = 6.4 m/s`，`ACCEL = 1.55 m/s²`，`AnimatableBody3D` 逐帧 `global_position.z -= speed*dt` |
| 10 | 未固定/固定的实际差别 | **没有差别**：两者物理上都不存在 |
| 11 | 玩家能否靠近 | 能。原交互点在站台面上 (6.4, 2.05, −43.9) |
| 12 | 复位与登车 | `_reset_state()` 复位门/推车/风机/仪器箱/矿车；登车靠 `is_player_aboard()` + `attach_to()` 跟随 |

**关键结论：矿车是 `Act1MineCartRig extends AnimatableBody3D` 的剧情运输体，不是真实刚体车辆。
改造前车上根本没有"货物"，所以本轮不是"把装饰换成物理"，而是**新建**一套货物—锚点—带—张紧机构。**

---

## 三、固定带与张紧机构的实际结构

新增文件 `game/act1/scripts/machines/act1_cargo_rig.gd`（`Act1CargoRig`），整组机构挂在**矿车**上
（锚点随车运动）；货物是**独立的世界级刚体**（不是矿车子节点）。

```
矿车局部坐标（矿车原地 (0,0,−47)，台面 y=1.51）
  货箱刚体 CargoCrate   100 kg  0.90×0.80×0.90  中心 (2.55, 1.907, −0.20)
  卷筒/棘轮 DRUM_ANCHOR  (3.95, 1.62, −0.20)   ← 玩家从这里摇
  挂钩 A  HOOK_A         (1.50, 1.60,  0.66)
  挂钩 B  HOOK_B         (1.50, 1.60, −1.06)
  带 1：卷筒 → 顶角 SE(3.00,2.31,−0.65) → 顶角 NW(2.10,2.31,0.25) → 挂钩 A     （对角交叉）
  带 2：卷筒 → 顶角 NE(3.00,2.31, 0.25) → 顶角 SW(2.10,2.31,−0.65) → 挂钩 B    （对角交叉）
```

* **棘轮卷筒 + 棘爪 + 释放锁扣**：8 齿卷筒，手柄行程 1.35 rad / 0.55 s，每档卷绕 0.020 m，
  共 8 档；棘爪在行程结束后 0.12 s 内落入齿槽（`pawl_depth→1`）。
* **释放锁扣**是**独立交互点** `cargo_latch`（棘轮侧面手柄），不是"再按一次 E"。
  打开后卷筒在张力下回卷（0.10 m/s）到底，再放出 0.45 m 带尾，带子真正松脱。
* **可见带体**：每条带 3 段 × 3 子段，用二次贝塞尔中点下垂表现松弛；张力越大越直。
  松弛量 0.10 m 起步，玩家能看到"松垮下垂 → 逐步拉直 → 绷紧"的连续变化。
* **货舱作业灯**：车厢内部原本只有车顶灯，带体细节看不清；装在卷筒旁的实体灯罩 + 2.1 能量
  点光（不是悬浮文字提示）。

### 3.1 玩家操作步骤（真实链路）

```
走到发车站台边（x≈5.9–6.2）
→ 移走车轮止轮楔（E，001D 机构）
→ 释放停车制动（E，001E 机构，销爪真实退出齿圈）
→ 对着货舱棘轮按 E：每一档  棘轮手柄转动 → 卷筒转角 +0.785 rad → 卷绕 +0.020 m
→ 第 6 档 张力 600 N（不足）→ 第 7 档 张力 1200 N（≥700 N 阈值）→ 棘爪落位
→ HUD：货舱固定带达到工作张力 1200 N · 棘爪落位 · 发车联锁该项完成
→ 绕开 100 kg 货箱登车 → 发车联锁 → 原有剧情发车
```

`E` 只做两件事：启动一个棘轮行程；提供一个 0.020 m 的卷绕量。**`cargo_secured` 完全不看按了几次 E。**

---

## 四、张力模型与机械约束原理

每条带是一条**只能受拉**的弹性索：

```
L   = |A→P1| + |P1→P2| + |P2→H|          （A=卷筒锚点，P=货箱顶角，H=挂钩；全部实时世界坐标）
R   = L0 + SLACK + payout − take_up        （L0=初始几何长度，SLACK=0.10 m，take_up=clicks×0.020）
T   = clamp( k·max(0, L−R) + c·max(0, dL/dt), 0, MAX_TENSION )
      k = 30 000 N/m（≈50 mm 聚酯带量级），c = 900 N·s/m，MAX_TENSION = 2 600 N
```

受力施加方式（**没有一处直接设置货物位置或速度**）：

```gdscript
crate.apply_force(T·û(P1→A) + T·û(P1→P2), P1 − crate.global_position)
crate.apply_force(T·û(P2→P1) + T·û(P2→H), P2 − crate.global_position)
```

* `max(0, …)` 保证**只受拉**：松弛段张力恒为 0，不存在"刚性杆把货物推走"。
* 力作用在**真实接触点**（货箱顶角）上，因此同时产生力矩 → 货物被压向台面、被限制转动。
* 锚点是随矿车运动的实体硬件，所以矿车加速时带长变化 → 张力变化 → 力真的传到货物上。
* `MAX_TENSION` 是额定上限：超载时张力被限制（视为屈服），数值不发散，也不做撕裂特效。

**发车联锁的唯一真值来源**（`Act1CargoRig.secured()`）：

```
货物在货台有效区域（水平 <0.55 m、竖向在台面上 0.25–1.10 m、未倾倒 up·Y>0.72）
且 锁扣未打开 且 棘爪落位（pawl_depth>0.95） 且 至少 1 档卷绕
且 两条带张力都 ≥ 700 N
```

`act1_app._sync_cargo()` 每帧把它同步成 `flags["cargo_secured"]`：**涨上去**发提示，
**掉下来**（松脱 / 货物被推走 / 锁扣打开）立刻恢复 false。剧情发车之后掉下来不刹停矿车，
只报警并把状态如实回退（详见第六节）。

---

## 五、固定前 / 固定后 / 解除后的受力数据（同质量、同起点、同受力）

统一工况：同一 `CargoCrate`、同一起点（货台坐标 (2.55, 1.91, −0.20)）、同一外力
**600 N 沿 −Z 推 60 帧（1.0 s）**。数据由 `mech001f_cargo.gd` 的 `EVID` 行打印。

| 组 | 状态 | 位移 | 峰值速度 | 张力 | 锚点 | 棘轮状态 | cargo_secured |
|---|---|---|---|---|---|---|---|
| **A** | 未固定（带松弛 0.10 m） | **0.2807 m** | 1.017 m/s | 111 N（货物滑到带子绷直后才有） | (3.95,1.62,−47.20) | clicks=0, pawl=1.00, latch=false | **false** |
| **B** | 真实张紧固定（1200 N） | **0.0130 m** | 0.054 m/s | 1060.8 N | 同上 | clicks=7, pawl=1.00, latch=false | **true** |
| **C** | 真实解除（锁扣打开、放出 0.45 m） | **1.8306 m** | 3.537 m/s | 2600 N（带子被拉到头，达到额定上限） | 同上 | clicks=0, pawl=0.00, latch=true | **false** |

* A/B 对比：**位移 0.281 → 0.013 m，减少 21.6 倍**；速度 1.02 → 0.05 m/s。
* C 相对 B：**位移 0.013 → 1.831 m，恢复 141 倍**，货物真正重新自由。
* 带子本身在 A 组里也如实起作用：货物滑出 0.10 m 松弛量后，张力从 0 涨到 111 N
  ——这正是"张力随相对运动变化"，不是脚本给的假约束。

### 5.1 其他方向与工况

| 工况 | 数据 |
|---|---|
| 横向 / 竖向扰动 | 由 4 点交叉锚点覆盖（货箱顶四角全部受拉）：`F7` 施加 800 N，张力 1200→970 N 真实变化，位移 0.063 m |
| **正常矿车起步**（0→6.4 m/s，1.55 m/s²） | `F14`：矿车速度 4.65 m/s 时，货物相对货台**最大漂移 0.035 m**，末位移 0.035 m，仍在有效区域，`secured=true` |
| **更高但合理的载荷**（6000 N） | `F15`：张力被限制在 **2600 N**（额定），货物滑到 (2.99,1.91,−3.95) 仍在货台，`cargo_secured` 自动回退成 false，无数值发散 |
| **不同质量的货物** | `F21`：60 kg → 0.0381 m；100 kg → 0.0130 m；160 kg → 0.0000 m（张力 991/1061/1200 N，全部 secured=true）。**质量真的进入结果**：越重越难被推动 |
| 护栏是否会"替我固定" | 货箱中心距矿车东侧壁 2.2 m、前后舱壁 4.3 m，**都碰不到**；`crate_in_zone()` 允许 0.55 m，B 组实测只走 0.013 m。不存在"被护栏挡住却算成固定带功劳"的情况 |

---

## 六、货舱固定状态与发车联锁的对应关系

```
通风恢复 → 止轮楔移走 → 停车制动销爪退出（brake_released）
        → 固定带张力 ≥700 N + 棘爪落位 + 锁扣闭合 + 货物在区域（cargo_secured）
        → 全员登车 → 发车联锁 → 原有剧情发车
```

* `_launch_conditions_ok()` 保持原样读 `flags["cargo_secured"]`，但这个 flag 现在**只由**
  `Act1CargoRig.secured()` 写入（`_sync_cargo()`）。E 按多少次都不影响它。
* **张力不足**（600 N < 700 N）：`F11` 实测 `_launch_conditions_ok()=false`，拒绝语
  「发车联锁：货舱固定带未拉紧」。
* **货物偏位**（被推到 z+1.25）：`F12` 实测 `crate_in_zone()=false`、`pump()` 直接拒绝、
  `secured()=false`，不会隔空固定。
* **发车后的异常**：`departure_started` 为真时若带子松脱，`_sync_cargo()` 置
  `cargo_lost_in_transit=true` 并提示「货舱固定带在行驶中松脱 · 货物失去约束（矿车继续前进）」，
  **不无条件刹停正在行驶的矿车**，也不回退已完成标记——这是本轮明确的设计选择，
  理由是矿车是剧情运输体，半路急停会打断既有桥段。

---

## 七、矿车是运动学剧情体：边界与实测

* 锚点随矿车运动（`F2`：矿车后退 1.5 m，锚点世界坐标同步 −1.5 m），但**带子的反作用不会改变矿车轨迹**
  ——矿车仍是 `AnimatableBody3D`，不是刚体车辆。这一点在本报告里明确声明，不虚报。
* **最小复现（接触与承载）**：新建一块 `AnimatableBody3D` 货台（layer 16，mask 0，与矿车同一做法）
  + 一个 100 kg 刚体货箱，货台以 1.55 m/s² 加速到 6.4 m/s 平移 240 帧：
  `sync_to_physics=false` 与 `true` 两种设置下，货箱相对货台漂移都只有 **0.003 m**。
  结论：Jolt 会按运动学体的位移给接触算速度，**不需要**给矿车加"隐藏父子吸附"，
  也不需要每帧同步货物位置。测试输出见 `work/…/logs/`（该复现场景已在交付前删除）。
* **玩家推不动货物**：如果货箱 `collision_mask` 含玩家层，角色行走会把 100 kg 货箱推走 **6.9 m**
  （实测）。最终取货箱 layer=4 / mask=1|4|16：角色被货箱真实挡住（停在 0.90 m），
  货箱纹丝不动。这条是三次对照实验得出的，写进了代码注释。

---

## 八、修改文件清单

```
新增  game/act1/scripts/machines/act1_cargo_rig.gd     0126BB6966D215F26D22904D6CD22CC890223FD86AB57B96088E41636224F5A9
新增  game/act1/tests/mech001f_cargo.gd                8639B07FB05A79983D69950DE85CA2C2612CAA1A044E3AFE77688BB94939F774
新增  game/act1/tests/mech001f_cargo.tscn              C7AAF805A21FB0AE0B1DE815C9D5D8F5328B405664CC538C96D58204150633F5
新增  game/act1/tests/mech001f_capture.gd              A5BDCFDAC4AF8142CC8CCE038E4243CF1E78EB1863885A9CA48D3A7A9AFCC005
新增  game/act1/tests/mech001f_capture.tscn            937CD64084EF911FE6986570593AB77DF575BC69C3E97482C3E276795D6C7029
改动  game/act1/scripts/act1_app.gd                    1234E7B8645D39105B95B0308C692E4512BA6B8A748CAA18A560FB2E6A733EDB
改动  game/act1/scripts/world/act1_station_builder.gd  ABEBDC6549166E084C5E54C22A5EF53F873E8010A7F57EF1BB79B9837366C87C
改动  game/act1/scripts/machines/act1_parking_brake_r2.gd 21D0DBE3CA22C51F3B0AC8FCBB600DAB5B14C66FD1DCD6347B6F44DBFAD5BFC9
改动  game/act1/scripts/machines/act1_wheel_chock.gd   59E622CFB964C5133883962692D9EEF44FE5D7BE3F5F0155BE40E68C10643111
改动  game/act1/tests/mech001e_brake.gd               90C750143EF689F6D9386B035B78A6B306501269770FCAE8B7D90DAC6659ECD3
改动  game/act1/tests/act1_solo_full_run.gd           11D408B0037F3B079D60BDE7AABEFE8202FDC9B969D62890A6341E21D941A4C8
改动  game/act1/tests/act1_autotest.gd                E90B02CF27259C7C8DEE9D0A9A1FDAC78E04592667C3B8139DCA6A5DF0FC8405
改动  game/act1/tests/act1_refusal_feedback_test.gd   0DE962E818F6A33655D0AD7649D671D42C6ABE73484D1ADA2F010D3CD94729B4
改动  game/act1/tests/act1_refusal_attribution.gd     8DDD1397D88F002DB1BDA32A24699BDC4DBB3ACA8403D680911443E945649C23
改动  game/act1/tests/act1_hud_stress.gd              75F8AC94F41C1E81D2B483053978080FAF9A2DFBA02364A0A9B4425AFE2785CC
改动  game/act1/tests/mech001d_capture.gd             5747EA5918A72E484D67BCEEFAFAFDFF712C9C1B7904F87C5236129D993C5004
```

改动要点：

* `act1_station_builder.gd`：删除装饰用 `CargoStrapBox`/`CargoStrap`；新增 `cargo_rig` 并挂到矿车上；
  删掉旧的 `cargo` 交互点（改由货舱组件自己注册两个交互点）。
* `act1_app.gd`：`cargo` 改为"启动棘轮行程"；新增 `cargo_latch`；新增 `_sync_cargo()`；
  `_cargo_prompt` / `_cargo_latch_prompt` 读真实张力与机械状态；复位时 `reset_cargo()`。
* `act1_parking_brake_r2.gd`：新增伸入端实体止挡 + 销爪肩部 + 棱柱副；删除"入位即停 + 清速度"；
  新增 `drive_torque`（供 ±12 N·m 干净测试）与 `pin_contacts()` / `pin_touching_in_stop()`。
* `act1_wheel_chock.gd`：`reset_chock()` 的刚体传送改为在 `_physics_process` 内生效（原因同 Bug #4）。
* 测试：`act1_solo_full_run.gd` / `act1_autotest.gd` / `mech001d_capture.gd` 把"按一次 E"改成
  "摇到真实张力"，并绕开 100 kg 货箱登车；`act1_refusal_*` / `act1_hud_stress` 的货舱站位改到
  矿车货台东侧（新交互点位置）。**所有原有断言均未放宽。**

---

## 九、自主修复的 Bug（复现 → 根因 → 修复 → 回归）

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| 1 | 加了伸入端止挡后，制动鼓**完全不转**（连 E7 都掉到 ω=0） | 止挡块塞在齿圈内侧（半径 ≤0.267 但 x 跨度压到鼓体/齿圈），销爪与止挡互相嵌入把鼓顶死 | 止挡改到**齿圈平面之外**（z 0.075–0.165），销爪加"肩部"碰撞块去顶它 |
| 2 | 重锁时销爪被推进 0.067 m（越过止挡） | 销爪能被鼓齿拧歪（无角约束），歪着就绕过了止挡 | 销爪改棱柱副（锁三个转动自由度）；`reset_brake()` 同时复位姿态 |
| 3 | 高速（27.9 rad/s）下鼓偶尔"穿过"销爪 | 60 Hz 下鼓齿角宽 0.34 rad < 每帧 0.465 rad，旋转穿透是离散求解器的已知极限 | 锁止测量改为"从静止加载"和"≤10 rad/s 下重锁"两个可分辨工况，如实写进限制；加力不再依赖高速碰撞 |
| 4 | `reset_cargo()` 之后货物仍在旧位置，重张紧全部失败（zone=false） | 刚体在物理步外被传送，随后被上一帧的物理状态覆盖 | `reset_cargo()` 置 `_pending_teleport`，在 `_physics_process` 内真正落位 |
| 5 | 玩家走到货舱会把 100 kg 货箱推走 6.9 m，固定带被拉爆 | 货箱 `collision_mask` 含玩家层 → 角色作为运动学体把刚体顶走 | 货箱 layer=4 / mask=1\|4\|16（三次对照实验选定）：角色被挡住，货箱不动 |
| 6 | 收尾截图里"张紧中"的 HUD 是拒绝语 | 截图脚本在按键前没重置前置 flag（主机同步会把 flag 拉回机构真值） | 截图脚本改走真实链路：先真移止轮楔、真解制动，之后只按 E |
| 7 | 测试里"按一次 E → 已固定"全部失效 | 新机制需要 7 档；旧测试按一次就断言 | 5 个测试改为循环按到 `cargo_secured`；**没有删掉或放宽任何断言** |
| 8 | R 复位后止轮楔仍是"已移走" | 001D 写了 `Act1WheelChock.reset_chock()`，但 `_reset_state()` 从来没调用它；且刚体传送在物理步外会被覆盖 | `_reset_state()` 补上 `reset_chock()`，并把传送放进 `_physics_process` |
| 9 | R 复位后停车制动仍是"已释放" | 001E 写了 `reset_brake()`，`_reset_state()` 同样没调用 | `_reset_state()` 补上 `reset_brake()` |

> Bug 8/9 是**既有缺陷**（不是本轮引入），由 `act1_refusal_feedback_test`（31 项）在本轮回归中暴露：
> 修复前 "reset cleared the platform chain" FAIL，修复后 **31/31 通过**。这两条直接影响任务书
> §9.9「R 复位后所有物体和机械恢复初始状态」，因此本轮一并修复并回归。

---

## 十、新增专项与全部既有回归

### 10.1 新增 `mech001f_cargo`（21 项，全部在正式 act01.tscn 内真实执行）

```
F1  货舱实际货物是真实刚体（100 kg / layer 4 / 未冻结 / 不挂在矿车下 / 有碰撞盒）   PASS
F2  固定带锚点是矿车实体硬件，并随矿车运动（+1.5 m 跟随）                          PASS
F3  初始固定带松弛（L=3.546 / R=3.646 / 松弛 0.100 m）、棘轮未张紧、未固定          PASS
F4  按一次 E 不直接置 cargo_secured（瞬间 false，45 帧后仍 false，clicks=1）        PASS
F5  张紧机构真实运动（手柄 1.35 rad / 卷筒 0→0.785 rad / 棘爪 1.00）                PASS
F6  固定带真实产生张力（clicks=7 / 卷绕 0.140 / 伸长 0.0400 m / 张力 1200 N）        PASS
F7  张力随相对运动真实变化并作用在刚体上（1200→970 N，位移 0.063 m）                PASS
F8  A 未固定：600 N×1 s → 位移 0.281 m，峰值 1.02 m/s                              PASS
F9  B 固定：同力 → 位移 0.013 m（A 的 1/21.6）                                      PASS
F10 C 解除：同力 → 位移 1.831 m（B 的 141 倍）                                      PASS
F11 张力不足（600 N < 700 N）不允许发车，拒绝原因=货舱固定带未拉紧                  PASS
F12 货物偏位（z+1.25）不能隔空固定                                                  PASS
F13 机械锁扣真实到位：棘爪 1.00=锁定 / 0.00=释放                                    PASS
F14 正常矿车起步（→4.65 m/s）货物最大漂移 0.035 m，仍在货台                        PASS
F15 过载 6000 N：张力封顶 2600 N、不发散、货物仍在货台、flag 自动回退 false          PASS
F16 R 复位：clicks=0 / 张力 0 / 放出 0 / 锁扣闭合 / 货物回 (2.55,1.91,−0.2)         PASS
F17 连续 5 轮张紧/释放：1199→0 N ×5，无异常                                          PASS
F18 原有发车条件仍有效（止轮楔/制动照旧拦截）                                       PASS
F19 顺序不变：缺止轮楔 clicks=0；缺制动 clicks=0；两者齐备后真实张紧 secured=true    PASS
F20 正式玩家交互：站台 1.40 m 处瞄准到 cargo、提示含"固定带"、按键真的启动行程        PASS
F21 不同质量 60/100/160 kg：0.0381 / 0.0130 / 0.0000 m，全部 secured=true            PASS
MECH001F_DONE checks=21 failures=0
```

关键工况均记录了 `mass / force / displacement / velocity / tension / anchor_position / ratchet_state / cargo_secured`
（`EVID` 行），全部断言真实执行，失败返回非零退出码。

### 10.2 全部既有回归（本轮最终代码，一次性跑完）

```
MECHANICS-001A 电源模块      MECH001A_DONE failures=0
MECHANICS-001B 旋转锁爪      MECH001B_DONE checks=12 failures=0
MECHANICS-001C 通风联锁      MECH001C_DONE checks=15 failures=0
MECHANICS-001D 止轮楔        MECH001D_DONE checks=11 failures=0
MECHANICS-001E 停车制动      MECH001E_DONE checks=25 failures=0   （原 12 + 新增 13）
MECHANICS-001F 货舱固定带    MECH001F_DONE checks=21 failures=0   （F21 加入后复跑 5 次均 21/21）
回归补充：act1_refusal_feedback_test 31/31（本轮修好两条既有复位缺陷后）
第一幕 21 项完整流程 ×3      RESULT failures=0 completion=true （三次全绿）
```

* 完整任务重复 3 次（3/3）。载重/碰撞/张紧/恢复敏感工况重复 5 次（001F 5/5 全绿）。
* 正式 `act01.tscn` 加载：以上每一项都在 `res://act1/act01.tscn` 实例上执行。
* 未开展网络压力/高延迟专项（按任务要求暂停）。

---

## 十一、真实图形窗口截图

`game/act1/captures/mech001f/`（真实 GPU、真实物理时序；01/02/03/05 为**玩家视角**，
04a/04b 为**证据镜头**，已在文件名与注记里标明）：

| 文件 | 内容 | 亮度 |
|---|---|---|
| `01_before.png` | 固定前：货箱在货台上，两条交叉固定带松弛下垂，HUD 步骤④ | 0.210 |
| `02_tensioning.png` | 张紧中：棘轮手柄在行程中，HUD「棘轮转过一齿 · 固定带正在收紧（7/8 齿）」，张力 498 N | 0.257 |
| `03_secured.png` | 固定后：张力 1098 N，HUD「货舱固定带达到工作张力 1098 N · 棘爪落位 · 发车联锁该项完成」 | 0.258 |
| `04a_force_fixed.png` | 证据镜头｜600 N 外推 1 s：位移 0.021 m，张力 932 N | 0.412 |
| `04b_force_released.png` | 证据镜头｜同一 600 N 外推：位移 2.386 m | 0.221 |
| `05_departing.png` | 发车中：矿车 1.6 m/s 驶离，货物相对货台漂移 0.010 m，HUD「发车 · 矿车正在驶向深层矿区」 | 0.336 |

截图走真实链路：先真移走止轮楔（`wheel_chock.pull()` 到 `removed()`）、再真解停车制动
（`parking_brake.release_brake()` 到 `released()`），之后只用 E 摇棘轮。没有直接摆 flag。

---

## 十二、可试玩入口

```
引擎：C:\Users\ASUS\Desktop\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe
工程：C:\Users\ASUS\Desktop\迷失太空\game
场景：res://act1/act01.tscn
操作：WASD 移动 / SHIFT 冲刺 / E 交互 / Q 松手 / R 重置 / ESC 鼠标
```

---

## 十三、尚存限制（如实列出）

1. **矿车仍是 `AnimatableBody3D` 剧情运输体**：固定带对锚点的反作用不会改变矿车轨迹，
   不是整车动力学。本轮只做到"运动学货台 + 真实货物刚体 + 随车锚点 + 真实张力约束"。
2. **棘轮/棘爪是 1 自由度机构仿真**（力矩平衡 + 齿相位几何），不参与 Jolt 刚体求解；
   它真实决定静止长度 R，而 R 通过张力模型真实影响货物——但棘轮本身不是刚体。
3. **旋转穿透**：鼓以 >25 rad/s 转动时，60 Hz 下鼓齿角宽小于每帧转角，可能穿过销爪。
   锁止测量因此取"静止加载"与"≤10 rad/s 重锁"两个可分辨工况。停车制动的实际用法
   （车停住时施加）不在这个极限里。
4. **固定带不模拟布料**：只有受拉弹性索 + 下垂视觉，没有纤维、摩擦滑移、撕裂。
   超载只表现为张力封顶（屈服），不做破坏特效。
5. **联机未同步货物刚体**：网络专项本轮暂停；客户端看到的是主机同步的 `cargo_secured` 标志，
   看不到货箱的连续运动。
6. `crate_in_zone()` 的 0.55 m 容差是经验值：货物滑出 0.55 m 后即使带子还连着也判"脱离有效区域"。
7. 玩家被 100 kg 货箱挡住（不能推开），这是刻意的取舍：否则角色能把货箱顶走 6.9 m。
8. 创建者真人手感验收仍然独立保留，本轮未做。

---

## 十四、安全回退方法

改造前的正式版本（001E-R3）已完整备份，且带 `.gdignore`（不会被 Godot 重复注册）：

```
work/postmid-001/dev/physics_lab/accepted_mechanics001e_r3/
    act1_app.gd / act1_station_builder.gd / act1_parking_brake_r2.gd / act1_mine_cart.gd
    mech001e_brake.gd / act1_solo_full_run.gd / act1_autotest.gd
    act1_refusal_feedback_test.gd / act1_refusal_attribution.gd / act1_hud_stress.gd
    mech001d_chock.gd / SHA256.txt / .gdignore
```

回退到 001E-R3：把上述 `.gd` 复制回 `game/act1/` 对应位置，删除
`game/act1/scripts/machines/act1_cargo_rig.gd`、`game/act1/tests/mech001f_*`，
并删除 `act1_station_builder.gd` 里对 `cargo_rig` 的引用（恢复时用备份文件即可）。
备份 SHA-256 见 `SHA256.txt`；本轮改动后的哈希见第八节。

`game/act1/` 依旧**未被 Git 跟踪**（本轮未改 `.gitignore`、未做任何 Git 破坏性操作、未提交）。

---

## 十五、结论：**GO**

| # | 验收标准 | 结果 |
|---|---|---|
| 1 | 实际货物有真实质量与碰撞 | ✅ 100 kg / layer 4 / BoxShape 0.90×0.80×0.90 / 世界级刚体 |
| 2 | 固定带锚点与受力路径合理 | ✅ 卷筒 + 两挂钩在矿车上，受力点在货箱顶四角 |
| 3 | 玩家可实际操作张紧机构 | ✅ 7 档棘轮，手柄/卷筒/棘爪真实运动（F5/F20） |
| 4 | 张力真实影响货物运动 | ✅ 1200 N 真实张力，`apply_force` 作用在刚体上（F6/F7） |
| 5 | 固定前/后/释放后结果明确不同 | ✅ 0.281 / 0.013 / 1.831 m（F8/F9/F10） |
| 6 | 正常发车下货物保持稳定 | ✅ 0→6.4 m/s，漂移 0.035 m（F14），截图漂移 0.010 m |
| 7 | 固定状态由真实机械决定 | ✅ `secured()` = 区域 + 棘爪 + 锁扣 + 双带张力 |
| 8 | E 不直接完成固定 | ✅ F4（按一次 E 只加 1 档，flag 仍 false） |
| 9 | 误操作/解除/复位可处理 | ✅ F11/F12/F13/F16/F17 |
| 10 | 原有发车联锁不退化 | ✅ F18/F19 + 21 项流程 ×3 |
| 11 | 新增专项全部通过 | ✅ 21/21 |
| 12 | 001A–001E 全部通过 | ✅ 0 / 12 / 15 / 11 / 25 |
| 13 | 第一幕 21 项完整流程 | ✅ 3/3 failures=0 completion=true |
| 14 | 实际图形窗口正常运行 | ✅ 6 张（4 张玩家视角 + 2 张已标记的证据镜头） |
| 15 | 有安全回退方案 | ✅ accepted_mechanics001e_r3 + SHA256 |
| 16 | 不虚报矿车已成为真实动力学车辆 | ✅ 第十三节第 1 条明确声明 |
| 附 | 001E 双向 ±12 N·m 三态 | ✅ 第四节全部数据，锁止后 ω=0.000 |
| 附 | 0.021 m 越位问题 | ✅ 由 `PinInStop` 实体止挡解决（+0.0015 m），旧台架标记为历史测试 |
| 附 | "入位即停清速度"审计 | ✅ 运行路径写速度 0 次，改由限力执行器 + 实体止挡 |

**最高原则复核**：固定带不是画在货物表面的一条线——它由两点锚点、真实刚体货物、交叉带体、
可测张力、机械锁扣组成，张力由几何伸长量算出并**以力的形式**施加到货物刚体上，
玩家必须真的把棘轮摇到工作张力，`cargo_secured` 才成立。**GO。**

