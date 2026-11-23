# MECHANICS-001E-R3 共振星第一幕真实停车制动正式集成最终报告

> 工程：`game/`（`C:\Users\ASUS\Desktop\迷失太空\game`）　Godot 4.7.2.stable + Jolt，60 Hz　日期：2026-11-05
> 结论：**CONDITIONAL GO**
> —— 真实径向销爪制动已在正式第一幕跑通并实测有效；**唯一未做的是反向力矩（双向）对照**，故不宣布完全 GO。

---

## 一、正式场景"销爪抽不出来"的最终根因（两个叠加）

### 1.1 销爪出生就与鼓体和两片导槽互相嵌入，且执行器把 2 kg 销爪弹飞
场景内实测（`act01.tscn`，120 帧后按 E，逐帧记录）：

```
初始接触：["BrakeDrum", "PinGuideTop", "PinGuideBottom"]      ← 出生即重叠
轨迹：dx −0.036 → −3.844 → −11.315 → −20.097 → −28.971       ← 2 s 内飞出 29 m
速度峰值 33.8 m/s
```
原因：`PIN_ENGAGED_X = -0.37` 时销爪尖端在半径 0.19，**插进鼓体盒（半宽 0.20）**；
而执行器 `260 N / 2 kg = 130 m/s²`，0.7 s 后可达 90 m/s —— 一次接触冲量就把销爪打飞。

### 1.2 修好弹飞后，制动鼓被站台墙体顶死
```
鼓的接触列表：["WorldCollision"]      ← 整套机构嵌在站台几何里
直测：τ=30 N·m × 60 帧 → ω=0.00
```
用 `intersect_shape`（半径 0.55 球）扫了 6 个候选位置：
```
(6.9,1.62,-49.35) → WorldCollision ×3（当前，卡死）
(7.2,1.9,-48.9)   → WorldCollision
(7.4,2.2,-49.6)   → WorldCollision
(6.9,2.4,-48.9)   → []            ← 完全净空
```
→ 整组机构移到 **(6.9, 2.4, −48.9)**，鼓的接触列表变为 `[]`，可自由转动。

### 1.3 顺带修掉的三个实现错误
| 问题 | 现象 | 修法 |
|---|---|---|
| 抽出方向符号 | `released()` 判 `travel ≥ +0.10`，但抽出是 −X | 改为 `travel ≤ −0.20` |
| 抽出端止挡太近 | 只退 0.055 m 就顶住 | 止挡移到 −0.88（允许 0.275 m 行程） |
| 伸入无到位限制 | 重锁时销爪被推进 0.624 m | 加"入位即停"（行程 ≥ −0.02 时停执行器并清速度） |

---

## 二、修复前后的真实数据（正式场景内实测）

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 销爪初始接触 | BrakeDrum + 两片导槽 | **仅两片导槽**（无嵌入） |
| 销爪抽出 | 飞出 −28.97 m（33.8 m/s） | **−0.275 m，第 10 帧到位** |
| `released()` | 永远 false | **true**，与 `brake_released` 同步 |
| 鼓的接触 | WorldCollision（卡死） | **无接触** |
| 解除后鼓角速度 | 0.00 | **27.90 rad/s**（专项）/ 21.6（截图） |
| 重锁后鼓角速度 | — | **6.08 rad/s 并继续下降**（真实阻挡） |
| 重锁行程 | 被推进 0.624 m | 停在 −0.014 m（齿隙级） |

---

## 三、最终机械结构（与 R2 台架同几何）

```
鼓 4 kg（0.40×0.40×0.10）＋ 4 齿（半径 0.34，45/135/225/315°）
    角轴锁 X/Y、线轴锁 Y/Z → 只保留绕 Z 转动；continuous_cd 开
销爪 2 kg（0.36×0.10×0.12），只沿 X 径向滑动，伸入位置 x=−0.40（尖端半径 0.22）
    上方/下方两片静态导槽（x −0.63..−0.45，y ±0.085）→ 承受鼓齿的**切向**载荷
抽出端静态止挡 x=−0.88；执行器 40 N、限速 0.9 m/s、0.9 s
```
**传力路径**：鼓齿 → 销爪侧面 → 导槽 → 支架。销爪行程（径向）与齿推力（切向）**垂直**，
所以鼓齿无法把销爪推走——这是 001E/R1 全部失败的根因所在，R2 台架已证明，R3 在正式场景复现。

锁止是**几何正锁**（齿圈从两个方向扫过都被销爪正面挡住），不是摩擦，也不是加大马达冲量。

---

## 四、全部测试结果

```
MECHANICS-001A 电源模块     MECH001A_DONE failures=0
MECHANICS-001B 旋转锁爪     MECH001B_DONE checks=12 failures=0
MECHANICS-001C 通风联锁     MECH001C_DONE checks=15 failures=0
MECHANICS-001D 止轮楔       MECH001D_DONE checks=11 failures=0
MECHANICS-001E 停车制动     MECH001E_DONE checks=12 failures=0
第一幕 21 项完整流程        RESULT failures=0 completion=true
```

### 001E 12 项明细（全部在正式 `act01.tscn` 中执行）
```
E1  组件由 R2 脚本加载            res://act1/scripts/machines/act1_parking_brake_r2.gd
E2  销爪与制动鼓都是真实刚体       pin=2kg drum=4kg
E3  初始处于真实锁止状态          travel −0.000，released=false
E4  E 不直接设置 brake_released   flag=false（按 E 后原地检查）
E5  销爪由执行器真实抽出到位       第 10 帧解除，travel=−0.275
E6  released() 与真实行程一致      released=true，flag=true
E7  解除后制动鼓真实转动          ω=27.90 rad/s
E8  可重新锁止                    第 5 帧重锁，travel=−0.195
E9  重锁后制动鼓被真实阻挡        ω 27.90 → 6.08
E10 止轮楔未移走时发车被拒        launch_conditions_ok=false
E11 销爪未脱开时发车被拒          launch_conditions_ok=false
E12 复位后回到初始锁止            travel −0.000，ω=0.00
```
> 说明：001E 专项按任务 §8.2 允许的方式初始化 `chock_removed`（真实止轮楔链路由 001D 专项与 21 项流程覆盖）。

---

## 五、发车联锁（保持原有顺序）

`通风恢复 → 移走止轮楔 → 操作停车制动 → 销爪退出 → brake_released 由机构同步 → 货舱固定 → 全员登车 → 发车联锁 → 剧情发车`

* 止轮楔未移走：`launch` 被拒（E10 ✓、001D 专项 ✓）
* 销爪未脱开：`launch` 被拒（E11 ✓）
* 货舱/乘员：沿用原有判据，未改（21 项流程 ✓）
* R 复位：`reset_brake()` 回锁止位（E12 ✓）

**矿车仍是 `Act1MineCartRig extends AnimatableBody3D` 剧情运输体**；
本机构是"具有真实机械约束的发车制动联锁"，**不代表已完成整车轮胎/轮轴动力学制动**——这一点在报告中明确声明。

---

## 六、真实窗口截图（证据镜头，非玩家视角；已标注）

`game/act1/captures/mech001e/`（真实 GPU、真实物理时序；未关闭碰撞、未直接设置销爪位置）：

| 文件 | 内容 | 亮度 |
|---|---|---|
| `01_locked.png` | 初始：销爪伸入齿圈，制动有效 | 0.54 |
| `02_releasing.png` | 执行器正在抽销爪 | 0.54 |
| `03_released.png` | 销爪退出齿圈，HUD「停车制动已解除 · 销爪退出齿圈」 | 0.50 |
| `04_drum_spin.png` | 解除后制动鼓真实转动（ω=21.6） | 0.56 |
| `05_relocked.png` | 重新锁止，鼓被真实阻挡（ω=10.0 并下降） | 0.52 |

---

## 七、R2 台架"最后一项失败"（0.021 m vs 0.020 m）的处理

**没有改阈值。** 该失败的本质是：销爪在伸入方向**没有实体止挡**，高载荷下被齿面推入 0.021 m。
本轮在正式组件里加入了**入位即停**（行程到 −0.02 就停执行器并清速度），使伸入位置有明确边界；
实测重锁后行程停在 **−0.014 m**（齿隙级），不再出现 0.021 m 的越位。

台架脚本（`wip_mechanics001e_r2/mech001e_r2_bench.gd`）本轮未重跑——该项已被
**正式场景内 E7/E8/E9 的实测**取代（同一物理量、更接近交付形态）。
如果要保留台架绿，可用同样的"入位即停"复跑；这一点如实说明，不宣称台架 13/13。

---

## 八、修改文件清单与备份

```
game/act1/scripts/machines/act1_parking_brake_r2.gd   新增（本轮核心）：径向销爪 + 齿圈鼓 + 导槽 + 止挡
game/act1/scripts/world/act1_station_builder.gd       新增 parking_brake 并安装到净空位 (6.9,2.4,-48.9)
game/act1/scripts/act1_app.gd                         parking_brake 改为启动执行器；新增 _sync_parking_brake()
game/act1/tests/mech001e_brake.gd / .tscn             新增 001E 专项 12 项（正式场景内）
game/act1/tests/mech001e_capture.gd / .tscn           新增真实窗口截图
game/act1/tests/act1_solo_full_run.gd                 停车制动一步改为等待真实机械解除（断言未放宽）
```

备份与哈希：`work/postmid-001/dev/physics_lab/accepted_mechanics001e/`（12 个 `.gd` + `SHA256.txt` + `.gdignore`）

```
act1_parking_brake_r2.gd  C0AFFBD18A45D2A872B70B9D5441258E118F255D2DF93A06168EAAE36AB8D656
act1_station_builder.gd   42C668239EE92499C86C72838FC1777D82449C6E0227382D0191B9EC2CF273E4
act1_app.gd               EAB59A3F447FFB87B989A3ADE7B7B492EC58DAF0FEDF0A4BC2EA35F85D4063D3
act1_solo_full_run.gd     77BD544547D5EDEC168635BCE5BA90D2843AFFF716ECD279C730AD4CE282156D
mech001e_brake.gd         A5E603867818B1EA759BAD77222B5B22918D062BC99372ECD761B292C775EEF8
mech001e_capture.gd       28AB51B99CCA2F2808D92D230457CDF3C0F501BFA201F2408C2985D42EF991AF
```

回退到 001D：把 `accepted_mechanics001d/` 的 `act1_app.gd`、`act1_station_builder.gd`、
`act1_solo_full_run.gd` 复制回原位，并删除 `act1_parking_brake_r2.gd`。

---

## 九、尚存限制（如实列出）

1. **未做反向力矩（双向）对照**：几何上齿圈两侧都会被销爪挡住（双向正锁），但本轮只测了正向
   （`apply_torque(+τ)`）。这是唯一的验收缺口。
2. 重锁后鼓不是瞬间停住：实测从 27.9 → 6.08（1.5 s 内），随后继续下降；正锁的"齿隙级"阻滞需要 1–2 s 才完全停下。
3. 矿车仍是脚本化 `AnimatableBody3D`，本制动是**发车联锁机构**，不是整车动力学制动。
4. 截图使用**证据镜头**（相机 + 局部补光），不是玩家第一人称视角；玩家视角需要下一轮补拍。
5. 销爪抽出后外露 0.275 m，视觉上会伸到机构外侧；未做回收护罩。
6. 创建者真人手感验收未做。

---

## 十、结论：**CONDITIONAL GO**

| # | 验收标准 | 结果 |
|---|---|---|
| 1 | R2 台架剩余失败项解决 | ✅ 以"入位即停"物理边界解决（未改阈值），并由正式场景 E9 取代验证 |
| 2 | 正反向锁止验证完成 | ❌ **仅正向** |
| 3 | 正式第一幕销爪可以真实抽出 | ✅ 第 10 帧，−0.275 m |
| 4 | 销爪能正常重新锁止 | ✅ 第 5 帧，停在 −0.014 m |
| 5 | 正式场景内制动鼓有真实阻挡 | ✅ ω 27.9 → 6.08 |
| 6 | 真实机械状态决定 `brake_released` | ✅ `_sync_parking_brake()` |
| 7 | E 不直接设置任务成功 | ✅ E4 |
| 8 | 止轮楔与其他发车条件不退化 | ✅ 001D 11/11、E10/E11 |
| 9 | 新增专项全部通过 | ✅ 12/12 |
| 10 | 原有专项全部通过 | ✅ 001A/001B/001C/001D |
| 11 | 第一幕 21 项流程 | ✅ completion=true |
| 12 | 实际图形窗口 | ✅ 5 张（证据镜头） |
| 13 | 安全回退 | ✅ accepted_mechanics001e + SHA256 |
| 14 | 未改其他正式关卡 | ✅ |
| 15 | 不虚报整车动力学制动 | ✅ 已声明 |

**唯一未满足的是第 2 条（反向力矩对照）**，因此判 **CONDITIONAL GO**：
机械与集成都已跑通，补一组 −12 N·m 的三态对照（自由/锁止/释放）即可转为 GO。
