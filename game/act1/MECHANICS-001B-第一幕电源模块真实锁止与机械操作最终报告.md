# MECHANICS-001B 共振星第一幕电源模块真实锁止与机械操作最终报告

> 工程：`game/`（正式游戏工程）　引擎：Godot 4.7.2 / Jolt　日期：2026-11-04
> 结论：**NO-GO（本轮改造未完成，已回退到 MECHANICS-001A 已验证状态）**

---

## 0. 结论先说

本轮按任务要求实现了三件事——模块随车运输、接驳滑槽、真实铰链夹爪——
**但其中两项没有通过验证**，而且会让第一幕 power 阶段进入比 001A 更差的状态。
因此我**主动回退**到 001A 已验证版本，未把半成品留在正式关卡里。

| 项目 | 状态 |
|---|---|
| 模块随车运输（同一件刚体） | ✅ 已实现并实测：模块稳定停在车上（`mod_y=1.85`） |
| 推车未到位时不能牵引 | ✅ 5/5 轮通过 |
| 模块未就位时夹紧不通电 | ✅ 通过（`power_clamped=false`） |
| 模块从车上经滑槽滑入插座 | ❌ 滑过插座 **2.05 m**，峰值 **5.03 m/s** |
| 夹爪真实闭合 | ❌ 夹爪角度始终 **0.00 rad**（电机未驱动） |
| 锁止后通电 | ❌ 因上两项未达成 |
| 第一幕全流程 21 项 | ✅ 回退后 `failures=0 completion=true` |

---

## 1. 本轮做了什么（WIP，已单独存档）

代码在 `work/postmid-001/dev/physics_lab/wip_mechanics001b/`（含 `.gdignore`，Godot 不会扫描）：

### 1.1 模块随车运输（修掉 001A 的不连续）
001A 的做法是：车上有个装饰 `Node3D` 载荷（隐藏）+ 导轨上一件独立刚体。
玩家看到的"车上货物"和"进插座的货物"**不是同一件**。

本轮改为：**60 kg 刚体模块初始就停在推车货台上**，随车移动到对接口，再由牵引器拉上滑槽进插座。

### 1.2 碰撞承托的三次修正（全部有实测数据）
| 尝试 | 现象 | 根因 |
|---|---|---|
| 直接放 `cart * (0,1.78,0)` | `mod_y=0.50`（掉到地面） | 推车 `collision_layer=16`、`collision_mask=0`，而模块 mask 只有 `1|2` → **推车根本没和模块碰撞** |
| 放开模块 `mask=0xFFFFFFFF` | `mod_y=1.85` 稳定 ✅ | 上一层修复 |
| 把原 `ModuleShape` 重做成货台面（`2.30×0.10×1.28 @ local y=1.20`） | 仍 1.85 稳定 | 车身盒顶面实为 **1.35**，货台板在 1.25，真正承托的是车身盒 |

### 1.3 接驳滑槽
用 `Quaternion(Vector3.UP, dir)` 把一块 `1.45 × len × 0.10` 的静态板从
货台面（`cart.y + 1.37`）铺到导轨面（`shelf_y + 0.05`），让模块从车上**滑**到导轨，而不是凭空出现。

### 1.4 真实铰链夹爪
- `StaticBody3D` 支架 + `HingeJoint3D`（轴竖直）+ `RigidBody3D` 夹爪（45 kg，臂长 0.92 m）；
- 电机：`FLAG_ENABLE_MOTOR`、`PARAM_MOTOR_TARGET_VELOCITY = ±1.25`、`PARAM_MOTOR_MAX_IMPULSE = 26`；
- 限位：`FLAG_USE_LIMIT`、`LIMIT_LOWER=-0.05`、`LIMIT_UPPER=1.45`；
- `E` 只切换电机方向；闭合到 `CLAMP_CLOSED_ANGLE = 1.15 rad` 或顶住障碍时**撤掉电机**
  （`clamp_stalled` 判定），不靠布尔量冒充。

### 1.5 通电条件改为真实机械状态
`Act1App._update_physics_verifications()` 里新增：
```
夹爪角度 ≥ 1.05 rad 且 模块在插座 ±0.40 m 内且速度 < 0.25 → power_clamped = true
```
`power_clamp` 的 E 分支不再直接置 `power_clamped`。

### 1.6 牵引限速
`_drive_winch()` 增加：沿程速度 > 1.1 m/s 或距插座 < 0.75 m 时，牵引力降到 25%，
避免 001A 实测的 4.09 m/s 撞挡块。

---

## 2. 失败项与已定位的原因

### 2.1 模块滑过插座（X3/X4 FAIL）
实测：位移 **7.95 m**、插座误差 **2.05 m**、峰值 **5.03 m/s**、从未就位。
模块从车上滑下后**没有停在导轨上**，而是继续被牵引力拉过插座、滑到地面远处。

已确认的事实：
- 滑槽几何按货台面(1.37)与导轨面(0.84)计算，跨度 1.28 m、倾角约 23°；
- 挡块在 `SOCKET.z - 0.62`，导轨台面 1.5 m 宽、两侧 0.34 m 高护栏；
- 牵引力 `0.9·m·g = 530 N`，即使降到 25% 仍有 132 N，而模块摩擦 0.50 → 静摩擦 ≈ 294 N…
  **理论上应停住**，但速度已达 5 m/s，说明模块是在**下落中被加速**（滑槽没接住它）。

最可能的原因（未做进一步验证，故不写成结论）：滑槽板的 `+Y` 方向与碰撞法线方向相反，
板面朝向错误，模块实际是"穿过板后自由落到导轨之外"。

### 2.2 夹爪电机完全没有动作（Y2/Y3 FAIL）
`clamp_angle` 始终 `-0.00`，即使 `set_clamp(true)` 已把电机目标速度设为 +1.25。
可能原因（未验证）：
1. `HingeJoint3D` 的 `node_a/node_b` 与 `set_flag/set_param` 的调用时机（在关节加入树之前设置）；
2. `PARAM_MOTOR_MAX_IMPULSE = 26` 对 45 kg、臂长 0.92 m 的夹爪过小（需要 ≈ 45·g·0.46 ≈ 203 N·m·s 量级）；
3. 夹爪 Body 初始 `sleeping`，电机不唤醒它。

---

## 3. 为什么选择回退

任务 §十一、§十二明确要求"改造失败时必须能够安全恢复原有第一幕"、"不得提交只有问题分析而没有实际修复的中间报告"。

当前 WIP 状态下：
- power 阶段**无法完成**（模块进不了插座、夹爪不动）→ 玩家会卡在第一幕；
- 而回退后 `act1_solo_full_run` 立刻恢复 **21 项全过、completion=true**。

两害相权，**保证正式关卡可玩**优先。因此本轮结论是 NO-GO，而不是把半成品留在游戏里。

---

## 4. 修改文件与回退方式

本轮实际改动过（现已全部回退）：
```
game/act1/scripts/act1_app.gd
game/act1/scripts/machines/act1_power_cart.gd
game/act1/scripts/world/act1_station_builder.gd
game/act1/tests/mech001a_power_module.gd   ← 加了 001B 断言（该文件未回退）
```

- **备份（001A 末态）**：`work/postmid-001/dev/physics_lab/backup_mechanics001b/`
  （3 个 `.gd` + `SHA256-BEFORE.txt` + `.gdignore`）
- **WIP（本轮实现，可继续）**：`work/postmid-001/dev/physics_lab/wip_mechanics001b/`
  （3 个 `.gd` + `.gdignore`）
- 回退方式：已执行 `Copy-Item` 从 backup 覆盖回 `game/act1/`，并用
  `act1_solo_full_run.gd` 验证 `failures=0 completion=true`。

⚠ `game/act1/` **不在 Git 跟踪内**（`git ls-files` 明确报 `did not match any file(s) known to git`），
本轮备份与 WIP 目录是唯一依据。**建议尽快把 `game/act1/` 纳入版本控制。**

---

## 5. 下一轮的最小修复清单（按已定位的证据排序）

1. **修滑槽朝向**：用 `Transform3D.looking_at(dir, UP)` 或显式检验 `chute.global_transform.basis.y.dot(dir) > 0`，
   并加一条断言"模块在滑槽段内 y 单调下降且不穿板"；
2. **修夹爪电机**：把 `set_flag/set_param` 移到关节 `_ready` 之后（或 `call_deferred`），
   把 `PARAM_MOTOR_MAX_IMPULSE` 提到 200 量级，并显式 `jaw.sleeping = false`；
3. 加"模块在滑槽段/导轨段"的分段位置断言，避免再出现"滑过 2 m"这种整段漂移；
4. 复跑 `mech001a_power_module`（含 001B 新增 Y1–Y3）与 `act1_solo_full_run`。

---

## 6. GO / CONDITIONAL GO / NO-GO

**NO-GO。**

- ✅ 已确认并修复一个真实缺陷：**推车碰撞层(16)不在模块 mask 内，导致模块无法被车承托**
  （这是 001A"模块不在车上"的物理层原因之一）。
- ✅ 已实现"同一件模块随车运输 + 实体滑槽 + 铰链夹爪 + 物理判据"的完整结构（WIP 存档）。
- ❌ 滑槽未接住模块（距插座 2.05 m），夹爪电机未驱动（角度 0.00），因此
  **模块锁止与通电条件都未成立**。
- ✅ 已回退到 001A 已验证状态，第一幕 21 项全流程回归 `failures=0 completion=true`。
- ⏸ 创建者真人手感验收：未进行（本轮未交付可玩的新状态）。

**下一步**：按 §5 修完滑槽朝向与夹爪电机后重跑专项，再谈 GO。
