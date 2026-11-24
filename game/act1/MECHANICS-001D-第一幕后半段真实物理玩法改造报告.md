# MECHANICS-001D 共振星第一幕后半段真实物理玩法改造报告

> 工程：`game/`　Godot 4.7.2.stable + Jolt Physics，60 Hz　日期：2026-11-04
> 结论：**GO**（技术验收）。departure 的**车轮止轮楔**已从"按 E 隐藏网格"改为真实刚体拖出。

---

## 一、hazard / departure 交互审计

数据来源：`game/act1/scripts/act1_app.gd::_execute_interaction`、`act1_wind_crate.gd`、
`act1_station_builder.gd` 中的交互点与道具。

### hazard 阶段
| 交互 id | E 实际做什么 | 真实程度 |
|---|---|---|
| `secure_crate` | `flags.crate_secured=true` + `crate.set_secured(true)` | **基本真实**：仪器箱是 `CharacterBody3D`，平时由**真实风场**推动、会滑出栈桥坠落；固定后 `velocity=0` 并出现固定带。属于"拉紧固定带"的合理简化，本轮不动 |
| `self_rescue` / `rescue_winch` | `_climb_pid(...)` 沿脚本路径把玩家搬到栈桥 | **玩家位移动画**，不是机械；属于救援演出，本轮不动 |
| `grab_*`（扶手） | 抓住/松开，风场中保持 | 真实（抓握状态参与风场加速计算） |

### departure 阶段
| 交互 id | 改造前 | 真实程度 |
|---|---|---|
| `chock`（车轮止轮楔） | `flags.chock_removed=true` + `_hide_chock()` **把网格隐藏** | ❌ **纯视觉假动作**，无碰撞、无物理 → **本轮选中改造** |
| `parking_brake`（停车制动） | 仅 `flags.brake_released=true` | ❌ 纯 flag（无闸把/制动器实体） |
| `cargo`（货舱固定带） | 仅 `flags.cargo_secured=true` | ❌ 纯 flag（无带子/张紧机构） |
| `launch_cart`（发车联锁） | 读 6 个条件后 `mine.begin_departure()` | 条件里有真实项（`vent_complete` 来自真实风机），也有 flag 项 |

**选择依据**：`chock` 是三者中最具物理意义、且改动面最小的一项——它是唯一**曾经有实体网格却被直接隐藏**的物体，
且"楔块是否还在轮下"天然就是一个**位置判定**，最适合改成真实刚体。`parking_brake`/`cargo` 没有现成实体，
本轮不凭空新增机构（按任务要求，不为凑任务量而改造）。

---

## 二、改造前后对比

| 项目 | 改造前 | 改造后 |
|---|---|---|
| 视觉 | `kit.box("WheelChockVisual", ...)` 无碰撞网格 | 移除该网格，改为 `RigidBody3D` 楔块（含斜面板视觉） |
| E 的作用 | 直接 `visible=false` + 置 flag | 启动**拖出执行器**：0.85 s 内施加 300 N 沿 −Z |
| 移走判定 | flag（瞬间） | 刚体沿 −Z 位移 **≥0.30 m** 才算移走 |
| 任务状态 | E 直接置位 | `_sync_wheel_chock()` 每帧从刚体位置同步到 `flags.chock_removed` |
| 阻挡 | 无（网格不存在于物理世界） | 轮肩（静态，压在上方）+ 背挡（静态，+Z 侧）→ 楔块不能陷入轮下、不能穿透 |

---

## 三、真实机械结构与物理原理

新组件 `game/act1/scripts/machines/act1_wheel_chock.gd`（`class_name Act1WheelChock`），
**不用关节**（沿用 001B/001C 结论：力 + 静态止挡 + 实体碰撞最稳）。

| 项 | 值 |
|---|---|
| 楔块刚体 | `RigidBody3D` 14 kg，0.55×0.34×0.85，`can_sleep=false`，linear_damp 1.6，angular_damp 2.2 |
| 轮肩（静态） | 0.80×0.34×1.10，位于楔块上方 0.62 m 处 → 表现为"压在轮下" |
| 背挡（静态） | 0.70×0.40×0.14，位于 +Z 0.42 m → 楔块不能被推得更深 |
| 执行器 | E 后 0.85 s 内施加 **300 N** 沿 −Z（> 14 kg×g ≈ 137 N） |
| 判定 | `(_home.z − 当前位置.z) ≥ 0.30 m` |
| 复位 | `reset_chock()` 把刚体放回原位、清零速度 |

**为什么沿 −Z**：玩家从 +Z/+X 侧走近操作（实测站在 z≈−45.5），若沿 +X 拖出会**把楔块推进玩家身体**而被挡住
（第一次实现在第一幕流程里就是这么失败的：`AIM cargo` 提示"需先移走止轮楔"）。改成沿 −Z 与站台平行拖出，
既避开玩家，也符合"从轮下横向抽出"的机械直觉。

---

## 四、玩家实际操作步骤

1. 完成通风后进入发车平台（阶段④「准备矿车并发车」）；
2. 走到车轮止轮楔（交互点 `−5.62, 0.98, −46.55`）按 **E**：拖出执行器开始工作；
3. 看到楔块从轮下被抽出、HUD 弹出「止轮楔已拖出 · 车轮仍被机械制动锁住」；
4. 再按 E 释放停车制动、拉紧货舱固定带、全员登车 → 发车联锁。

---

## 五、任务状态与物理状态关系

```
楔块刚体位置 ──(_home.z − z ≥ 0.30 m)──→ _sync_wheel_chock() ──→ flags.chock_removed
                                                                      │
                                    parking_brake / cargo 的前置条件 ──┤
                                                                      ↓
                                            _launch_conditions_ok() → launch_cart
```
通风未完成时按 E 会被剧情联锁拒绝（`_refuse(... 通风未恢复，站台仍被联锁)`），与改造前一致。

---

## 六、新增与修改文件清单

```
game/act1/scripts/machines/act1_wheel_chock.gd   新增：14 kg 止轮楔刚体 + 轮肩/背挡 + 拖出执行器
game/act1/scripts/world/act1_station_builder.gd  删除无碰撞的 WheelChockVisual；
                                                 新增 var wheel_chock 与构建；
                                                 chock 交互点抬高到 (−5.62,0.98,−46.55) 以避开新实体遮挡射线
game/act1/scripts/act1_app.gd                    chock 处理改为启动执行器；
                                                 新增 _sync_wheel_chock() 每帧由位置同步状态
game/act1/tests/mech001d_chock.gd / .tscn        新增 001D 专项 11 项
game/act1/tests/mech001d_capture.gd / .tscn      新增四阶段真实窗口截图（含截图用小范围补光）
```

未改：其他四幕、其他星球、归航号、网络系统、全局物理配置；001A 电源、001B 锁爪、001C 风机联锁的物理与判据。

---

## 七、自主修复的 Bug

1. **楔块被拖到玩家身上**：首版沿 +X 拖出，玩家就站在 +X 侧，第一幕流程里 `chock_removed` 始终不成立 →
   改为沿 −Z 拖出（与站台平行）。
2. **新实体挡住交互射线**：加入轮肩后 `AIM chock target=none prompt=`（玩家瞄不到交互点，因为射线打在实体上）→
   把轮肩高度 0.60 → 0.34（顶面 0.79），交互点从 y=0.35 抬到 **y=0.98**（净空），恢复 `target=chock`。
3. **截图全黑（lum 0.011）**：发车平台本身极暗 → 按任务 §10 允许范围内，在**截图工具里**加两盏临时 `OmniLight3D`
   （不改场景美术），亮度提升到 0.18。

---

## 八、专项与完整流程回归

```
MECHANICS-001D 止轮楔专项     MECH001D_DONE checks=11 failures=0
MECHANICS-001C 通风专项       MECH001C_DONE checks=15 failures=0
MECHANICS-001B-R2 锁爪专项     MECH001B_DONE checks=12 failures=0
MECHANICS-001A 基线专项        MECH001A_DONE failures=0
第一幕 21 项完整流程           RESULT failures=0 completion=true
正式 act01.tscn 加载           通过（上述测试均实例化正式场景）
实际图形窗口                   4 张截图（见 §九）
```

### 001D 11 项明细
```
D1  止轮楔是真实刚体（不是无碰撞网格）      RigidBody3D mass=14 layer=2
D2  初始：楔块在位、任务未完成              removed=false flag=false
D3  通风未完成时拖不动（剧情联锁保留）       位移 0.000 m
D4  按 E 只启动执行器（非瞬移）             按下瞬间 dz=0.040 m，removed=false
D5  楔块被真实拖出（位移达标）              第 8 帧判定，位移 1.431 m
D6  任务状态由刚体位置同步                  chock_removed=true
D7  仅移走止轮楔不足以发车（其它联锁有效）   launch_conditions_ok=false
D8  楔块回原位时不再判定已移走              removed=false
D9  楔块被 +Z 背挡挡住（不穿透/不陷入轮下）  反向推 40 帧位移 0.000 m
D10 重置后回到初始位置                      距原位 0.055 m
D11 连续 3 轮拖出/复位稳定                  3/3，最小位移 0.327 m，末 y=0.16
```
> 说明：001D 专项按任务 §9 允许的方式初始化 `vent_complete` 前置状态；
> **真实任务链路**由第一幕 21 项流程验证（通风压力测试 → 止轮楔 → 制动 → 货物 → 发车）。

---

## 九、实际窗口截图

`game/act1/captures/mech001d/`（真实 GPU 渲染；未关闭碰撞、未预设机械成功状态）：

| 文件 | 内容 |
|---|---|
| `01_before.png` | 操作前：楔块压在轮下，阶段④提示「止轮楔 → 停车制动 → 货舱固定带 → 全员登车 → 发车联锁」 |
| `02_pulling.png` | 操作中：执行器拖出楔块（HUD「止轮楔已拖出 · 车轮仍被机械制动锁住」） |
| `03_removed.png` | 物理条件满足：楔块脱离轮下，画面可见矿车与车轮 |
| `04_interlock_ready.png` | 任务链路就绪：止轮楔已移走 / 制动已释放 / 货物已固定 |

（截图内 `launch_ok=false` 是因为截图场景里没有玩家登车，`all_active_aboard()` 不满足——这是发车的第 4 个真实条件，不是缺陷。）

---

## 十、可试玩入口

`godot --path game` → 第一幕 → 完成电源（001B）→ 通风（001C）→ 发车平台：
止轮楔 `(−5.62, 0.98, −46.55)`、停车制动、货舱固定带、矿车。

---

## 十一、尚存限制

1. **停车制动与货舱固定带仍是 flag**（没有实体闸把/带子）。审计表里已列明，属下一轮候选，本轮按"只改一项"未动。
2. 楔块拖出后沿 −Z 滑出约 1.4 m 才停（地面摩擦低），视觉上会滑到旁边；未加回收槽。
3. 截图取景仍偏暗（发车平台本身黑），HUD 证据清楚但机构在画面中不占主体。
4. 创建者真人手感验收未做。
5. 001B 遗留的电源模块峰值 5.53 m/s、001C 通风区偏暗等已知问题按任务要求未处理。

---

## 十二、安全回退

```
accepted_mechanics001d/   本轮交付版本（10 个文件）+ SHA256.txt + .gdignore
accepted_mechanics001c/   MECHANICS-001C 已验收版本
accepted_mechanics001b_r2/ MECHANICS-001B-R2 已验收版本
backup_mechanics001b/      001A 基线
```
回退到 001C：把 `accepted_mechanics001c/` 的 `act1_app.gd`、`act1_station_builder.gd`、
`act1_fan_interlock.gd`、`act1_ventilation.gd`、`act1_power_cart.gd` 复制回 `game/act1/scripts/`，
并删除本轮新增的 `act1_wheel_chock.gd`。

SHA-256（关键项）：
```
act1_app.gd              4B36C8678FD43CE682A68F0458E0223018CE5F4C5CDFA001DFF43676071A0F00
act1_station_builder.gd  7D5017780ECAA9771BF31D0523593851092FDE48399C7B861B3D477ED9C28A24
act1_wheel_chock.gd      A58818EA7E5C26A77E784FA81C567BB57FD5864399F1ED2FFCAF2809F8855C4D
mech001d_chock.gd        9EEED52EB4C5165E196986CFFC774D2CD2CB2089681A87496EAFF6C48FC705DF
mech001d_capture.gd      9606915C622BEC47E4944A03ED01B79CF97597EF4A5427464644DC595606A288
```

---

## 十三、结论：**GO**

1 ✅ 审计了 hazard 与 departure 全部交互（§一 表格，逐项标注真实/伪）
2 ✅ 选中 `chock`（唯一"有网格却被直接隐藏"的伪交互）
3 ✅ 保留原剧情与关卡目标（阶段④顺序、拒绝提示均未变）
4 ✅ 玩家用正常控制（走到位置 + E）即可完成
5 ✅ 楔块是 14 kg 刚体，由 300 N 执行器真实拖出 1.4 m
6 ✅ E 不再直接制造结果（按下瞬间仅移动 0.04 m，未判定移走）
7 ✅ 任务成功由刚体位置（≥0.30 m）决定
8 ✅ 误操作不会永久卡关（复位后可重试，D8/D10/D11）
9 ✅ 001D 专项 11/11
10 ✅ 001A 5/5、001B 12/12、001C 15/15 无回归
11 ✅ 第一幕 21 项完整流程通过（`completion=true`）
12 ✅ 真实图形窗口可运行并出 4 张截图
13 ✅ 有备份与 SHA-256、明确回退路径
14 ✅ 未修改其他四幕与非授权区域
