# MECHANICS-001C 共振星第一幕通风机组真实物理操作改造报告

> 工程：`game/`　Godot 4.7.2.stable + Jolt Physics，60 Hz　日期：2026-11-04
> 结论：**GO**（技术验收）。转子锁销与传动联轴器已改为真实刚体，风机能否运转由**机械位置**决定。

---

## 一、vent 阶段原有交互审计

`game/act1/scripts/act1_app.gd`（`_execute_interaction`）+ `act1_ventilation.gd`：

| 交互 id | E 的作用 | 改造前真实程度 |
|---|---|---|
| `fan_lock`（转子机械锁） | ~~直接 `flags["rotor_lock_released"]=true`~~ | **纯 flag**，没有任何机械件 |
| `coupling`（传动联轴器） | ~~直接 `flags["coupling_engaged"]=true`~~ | **纯 flag**，没有任何机械件 |
| `start_fan`（主启动手柄） | 检查 coupling/power 两个 flag 后 `vent.set_running(true)` | 有前置检查，但前置是 flag |
| `governor`（调速器） | 档位循环 62%→100%→55%→78% | **真实状态**（`vent.governor` 参与压力计算） |
| `damper`（双风道风门） | `vent.set_damper_target(0/1)` | **真实状态**（风门按 0.42 rad/s 摆动，参与风压） |
| `emergency`（紧急停机） | `vent.set_emergency(bool)` | **真实状态** |

风机本体（`Act1Ventilation`）**不是假的**，是对物理机的合理简化模型：
```
target_speed = governor if running and not emergency else 0
speed  = move_toward(speed, target_speed, 0.38*Δt / 0.28*Δt)   # 加速/停机的惯性差
pressure = speed * (0.28 + 0.72*damper)
6 s 压力测试：running && !emergency && damper>0.72 && pressure>0.58 才累加，否则以 0.5×Δt 回落
rotor.rotation.x += speed*Δt*7.2                                # 转子角度随转速累积
```
即：转速、风压、转子角度、压力测试都是**连续量**，不是 flag 动画。**因此本轮没有重建风机**，只修真正伪的部分。

**选择改造项**：`fan_lock`（转子锁销）+ `coupling`（传动联轴器）——vent 阶段唯一两处纯 flag 的机械件，
且正是"E 一按就完成"的典型。风机启动的准入也改为读机械位置。

---

## 二、改造前后对比

| 项目 | 改造前 | 改造后 |
|---|---|---|
| 转子锁 | E → flag=true | E → **执行器**沿 +X 拉销钉；销钉在托架上真实滑动 ≥0.30 m 或掉落，`rotor_released()` 才为真 |
| 联轴器 | E → flag=true | E → **执行器**沿 +X 推滑套；滑套顶住实体止挡、距啮合位 ≤0.06 m，`coupling_engaged()` 才为真 |
| 启动手柄 | 读两个 flag | 读 `machine_ready() = rotor_released() && coupling_engaged()`（真实位置） |
| 机械一旦失效 | 不会发生（flag 不会自己变） | 每帧同步：销钉/滑套一旦不在位，`fan_started=false` 且 `vent.set_running(false)`，风机立即失动力 |
| 任务状态 | E 直接置位 | 由 `_sync_fan_interlock()` 从机械位置同步到 flag/HUD |

---

## 三、实际机械结构与运动原理

新组件 `game/act1/scripts/machines/act1_fan_interlock.gd`（`class_name Act1FanInterlock`）。
**不使用 HingeJoint3D**——按 MECHANICS-001B 的教训，本工程里关节行为不稳，改用**力 + 静态导向 + 实体止挡**。

### 转子锁销
| 项 | 值 |
|---|---|
| 销钉刚体 | `RigidBody3D` 8 kg，0.12×0.50×0.12，`can_sleep=false`，linear_damp 2.6 |
| 托架（静态） | 0.90×0.08×0.30，顶面正好托住销钉底面 → 未通电时销钉**静止不动** |
| 挡边（静态） | 0.10×0.30×0.30 在 −X 侧，阻止销钉自行滑回 |
| 执行器 | E 后 0.60 s 内施加 **115 N** 沿 +X（> 8 kg×g ≈ 78 N） |
| 判定 | `销钉 x 位移 ≥ 0.30 m` 或 `y ≤ −0.35 m`（滑过托架末端掉落） |
| 实测 | 按下瞬间 dx=0.011 m（**不是瞬间到位**）；第 19 帧脱开；最终位移 0.653 m 后落地 |

### 传动联轴器
| 项 | 值 |
|---|---|
| 滑套刚体 | `RigidBody3D` 12 kg，0.22³，`can_sleep=false`，linear_damp 1.8 |
| 导杆（静态） | 0.95×0.08×0.10 在滑套下方 → 滑套坐在杆上，只能沿 X 滑动 |
| 止挡（静态） | 0.10×0.34×0.34 在啮合位的 +X 侧 |
| 执行器 | E 后 1.10 s 内施加 **420 N** 沿 +X 并带 −60 N 压杆分量 |
| 判定 | 与啮合位三轴偏差 ≤ **0.06 m** |
| 实测 | 第 5 帧啮合，滑套位移 0.280 m |

两件都真实到位 → `machine_ready()` 为真 → 启动手柄才有反应。

---

## 四、玩家操作步骤

1. 走到转子机械锁（`7.65, 1.15, −23.55` 的交互点）按 **E**：执行器开始拉销钉；
2. 看到销钉滑出、HUD 弹出「锁销已脱开 · 转子可自由转动」；
3. 走到传动联轴器（`8.15, 1.40, −29.05`）按 **E**：执行器推入滑套；
4. 滑套顶到止挡、HUD 弹出「联轴器啮合到位 · 动力可传递」；
5. 得电后走到主启动手柄按 **E**：风机开始建立转速（`speed` 从 0 沿惯性爬升）；
6. 用调速器把转速档提到 ≥78%、按风门开主风道；
7. 持续 6 秒满足 `damper>0.72 且 pressure>0.58` → `vent_complete=true` → 进入 hazard。

任一步机械不在位（销钉被插回、滑套被推回），`_sync_fan_interlock()` 会立刻让风机失去动力并把状态回退。

---

## 五、真实机械状态 ↔ 任务状态

```
转子锁销位置 ─┐
              ├─ machine_ready() ─→ start_fan 准入 ─→ vent.set_running(true)
联轴器滑套位置 ┘                                        │
                                             speed/pressure/damper（连续量）
                                                        │
                              running && !emergency && damper>0.72 && pressure>0.58
                                                        │ 连续 6 s（不满足则 0.5×Δt 回落）
                                                        ↓
                                               vent_complete → hazard
```

---

## 六、修改文件清单

```
game/act1/scripts/machines/act1_fan_interlock.gd   新增：转子锁销 + 联轴器（真实刚体）
game/act1/scripts/world/act1_station_builder.gd    新增 var fan_interlock 并在通风厅构建设备
game/act1/scripts/act1_app.gd                      rotor_lock/coupling 改为启动执行器；
                                                   start_fan 准入改读 machine_ready()；
                                                   新增 _sync_fan_interlock() 每帧同步机械状态
game/act1/tests/mech001c_vent.gd / .tscn           新增 001C 专项 15 项
game/act1/tests/mech001c_capture.gd / .tscn        新增真实窗口截图
game/act1/tests/act1_solo_full_run.gd              电源牵引一步改为等待真实状态（见 §七.3）
```

未改：其他四幕、其他星球、归航号、网络系统、全局 Jolt 配置、001B 的锁爪与滑槽物理。

---

## 七、自主修复的 Bug（复现 → 根因 → 修复 → 验证）

1. **销钉悬空 / 导杆在滑套上方**
   首版把静态套筒放在销钉正下方 0.55 m 处（等于没托住），导杆放在滑套上方 0.22 m（滑套无处可坐），
   两者都会直接掉到地上。→ 改为"托架在销钉正下方、导杆在滑套正下方"，实测静止漂移 <0.03 m。
2. **锁销被拉飞 3.3 m**
   320 N × 0.8 s 对 8 kg 相当于 40 m/s² → 销钉飞出。→ 降到 115 N / 0.60 s / damp 2.6，
   实测位移 0.653 m 后落地。
3. **新加的静态托架挡住玩家通道**
   首版把设备放在走廊正中，玩家走到 `x=7.9` 就被挡，走不到联轴器（`AIM coupling distance too far 6.18`）。
   → 整组设备移到走廊外侧 `x=6.85`（贴墙），玩家通道恢复。
4. **第一幕流程里"电源模块牵引"偶发失败**
   根因不是本轮物理：该步骤用固定 `create_timer(2.5)` 等待，场景变重后墙钟 2.5 s 对应的物理帧变少。
   → 改为**等待真实 `module_transferred_flag`**（最多 6 s），断言未变。

---

## 八、测试结果（全部真实执行、带计数、失败返回非零）

```
MECHANICS-001C 专项          MECH001C_DONE checks=15 failures=0
MECHANICS-001B-R2 锁爪专项    MECH001B_DONE checks=12 failures=0
MECHANICS-001A 基线专项       MECH001A_DONE failures=0
第一幕 21 项全流程            RESULT failures=0 completion=true
```

### 001C 15 项明细
```
C1  通风机组与机械联锁都存在
C2  初始：锁销未脱开、联轴器未啮合
C3  未通电时启动手柄无反应
C4  锁销未脱开时联轴器推不动            collar 偏移 0.020 m
C5  按 E 只启动执行器（销钉不是瞬间到位）按下瞬间 dx=0.011 m
C6  锁销由执行器真实拔出并脱开          第 19 帧，位移 0.653 m
C7  任务状态由机械位置同步              rotor_lock_released=true
C8  联轴器由执行器真实推入并啮合        第 5 帧，位移 0.280 m
C9  锁销脱开 + 联轴器啮合 → 联锁成立    ready=true
C10 启动后转速真实上升                 speed 0.000 → 0.310（45 帧）
C11 转子真实转动                       Δ=1.471 rad，speed=0.500
C12 机械联锁断开后风机自动失去动力      fan_started=false running=false
C13 风门未开时压力测试不会通过          pressure=0.273 complete=false
C14 风门+调速器满足后 6 s 压力测试通过  第 462 帧（约 7.7 s）
C15 重置后回到初始状态                 released/engaged=false，speed=0
```

> 说明：001C 专项允许初始化 `power_ready`（按任务 §6 允许专项初始化前置状态）；
> **真实电源链路**由第一幕 21 项流程验证（模块随车→滑槽→插座→锁爪闭合→通电→通风）。

---

## 九、真实窗口截图

`game/act1/captures/mech001c/`（真实 GPU 渲染，未关碰撞、未直接设置机械成功）：

| 文件 | 内容 |
|---|---|
| `01_before.png` | 操作前：销钉在位、联轴器未啮合，HUD「风机待机」 |
| `02_lock_pulling.png` | 正在操作：执行器拉销钉 |
| `03_lock_released.png` | 机械运动结果：HUD「锁销已脱开 · 转子可自由转动」 |
| `04_coupling_pushing.png` | 正在操作：执行器推联轴器 |
| `05_coupling_engaged.png` | HUD「联轴器啮合到位 · 动力可传递」+「检修就绪（锁已拔/联轴器已接）」 |
| `06_fan_spinning.png` | 主风机真实转动 speed=0.62（该角度光照偏暗，见 §十一） |

---

## 十、可试玩入口

`godot --path game`（正式工程）→ 第一入口场景 → 进入第一幕 → 完成电源安装 → 进入通风厅。
通风厅内三个交互点：转子机械锁 `(7.65,1.15,−23.55)`、传动联轴器 `(8.15,1.40,−29.05)`、主启动手柄。

---

## 十一、尚未完成 / 已知限制

1. **截图取景不理想**：通风厅在这一侧光照很暗，机构在画面中偏小（HUD 与数值可验证，但"肉眼看清机械动作"还需一轮取景/补光）。
2. 联轴器目前是**滑套顶到止挡**的啮合表达，没有真实的扭矩传递阻尼；动力传递仍由 `machine_ready()` 把关（与风机简化模型一致）。
3. 转子锁销脱开后**落到地面**（真实落体），没有回收槽；视觉上会躺在地上。
4. 风机响应的 `governor` 仍是离散档位（62/78/100/55），未做连续调节。
5. 创建者主观手感验收未做；001B 遗留的模块峰值速度 5.53 m/s 仍未优化（按任务要求本轮不因此中断）。

---

## 十二、结论：**GO**

* ✅ 已核实 vent 阶段原有交互的真实状态（§一，逐项列出哪些真、哪些伪）
* ✅ 转子锁销与传动联轴器完成物理化升级；风机本体**保留原有正确模型，未重建**
* ✅ 玩家用正常控制（走到位置 + E）即可完成；E 只启动执行器
* ✅ 机械运动来自真实力 + 静态导向 + 实体止挡（8 kg / 12 kg 刚体，115 N / 420 N）
* ✅ E 不再直接标记成功；任务状态由机械位置同步
* ✅ 条件不足（未通电、销未拔、未啮合）时不会错误成功
* ✅ 误操作/重置可恢复（C12/C15）
* ✅ 剧情与顺序未变；001B 的电源安装无回归（12/12）
* ✅ 001C 15/15、001A 5/5、001B 12/12、第一幕 21/21
* ✅ 真实图形窗口可运行并出图
* ✅ 有备份与 SHA-256（`work/postmid-001/dev/physics_lab/accepted_mechanics001c/`）
* ✅ 未修改其他四幕与非授权区域

**备份与回退**：`accepted_mechanics001c/` 内为本轮交付版本 + `SHA256.txt` + `.gdignore`（避免 Godot 重复注册）。
回退到 001B-R2：把 `accepted_mechanics001b_r2/` 的 `act1_app.gd`、`act1_station_builder.gd`、
`act1_power_cart.gd` 复制回 `game/act1/scripts/`（并删除本轮新增的 `act1_fan_interlock.gd`）。
