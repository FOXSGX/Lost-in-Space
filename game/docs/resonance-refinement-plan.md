# 共振星精良化方案（全 AI 工作流）

## 一、故事与叙事深化

### 1.1 共振星的场景背景
目前缺失的核心问题：玩家不知道**为什么在这儿**、**为什么要做这些**。

**设计方向：** 工业废墟的"最后希望"
- 共振星是**废弃的能源提炼站**，曾经为整个星际舰队供能
- 反应堆因某个事故**被人为冻结**了（这会成为后续故事的悬念点）
- 你的队伍接收到"核心能源信号"，需要在熔岩侵蚀前重启一份备用核心
- 时间紧迫：熔岩潮汐每 45 秒上升一次（现有机制），这不只是难度，而是**物理的倒计时**

**AI 工作流：**
```
1. 用 Claude 生成 3-5 条"现场遗留的语音日志"（工程师/管理者的记录）
   - 日志 1：设施何时建立、用途是什么
   - 日志 2：事故发生的原因（引入悬念）
   - 日志 3：为什么能源核心被封存
   
2. 日志用 TTS（Azure/Google/ElevenLabs）合成语音
   - 背景应该很 sci-fi：电子底纹 + 微弱的机器音
   - 质量标准：不能是"机器人"感，要有某种"疲惫感"

3. 日志触发时机：玩家第一次靠近关键地点时
   - 靠近热阀链 → 日志 1（设施介绍）
   - 靠近反应堆塔 → 日志 2（事故背景）
   - 拿起核心 → 日志 3（任务意义）
```

### 1.2 多人互动的"对话时刻"
核心搬运段需要**社交压力**和**信息同步**。

**设计：** 在核心搬运阶段，队伍需要"集体决策"
- 核心拿起时，系统显示"核心温度：145°C → 接收座温度：120°C 不匹配"
- 需要一个队友去调节冷却参数，其他人继续搬运
- 调节时有**实时数字同步**（屏幕显示"队友名 正在调节冷却系统..."）
- 这形成了"信息共享→决策分工→时间压力"的互动

**Godot 实现（玩法层）：**
```gdscript
# 核心搬运时的并行任务
class CoreTransportLogic:
    var core_temperature: float = 145.0
    var receiver_temperature: float = 120.0
    var temperature_matched: bool = false
    
    # 检测是否需要冷却调节
    func should_require_cooling() -> bool:
        return abs(core_temperature - receiver_temperature) > 15.0
    
    # 冷却参数的实时同步（RPC）
    @rpc("reliable")
    func sync_cooling_adjustment(player_id: int, adjustment: float):
        # 调节冷却流量
        receiver_temperature += adjustment * 0.8  # 延迟效应
        
    # 广播"某队友在调节"
    @rpc("reliable")
    func announce_cooling_in_progress(player_name: String):
        hud.show_status(f"{player_name} 正在调节冷却系统...")
```

---

## 二、玩法精良化

### 2.1 校准小游戏的完整反馈链

现在的问题：校准条存在，但反馈很"干"。需要完整的**感觉反馈**。

**设计维度（每个设备不同）：**

| 设备 | 绿区宽度 | 光标速度 | 反馈音效 | 视觉演出 |
|------|---------|--------|--------|--------|
| 热阀 | 40% | 1.0x | 热流"呼呼"音 | 绿区闪烁，边界红光 |
| 模块电源端 | 30% | 1.3x | 电流"滋滋"音 | 光标轨迹发光 |
| 镜面节点 | 20% | 1.8x | 高频"嘟嘟"音 | 精准时的星星粒子 |
| 冷却座 | 25% | 1.5x | 冷媒流动音 | 蓝色寒雾环绕 |

**AI 工作流：**
```
1. 用 Claude Sonnet 生成校准小游戏的完整规范
   - 每个设备的音效描述（用 Sonic Pi / Pure Data 可合成）
   - 每个难度的参数曲线
   - 失败/成功时的动画关键帧

2. 音效生成（用 Replicate 的 Bark / MusicGen）
   - "热流呼呼声"可以用频率扫描合成
   - "电流滋滋音"可以用白噪声 + 谐波生成
   - "冷媒流动"可以用低频段合成

3. 粒子效果代码（Claude 生成 GDScript）
   - 绿区闪烁的 Tween 动画
   - 成功时的星星粒子飞出
   - 失败时的红光脉冲
```

**GDScript 框架（由 Claude 生成）：**
```gdscript
class MinigameCalibration:
    var difficulty: int  # 0=热阀(宽) 1=电源(中) 2=镜面(窄) 3=冷却(中)
    var cursor_position: float = 0.0
    var cursor_speed: float = [1.0, 1.3, 1.8, 1.5][difficulty]
    var success_zone_width: float = [40, 30, 20, 25][difficulty]
    
    func _ready():
        play_ambient_sound()  # 对应设备的环境音
        create_visual_feedback()
    
    func _process(delta):
        # 光标往返运动
        cursor_position += cursor_speed * delta * 60
        if cursor_position > 100:
            cursor_position = 100
            cursor_speed *= -1
        if cursor_position < 0:
            cursor_position = 0
            cursor_speed *= -1
        
        update_cursor_visual()
        check_input_window()
    
    func check_input_window():
        var success_start = (100 - success_zone_width) / 2
        var success_end = success_start + success_zone_width
        
        if Input.is_action_just_pressed("ui_accept"):
            if success_start <= cursor_position <= success_end:
                on_calibration_success()
            else:
                on_calibration_fail()
    
    func on_calibration_success():
        # 播放成功音效
        audio_success.play()
        # 生成粒子
        particle_burst(cursor_position, Color.GREEN)
        # 屏幕闪烁
        screen_flash(Color.GREEN, 0.2)
        emit_signal("calibration_complete")
    
    func on_calibration_fail():
        # 播放失败音效
        audio_fail.play()
        # 红光脉冲
        screen_flash(Color.RED, 0.15)
        # 重置（不清除UI，让玩家重试）
        cursor_position = 0.0
        cursor_speed = abs(cursor_speed)
```

### 2.2 多人协作时的"优先级冲突"

现在的架构是"单一链路"：热阀 → 模块 → 反应堆 → 核心。

改进：引入**平行但互相影响的目标**

**设计（第二节及以后）：**
- 低位快线选择 + 磁力货箱 操作由玩家 A 进行
- 同时，高位维护桥需要玩家 B 做"支援接力"
- 如果 B 没在规定时间内完成，A 的"快线过载"风险上升
- 反应堆升降接力时，平台上升速度决定了冷却参数调节的难度

```gdscript
# 并行约束系统
class ResonanceParallelTasks:
    var low_position_risk: float = 0.0  # 快线过载百分比
    var high_position_cooldown: float = SUPPORT_RELAY_WINDOW  # 倒计时
    
    func _process(delta):
        # 低位玩家操作时，如果高位支援没跟上，风险上升
        if is_low_player_operating and not is_high_player_relaying:
            low_position_risk += delta * 0.15
        
        # 高位玩家完成接力后，风险重置
        if is_high_player_relaying:
            high_position_cooldown -= delta
            low_position_risk = 0.0
        
        # 风险过高 → 低位玩家受伤
        if low_position_risk > 100:
            damage_low_player(20)
            low_position_risk = 0  # 重置
    
    func announce_risk_to_team():
        if low_position_risk > 50:
            hud.show_warning(f"低位快线过载！高位接力迫在眉睫")
            # 播放警告音
            audio_alert.play()
```

这样，玩家不只是"等待别人完成"，而是**感受到时间压力**和**互相依赖**。

---

## 三、美术与视觉演出精良化

### 3.1 Blender 美术资产的增强

现在你已经用 Blender 生成 GLB 了，可以进一步：

**增强方向：**
1. **材质细节** — 现在可能是标准的工业纹理，可以加入：
   - 发光度变化（热阀发热时泛红光）
   - 污垢/磨损贴图（增加沧桑感）
   - 动画纹理（热阀的流体流动、反应堆的核心发光脉冲）

2. **动画绑定** — 用 AI 生成 Blender 动画脚本
   - 热阀开启时的机械转动
   - 模块对接时的气压释放粒子
   - 核心被拿起时的悬浮态转换

**AI 工作流（用 Claude + Blender Python API）：**
```python
# Blender 脚本（由 Claude 生成）
import bpy

def create_heat_valve_animation():
    """生成热阀开启的旋转动画"""
    valve_obj = bpy.data.objects.get("heat_valve_main")
    
    # 关键帧：0-120 帧
    for frame in range(0, 120):
        bpy.context.scene.frame_set(frame)
        
        # 旋转角度随帧增加
        rotation = frame / 120 * 3.14159  # 半周旋转
        valve_obj.rotation_z = rotation
        valve_obj.keyframe_insert(data_path="rotation_euler", index=2)
    
    return valve_obj.animation_data.action

def create_core_energy_glow():
    """核心拿起时的发光脉冲"""
    core_obj = bpy.data.objects.get("energy_core")
    emission_material = core_obj.material_slots[0].material
    
    # 发光强度脉冲：0-60-0
    for frame in range(0, 60):
        bpy.context.scene.frame_set(frame)
        
        # 脉冲曲线
        intensity = abs(sin(frame / 60 * 3.14159)) * 3.0
        emission_material.node_tree.nodes["Emission"].inputs[1].default_value = intensity
        emission_material.node_tree.nodes["Emission"].inputs[1].keyframe_insert()

# 在 Godot 导出时调用
if __name__ == "__main__":
    create_heat_valve_animation()
    create_core_energy_glow()
    bpy.ops.export_scene.gltf(filepath="resonance_factory_assets.glb")
```

**Godot 端接收这些动画：**
```gdscript
# 热阀开启时触发动画
func activate_heat_valve(valve_index: int):
    var valve_node = valve_nodes[valve_index]
    var animation_player = valve_node.get_child(0) as AnimationPlayer
    animation_player.play("valve_open")
    
    # 同时播放音效
    audio_valve_open.play()
```

### 3.2 粒子效果的精雕细琢

每个交互都应该有**微观反馈**。

**粒子方案：**
| 事件 | 粒子类型 | 颜色 | 生命周期 | 触发条件 |
|------|--------|------|--------|--------|
| 热阀开启 | 热气上升 | 橙→透明 | 1.2s | 校准成功 |
| 模块对接 | 气体喷射 | 白→淡蓝 | 0.8s | 对接夹具就位 |
| 核心悬浮 | 能量环绕 | 青蓝发光 | 持续 | 核心被拿起中 |
| 镜面对齐 | 反射光束 | 彩虹渐变 | 0.5s | 镜面校准成功 |
| 坠入熔岩 | 烈焰飞溅 | 红→黑 | 1.5s | 玩家死亡 |

**GDScript 生成器（由 Claude 生成）：**
```gdscript
class ParticleEffectGenerator:
    static func spawn_heat_valve_effect(position: Vector3):
        var particles = GPUParticles3D.new()
        var material = ParticleProcessMaterial.new()
        
        material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
        material.emission_sphere_radius = 0.5
        material.initial_velocity_min = 2.0
        material.initial_velocity_max = 4.0
        material.gravity = Vector3(0, 2.5, 0)  # 热气上升
        material.lifetime = 1.2
        
        # 颜色：橙色 → 透明
        var gradient = Gradient.new()
        gradient.add_point(0.0, Color.ORANGE)
        gradient.add_point(1.0, Color(1, 1, 1, 0))
        material.color_ramp = gradient
        
        particles.process_material = material
        particles.global_position = position
        particles.emitting = true
        
        return particles
    
    static func spawn_core_energy_aura(position: Vector3):
        var particles = GPUParticles3D.new()
        var material = ParticleProcessMaterial.new()
        
        material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
        material.emission_ring_radius = 1.0
        material.emission_ring_height = 0.1
        material.lifetime = 2.0  # 核心持续发光
        
        # 青蓝色环绕
        var gradient = Gradient.new()
        gradient.add_point(0.0, Color.CYAN)
        gradient.add_point(0.5, Color.CYAN * Color(1, 1, 1, 0.5))
        gradient.add_point(1.0, Color.CYAN * Color(1, 1, 1, 0))
        material.color_ramp = gradient
        
        particles.process_material = material
        particles.global_position = position
        particles.emitting = true
        
        return particles
```

---

## 四、音景设计（声音环境的精良化）

### 4.1 分层音景

共振星应该有**持续的声音环境**，不只是"事件音效"。

**音景分层（用 AI TTS + 音频合成）：**

1. **基础环境层** — 低频持续音（工业设施的低频嗡鸣）
   - 频率：40-60 Hz
   - 强度：-18dB（不压低对话）
   - 源：Audacity / Pure Data 合成

2. **机械工作层** — 中频的机械音
   - 热阀运转：周期性的"咔咔"声（400-600 Hz）
   - 液压系统：脉冲的"呼呼"声
   - 冷却循环：流水般的"沙沙"声

3. **风险警告层** — 高频的实时警告
   - 熔岩上升时：低沉的"轰隆"声
   - 快线过载：高频的"嘟嘟嘟"警告
   - 紧急情况：脉冲的警报音

**实现工作流：**
```bash
# 1. 生成基础环保层
# 用 Pure Data 或 Audacity 的脚本生成工业低频背景
# 输出：resonance_ambient_base.wav (loop)

# 2. 生成机械音效
# 热阀音：440Hz 正弦波 + 脉冲包络
ffmpeg -f lavfi -i "sine=f=440:d=0.3" -af "aecho=0.8:0.9:500:0.8" valve_mechanism.wav

# 3. 合成所有层
# 在 Godot 用 AudioStreamPlayer 分层播放
```

**Godot 实现：**
```gdscript
class ResonanceAudioscape:
    var ambient_player: AudioStreamPlayer
    var mechanical_player: AudioStreamPlayer
    var warning_player: AudioStreamPlayer
    
    func _ready():
        # 持续播放基础环保
        ambient_player.stream = load("res://assets/resonance/audio/ambient_base.ogg")
        ambient_player.bus = "Ambient"
        ambient_player.play()
        
        # 机械层可随时启动/停止
        mechanical_player.bus = "Mechanical"
        
        # 警告层等待事件触发
        warning_player.bus = "Warning"
    
    func trigger_heat_valve_sound():
        mechanical_player.stream = load("res://assets/resonance/audio/valve_open.ogg")
        mechanical_player.play()
    
    func trigger_lava_warning():
        warning_player.stream = load("res://assets/resonance/audio/alert_warning.ogg")
        warning_player.play()
```

### 4.2 语音日志与叙事音景

玩家通过**现场录音日志**理解背景。

**日志设计（由 Claude 写文本，用 ElevenLabs/Bark TTS 合成）：**

```
日志 1【设施介绍】— 靠近热阀链时触发
播放者：已故的工程主管（沙哑、沧桑）
"...这是共振能源站的核心区域。三条热阀链连接了地下的地热循环系统。
当年我们建立这个设施，就是为了给舰队源源不断地提供能量。
现在...只有这个被冻结的反应堆还在，等待着...重启。"

日志 2【事故背景】— 靠近反应堆塔时触发
播放者：不同的声音（年轻、焦急）
"所有人听着！指挥官下达了冻结命令。核心能量太不稳定了，
如果不立即隔离，整个设施可能会...
我们把备用核心封存到了深层接收座。
希望有朝一日，有人能来重启它。"

日志 3【最后希望】— 拿起核心时触发
播放者：第一个声音，更虚弱了
"如果你听到这个录音，说明你已经拿到了核心。
出去吧。带着它离开这个地方。
也许...这就是我们的最后希望。"
```

**AI 工作流：**
```
1. 用 Claude 写日志文本（中英文均可）
2. 用 ElevenLabs API 合成语音
   - 角色 1 的音色：older male, gravelly (工程主管)
   - 角色 2 的音色：young male, urgent (年轻技术员)
   - 背景音：微弱的机器嗡鸣 + 电子底纹

3. 用 Audacity/FFmpeg 混音
   - 日志音量：-6dB（可清晰听见但不刺耳）
   - 背景环保：-18dB（衬托日志）

4. 导入 Godot，设置触发条件
```

---

## 五、技术实现检查清单

### 5.1 玩法精良化
- [ ] 校准小游戏：完整音效反馈（热/电/冷/镜各有专属音）
- [ ] 校准小游戏：成功/失败的视觉演出（粒子、屏幕闪烁）
- [ ] 多人协作：低位快线风险实时同步到高位队友
- [ ] 多人协作：倒计时与紧张感音效（接近截止时播放警告音）
- [ ] 熔岩潮汐：视觉表现与声音反馈（上升时有"轰隆"声）

### 5.2 美术精良化
- [ ] Blender 脚本：热阀开启动画 + GLB 导出
- [ ] Blender 脚本：核心拿起时的发光脉冲动画
- [ ] Blender 脚本：模块对接时的气体喷射
- [ ] Godot 粒子：5 类主要交互事件的粒子效果
- [ ] Godot 渲染：确保镜头不透明淡出（已有规范）

### 5.3 音景精良化
- [ ] 生成基础环保层（工业低频嗡鸣）
- [ ] 生成机械层（热阀、液压、冷却各 3 段音效）
- [ ] 生成警告层（过载、紧急、死亡各 2 段音效）
- [ ] 合成 3 条语音日志（角色、背景、音量平衡）
- [ ] 在 Godot 实现分层音景管理器

### 5.4 叙事与交互
- [ ] 实现日志触发系统（靠近地点时自动播放）
- [ ] 实现并行任务系统（低位风险 ↔ 高位倒计时）
- [ ] 核心搬运时的温度同步 UI 显示
- [ ] 队伍公告系统（"X 正在调节冷却..."）

---

## 六、优先级排序（按价值密度）

**第 1 阶段（这周）：**
1. 校准小游戏的完整反馈（音效 + 视觉）⭐⭐⭐⭐⭐
   - 影响：玩家最频繁接触的交互
   - 工作量：中等（音效 2h + 粒子 2h）
   - 回报：立即提升手感

2. 多人并行任务系统 ⭐⭐⭐⭐
   - 影响：区分"好玩"vs"无聊"的分水岭
   - 工作量：中等（逻辑 3h + 网络同步 2h）
   - 回报：让协作有意义

**第 2 阶段（下周）：**
3. 语音日志系统 + 叙事背景 ⭐⭐⭐⭐
   - 影响：玩家理解"为什么"
   - 工作量：小（文本 1h + TTS 0.5h + 混音 1h）
   - 回报：情感代入

4. 美术动画与 Blender 脚本 ⭐⭐⭐
   - 影响：视觉精良度
   - 工作量：中等（Blender 脚本 3h + 集成 2h）
   - 回报：机械感与科技感

**第 3 阶段（后续）：**
5. 完整音景分层 ⭐⭐⭐
   - 影响：氛围与沉浸感
   - 工作量：小（音频合成 2h + Godot 管理器 1h）
   - 回报：长期体验提升

---

## 七、AI 工具对应表

| 任务 | 工具 | 输出 | 成本估计 |
|------|------|------|--------|
| 校准音效生成 | Audacity/Pure Data 脚本 | .wav/.ogg | 2h |
| 语音日志合成 | ElevenLabs API / Bark | .wav | $1-3 / 脚本 |
| Blender 动画脚本 | Claude Sonnet → 生成 Python 脚本 | .blend → .glb | 3h |
| 粒子效果代码 | Claude Sonnet → 生成 GDScript | .gd | 2h |
| 故事文案 | Claude Opus | .txt | 1h |
| 美术概念图 | DALL-E 3 / Midjourney | .png（参考） | $5-10 |

---

## 八、验收标准

一个**精良的共振星**应该满足：

✅ **玩法维度：**
- [ ] 每个校准都有独特的难度曲线和音效
- [ ] 多人协作时存在明确的时间压力
- [ ] 失败与重试有明确的反馈（不会困惑）

✅ **视觉维度：**
- [ ] 热阀/模块/反应堆/核心各有开启动画
- [ ] 关键交互处有粒子反馈
- [ ] 镜头流畅，无卡顿/穿模

✅ **音景维度：**
- [ ] 始终有工业氛围音（不是沉默）
- [ ] 每个事件都有对应音效
- [ ] 语音日志清晰可闻，背景适当

✅ **叙事维度：**
- [ ] 玩家知道"为什么来这儿"
- [ ] 玩家知道"在做什么"
- [ ] 玩家知道"这很重要"

---

## 立即行动清单

**今天：**
1. 用 Claude 生成 3 条语音日志文本
2. 列出校准小游戏的 5 类音效需求

**明天：**
3. 生成校准音效（用 Audacity 脚本）
4. 编写多人并行任务的逻辑代码框架

**本周：**
5. 集成校准音效 + 粒子到 Godot
6. 集成并行任务系统
7. 用 ElevenLabs 合成语音日志

**下周：**
8. Blender 动画脚本
9. 分层音景管理器
10. 完整试玩测试

这就是**每个层面都精良**的共振星。开始吧？
