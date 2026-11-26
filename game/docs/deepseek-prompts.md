# 3 个 DeepSeek 并行任务提示词

复制粘贴到 3 个不同的 DeepSeek 窗口。

---

## 窗口 1：多人协作系统

```
你是共振星游戏的网络逻辑工程师。任务是实现完整的多人协作系统。

## 背景

共振星是一个 3D 多人协作关卡。核心的多人压力机制：
- **低位玩家** 在操作快线模块时，如果**高位队友没有及时完成接力**，风险会不断上升
- **高位玩家** 有一个明确的 **8 秒倒计时** 去完成支援接力
- 如果时间到了，低位玩家受伤，风险重置，可以重试
- 如果任何玩家死亡，全队回到最后的检查点

这三个系统必须完美同步，否则多人体验会崩溃。

## 需要实现的 3 个类

### 1. LowPositionRiskSystem

```gdscript
class_name LowPositionRiskSystem
extends Node

# 参数（锁定不改）
const RISK_PER_SECOND_NO_SUPPORT = 0.8  # 每秒 +0.8%
const RISK_THRESHOLD_WARNING = 50.0     # 50% 时警告
const RISK_THRESHOLD_CRITICAL = 80.0    # 80% 时受伤
const DAMAGE_ON_CRITICAL = 25            # 受伤 25 HP

var risk_level: float = 0.0
var is_low_player_operating: bool = false
var is_high_player_relaying: bool = false
var warned_once: bool = false

func _process(delta):
    # 核心逻辑
    if is_low_player_operating and not is_high_player_relaying:
        risk_level += RISK_PER_SECOND_NO_SUPPORT * delta
    
    if is_high_player_relaying:
        risk_level = 0.0
    
    # 50% 时警告
    if risk_level >= RISK_THRESHOLD_WARNING and not warned_once:
        on_risk_warning()
        warned_once = true
    
    # 80% 时受伤
    if risk_level >= RISK_THRESHOLD_CRITICAL:
        on_risk_critical()

func on_risk_warning():
    rpc("sync_risk_warning", risk_level)
    hud.show_warning("低位快线过载！高位接力迫在眉睫！")
    audio_alert_warning.play()

func on_risk_critical():
    rpc("damage_low_player", DAMAGE_ON_CRITICAL)
    risk_level = 0.0
    warned_once = false
    rpc("announce_risk_critical")

@rpc("reliable")
func sync_risk_warning(new_risk: float):
    risk_level = new_risk
    hud.update_risk_display(risk_level)

@rpc("reliable")
func announce_risk_critical():
    hud.show_critical_warning("低位快线过载！")
    screen_shake(1.2)
    audio_alert_critical.play()
```

### 2. HighPositionRelaySystem

```gdscript
class_name HighPositionRelaySystem
extends Node

# 参数
const RELAY_WINDOW = 8.0           # 接力窗口 8 秒
const DAMAGE_ON_TIMEOUT = 25        # 超时时受伤 25 HP
const LOW_RISK_PENALTY = 20.0       # 连带低位风险 +20%

var countdown: float = RELAY_WINDOW
var is_relay_active: bool = false
var sync_counter: int = 0

func _process(delta):
    if is_relay_active:
        countdown -= delta
        
        # 每 0.1 秒同步一次（60 FPS 下约 6 帧）
        sync_counter += 1
        if sync_counter >= 6:
            rpc("sync_relay_countdown", countdown)
            sync_counter = 0
        
        if countdown <= 0:
            on_relay_timeout()

func start_relay():
    is_relay_active = true
    countdown = RELAY_WINDOW

func on_relay_complete():
    is_relay_active = false
    countdown = RELAY_WINDOW
    rpc("announce_relay_complete")

func on_relay_timeout():
    is_relay_active = false
    rpc("damage_high_player", DAMAGE_ON_TIMEOUT)
    rpc("increment_low_risk", LOW_RISK_PENALTY)
    reset_relay()

@rpc("unreliable")
func sync_relay_countdown(remaining: float):
    hud.show_relay_countdown(remaining)
    if remaining <= 3:
        hud.set_countdown_color(Color.RED)
        audio_beep_fast.play()

@rpc("reliable")
func announce_relay_complete():
    hud.show_relay_success("接力完成！")
    audio_relay_success.play()
```

### 3. MultiplayerDeathSystem

```gdscript
class_name MultiplayerDeathSystem
extends Node

func on_player_death(player_id: int):
    # 全队重启
    rpc("announce_team_death", player_id)
    await get_tree().create_timer(2.0).timeout
    rpc("reset_all_players_to_checkpoint")
    reset_low_position_risk()
    reset_high_position_relay()
    reset_module_progress()

@rpc("reliable")
func announce_team_death(player_id: int):
    hud.show_death_banner(f"玩家 {player_id} 阵亡！全队返回...")
    screen_flash(Color.RED, 0.5)

@rpc("reliable")
func reset_all_players_to_checkpoint():
    for player in get_players():
        player.global_position = last_checkpoint_position
        player.health = player.max_health
```

## 需要交付

1. **3 个完整的 .gd 文件**
   - low_position_risk_system.gd
   - high_position_relay_system.gd
   - multiplayer_death_system.gd

2. **集成代码片段**（如何在 resonance_stage.gd 中使用）

3. **单元测试代码**（可选但推荐）
   - 验证风险是否按 0.8%/s 上升
   - 验证倒计时是否在 8 秒后触发

4. **文档**（说明代码逻辑）

## 代码要求

- [ ] 没有竞态条件（RPC 顺序正确）
- [ ] 风险值不超过 100%
- [ ] 倒计时不出现负数
- [ ] 使用 reliable RPC 确保同步
- [ ] 清晰的中文注释

## 质量标准

这是共振星的**心脏**。多人协作体验全靠这个系统。

完成后，给出 4 个文件：代码 + 集成 + 测试 + 文档。
```

---

## 窗口 2：故事音频系统

```
你是共振星游戏的音频工程师。任务是生成 4 条中文语音日志并混音处理。

## 4 条日志的完整文本

### 日志 1：设施介绍
讲述者：Marcus Chen（工程主管，沙哑疲倦的中年男性）

```
这是...共振能源站的核心区域。
[停顿 0.5s]
三条热阀链连接了地下的地热循环系统。
当年我们建立这个设施，就是为了给舰队源源不断地提供能量。
[停顿 1s]
一千艘战舰，都靠这儿活着。
现在...只有冻结的反应堆，和这些被遗忘的机械。
[停顿 0.5s]
也许...有朝一日，会有人来重启它。
```

### 日志 2：事故背景
讲述者：Alex Kim（年轻技术员，焦急的声音）

```
[背景警报声持续]
所有人听着！所有人听着！
指挥官刚下达了冻结命令。
[停顿 0.3s]
核心能量读数超过安全值 340%，温度在上升。
如果不立即隔离，整个设施会...会...
[声音变得急促]
我们把备用能源核心搬到了深层接收座。
已经封存，已经锁定。
[停顿 0.5s]
希望有朝一日，有人能来重启它。
也许...也许那才是真正的救赎。
```

### 日志 3：最后希望
讲述者：Marcus Chen（生命垂危，虚弱的声音）

```
[咳嗽声]
如果...如果你听到这个录音，说明你已经找到了。
[停顿 1s，呼吸声]
你拿起了那个核心。
[停顿，虚弱的笑声]
我已经...等不到这一天了。
但...也许你能做到。
[停顿 1.5s]
出去吧。带着它离开这个地方。
找到能利用它的人。
[最后停顿，声音渐弱]
这是...我们最后的...希望。
```

### 日志 4：秘密通讯（隐藏）
讲述者：Alex Kim（备用频道旧录音，极其微弱扭曲）

```
[录音底噪，非常弱]
...这是...备用频道...
[停顿，咳嗽]
如果你们能听到这个，说明...
你们不仅找到了核心，还找到了我的...指引。
[停顿，声音略微清晰]
共振站...不是为了供能。
我们被派来这儿，是为了...监听。
监听某些...不该存在的东西。
[停顿，声音更急促]
那次爆炸...不是意外。
是...他们下令的。
[最后停顿，声音几乎消失]
如果你们看到这个日记...
就意味着...一切还没结束。
```

## TTS 参数（必须遵守）

| 日志 | 语言 | 音色描述 | 速度 | 稳定度 | 相似度 | 背景音 | 目标时长 |
|------|------|---------|------|--------|--------|--------|---------|
| 1 | 中文 | 沙哑、疲倦、中年男性 | 0.9x | 0.4 | 0.7 | 机器低频 -20dB | ~18s |
| 2 | 中文 | 焦急、年轻、紧张 | 1.1x | 0.6 | 0.8 | 警报 -15dB + 噪声 -18dB | ~21s |
| 3 | 中文 | 极其虚弱、即将死亡 | 0.85x | 0.3 | 0.65 | 微弱机器音 -25dB | ~17s |
| 4 | 中文 | 扭曲、破损的通讯频道 | 0.95x | 0.3 | 0.6 | 电流噪声 -22dB | ~22s |

## 方案选择（任选一个）

### 方案 A：ElevenLabs API（推荐）

如果有 ElevenLabs API 密钥，生成完整的 Python 脚本调用 API。

输出：`generate_voice_logs_elevenlabs.py`

### 方案 B：Azure 免费层

生成 Python 脚本调用 Azure Text-to-Speech。

输出：`generate_voice_logs_azure.py`

### 方案 C：Google Cloud TTS

生成 Python 脚本调用 Google Cloud API。

输出：`generate_voice_logs_google.py`

### 方案 D：手动步骤（如果没有 API）

给出详细的"哪个网站、什么参数、怎么下载"的步骤。

## 混音和导出

一旦有了 4 个 MP3 或 WAV 文件，生成 FFmpeg 或 Audacity 脚本进行混音：

```bash
# 伪代码示意
ffmpeg -i log_1.mp3 -i ambient_machine_hum.wav \
  -filter_complex "[0]volume=0.85[v0];[1]volume=0.08[v1];[v0][v1]amix" \
  -c:a libvorbis -q:a 8 log_1_mixed.ogg
```

输出：`mix_voice_logs.sh` 或 `mix_voice_logs.py`

## 最终交付物

1. **4 个 OGG 音频文件**
   - res_log_1_intro.ogg（~18s）
   - res_log_2_accident.ogg（~21s）
   - res_log_3_core.ogg（~17s）
   - res_log_4_secret.ogg（~22s）

2. **生成脚本**（选 A/B/C/D 之一）

3. **混音脚本**

4. **文档**
   - 每个日志的实际时长
   - 使用的 TTS 参数
   - 背景音混音比例

## 质量标准

- [ ] 日志 1：沙哑、疲倦、有故事感
- [ ] 日志 2：焦急、紧张、有警告感  
- [ ] 日志 3：虚弱、接近死亡
- [ ] 日志 4：极其微弱、像是破损的备用频道
- [ ] 背景音不刺耳、不盖过人声
- [ ] 总时长 ≈ 78 秒

## 重要

这是共振星游戏的**核心故事层**。音频质量直接影响玩家的沉浸感。

完成后，给出所有生成脚本和最终的 4 个 OGG 文件。
```

---

## 窗口 3：校准小游戏系统

```
你是共振星游戏的交互设计工程师。任务是实现完整的校准小游戏系统。

## 背景

校准小游戏是共振星中最频繁的玩家交互。玩家需要在**光标进入绿区时按下按键**来完成校准。

4 种设备各有不同的难度，形成教学→中等→高→中高的梯度。

## 4 种校准的参数

| 设备 | 绿区宽度 | 光标速度 | 难度 | 音效 |
|------|---------|--------|------|------|
| 热阀 | 40% | 1.0x | 教学 | 热流"呼呼" |
| 电源端 | 30% | 1.3x | 中等 | 电流"滋滋" |
| 镜面节点 | 20% | 1.8x | 高 | 高频"嘟嘟" |
| 冷却座 | 25% | 1.5x | 中高 | 冷媒流动 |

## 需要实现

### 1. CalibrationMinigame 主类

完整的校准小游戏逻辑，包含：
- 难度参数表（4 种设备）
- 光标往返运动
- 成功/失败判定
- 视觉和音效反馈
- 重试逻辑

```gdscript
class_name CalibrationMinigame
extends Node

var difficulty_params = {
    "heat_valve": {
        "name": "热阀",
        "green_zone_width": 40,
        "cursor_speed": 1.0
    },
    "power_node": {
        "name": "电源端",
        "green_zone_width": 30,
        "cursor_speed": 1.3
    },
    "mirror_node": {
        "name": "镜面节点",
        "green_zone_width": 20,
        "cursor_speed": 1.8
    },
    "cooling_node": {
        "name": "冷却座",
        "green_zone_width": 25,
        "cursor_speed": 1.5
    }
}

var current_device: String = ""
var cursor_position: float = 0.0
var cursor_direction: float = 1.0
var calibration_active: bool = false
var retry_count: int = 0

signal calibration_complete
signal calibration_failed

# 核心方法：
# - start_calibration(device_type)
# - start_cursor_oscillation(params)
# - check_calibration_success(cursor_pos, params)
# - on_calibration_success(params)
# - on_calibration_fail(params)
```

### 2. 音效生成脚本

生成 12 个音频文件（4 种设备 × 3 个音效）：

**热阀音效：**
- calibration_heat_ambient.ogg — 热流"呼呼"（背景）
- calibration_heat_success.ogg — 成功音
- calibration_heat_fail.ogg — 失败音

**电源端音效：**
- calibration_power_ambient.ogg
- calibration_power_success.ogg
- calibration_power_fail.ogg

**镜面节点音效：**
- calibration_mirror_ambient.ogg
- calibration_mirror_success.ogg
- calibration_mirror_fail.ogg

**冷却座音效：**
- calibration_cool_ambient.ogg
- calibration_cool_success.ogg
- calibration_cool_fail.ogg

用 Audacity/Pure Data/Python 脚本生成。

输出：`generate_calibration_audio.py` 或类似

### 3. 粒子效果代码

实现 5 类交互事件的粒子效果：

```gdscript
class_name ParticleEffects
extends Node

# 必须实现：
func spawn_heat_valve_success(position: Vector3)
func spawn_power_success_particles(position: Vector3)
func spawn_mirror_success_beam(position: Vector3)
func spawn_calibration_fail_flash(position: Vector3)
func spawn_module_attachment_spray(position: Vector3)
```

## 集成要求

在 resonance_stage.gd 中调用：

```gdscript
var calibration_system: CalibrationMinigame

func _ready():
    calibration_system = CalibrationMinigame.new()
    add_child(calibration_system)
    calibration_system.calibration_complete.connect(_on_calibration_complete)
```

## 最终交付物

1. **CalibrationMinigame.gd**（完整实现）
2. **generate_calibration_audio.py**（音效生成脚本）
3. **particle_effects.gd**（粒子效果代码）
4. **calibration_ui.gd**（UI 绘制，如果需要）
5. **README**（使用说明）

## 质量标准

- [ ] 4 种难度的体验符合"教学→中等→高→中高"梯度
- [ ] 成功/失败的反馈明确
- [ ] 音效不刺耳、不混浊
- [ ] 粒子不遮挡玩家视线
- [ ] 重试逻辑清晰

## 重要

这是共振星的**手感系统**。直接影响玩家对整个关卡的满足感。

完成后，给出所有 5 个文件。
```

---

## 使用方式

1. **复制"窗口 1"的提示词** → 粘贴到第一个 DeepSeek 对话框
2. **复制"窗口 2"的提示词** → 粘贴到第二个 DeepSeek 对话框
3. **复制"窗口 3"的提示词** → 粘贴到第三个 DeepSeek 对话框

三个窗口会并行工作，预期 3-5 小时内完成所有代码。

我同时审查 3 个窗口的产出。