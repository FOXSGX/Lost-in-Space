# MECHANICS-001A 共振星第一幕首个真实物理任务改造最终报告

> 工程：`game/`（正式游戏工程，与 `work/postmid-001/dev/` 是两个独立 Godot 工程）
> 引擎：Godot 4.7.2 / Jolt　日期：2026-11-04
> 结论：**技术 CONDITIONAL GO（自动化通过）／视觉与真人验收未完成**

---

## 1. 选择改造的任务：第一幕 power 阶段「电源模块就位」

### 1.1 原第一幕的真实结构（读自 `game/act1/`）

四阶段状态机 `entry → power → vent → hazard → departure`（`act1_app.gd:27`）：

| 阶段 | 交互 | 改造前的完成方式 |
|---|---|---|
| entry | `shove_gantry` | **已经是物理**：E 施加真实冲量（`act1_app.gd:590`），`debris_cleared` 由门架**实际位置**判定 |
| entry | `rail_shove` | 已经是物理：冲量 + 障碍位置判定 |
| **power** | `power_winch` → `transfer_module()` | **纯动画**：Tween 在 2.1 s 内把模块位置从车面插值到插座，回调直接置 `module_transferred_flag` |
| power | `power_clamp` | E 直接置 `power_clamped = true`（前置仅检查上面的 flag） |
| vent | 转子锁 / 联轴器 / 风机 / 调压器 | 已有物理或真实状态判定 |
| hazard | `wind_crate` | 已经是物理：被风吹落，按**真实高度**判定 |

**为什么选它**：它是第一幕里**唯一还完全靠 Tween 完成**的核心交互，前后流程（门已开→模块就位→机械夹→通电→通风）完整、判据清晰，且不需要新增剧情或改动任务顺序。entry 阶段已经是物理，不需要重复改造。

### 1.2 改造前后对比

| | 改造前 | 改造后 |
|---|---|---|
| 模块 | 推车上的 `Node3D` 载荷，无质量 | **`RigidBody3D`，60 kg**，有碰撞层与摩擦材质 |
| 移动方式 | Tween 沿直线插值「飞」到插座 | **沿实体导轨被真实绞盘力牵引**（`apply_central_force`） |
| 路径 | 空中直线 | 1.5 m 宽静态导轨 + 两侧护栏 + 插座端挡块 |
| 完成判定 | Tween 回调 | **物理状态**：模块中心进入插座 ±0.40 m 且速度 < 0.25 m/s 连续 20 帧 |
| E 的作用 | 一次按键 = 任务完成 | 只"接通绞盘"；不推不动，模块没滑到位就不算完成 |

---

## 2. 实际修改的文件与代码

| 文件 | 改动 |
|---|---|
| `game/act1/scripts/world/act1_station_builder.gd` | 新增 `_build_power_module_rail()`（导轨台面 / 两侧护栏 / 端部挡块 / 60 kg 模块刚体）+ `var power_module` |
| `game/act1/scripts/machines/act1_power_cart.gd` | 删除 Tween 与 `_set_transfer_progress`；`transfer_module()` 改为接通绞盘；新增 `_drive_winch()`（真实力）、`bind_module()`、`mark_module_seated()`；`reset_cart()` 复位模块与绞盘 |
| `game/act1/scripts/act1_app.gd` | `_update_physics_verifications()` 增加模块就位物理判定（`_seat_streak`）；新增 `var _seat_streak` |

**新增测试/工具**：
`game/act1/tests/mech001a_power_module.gd/.tscn`（5 项专项）、
`game/act1/tests/mech001a_capture.gd/.tscn`（真实窗口取景）。

**使用的已验收物理能力**：真实刚体 + 质量 + 碰撞层/材质、真实力驱动（绞盘牵引）、静态导轨碰撞、按位置与静止状态判定完成。
**没有**引入 `physics_lab` 的类（两个工程独立），也没有另写一套物理引擎。

---

## 3. 玩家操作步骤（主解法）

1. 推开压住门轨的维护架（既有物理）、按 E 释放门闩，进入站内。
2. 走到电力区，按 E 推车（`cart_push`）→ 用 W/S 把推车推到导轨插座端（`DOCK_X`）。未到位时操作绞盘会被拒绝。
3. 推车到位后，按 E 操作**导轨绞盘**（`power_winch`）→ 模块作为真实刚体被 530 N 牵引力沿导轨拉向插座。
4. 模块滑到端部挡块停住、静止 20 帧后，任务状态自动置为"模块就位"。
5. 按 E 操作**机械夹**（`power_clamp`）→ 通电，HUD 提示"电源锁定 · 风机控制回路得电"。
6. 之后按原有流程进入通风阶段。

**替代解法**：模块是自由刚体，玩家也可以用身体推它（碰撞会把力传给它）；任何把它推进插座容差并停住的方式都算成功——判定只看位置与静止，不看是谁做的。

---

## 4. 任务状态 ↔ 机械状态对应

| 任务状态 | 由什么真实状态决定 |
|---|---|
| `power_cart.docked` | 推车实际位置（`DOCK_X ± 0.48`，既有逻辑） |
| `module_transferred_flag` | **模块刚体**中心与插座水平距离 < 0.40 m 且 `linear_velocity < 0.25`，连续 20 帧 |
| `flags["power_clamped"]` | 仍需 E，但**前置为上面的 flag** —— 模块没物理就位就无法夹 |
| `flags["power_ready"]` | 由 `power_clamped` 派生（既有） |

E 在任何一步都**不再**直接置成功；它只推车、接通绞盘、夹紧机械夹。

---

## 5. 测试结果

### 5.1 专项：`act1/tests/mech001a_power_module.tscn` — **5/5 PASS**

```
PASS  X1 模块是真实刚体（质量/碰撞/层）  |  mass=60.0 kg, layer=2, mask=3
PASS  X2 推车未到位时绞盘不动作、任务不完成  |  flag=false，模块位移 0.000 m
PASS  X3 绞盘真实牵引模块沿导轨滑入插座  |  峰值速度 4.09 m/s，位移 1.85 m，55 帧后就位（插座水平误差 0.07 m）
PASS  X4 就位标志由物理状态触发（容差内 + 静止）  |  flag=true，水平误差 0.07 m（容差 0.40）
PASS  X5 复位后模块回到导轨起点、标志清除  |  flag=false，距起点 0.030 m
MECH001A_DONE failures=0
```

### 5.2 既有全流程回归：`act1_solo_full_run.gd` — **21 项全过，completion=true**

其中两行直接覆盖本次改造：

```
PASS power module physically traversed the guide rail
PASS power module clamped and control circuit live
...
PASS Act01 completion recorded through Act1SessionBridge (completed=true)
RESULT failures=0 completion=true
```

说明：原文任务顺序、通风/矿车/发车流程、会话完成回传全部未被破坏。

### 5.3 真实窗口

`mech001a_capture.tscn` 在 NVIDIA 显卡窗口下运行成功，4 张 1280×720 截图落盘
（`game/act1/captures/mech001a/`）：电源区全景、模块在导轨上、绞盘牵引中、模块就位。

**五次尝试后的最终结果（成功）**：

| 尝试 | 做法 | 结果 |
|---|---|---|
| 1 | 直接拍 | 被开场模态简报 `hud._intro`（6.5 s 自动淡出）挡住 |
| 2 | `hud._intro.visible = false` | 遮罩消除，但画面几乎全黑——剧情是"恢复电源"，**通电前站内照明是关的** |
| 3 | 取景前 `_builder_power_light_on()` + **平均亮度自检** | `0.113/0.066/0.184/0.067`，有内容但对着灯具 |
| 4 | 以模块为锚的相对取景 | 拍到走廊墙面，没框住模块 |
| **5** | **改用自己的 `Camera3D`（`make_current()`）** | `0.068/0.205/0.205/0.247`，**成功框住模块** |

最终可用画面（`game/act1/captures/mech001a/04_module_seated.png`）里可以看到：
* 青绿色发光的**电源模块已停在插座端**（缆绳/挡块位置正确）；
* HUD 中部提示 **"模块到位 · 锁定机械夹完成供电"** ——即物理状态触发后的任务提示；
* 左上阶段已推进到 **"③ 启动主通风机"**，说明 power 阶段确实完成、流程继续。

其余三张（`01` 全景、`02` 模块在导轨起点、`03` 绞盘牵引中）同时落盘。
**限制**：取景很贴近（相机在导轨上方 1.9 m），是"证据镜头"而不是美术展示镜头。

---

## 6. 自主修复的 Bug

1. **Tween 冒充物理**（本次改造目标本身）：删除 `_transfer_tween` 与 `_set_transfer_progress`，完成判定移出动画回调。
2. **模块无法起动**：初版绞盘力 0.9·m·g = 530 N，而默认摩擦（μ≈1.0）需要 589 N → 模块纹丝不动。
   给模块加 `PhysicsMaterial(friction=0.22)` 后正常滑动（X3 通过）。
3. **重复载荷**：车上原有装饰模块与新刚体同时存在 → `bind_module()` 里隐藏车上载荷并禁用其 `ModuleShape`。

未发现共享物理组件的真实缺陷，因此**没有**修改任何已验收物理组件。

---

## 7. 物理回归

- 本轮只改 `game/act1/`（另一个工程）中的 3 个脚本；`physics_lab` 的共享组件**一行未动**，
  其 14 套回归的结论不因本轮改变。
- 第一幕自身：`act01.tscn` headless 启动 exit 0；`act1_solo_full_run.gd` 21 项全过。
- 未运行：`act1_autotest` / `act1_sync3` / 多人联机专项（网络专项按任务要求暂停）。

---

## 8. 未解决的限制

1. **视觉验收未完成**：简报遮罩挡住截图（见 §5.3）。
2. **创建者真人手感未验证**：无人试玩。
3. 模块峰值速度 4.09 m/s 偏快（1.85 m 行程 55 帧走完）；手感上可能显得"弹射"，建议真人试玩后再调牵引力系数。
4. 模块被推到导轨外（z 方向越界）时没有自动恢复，只能按 R 重置。
5. 多人联机下模块刚体的权威同步仍走既有快照字段 `module`（位置），
   但**未在联机环境下验证**——本轮按要求不做网络专项。

---

## 9. 创建者试玩入口

```powershell
tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe `
  --path game res://act1/act01.tscn
```

**试玩清单**：
1. 进站后走到电力区，按 E 抓住推车推杆，W/S 推到插座端（听到到位音）。
2. 按 E 操作导轨绞盘，看 60 kg 模块沿导轨被拉过去、撞到端部挡块停住。
3. 注意 HUD 是否提示"模块就位"；再按 E 夹紧机械夹，确认"电源锁定"。
4. 故意在推车没到位时按 E 绞盘，确认被拒绝、模块不动。
5. 按 R 重置，确认模块回到导轨起点、可以再做一次。

---

## 10. 安全回退

改动前的 4 个文件与 SHA-256 已备份：

```
work/postmid-001/dev/physics_lab/backup_mechanics001a/
  act1_app.gd  act1_power_cart.gd  act1_station_builder.gd  act1_interactable.gd
  SHA256-BEFORE.txt
```

回退：把上述 4 个文件拷回 `game/act1/scripts/` 对应路径，并删除
`game/act1/tests/mech001a_*`。未执行任何破坏性 Git 操作，未提交/推送。

**重要**：`game/act1` 目前**不在 Git 跟踪范围内**（`git status` 无记录），
本轮备份是唯一回退依据。建议尽快把 `game/act1/` 纳入版本控制。

---

## 11. GO / CONDITIONAL GO / NO-GO

**技术 CONDITIONAL GO。**

已达成（14 项验收中 11 项）：
1. ✅ 第一幕剧情与任务结构完整（21 步全流程回归）
2. ✅ 一个正式任务已真正改造成物理操作玩法
3. ✅ 玩家用正常控制（E/推车/绞盘）可完成
4. ✅ 过程中物体与机械真实运动（刚体 + 真实力）
5. ✅ E 不再直接完成任务（X2 证明未到位按 E 无效）
6. ✅ 成功由真实机械状态触发（位置 + 静止 20 帧）
7. ✅ 有清楚的主要解法
8. ✅ 误操作可恢复（R 重置，X5 通过）
9. ✅ 前后流程未断裂（21 步回归）
10. ✅ 新增专项 5/5、既有全流程 21/21
11. ✅ 其他四幕与未授权区域未修改

未达成（2 项）：
12. ⚠ **创建者真人手感**：未试玩（模块峰值 4.09 m/s 偏快，需真人判断）
13. ⚠ 多人联机下未验证模块同步

**重复性（已补做）**：专项 `mech001a_power_module` 现为
**5 轮异常（未到位操作绞盘）+ 3 轮完整链**，全部通过：
`5/5 轮通过，最大位移 0.000 m`；`3/3 轮通过；最小位移 1.85 m，最大插座误差 0.07 m，最长 56 帧`。

**结论**：自动化技术验收通过；**视觉与真人体感验收待完成**，不能宣称第一幕物理化已获最终体验认可。
