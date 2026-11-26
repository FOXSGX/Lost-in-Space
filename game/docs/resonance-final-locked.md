# 🔒 共振星最终蓝图（完全锁定）

**现有时长：** 11-12 分钟
**目标时长：** 30-35 分钟
**扩展倍数：** 3 倍（需增加 18-24 分钟）

**冻结日期：** 2026-06
**状态：** 不再修改，直线执行

---

## 第一部分：关卡时长分配（锁定）

### 现有 7 个环节的时间分析

| 环节 | 当前时长 | 扩展后时长 | 改动 | 总计 |
|------|---------|----------|------|------|
| 热阀链 | 1.5-2m | 2m | 保持 | 2m |
| 第一节模块 | 1.5-2m | 3-4m | **+突发事件（2m）** | 4m |
| 支援接力 | 1.5-2m | 2-3m | 冷却参数更复杂 | 2.5m |
| 第二节模块 | 1.5-2m | 4-5m | **+货箱卡住微操（2-3m）** | 4.5m |
| 第三节模块 | 1.5-2m | 4-5m | **+镜面失败→成功（2-3m）** | 4.5m |
| 反应堆甲板 | 1.5-2m | 2-3m | 保持 | 2.5m |
| 核心搬运 | 1.5-2m | 5-7m | **+路线投票选择（2-3m）** | 6m |
| **总计** | **11-12m** | **30-35m** | | **28m** |

**每个环节的详细设计见下文。**

---

## 第二部分：4 个改动的完整实现规范（锁定）

### 改动 1：第一节突发事件（+2 分钟）

**位置：** 第一节模块完成到 80% 时触发
**触发条件：** 玩家已完成"模块路线切换"和"供能端连接"

**突发事件类型（三选一，随机）：**

| 事件 | 表现 | 持续时间 | 影响 |
|------|------|---------|------|
| **敌人入侵** | 1-2 个敌人进入模块区域 | 1.5-2m | 需要一个队友去吸引/对付，其他人继续操作 |
| **熔岩异常** | 熔岩突然上升 10-20% | 2-2.5m | 平台振动，需要稳定操作，风险上升 |
| **冷却泄漏** | 模块温度上升到 160°C | 1.5-2m | 时间压力（"快点完成，不然模块过热"） |

**GDScript 实现框架：**
```gdscript
func trigger_first_module_incident():
    var incident_type = randi() % 3  # 0=敌人, 1=熔岩, 2=冷却
    
    match incident_type:
        0:  # 敌人入侵
            spawn_enemies_in_module_area()
            hud.announce("敌人入侵！分散应对！")
            
        1:  # 熔岩异常
            lava_sudden_rise(10)  # 上升 10%
            hud.announce("熔岩上升！保持稳定！")
            screen_shake(0.8)
            
        2:  # 冷却泄漏
            module_temperature = 160
            hud.show_temperature_warning(160)
            hud.announce("冷却系统泄漏！加快进度！")
    
    yield(get_tree(), "process_frame")
    
    # 2-2.5 分钟后，事件解除
    yield(get_tree(), "physics_frame")
    await get_tree().create_timer(randi_range(120, 150)).timeout
    
    on_incident_resolved()
```

**多人影响：**
- 低位玩家需要暂停模块操作去处理突发情况
- 高位队友继续支援接力的准备
- 增加"管理复杂性"和"时间压力"

---

### 改动 2：磁力货箱卡住微操（+2-3 分钟）

**位置：** 第二节模块的"磁力货箱"阶段
**触发条件：** 玩家开始拖动磁力货箱时

**场景：** 货箱被吸附到了侧面的金属支架，不能直接推

**三人协作操作：**

```
玩家 A（稳定者）：按住 E
  - 作用：稳定货箱，防止掉落
  - 视觉反馈：蓝色护盾环绕货箱
  - 持续时间：整个卡住阶段

玩家 B（调节者）：完成"磁力校准"小游戏
  - 作用：调节磁力强度（0-100%）
  - 目标：降低磁力，让货箱能被推动
  - 难度：中等（绿区 30%）
  - 光标速度：1.3x

玩家 C（推动者）：按住方向键推
  - 作用：推动货箱向前
  - 约束：只有在 B 完成校准且 A 继续稳定时才能推
  - 视觉反馈：货箱缓慢向前移动（0.5m/s）
```

**失败条件：**
- A 松开 E → 货箱掉落 → 游戏失败，回到这个阶段
- B 校准失败 3 次 → 货箱过热 → 重试
- C 试图强行推动（磁力未降）→ 货箱被拉回 → 重新开始

**成功时的奖励感：**
```gdscript
func on_cargo_successfully_moved():
    # 音效：货箱磁力降低的"呼呼"声 + 推动的"咔啦"声
    audio_success.play()
    
    # 视觉：货箱缓慢向前，最后"啪"地到位
    particle_burst(cargo_position, Color.CYAN)
    
    # HUD 公告：
    hud.announce("磁力货箱已放入接收座！")
    
    # 进度推进
    emit_signal("second_module_cargo_complete")
```

**时长：** 3-4 分钟（包括 3 次失败重试的可能性）

---

### 改动 3：镜面校准的"故意失败"高潮（+2-3 分钟）

**位置：** 第三节模块的反应堆镜面校准
**触发条件：** 玩家完成两个光束校准后

**第一次尝试（故意失败）**

```gdscript
func first_mirror_calibration_attempt():
    # 玩家完成 A 和 B 光束校准
    var alignment_a = get_beam_alignment("A")  # 98%
    var alignment_b = get_beam_alignment("B")  # 96%
    var total_alignment = (alignment_a + alignment_b) / 2  # 94%
    
    # 结果：失败（设计好的）
    if total_alignment < 98:
        on_mirror_alignment_fail(total_alignment)
```

**失败反馈：**
- UI 显示：`对齐度 94% | 需要 ≥98%`（金色数字逐渐变红）
- 音效：失败的"呃"声（低频、沉闷）
- 画面：镜面微微抖动，光束没有完全对齐，只是接近
- 屏幕闪烁：红色预警闪 1 秒
- 持续时间：2-3 秒

**中间的"学习"阶段：**
```
系统提示："镜面对齐度不足，需要更精准的相位调整。"
（停顿 2 秒）
玩家讨论："哦，我们的校准还差一点，需要更小心。"
（停顿 2 秒）
系统恢复："准备重新尝试..."
```

**第二次尝试（成功）**

```gdscript
func second_mirror_calibration_attempt():
    var alignment_a = get_beam_alignment("A")  # 99%
    var alignment_b = get_beam_alignment("B")  # 99%
    var total_alignment = (alignment_a + alignment_b) / 2  # 99%
    
    if total_alignment >= 98:
        on_mirror_alignment_success()
```

**成功反馈（高潮时刻）：**

```gdscript
func on_mirror_alignment_success():
    # 1. 音效层
    audio_success.play()  # "叮"的清晰音
    music_pitch_up(1.5)   # 音乐升调
    audio_energy_flow.play()  # 能量流动的"滋"声
    
    # 2. 视觉层
    screen_flash(Color.CYAN, 0.3)  # 青色闪烁
    
    # 镜面反射出彩虹光束
    for i in range(3):
        spawn_rainbow_beam_particle(mirror_position + Vector3(i*2, 0, 0))
    
    # 反应堆发出低沉共鸣
    reactor_glow_pulse()
    reactor_sound.play()
    
    # 3. UI 层
    hud.show_success_banner("镜面对齐完成！能量流动激活！")
    
    # 4. 持续时间
    await get_tree().create_timer(5).timeout  # 让玩家享受 5 秒成功感
    
    emit_signal("third_module_complete")
```

**心理效应：**
- 第一次"差一点"失败 → 压力
- 中间"我们知道怎么做了" → 信心
- 第二次成功 → 爽感
- 总体：学习→挑战→成功 的完整情感弧线

**时长：** 4-5 分钟（包括失败+重试）

---

### 改动 4：核心搬运的"三路投票"（+2-3 分钟）

**位置：** 核心拿起后，搬运到返航平台前
**触发条件：** 玩家从反应堆拿起能源核心

**投票阶段：**

```gdscript
func core_transport_route_choice():
    # 核心被拿起时触发
    hud.show_route_selection({
        "fast": "快速路（风险高）",
        "safe": "安全路（风险低）",
        "hidden": "隐藏路（需特殊条件）"
    })
    
    # 多人投票
    var votes = await wait_for_route_votes()  # 每个玩家投一次
    var chosen_route = determine_majority_route(votes)
    
    # 公告选择
    hud.announce(f"队伍选择了：{chosen_route}")
    
    emit_signal("route_chosen", chosen_route)
```

**三条路的详细参数：**

#### **快速路（30 秒，危险）**

```gdscript
const FAST_ROUTE = {
    "distance": 8.0,
    "time": 30,
    "difficulty": "hard",
    "description": "熔岩峡谷边缘的捷径",
    
    # 路径：
    # 返航平台 ─→ [熔岩峡谷边缘] ─→ 飞船
    #              ↑ 高坠落风险 ↑
    
    "hazards": [
        {"type": "cliff_edge", "position": Vector3(45, -5, -20), "radius": 3.0},
        {"type": "lava_updraft", "position": Vector3(50, -8, -18), "intensity": 1.5}
    ],
    
    "success_condition": "玩家保持在路线上，不掉落",
    "failure_condition": "掉入熔岩或超时 > 35 秒",
    
    "outcome": {
        "success": {
            "message": "我们很勇敢，冒着风险成功了！",
            "energy_core_status": "完好",
            "next_planet_penalty": 0,  # 无惩罚
            "achievement": "speed_runner"
        },
        "failure": {
            "message": "核心...毁了。我们太贪心了。",
            "energy_core_status": "受损",
            "next_planet_penalty": -20,  # 下一颗星球能源 -20%
            "effect": "后续游戏难度提升"
        }
    }
}
```

**视觉表现：**
- 路线以蓝色发光的浮标标记
- 边缘有危险的红色警告纹
- 坠落时的画面急速下降 + 红屏

#### **安全路（60 秒，稳定）**

```gdscript
const SAFE_ROUTE = {
    "distance": 15.0,
    "time": 60,
    "difficulty": "easy",
    "description": "高架折返路，安全但绕远",
    
    # 路径：
    # 返航平台 ─→ [高架折返] ─→ [支援通道] ─→ 飞船
    #              ↑ 低危险 ↑      ↑ 低危险 ↑
    
    "hazards": [],  # 无主要危险
    
    "success_condition": "跟随高架走完整条路",
    "failure_condition": "极端情况（几乎不会失败）",
    
    "outcome": {
        "success": {
            "message": "我们很谨慎，稳健地完成了任务。",
            "energy_core_status": "完好无损",
            "next_planet_bonus": 0,  # 无加成（但无惩罚）
            "achievement": "careful_guardian"
        },
        "failure": {
            "message": "（极少发生）",
            "rarity": "99% 概率不会失败"
        }
    }
}
```

**视觉表现：**
- 绿色发光的稳定路线
- 高架平台明确可见
- 沿途有"队友在此"的暗示

#### **隐藏路（45 秒，聪慧）**

```gdscript
const HIDDEN_ROUTE = {
    "distance": 11.0,
    "time": 45,
    "difficulty": "medium",
    "description": "工程师留下的秘密捷径",
    
    # 路径：
    # 返航平台 ─→ [隐蔽通道] ─→ [秘密梯道] ─→ 飞船
    #              ↑ 不明显 ↑      ↑ 工程师标记 ↑
    
    "unlock_condition": "玩家在反应堆精准控制温度（125-135°C）",
    "visibility": "只在解锁后显示为第三选项",
    
    "hazards": [
        {"type": "narrow_passage", "width": 1.5, "challenge": "需要精准控制位置"}
    ],
    
    "success_condition": "通过秘密梯道，发现 Marcus 的日记",
    "failure_condition": "掉落或超时 > 50 秒",
    
    "outcome": {
        "success": {
            "message": "我们很聪慧...我们找到了 Marcus 留下的指引。",
            "energy_core_status": "完好",
            "unlock_content": {
                "ui_new": "Marcus 的日记（新界面）",
                "log_hidden": "第 4 条隐藏日志（Alex 的秘密通讯）",
                "story_hookup": "共振站的真实用途被揭示"
            },
            "achievement": "found_secrets"
        },
        "failure": {
            "message": "秘密梯道很难走，但我们可以重试或换路线。",
            "penalty": 0,  # 失败无惩罚，可重试
            "retry_option": "选择其他路线或重试此路线"
        }
    }
}
```

**视觉表现：**
- 路线以紫色/深蓝色发光（神秘感）
- 沿途有"工程师标记"的暗示（手绘符号等）
- 到达梯道时，墙上闪现 Marcus 的名字

**投票系统的实现：**

```gdscript
func wait_for_route_votes() -> Dictionary:
    var votes = {}
    
    for player_id in get_connected_players():
        # 每个玩家有 10 秒时间投票
        var choice = await wait_for_player_input(player_id, 10)
        votes[player_id] = choice
        
        hud.announce(f"玩家 {player_id} 投票选择：{choice}")
    
    return votes

func determine_majority_route(votes: Dictionary) -> String:
    var vote_counts = {}
    
    for player_id in votes:
        var choice = votes[player_id]
        vote_counts[choice] = vote_counts.get(choice, 0) + 1
    
    # 最多票的路线获胜
    return vote_counts.max()
```

**时长分配：**
- 投票界面显示：3-5 秒
- 玩家投票：5-10 秒
- 宣布选择：2 秒
- 路线执行：30-60 秒（取决于选择）

---

## 第三部分：多人协作的网络同步参数（锁定）

### 低位快线风险系统

```gdscript
class LowPositionRiskSystem:
    var risk_level: float = 0.0  # 0-100%
    var max_risk: float = 100.0
    var risk_per_second_no_support: float = 0.8  # 每秒 +0.8%
    var risk_threshold_warning: float = 50.0
    var risk_threshold_critical: float = 80.0
    
    func _process(delta):
        if is_low_player_operating and not is_high_player_relaying:
            risk_level += risk_per_second_no_support * delta
            
            # 风险达到 50% 时发出警告
            if risk_level >= risk_threshold_warning and not warned_once:
                hud.show_warning("低位快线过载！高位接力迫在眉睫！")
                audio_alert_warning.play()
                warned_once = true
            
            # 风险达到 80% 时，低位玩家受伤
            if risk_level >= risk_threshold_critical:
                damage_low_player(25)
                risk_level = 0  # 重置（这是一次"惩罚"）
        
        # 高位完成接力后，风险重置
        if is_high_player_relaying:
            risk_level = 0
```

**RPC 同步：**
```gdscript
@rpc("reliable")
func sync_risk_level(new_risk: float):
    # 主机计算风险，客户端接收
    risk_level = new_risk
    update_risk_hud_display(new_risk)

@rpc("reliable")
func announce_risk_critical():
    hud.show_critical_warning("低位快线即将过载！")
    screen_shake(1.2)
    audio_alert_critical.play()
```

**参数锁定：**
- 风险上升速度：0.8%/秒 ✅
- 警告阈值：50% ✅
- 危险阈值：80% ✅
- 受伤数值：25 HP ✅

---

### 高位接力的倒计时系统

```gdscript
class HighPositionRelaySystem:
    const RELAY_WINDOW: float = 8.0  # 秒
    var countdown: float = RELAY_WINDOW
    var is_relay_active: bool = false
    
    func start_relay():
        is_relay_active = true
        countdown = RELAY_WINDOW
    
    func _process(delta):
        if is_relay_active:
            countdown -= delta
            
            # 实时同步到客户端（每 0.1 秒一次）
            if int(countdown * 10) != int((countdown + delta) * 10):
                rpc("sync_relay_countdown", countdown)
            
            # 倒计时到 0
            if countdown <= 0:
                on_relay_timeout()
    
    func on_relay_timeout():
        # 接力失败（高位玩家没完成）
        damage_high_player(25)
        increment_low_risk(20)  # 额外增加低位风险 20%
        
        # 接力重置，可以重试
        reset_relay()

@rpc("unreliable")
func sync_relay_countdown(remaining: float):
    # 客户端端显示倒计时
    hud.show_relay_countdown(remaining)
    
    # 倒计时 ≤ 3 秒时，UI 变红
    if remaining <= 3:
        hud.set_countdown_color(Color.RED)
        audio_beep_fast.play()  # 快速"嘟嘟嘟"声
```

**参数锁定：**
- 接力窗口：8 秒 ✅
- 失败惩罚（高位）：25 HP ✅
- 连带惩罚（低位风险）：+20% ✅

---

### 多人重启规则

```gdscript
func on_player_death(player_id: int):
    # 全队重启（而非单人重启）
    rpc("announce_team_death", player_id)
    
    # 2 秒后，全队返回到最后的检查点
    await get_tree().create_timer(2).timeout
    
    rpc("reset_all_players_to_checkpoint")
    
    # 重置所有临时状态
    reset_low_position_risk()
    reset_high_position_relay()
    reset_module_progress()

@rpc("reliable")
func announce_team_death(player_id: int):
    hud.show_death_banner(f"玩家 {player_id} 阵亡！全队返回...")
    screen_flash(Color.RED, 0.5)
```

---

## 第四部分：校准小游戏的完整参数（锁定）

### 四种难度的标准参数

| 设备 | 绿区宽度 | 光标速度 | 预期耗时 | 失败惩罚 | 音效 |
|------|---------|--------|--------|---------|------|
| **热阀** | 40% | 1.0x | 8-12s | 重试（无伤害） | 热流"呼呼"音 |
| **电源端** | 30% | 1.3x | 10-15s | 重试 | 电流"滋滋"音 |
| **镜面节点** | 20% | 1.8x | 12-18s | 重试→失败→需要重新校准两个光束 | 高频"嘟嘟"音 |
| **冷却座** | 25% | 1.5x | 10-16s | 重试 | 冷媒流动音 |

**详细实现：**

```gdscript
class CalibrationMinigame:
    var difficulty_params = {
        "heat_valve": {
            "green_zone_width": 40,
            "cursor_speed": 1.0,
            "min_time": 8,
            "max_time": 12,
            "audio_ambient": "res://assets/audio/calibration_heat_ambient.ogg",
            "audio_success": "res://assets/audio/calibration_heat_success.ogg",
            "audio_fail": "res://assets/audio/calibration_heat_fail.ogg"
        },
        "power_node": {
            "green_zone_width": 30,
            "cursor_speed": 1.3,
            "min_time": 10,
            "max_time": 15,
            "audio_ambient": "res://assets/audio/calibration_power_ambient.ogg",
            "audio_success": "res://assets/audio/calibration_power_success.ogg",
            "audio_fail": "res://assets/audio/calibration_power_fail.ogg"
        },
        "mirror_node": {
            "green_zone_width": 20,
            "cursor_speed": 1.8,
            "min_time": 12,
            "max_time": 18,
            "audio_ambient": "res://assets/audio/calibration_mirror_ambient.ogg",
            "audio_success": "res://assets/audio/calibration_mirror_success.ogg",
            "audio_fail": "res://assets/audio/calibration_mirror_fail.ogg"
        },
        "cooling_node": {
            "green_zone_width": 25,
            "cursor_speed": 1.5,
            "min_time": 10,
            "max_time": 16,
            "audio_ambient": "res://assets/audio/calibration_cool_ambient.ogg",
            "audio_success": "res://assets/audio/calibration_cool_success.ogg",
            "audio_fail": "res://assets/audio/calibration_cool_fail.ogg"
        }
    }
    
    func start_calibration(device_type: String):
        var params = difficulty_params[device_type]
        
        # 绘制校准界面
        draw_calibration_ui(params)
        
        # 播放环境音
        audio_player_ambient.stream = load(params["audio_ambient"])
        audio_player_ambient.play()
        
        # 启动光标往返运动
        start_cursor_oscillation(params["cursor_speed"])
    
    func start_cursor_oscillation(speed: float):
        var cursor_pos = 0.0
        var direction = 1.0
        
        while calibration_active:
            cursor_pos += speed * direction * delta * 60
            
            # 边界反弹
            if cursor_pos >= 100:
                cursor_pos = 100
                direction = -1.0
            elif cursor_pos <= 0:
                cursor_pos = 0
                direction = 1.0
            
            # 绘制光标和绿区
            draw_cursor(cursor_pos)
            draw_green_zone(params["green_zone_width"])
            
            # 检查玩家输入
            if Input.is_action_just_pressed("ui_accept"):
                check_calibration_success(cursor_pos, params)
            
            await get_tree().process_frame
    
    func check_calibration_success(cursor_pos: float, params: Dictionary):
        var green_zone_start = (100 - params["green_zone_width"]) / 2
        var green_zone_end = green_zone_start + params["green_zone_width"]
        
        if green_zone_start <= cursor_pos <= green_zone_end:
            # 成功
            on_calibration_success(params)
        else:
            # 失败
            on_calibration_fail(params)
    
    func on_calibration_success(params: Dictionary):
        # 音效
        audio_player_success.stream = load(params["audio_success"])
        audio_player_success.play()
        
        # 视觉反馈
        screen_flash(Color.GREEN, 0.2)
        spawn_success_particles(cursor_position)
        
        # 进度推进
        calibration_active = false
        emit_signal("calibration_complete")
    
    func on_calibration_fail(params: Dictionary):
        # 音效
        audio_player_fail.stream = load(params["audio_fail"])
        audio_player_fail.play()
        
        # 视觉反馈
        screen_flash(Color.RED, 0.15)
        hud.show_retry_prompt()
        
        # 重试（光标重置，重新开始）
        cursor_pos = 0
        direction = 1.0
```

**参数锁定完成** ✅

---

## 第五部分：故事与叙事框架（锁定）

### 四条日志的完整文本与 TTS 参数

#### **日志 1：设施介绍**
**触发：** 玩家靠近热阀链（距离 < 15 米）
**讲述者：** Marcus Chen（工程主管，已故）
**音色：** 沙哑、沧桑、疲倦的中年男性

**文本（中文）：**
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

**TTS 参数：**
- 提供商：ElevenLabs（推荐）或 Azure TTS
- 语言：中文（zh-CN）
- 音色：male-gravelly-older
- 速度：0.9x（略显拖沓）
- 稳定度：0.4（不稳定 = 更疲倦）
- 相似度：0.7
- 背景音：机器低频嗡鸣 -20dB
- 输出格式：OGG（Godot 优化）
- 持续时间：~18 秒

**Godot 实现：**
```gdscript
func trigger_log_1_on_heat_valve_proximity():
    if not log_triggered["intro"]:
        play_voice_log({
            "id": "log_1_intro",
            "audio_path": "res://assets/resonance/audio/log_1_intro.ogg",
            "subtitle": "这是...共振能源站的核心区域。",
            "background_audio": "res://assets/resonance/audio/ambient_machine_hum.ogg",
            "background_volume_db": -20
        })
        log_triggered["intro"] = true
```

---

#### **日志 2：事故背景**
**触发：** 玩家靠近反应堆塔（距离 < 20 米）
**讲述者：** Alex Kim（年轻技术员）
**音色：** 焦急、年轻、中等音量

**文本（中文）：**
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

**TTS 参数：**
- 提供商：ElevenLabs 或 Azure
- 语言：中文（zh-CN）
- 音色：male-young-urgent
- 速度：1.1x（紧张感）
- 稳定度：0.6
- 相似度：0.8
- 背景音：警报音 -15dB + 机械噪声 -18dB
- 输出格式：OGG
- 持续时间：~21 秒

---

#### **日志 3：最后希望**
**触发：** 玩家拿起能源核心瞬间
**讲述者：** Marcus Chen（生命垂危时期）
**音色：** 极其沙哑、虚弱、接近生命终点

**文本（中文）：**
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

**TTS 参数：**
- 提供商：ElevenLabs 或 Azure
- 语言：中文（zh-CN）
- 音色：male-old-gravelly-dying
- 速度：0.85x（非常缓慢）
- 稳定度：0.3（极不稳定 = 极度虚弱）
- 相似度：0.65
- 效果：轻微回声（模拟老化录音）+ 淡出
- 背景音：极其微弱的机器音 -25dB
- 输出格式：OGG
- 持续时间：~17 秒

---

#### **日志 4：秘密通讯（隐藏）**
**触发：** 玩家在反应堆精准控制温度（125-135°C）并选择隐藏路成功
**讲述者：** Alex Kim（备用频道的旧录音，几乎听不清）
**音色：** 极其微弱、扭曲的音质（模拟"备用通讯频道"）

**文本（中文）：**
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

**TTS 参数：**
- 提供商：ElevenLabs 或 Azure
- 语言：中文（zh-CN）
- 音色：male-distorted-backup-channel
- 速度：0.95x
- 稳定度：0.3（极不稳定）
- 相似度：0.6
- 效果：
  - 频率衰减（模拟老旧通讯）
  - 背景底噪 -22dB
  - 间歇性的电流声
  - 逐渐淡出
- 输出格式：OGG
- 持续时间：~22 秒

**后续效果：**
```gdscript
func on_hidden_log_play():
    # 解锁新 UI
    unlock_marcus_diary_ui()
    
    # 日记内容可重复阅读
    marcus_diary = {
        "title": "Marcus 的日记",
        "entries": [
            "我很遗憾当初没有更早发现真相。",
            "共振站的真实用途...不是能源，而是通讯。",
            "我们在监听...但监听的是什么？",
            "爆炸不是意外。这是一场有预谋的隔离。"
        ]
    }
    
    # 为下一颗星球伏线
    hud.show_story_hookup("共振站的秘密...只是开始")
```

---

## 第六部分：工作清单与分工（56 项任务）

### **第 1-7 项：游戏设计与规划（Claude）**

1. ✅ 现有时长测试 → 确认为 11-12 分钟（已完成）
2. ⏳ 编写"第一节突发事件"的详细设计文档
3. ⏳ 编写"磁力货箱卡住"的详细设计文档
4. ⏳ 编写"镜面失败→成功"的详细设计文档
5. ⏳ 编写"路线选择投票"的详细设计文档
6. ⏳ 确认所有 4 个改动的交互流程
7. ⏳ 生成"质量审查检查表"

---

### **第 8-15 项：故事与音频（DeepSeek + Claude 审查）**

8. ⏳ 调用 ElevenLabs API，生成日志 1 的 MP3
9. ⏳ 调用 ElevenLabs API，生成日志 2 的 MP3
10. ⏳ 调用 ElevenLabs API，生成日志 3 的 MP3
11. ⏳ 调用 ElevenLabs API，生成日志 4（隐藏）的 MP3
12. ⏳ 用 Audacity/FFmpeg 脚本混音 4 条日志（添加背景音）
13. ⏳ 导出所有日志为 OGG 格式
14. ⏳ 将 4 个 OGG 文件放入 `res://assets/resonance/audio/`
15. ✅ Claude 审查音频质量（清晰、情感表达、背景音平衡）

---

### **第 16-25 项：多人协作系统（DeepSeek）**

16. ⏳ 实现 `LowPositionRiskSystem` 类
    - 风险上升逻辑
    - 警告阈值（50%）
    - 危险阈值（80%）
    - RPC 同步
    
17. ⏳ 实现 `HighPositionRelaySystem` 类
    - 倒计时逻辑（8 秒）
    - 超时处理
    - RPC 同步
    
18. ⏳ 实现 `MultiplayerDeathSystem` 类
    - 全队重启规则
    - 检查点管理
    
19. ⏳ 编写单元测试：低位风险是否按 0.8%/s 上升
20. ⏳ 编写单元测试：高位倒计时是否在 8 秒后触发
21. ⏳ 编写单元测试：全队重启是否正确重置状态
22. ⏳ 集成到 `resonance_stage.gd`
23. ⏳ 集成 RPC 网络同步
24. ⏳ 创建 HUD 显示面板（风险百分比 + 倒计时）
25. ✅ Claude 审查多人协作的逻辑是否符合设计（无竞态条件、同步正确）

---

### **第 26-35 项：校准小游戏（DeepSeek）**

26. ⏳ 实现 `CalibrationMinigame` 类（基础框架）
27. ⏳ 实现热阀校准（绿区 40%，速度 1.0x）
28. ⏳ 实现电源节点校准（绿区 30%，速度 1.3x）
29. ⏳ 实现镜面节点校准（绿区 20%，速度 1.8x）
30. ⏳ 实现冷却座校准（绿区 25%，速度 1.5x）
31. ⏳ 为 4 种校准生成音效脚本（用 Audacity 或 Pure Data）
32. ⏳ 实现成功/失败的视觉反馈（屏幕闪烁、粒子）
33. ⏳ 实现成功/失败的音效反馈
34. ⏳ 集成 HUD 显示（绿区、光标、对齐度百分比）
35. ✅ Claude 测试：4 种难度的体验是否符合"教学→中等→高难→中高"的梯度

---

### **第 36-45 项：4 个改动的完整实现（DeepSeek）**

**改动 1：第一节突发事件**
36. ⏳ 实现 `trigger_first_module_incident()` 函数
37. ⏳ 随机选择 3 种事件中的一种（敌人/熔岩/冷却）
38. ⏳ 实现各事件的视觉和音效反馈
39. ⏳ 实现 2-2.5 分钟的事件持续时间

**改动 2：磁力货箱卡住**
40. ⏳ 实现三人协作操作（稳定 A + 调节 B + 推动 C）
41. ⏳ 实现磁力校准小游戏（集成到 CalibrationMinigame）
42. ⏳ 实现失败条件和重试逻辑
43. ⏳ 实现成功时的奖励粒子和音效

**改动 3：镜面失败→成功**
44. ⏳ 实现"第一次尝试失败"（对齐度 94%）
45. ⏳ 实现"第二次尝试成功"的高潮视觉和音效

**改动 4：核心搬运的三路投票**
46. ⏳ 实现投票 UI 和玩家投票逻辑
47. ⏳ 实现多数决规则
48. ⏳ 实现 3 条路线的路径和碰撞（快速路、安全路、隐藏路）

---

### **第 46-50 项：故事集成（DeepSeek）**

46. ⏳ 实现 `ResonanceVoiceLogManager` 类
    - 日志触发条件（靠近热阀、靠近反应堆、拿起核心）
    - 隐藏日志的解锁条件（反应堆温度精准控制 + 选择隐藏路）
    
47. ⏳ 集成 4 条日志的播放和字幕显示
48. ⏳ 实现 Marcus 日记 UI（隐藏日志触发后显示）
49. ⏳ 实现后续故事钩子的显示（"一切还没结束..."）
50. ✅ Claude 审查：故事弧线是否完整、叙事是否清晰

---

### **第 51-55 项：美术与音效生成（DeepSeek + Claude 审查）**

51. ⏳ 生成校准音效脚本（热/电/镜/冷各 2 种音效）
52. ⏳ 生成粒子效果代码（5 类交互事件）
53. ⏳ 生成 Blender 动画脚本（热阀转动 + 核心悬浮 + 模块喷射）
54. ⏳ 验证所有音效清晰可闻（无刺耳、无混浊）
55. ⏳ 验证所有粒子效果不会遮挡玩家视线

---

### **第 56 项：最终验收和冻结（Claude）**

56. ⏳ **多人试玩 1 轮**（自己 + 1 个朋友）
    - 玩完整的共振星，记录时长
    - 朋友反馈：好玩吗？节奏如何？多人协作感如何？
    - 如果反馈是"好玩"，则锁定，进入下一个星球的开发
    - 如果反馈需要微调，进行**最多 1 轮微调**（不改大机制，只改参数）

---

## 第七部分：验收标准与检查清单（锁定）

### 🎮 玩法维度

- [ ] 第一节突发事件正确触发（80% 进度时）
- [ ] 磁力货箱三人协作逻辑正确（A 稳定、B 校准、C 推动）
- [ ] 镜面校准第一次失败、第二次成功的高潮感明显
- [ ] 路线投票的投票界面清晰，多数决规则正确
- [ ] 全队重启规则正确（一人死亡 → 全队回到检查点）
- [ ] 低位风险每秒 +0.8%，达到 50% 时警告，达到 80% 时伤害
- [ ] 高位倒计时 8 秒，超时时伤害高位玩家

### 📖 故事维度

- [ ] 日志 1 在靠近热阀时自动播放
- [ ] 日志 2 在靠近反应堆时自动播放
- [ ] 日志 3 在拿起核心时自动播放
- [ ] 日志 4（隐藏）仅在反应堆精准控制 + 选隐藏路成功时播放
- [ ] 每条日志的音量和背景音平衡合理
- [ ] Marcus 日记 UI 能正确显示（隐藏日志触发后）
- [ ] 故事钩子"一切还没结束"能正确显示

### 🎨 美术与音效维度

- [ ] 校准小游戏的 4 种音效各不相同、清晰可闻
- [ ] 粒子效果在关键时刻（成功、高潮、死亡）出现，不遮挡视线
- [ ] Blender 动画（热阀转动、核心悬浮、模块喷射）流畅无卡顿
- [ ] 没有刺耳的音效，没有混浊的背景音

### ⏱️ 时长维度

- [ ] 完整运行从进入到返航：28-35 分钟
- [ ] 各环节的时长分配符合设计（热阀 2m、模块 4m 等）

### 👥 多人维度

- [ ] 多人协作感强（不是被动等待，而是主动分工）
- [ ] 没有"我在做这个，队友也在做这个，冗余"的感觉
- [ ] 时间压力明确且可控（紧张但不绝望）

### ✅ 最终判定

**完成条件：**
- 自己完整试玩一遍，没有明显 bug
- 1 个朋友试玩一遍，反馈"很好玩"或"节奏很紧张、多人配合感强"
- 上述所有检查清单 ≥ 90% 通过

**锁定条件：**
- 一旦满足"完成条件"，共振星锁定，不再改动
- 进入下一颗星球的开发或整体游戏的打磨

---

## 🚀 立即行动清单

**Week 1（第一周）：**
- [ ] DeepSeek 任务 1-15（故事 + 音频）→ 生成 4 条日志 MP3，混音处理
- [ ] DeepSeek 任务 16-25（多人系统）→ 实现风险 + 倒计时 + 重启逻辑
- [ ] DeepSeek 任务 26-35（校准小游戏）→ 4 种难度完整实现
- [ ] Claude 审查这 24 项任务的代码质量

**Week 2（第二周）：**
- [ ] DeepSeek 任务 36-50（4 个改动 + 故事集成）→ 完整关卡逻辑
- [ ] Claude 审查故事叙事和玩法协作
- [ ] DeepSeek 任务 51-55（美术音效）→ 完整的视觉和听觉反馈
- [ ] Claude 任务 56（多人试玩）→ 测试、反馈、微调、锁定

**试玩后：**
- ✅ 锁定共振星
- 🚀 开始下一颗星球 或 整体打磨

---

**现在，所有决定都已锁定。**

**没有回头路，直线冲到完成。**

**下一步：谁开始第 1-15 项任务？**