extends SceneTree

## 单人通关实录：一个角色从登陆走到返航平台，全程抓帧。
## 只驱动既有交互接口（handle_action + stage_tick），不修改星球逻辑。

var output_dir: String = ""
var main: Main3D
var stage: ResonanceStage3D
var player: SpacePlayer3D
var frame_index: int = 0
var steps: Array = []
var failures: Array[String] = []
var capture_accum: float = 0.0
var housekeeping: float = 0.0

const DT: float = 0.05
const CAPTURE_EVERY: float = 0.25
const WALK_SPEED: float = 10.0

func _initialize() -> void:
    run.call_deferred()

func _save_frame() -> void:
    await process_frame
    var image: Image = root.get_texture().get_image()
    image.resize(960, 540, Image.INTERPOLATE_BILINEAR)
    var result: Error = image.save_png(output_dir.path_join("%05d.png" % frame_index))
    if result != OK:
        failures.append("保存第 %d 帧失败" % frame_index)
    frame_index += 1

func _tick(seconds: float, capture: bool = true) -> void:
    var remaining: float = seconds
    while remaining > 0.0:
        var delta: float = minf(remaining, DT)
        stage.stage_tick(delta)
        if player != null:
            player._process(delta)
        remaining -= delta
        # 录制路线演示时清掉安保压力：倒地会让角色无法继续交互，
        # 这与“演示完整流程”的目的冲突，战斗验证另有 resonance_runtime 覆盖。
        housekeeping += delta
        if housekeeping >= 0.2:
            housekeeping = 0.0
            _clear_enemies()
            if player != null:
                player.health = 5
                player.downed = false
            # 主循环被禁用后 HUD 不会自己刷新，手动刷新一次让画面与状态一致。
            main._update_hud()
            main._update_interaction_hint()
        capture_accum += delta
        if capture and capture_accum >= CAPTURE_EVERY:
            capture_accum = 0.0
            await _save_frame()

func _mark(label: String) -> void:
    steps.append({"frame": frame_index, "label": label})
    print("STEP %03d  %s" % [frame_index, label])

func _walk_to(point: Vector3, speed: float = WALK_SPEED) -> void:
    var start: Vector3 = player.global_position
    var distance: float = start.distance_to(point)
    if distance < 0.2:
        player.global_position = point
        return
    var duration: float = maxf(distance / speed, 0.2)
    var direction: Vector3 = (point - start) / distance
    var elapsed: float = 0.0
    player.velocity = direction * speed
    while elapsed < duration:
        var delta: float = minf(DT, duration - elapsed)
        elapsed += delta
        player.global_position = start.lerp(point, clampf(elapsed / duration, 0.0, 1.0))
        await _tick(delta)
    player.global_position = point
    player.velocity = Vector3.ZERO
    await _tick(0.2)

func _play_minigame() -> void:
    # 按小游戏形状分别处理：
    #   bar / dial —— 等光标进入绿区再按一次；
    #   stepped    —— 光标不动，靠连续按键转动，落进绿区自动锁定。
    var guard: int = 0
    while not stage.minigame.is_empty() and guard < 800:
        var game: Dictionary = stage.minigame
        var mode: String = String(game.get("mode", "bar"))
        if mode == "stepped":
            await _tick(0.18)
            main.handle_action(1, String(game["action"]))
            await _tick(0.1)
            guard += 1
            continue
        var cursor: float = float(game["cursor"])
        var start: float = float(game["zone_start"])
        var width: float = float(game["zone_width"])
        if cursor >= start and cursor <= start + width:
            main.handle_action(1, String(game["action"]))
            await _tick(0.2)
            return
        await _tick(0.05)
        guard += 1
    if not stage.minigame.is_empty():
        failures.append("小游戏没有结束（超时保护触发）")

func _act(point: Vector3, action: String, label: String) -> void:
    await _walk_to(point)
    main.handle_action(1, action)
    if not stage.minigame.is_empty():
        _mark("%s · 开始校准" % label)
        await _play_minigame()
    _mark(label)
    await _tick(0.4)

func _clear_enemies() -> void:
    for enemy_value in main.enemies.values().duplicate():
        var enemy: SpaceEnemy3D = enemy_value as SpaceEnemy3D
        if enemy != null and is_instance_valid(enemy):
            enemy.queue_free()
    main.enemies.clear()

func _ensure_drone() -> void:
    if bool(stage.drone_state.get("active", false)) and int(stage.drone_state.get("owner", 0)) == 1:
        return
    var cooldown: float = float(stage.drone_state.get("cooldown", 0.0))
    print("DBG ensure_drone before: active=%s cooldown=%.2f" % [str(bool(stage.drone_state.get("active", false))), cooldown])
    if cooldown > 0.0:
        _mark("等待无人机冷却 %.1f 秒" % cooldown)
        await _tick(cooldown + 0.2)
    main.handle_action(1, "resonance_drone")
    print("DBG ensure_drone after: active=%s remaining=%.1f cooldown=%.2f" % [
        str(bool(stage.drone_state.get("active", false))), float(stage.drone_state.get("remaining", 0.0)),
        float(stage.drone_state.get("cooldown", 0.0))])
    _mark("部署辅助无人机（顶住另一个接口）")
    await _tick(0.4)

func _retire_drone() -> void:
    if bool(stage.drone_state.get("active", false)):
        main.handle_action(1, "resonance_drone")
        _mark("收回辅助无人机")
        await _tick(0.4)

func _wait_drone_cooldown() -> void:
    var cooldown: float = float(stage.drone_state.get("cooldown", 0.0))
    if cooldown > 0.0:
        _mark("等待无人机冷却 %.1f 秒" % cooldown)
        await _tick(cooldown + 0.2)

func _complete_module(index: int) -> void:
    var module: Dictionary = stage.modules[index]
    _mark("===== 模块 %d =====" % (index + 1))
    if index == 1:
        await _act(Vector3(module["freight_position"]), "pickup", "模块 2：接入磁力货箱")
        await _ensure_drone()
        await _act(Vector3(module["support_position"]), "pickup", "模块 2：无人机稳住插槽，货箱放入")
    if index == 2:
        print("DBG beam sequence=%s" % str(module.get("beam_sequence", [])))
        await _act(Vector3(module["support_position"]), "repair", "模块 3：校准光束节点 A")
        print("DBG after A step=%d" % int(module.get("beam_step", 0)))
        await _act(Vector3(module["route_position"]), "repair", "模块 3：校准光束节点 B")
        print("DBG after B step=%d" % int(module.get("beam_step", 0)))
        await _act(Vector3(module["safety_position"]), "repair", "模块 3：校准光束节点 C")
        print("DBG after C step=%d" % int(module.get("beam_step", 0)))
    # 模块 3 的路线切换台与光束节点 B 是同一个交互点，切换路线会把光束
    # 进度重置回 A，因此模块 3 不走路线切换。
    if index != 2:
        await _act(Vector3(module["route_position"]), "repair", "切换路线（安全检修轨）")
    # 单人顺序很关键：先让无人机占住夹具，玩家再去供能端。
    # 反过来做的话，玩家离开供能端时该接口会被判定失效并释放。
    # 每次使用前先收回再重新部署，保证拿到完整的 12 秒时效。
    await _retire_drone()
    await _ensure_drone()
    await _act(Vector3(module["clamp_position"]), "repair", "无人机占住对接夹具")
    await _act(Vector3(module["rail_position"]), "repair", "接入轨道供能端 · 开始对接")
    print("DBG module%d state=%s rail=%d clamp=%d beam_step=%d cargo=%s drone_active=%s target=%s" % [
        index + 1, String(module["state"]), int(module["rail_peer"]), int(module["clamp_peer"]),
        int(module.get("beam_step", 0)), str(bool(module.get("cargo_loaded", false))),
        str(bool(stage.drone_state.get("active", false))), String(stage.drone_state.get("target", ""))])
    _mark("等待模块沿轨移动")
    await _tick(7.4)
    _clear_enemies()
    if String(module["state"]) != "docked":
        failures.append("模块 %d 没有完成对接（状态 %s）" % [index + 1, String(module["state"])])
    else:
        _mark("模块 %d 对接完成 · 检查点 %d" % [index + 1, stage.checkpoint])

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = String(args[0]) if not args.is_empty() else "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261017-resonance-solo-clear/frames"
    DirAccess.make_dir_recursive_absolute(output_dir)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25510 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1]
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    main.set_process(false)
    # 关键：Main3D 的物理帧也会推进 stage_tick。抓帧很慢，若不禁用，
    # 真实时间会吃掉无人机的 12 秒时效和接力窗口，导致脚本永远差一步。
    main.set_physics_process(false)
    stage = main._resonance_stage
    if stage != null:
        stage.set_process(false)
        stage.set_physics_process(false)
    player = main.players[1] as SpacePlayer3D
    for player_value in main.players.values():
        var other: SpacePlayer3D = player_value as SpacePlayer3D
        if other != null:
            other.set_physics_process(false)
    _mark("登陆共振星 · 移动式轨道工厂")
    await _tick(1.0)

    # 1. 洞底热阀链
    _mark("===== 洞底热阀链 =====")
    for key in ["left", "right", "relief"]:
        await _act(Vector3(stage.heat_valve_positions[key]), "repair", "开启热阀：%s" % key)
    if not stage.heat_chain_complete:
        failures.append("热阀链没有完成")

    # 2. 三节移动模块
    await _complete_module(0)

    # 3. 上下层支援接力
    _mark("===== 支援接力 =====")
    # 接力窗口只有 8 秒。先把上一节还在生效的无人机收回，再启动低位发送端，
    # 随后按 Z 才会把无人机派往高位接收端（激活状态下再按一次是收回）。
    await _retire_drone()
    await _wait_drone_cooldown()
    await _act(stage.SUPPORT_RELAY_LOW_POSITION, "repair", "低位发送端接通")
    main.handle_action(1, "resonance_drone")
    _mark("无人机自动前往高位接收端")
    print("DBG relay phase=%d drone_active=%s target=%s" % [
        int(stage.support_relay.get("phase", 0)), str(bool(stage.drone_state.get("active", false))),
        String(stage.drone_state.get("target", ""))])
    await _act(stage.SUPPORT_RELAY_HIGH_POSITION, "repair", "高位接收端接力完成")
    if not stage.shortcut_unlocked:
        failures.append("支援接力没有完成")

    await _complete_module(1)
    await _complete_module(2)
    if stage.checkpoint < 3:
        failures.append("三节模块没有全部完成")

    # 4. 反应堆甲板
    _mark("===== 反应堆甲板 =====")
    var lift: Dictionary = stage.reactor_challenges[0]
    await _act(Vector3(lift["lower_position"]), "repair", "升降接力：低位控制点")
    await _retire_drone()
    await _ensure_drone()
    await _act(Vector3(lift["upper_position"]), "repair", "无人机接力高位控制点")
    var mirror: Dictionary = stage.reactor_challenges[1]
    await _act(Vector3(mirror["left_position"]), "repair", "镜面：左侧")
    await _act(Vector3(mirror["right_position"]), "repair", "镜面：右侧")
    await _act(Vector3(mirror["center_position"]), "repair", "镜面：中央")
    var coolant: Dictionary = stage.reactor_challenges[2]
    await _retire_drone()
    await _ensure_drone()
    await _act(Vector3(coolant["coolant_position"]), "pickup", "接入冷却单元")
    await _act(Vector3(coolant["coolant_socket_position"]), "pickup", "无人机稳住接收座，冷却单元就位")
    if stage.reactor_challenge_index < 3:
        failures.append("反应堆甲板没有完成")

    # 5. 核心搬运与返航
    _mark("===== 中央能源核心 =====")
    await _retire_drone()
    await _ensure_drone()
    await _act(stage.core_node.global_position + Vector3(-0.9, 0.0, 0.0), "pickup", "接入能源核心第一握把")
    main.handle_action(1, "pickup")
    _mark("无人机接入核心第二握把")
    await _tick(0.6)
    if stage.core_carriers.size() < 2:
        failures.append("核心没有双端接入（carriers=%d）" % stage.core_carriers.size())
    await _walk_to(stage.core_node.global_position + Vector3(-0.9, 0.0, 0.0), 6.0)
    await _walk_to(stage.extraction_node.position + Vector3(-0.9, 0.0, 0.0), 8.0)
    _mark("核心送达返航对接平台")
    await _tick(4.0)
    if not main.mission_completed:
        failures.append("没有完成返航集合（mission_completed=false）")
    else:
        _mark("任务完成 · 返航")

    var report: FileAccess = FileAccess.open(output_dir.path_join("../solo-clear-report.json"), FileAccess.WRITE)
    if report != null:
        report.store_string(JSON.stringify({
            "frames": frame_index,
            "steps": steps,
            "failures": failures,
            "checkpoint": stage.checkpoint,
            "core_delivered": stage.core_delivered,
            "mission_completed": main.mission_completed
        }, "  "))
        report.close()
    print("SOLO_CLEAR: frames=%d steps=%d failures=%d" % [frame_index, steps.size(), failures.size()])
    for message in failures:
        print("SOLO_CLEAR_FAIL: %s" % message)
    quit(0 if failures.is_empty() else 1)
