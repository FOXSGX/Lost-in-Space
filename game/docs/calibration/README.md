# 校准小游戏系统

当前版本：2026-10-29。本文记录共振星校准小游戏的手感参数、实现结构与验证方式。参数表数值来自用户本轮任务单，属于**已确认方向**；文中标注“待讨论建议”的部分尚未确定。

## 一句话说明

设备交互分两步：第一次按键开启校准，等于光标进入绿区时再按一次确认。4 种设备共用一套机制，只靠**绿区宽度**和**光标速度**拉出难度梯度，避免做成四种互不相干的玩法。

## 难度参数表（已确认方向）

| 设备 | 难度 | 绿区宽度 | 光标速度 | 单次容错窗口 | 形状 |
| --- | --- | --- | --- | --- | --- |
| 热阀 `heat_valve` | 教学 | 40% | 1.0x | 约 0.47 秒 | 计时条 |
| 电源端 `power_node` | 中等 | 30% | 1.3x | 约 0.27 秒 | 计时条 |
| 冷却座 `cooling_node` | 中高 | 25% | 1.5x | 约 0.20 秒 | 计时条 |
| 镜面节点 `mirror_node` | 高 | 20% | 1.8x | 约 0.13 秒 | 圆盘 / 步进 |

- 速度以 `CURSOR_UNITS_PER_SECOND = 0.85`（1.0x 时每秒扫过整条轨道的 85%）为基准，参数表里存的是倍率。
- **单次容错窗口** = 绿区宽度 ÷（倍率 × 0.85），是可以被玩家实际感受到的“反应时间”。教学设备 0.47 秒、高难度 0.13 秒，这是梯度成立的关键：只改宽度不改速度，宽度差距会被高速光标放大到不合理的程度。
- 高难度不能低于 0.12 秒。低于这个值玩家会认为“按了也没用”，而不是“我没按准”。

## 手感规则

- **光标往返**：位置 0…1，触到两端折返。`bar` / `dial` 两种形状光标自动移动；`stepped` 形状光标不动，每次按键转 1/12 圈（30°），落进绿区自动锁定，HUD 显示当前角度。步进形状是 2026-10-17 确认的镜面专用设计，本轮保留。
- **绿区不贴边**：随机取绿区起点时左右各留 10% 余量。步进形状额外把起点推出 2 格（60°），否则“一按就中”，步进没有意义。
- **判定**：`check_calibration_success` 支持绿区跨过 1.0 的绕回（`zone_start + width > 1` 时拆成头尾两段），避免边界情况被误判为失败。
- **超时**：每台设备有 7.5—9 秒的总时长，超时按失败结算，不推进任何玩法状态。
- **重试**：
  - 第 1 次失败：提示“偏差过大 · 重新对准”，绿区不变。
  - 第 2 次失败：再次开启时绿区放宽 35%，HUD 绿区变亮、提示文字追加“已放宽绿区”。
  - 第 3 次失败：标记 `aborted`，提示“设备已复位，休息一下再试”，避免玩家在同一台设备上无限撞墙。
  - 成功即清零；换一台设备也清零（辅助只针对“同一台设备一直失败”，不跨设备继承）。
  - 时长下限 0.4 秒。压力应该来自绿区宽度和光标速度，不能来自“看起来像 bug 的秒表”。

## 反馈

- **成功**：设备音效（热流涌出 / 电流接通 / 反射锁定 / 冷媒锁定）+ 对应粒子（热汽 / 电火花 / 细光柱 / 冷色喷流）+ HUD 绿色闪示 + 文案“XX 校准成功 · …”。
- **失败**：低沉钝音 + 橙红短闪 + 文案说明偏差方向；失败不复用成功色，玩家一眼能分清。
- **持续提示**：HUD 每帧显示设备名、剩余秒数、操作提示（“光标进绿区按 E”/“指针进绿弧按 E”/“按 E 转动”）、已失败次数和底部三格重试指示。
- **装置可动部件**：校准期间在装置朝向玩家的一侧生成实体拉杆，把手随光标角度转动；成功摆到开启位、失败回到关闭位后消失。

## 音效（12 个文件）

`game/assets/audio/calibration/` 下 4 种设备各 3 个：

- `calibration_<device>_ambient.ogg`：3.65 秒无缝循环，实时长 4.0 秒生成后交叉淡回，首尾 4 ms 落零。峰值 −14 dBFS，只作底噪。
- `calibration_<device>_success.ogg`：0.5—0.62 秒，上行音型。
- `calibration_<device>_fail.ogg`：0.36—0.42 秒，下行钝音。

不刺耳的工程约束：

- 全链路 20 Hz 高通去直流；起音 ≥ 8 ms、收尾 ≥ 10 ms 淡出，所以触发不会有“咔”。
- 环境音用一阶低通把噪声压在 520 Hz 以下（电流声保留 60/120/180 Hz 嗡鸣，镜面提示限制在 1.3 kHz 单音），避免长时间播放刺耳。
- 成功音刻意压低高次泛音，失败音以 74—210 Hz 为主体。
- 生成脚本 `game/tools/generate_calibration_audio.py`，纯 numpy + ffmpeg（libvorbis），可复现；同时写 `calibration_audio_report.json`，每个文件带 `expect`，可直接喂给 `inspect_audio` 复核。

## 粒子（5 类事件）

`game/scripts/particle_effects.gd`：

| 方法 | 事件 | 特征 |
| --- | --- | --- |
| `spawn_heat_valve_success` | 热阀成功 | 暖橙热汽上升，0.9 秒，非加色（更“汽”而不“亮”） |
| `spawn_power_success_particles` | 电源端成功 | 青白电火花四散，0.5 秒 |
| `spawn_mirror_success_beam` | 镜面对准 | 直径 0.1 米细光柱 + 高光，0.45 秒 |
| `spawn_calibration_fail_flash` | 校准失败 | 橙红环形短闪，0.36 秒 |
| `spawn_module_attachment_spray` | 模块/冷却座接入 | 冷色喷流，0.7 秒 |

不遮挡视线的约束：

- 粒子尺寸 0.06—0.16 米，单个特效 ≤ 48 个粒子，同时存活特效 ≤ 20 个，超限丢弃最旧的。
- 一律短命（0.35—0.9 秒），播完自动回收；`finished` 之外还有超时兜底，低帧率下也不会残留。
- 镜面光柱只有 0.1 米粗、2.4 米高，只标注“这台设备对上了”，不做全屏耀光。
- 保留深度测试，粒子会被墙面和设备挡住，不会浮在镜头前。

## 实现结构

| 文件 | 职责 |
| --- | --- |
| `game/scripts/calibration_minigame.gd` | 手感内核：难度表、光标、判定、重试、音效、粒子触发。不持有联网权威。 |
| `game/scripts/calibration_ui.gd` | HUD 绘制（bar / dial / stepped）、重试指示、成功失败闪示。只读 state，不做判定。 |
| `game/scripts/particle_effects.gd` | 5 类事件粒子。 |
| `game/tools/generate_calibration_audio.py` | 生成 12 个音效。 |
| `game/tests/calibration_minigame.gd` | 手感内核单测（104 项）。 |
| `game/tests/calibration_integration.gd` | 阶段接入测试（30 项）。 |

`resonance_stage.gd` 的接入点：

```gdscript
func setup(owner: Main3D) -> void:
    controller = owner
    name = "ResonanceStage"
    _setup_coop_pressure()
    _setup_calibration()          # 创建 CalibrationMinigame + ParticleEffects 并互相注入

# 开启校准时
calibration_system.start_calibration(device_id, overrides)
# 每帧
calibration_system.set_cursor(minigame["cursor"])
calibration_system.tick(delta)
# 确认
calibration_system.confirm()
# 结算
calibration_system.calibration_complete.connect(_on_calibration_complete)
calibration_system.calibration_failed.connect(_on_calibration_failed)
```

`minigame` 字典仍是阶段层的帧间缓存和对外接口（测试、网络快照、HUD 都读它），字段来自 `calibration_system.current_state()`，因此“测试直接改 `stage.minigame["cursor"]`”这种既有做法继续有效。

关卡层只保留“这台设备走哪种形状、叫什么标题”的映射（`_minigame_profile`），绿区宽度和速度一律来自难度表，不再两处各写一份。

## 与实时场景的关系（重要）

实时场景 `game/scenes/resonance_stage.tscn` 当前挂的是 `resonance_cave_chapter.gd`（洞穴章节，继承 `ResonanceStage3D`），它覆写了 `get_stage_action_target` / `handle_stage_action`，走自己的 `cave:*` 目标。本轮接入点在**轨道工厂阶段 `resonance_stage.gd`**，用 `resonance_stage_legacy.tscn` 驱动并通过 30 项集成检查。

**待讨论建议**：洞穴章节目前仍是“靠近按 E”。要把校准小游戏铺到实时流程，需要在洞穴章节的 `_manual_cave_objective` / `_solve_cave_objective` 前加一层校准门（复用 `CalibrationMinigame`，把 `cave:<kind>` 映射到四种设备参数），这属于对团队现有文件的改动，需先确认。

## 验证

```powershell
# 手感内核（难度梯度、判定、重试、超时、步进、HUD、粒子）
tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/calibration_minigame.gd
# 阶段接入（开启/失败/成功/超时/三种形状/粒子清理）
tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/calibration_integration.gd
# 音效复核（12 个文件的时长、峰值、循环接缝）
tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game \
  --script <godot-skill>/scripts/core/dispatcher.gd inspect_audio \
  '{"audio_paths":["assets/audio/calibration"],"format":"text","envelope":false,"expect":{"not_silent":true,"no_clipping":true,"loopable":true}}'
```

实测结果：`CALIBRATION_MINIGAME: 104 checks, 0 failures`、`CALIBRATION_INTEGRATION: 30 checks, 0 failures`、12 个音效全部 `loopable PASS`（环境音接缝 ≤ 0.0013）。
