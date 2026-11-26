# 共振星多人压力系统 · 实现说明

> 状态：`已实现`（代码 + 测试 + 接线均已完成并跑通）
> 范围：低位风险、高位 8 秒接力倒计时、全队回档三个系统
> 文档性质：实现说明与验证记录，不改变 `docs/design/` 下已确认的玩法规则

## 1. 交付物

| 文件 | 作用 | 大小 |
| --- | --- | --- |
| `game/scripts/mp/low_position_risk_system.gd` | 低位风险（0.8%/s、50% 警告、80% 受伤复位） | 12.3 KB |
| `game/scripts/mp/high_position_relay_system.gd` | 高位 8 秒接力倒计时与超时惩罚 | 10.4 KB |
| `game/scripts/mp/multiplayer_death_system.gd` | 全队回档（含竞态互斥） | 9.0 KB |
| `game/scripts/mp/resonance_coop_pressure.gd` | 集成层：权威绑定、关卡事件翻译、表现分发 | 19.8 KB |
| `game/tests/resonance_mp_pressure.gd` | 单元测试（77 项断言） | — |
| `game/tests/resonance_mp_pressure_integration.gd` | 关卡集成测试（26 项断言） | — |

集成点（已落地，不是示例代码）：`resonance_stage.gd`、`resonance_cave_chapter.gd`、`main_3d.gd`。

## 2. 为什么这样设计

原始需求给出的是三段示意代码。直接落地会踩到四个真问题，这份实现针对每个问题都有明确处理。

### 2.1 每个客户端各跑一份计时 → 两端必然分叉

示意代码里 `_process` 在每台机器上都推进 `risk_level`。三台机器帧率不同，1 秒后风险值就差出几个百分点；到 80% 时，伤害在不同帧触发，甚至只有一端触发。

**处理**：风险与倒计时**只在主机推进**。`authority_enabled` 由集成层按 `controller.is_host` 设置。客户端 `advance()` 直接返回，永远只跟随主机下发的值。

### 2.2 reliable 与 unreliable 混用 → 状态被旧包回滚

需求要求"用 reliable RPC 确保同步"。但把 10 Hz 的进度条也做成 reliable，等于为了一个装饰性数值付出可靠通道的重传开销与队头阻塞；而把关键事件做成 unreliable，则可能丢包导致"受伤了但没人知道"。

**处理**：拆成两条独立通道，各带自己的 revision 计数器：

| 通道 | 传输 | 内容 | 频率 |
| --- | --- | --- | --- |
| 状态 | `unreliable_ordered` | 风险值、警告标志、剩余秒数 | 10 Hz |
| 事件 | `reliable` | 50% 警告、80% 受伤、接力成功、接力超时、全队回档 | 仅在发生时 |

收端一律丢弃 `revision <= 已应用` 的包。这样 reliable 事件包即使因重传比后续状态包晚到，也不会把已经前进的状态改回去。

### 2.3 `await create_timer(2.0)` 期间的重复回档

`on_player_death` 要等 2 秒播报。这 2 秒里第二名玩家完全可能也倒下，于是两个协程都会在 2 秒后执行，把队伍连拍回检查点两次，而且第二次会抹掉第一次之后合法推进的进度。

**处理**：两条独立防线。

1. **代次号** `reset_generation`：每次进入领一个号，`await` 醒来先比对；不是最新代次就静默退出。
2. **互斥锁** `is_resetting`：回档执行期间拒绝新请求。

测试 `_test_death_reset_race` 直接复现这个场景（两次死亡相隔 0.2 秒）并断言 `reset_calls == 1`。

### 2.4 倒计时出现负数

`countdown -= delta` 遇上卡顿帧（或断点续跑）会直接变负，HUD 显示 `-1.2s`。

**处理**：
1. 主机侧每次递减后 `clampf(countdown, 0.0, RELAY_WINDOW)`；
2. 客户端收到包再夹一次（防御恶意/异常值）；
3. `advance` 的 `delta` 先截断到窗口长度，`RiskSystem` 截断到 0.25 秒；
4. 超时判定配 `_settled` 幂等锁，一帧内多次调用也只结算一次。

## 3. 各系统参数与行为

### 3.1 LowPositionRiskSystem

| 项 | 值 | 说明 |
| --- | --- | --- |
| `RISK_PER_SECOND_NO_SUPPORT` | 0.8 | 每秒 +0.8% |
| `RISK_THRESHOLD_WARNING` | 50.0 | 警告阈值，只触发一次 |
| `RISK_THRESHOLD_CRITICAL` | 80.0 | 受伤阈值 |
| `DAMAGE_ON_CRITICAL` | 25 | 百分制伤害 |
| `RISK_MAX` | 100.0 | 硬上限，任何来源都夹在此 |
| `MAX_STEP_DELTA` | 0.25 | 单帧最大推进步长 |
| `STATE_SYNC_INTERVAL` | 0.1 | 状态通道推送间隔 |

行为要点：

- **高位接力中风险立刻清零**，且 `warned_once` 一起复位。
- **受伤后风险复位、`warned_once` 复位**，所以下一轮超载会重新警告，玩家知道还能再试。
- **停止操作后不增长**，但也不衰减（`RISK_DECAY_PER_SECOND = 0`），保持原始规则语义。

### 3.2 HighPositionRelaySystem

| 项 | 值 |
| --- | --- |
| `RELAY_WINDOW` | 8.0 秒 |
| `DAMAGE_ON_TIMEOUT` | 25 |
| `LOW_RISK_PENALTY` | 20.0 |
| `COUNTDOWN_SYNC_INTERVAL` | 0.1 秒 |

相位：`idle → active → completed / failed → idle`。

原始的"每 6 帧同步一次"改成**按时间**累计 0.1 秒：120 FPS 下 6 帧只有 0.05 秒（多一倍流量），30 FPS 下 6 帧却是 0.2 秒（进度条一顿一顿）。按时间对齐才与帧率无关。

超时后自动 `reset_relay()`，低位可以立刻重按启动。

### 3.3 MultiplayerDeathSystem

| 项 | 值 |
| --- | --- |
| `TEAM_DEATH_BANNER_DELAY` | 2.0 秒 |
| 回档内容 | 位置 → 检查点、清风险、清接力、清当前模块进度 |

**血量不在这里重置**：血量由 `main_3d.gd` 的 `sync_health_state` 权威下发。客户端自己改血只会被下一包覆盖，造成血条跳动。

`reset_module_progress()` 只把**当前段**退回 `ready`，已完成模块不动 —— 与设计文档"每节模块完成后写入检查点，当前模块失败只回到该模块的待机状态"一致。

## 4. 集成代码（已落地）

### 4.1 resonance_stage.gd

```gdscript
const COOP_PRESSURE_SCRIPT: Script = preload("res://scripts/mp/resonance_coop_pressure.gd")

var coop_pressure: ResonanceCoopPressure

func setup(owner: Main3D) -> void:
    controller = owner
    name = "ResonanceStage"
    _setup_coop_pressure()

func _setup_coop_pressure() -> void:
    if coop_pressure != null and is_instance_valid(coop_pressure):
        coop_pressure.bind_controller(controller, self)
        return
    coop_pressure = COOP_PRESSURE_SCRIPT.new() as ResonanceCoopPressure
    if coop_pressure == null:
        return
    coop_pressure.name = "CoopPressure"
    add_child(coop_pressure)
    coop_pressure.bind_controller(controller, self)
```

`tick()` 里放在 host 分支**之外**，两端都走：

```gdscript
func tick(delta: float) -> void:
    if not is_active():
        return
    if coop_pressure != null and is_instance_valid(coop_pressure):
        coop_pressure.tick(delta)   # 内部按 authority 决定推进还是只显示
    if controller.is_host:
        ...
```

接力的三个时刻：

```gdscript
# 低位启动（在 _handle_support_relay_action 的 phase == 0 分支里）
_notify_coop_relay_phase(1, peer_id, 0, SUPPORT_RELAY_WINDOW)

# 高位完成（在 _complete_support_relay 开头）
_notify_coop_relay_phase(3, int(support_relay["low_peer"]), int(support_relay["high_peer"]))

# 超时（在 _tick_support_relay 里）
_notify_coop_relay_timeout()
```

快照里带上压力状态，中途加入的客户端一次对齐：

```gdscript
"coop_pressure": coop_pressure.pressure_snapshot() if ... else {},
```

```gdscript
var saved_pressure: Variant = snapshot.get("coop_pressure", {})
if coop_pressure != null and is_instance_valid(coop_pressure) and saved_pressure is Dictionary:
    coop_pressure.apply_pressure_snapshot(saved_pressure as Dictionary)
```

### 4.2 resonance_cave_chapter.gd（当前实际运行的章节）

实际场景 `resonance_stage.tscn` 挂的是 `resonance_cave_chapter.gd`，其中 `relay_entry` → `relay_exit` 才是现在生效的低位/高位接力。接线：

```gdscript
func stage_tick(delta: float) -> void:
    if controller == null:
        return
    _orient_cave_spawn_cameras()
    cave_sync_clock += delta
    if coop_pressure != null and is_instance_valid(coop_pressure):
        coop_pressure.tick(delta)
        _tick_coop_relay_gate()
    if controller.is_host:
        ...
```

在 `_solve_cave_objective` 里按目标类型分支：

```gdscript
if kind == "relay_entry" and not _objective_solved("relay_exit"):
    _start_coop_relay(peer_id)          # 低位启动 → 8 秒倒计时
elif kind == "relay_exit":
    _finish_coop_relay(peer_id, was_entry_solved)   # 高位完成 → 清零
```

`_start_coop_relay` / `_finish_coop_relay` / `_tick_coop_relay_gate` 三个桥接函数都在该文件内，`_tick_coop_relay_gate` 负责在超时后把 `_coop_relay_active` 落回 false 并提示"可重新按 E 启动"。

### 4.3 main_3d.gd

```gdscript
func _check_all_downed() -> void:
    if players.is_empty():
        return
    for player in players.values():
        var p := player as SpacePlayer3D
        if p != null and not p.downed and not p.lava_dead:
            return
    if _resonance_stage != null and current_planet_id == "electromagnetic":
        var victim: int = 1
        for player in players.values():
            var p := player as SpacePlayer3D
            if p != null:
                victim = p.peer_id
                break
        _resonance_stage.on_coop_player_death(victim)
    fail_mission()
```

`fail_mission()` 保留，非共振星流程与既有测试不受影响。

### 4.4 HUD 挂载（可选）

集成层不写死 HUD。任何带下列方法的对象赋给 `coop_pressure.hud` 即可：

```gdscript
coop_pressure.hud = my_hud
# 需要的方法（有则调用，没有则静默跳过）：
#   show_warning(text) / show_critical_warning(text) / update_risk_display(level)
#   show_relay_countdown(remaining) / set_countdown_color(color)
#   show_relay_success(text) / show_death_banner(text)
```

没有 HUD 对象时，表现走 `controller.show_feedback_rpc`（主机广播）与角色的 `trigger_camera_shake`（本机），所以即使不接管 HUD 也有完整反馈。

## 5. 验收项对照

| 要求 | 实现 | 验证 |
| --- | --- | --- |
| 没有竞态条件（RPC 顺序正确） | 状态/事件双通道 + 各自 revision 过滤；回档代次号 + 互斥锁 | `_test_out_of_order_dropped`、`_test_death_reset_race` |
| 风险值不超过 100% | `_set_risk` 统一 `clampf(0, 100)`，网络入口同样夹 | `_test_risk_clamped_at_max` |
| 倒计时不出现负数 | 主机夹 + 客户端再夹 + delta 截断 + `_settled` 幂等 | `_test_relay_countdown_never_negative`、集成测试的负值计数 |
| 使用 reliable RPC 确保同步 | 所有一次性事件用 `reliable`；倒计时流也用 `reliable` | 见 §2.2 的通道表 |
| 清晰的中文注释 | 三个文件与集成层均为中文注释，含"为什么"而非只写"做什么" | — |
| 风险按 0.8%/s 上升 | `RISK_PER_SECOND_NO_SUPPORT * step` | `_test_risk_accumulation`（含 30/60/144 FPS 一致性） |
| 倒计时 8 秒后触发 | `RELAY_WINDOW = 8.0` + 超时判定 | `_test_relay_countdown_timeout` |

## 6. 测试与运行

```powershell
# 单元测试（77 项）
tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe `
  --headless --path game -s res://tests/resonance_mp_pressure.gd

# 关卡集成测试（26 项）
tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe `
  --headless --path game -s res://tests/resonance_mp_pressure_integration.gd
```

本次运行的观察结果：

| 测试 | 结果 |
| --- | --- |
| `resonance_mp_pressure.gd` | `RESONANCE_MP_PRESSURE: 77 checks, 0 failures` |
| `resonance_mp_pressure_integration.gd` | `RESONANCE_MP_PRESSURE_INTEGRATION: 26 checks, 0 failures` |
| `resonance_cave_chapter_test.gd`（回归） | `CAVE_CHAPTER: 147 checks, 0 failures` |
| `lint_project.py game` | 新增文件 0 error 0 warning |

### 已知的既有问题（与本次改动无关）

- `resonance_stage.gd` 与 `resonance_coop_relay.gd` 这一组测试在**本次改动之前就已失败**：场景实际挂的是 `resonance_cave_chapter.gd`，旧工厂流程的 `modules` 为空，`resonance_coop_relay.gd:42` 取 `modules[0]` 越界。已用 `git stash` 对比运行确认基线一致。
- `resonance_cave_chapter_test.gd` 需要先 `--import` 重建类缓存（工作区里有未提交的 `calibration_*.gd`），否则报 `Could not find type "CalibrationUI"`。

## 7. 数值状态标记

| 内容 | 标记 |
| --- | --- |
| 0.8%/s、50%、80%、25、8 秒、20%、2 秒播报 | `已确认方向`（需求给定，锁定不改） |
| 伤害 25 百分制 → 角色生命值折算取 `ceil(25/100 × 5) = 2` 点（最少 2 点） | `待讨论建议`：当前 `SpacePlayer3D.MAX_HEALTH` 只有 5，25% 折算成 1.25 点；代码里用 `MIN_DAMAGE_HEALTH = 2` 取上整。若策划希望压力更轻，改这一个常量即可 |
| 风险不自然衰减（`RISK_DECAY_PER_SECOND = 0`） | `设计假设`：原始规则只有"高位接力"能清零。若希望低位停止操作后缓慢回血式下降，改该常量 |
| 10 Hz 状态推送、0.1 秒倒计时推送 | `待讨论建议`：帧率无关的取值，可按带宽实测调整 |
| 低位判定为"当前模块 docking + fast 路线 + 有操作者"（旧工厂）/ "回廊入口中继已启动"（洞穴章节） | `设计假设`：把"低位操作快线"翻译成现有关卡事实的映射方式，需试玩确认手感 |

## 8. 未覆盖 / 下一步

- **真实双进程网络验证**未做：本次所有测试都是单进程内驱动，RPC 走 `OfflineMultiplayerPeer` 的本地分发（`authority_enabled` 与 revision 过滤的逻辑验证成立，但真实 ENet 丢包与重排下的表现需要 `iteration_network_smoke.gd` 一类的双进程测试补上）。
- **HUD 视觉**未接入：集成层提供了 7 个 HUD 钩子，但没有新增 HUD 节点。现有 `resonance_cave_feedback.gd` 已有一套机关反馈层，风险条与倒计时条应当并进去，而不是另起一套。
- **`resonance_stage.gd` 旧工厂流程**的接线已完成，但它当前不是实际运行的章节；若后续切回工厂流程，接线可直接生效。
- 音效未接入：需求示意里的 `audio_alert_warning` / `audio_beep_fast` 等在项目里没有对应资源，表现统一走 `show_feedback_rpc` 与震屏。若要做提示音，建议先在 `game/assets/audio/` 补齐音源再挂到集成层的信号上。
