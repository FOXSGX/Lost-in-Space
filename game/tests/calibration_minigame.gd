extends SceneTree

## 校准小游戏诊断：难度梯度、判定、重试、超时、音效与粒子。
##
## 只测手感内核（CalibrationMinigame / CalibrationUI / ParticleEffects），
## 不启动整局游戏，运行成本低，可以每次改动后都跑。

const CALIBRATION_SCRIPT: Script = preload("res://scripts/calibration_minigame.gd")
const UI_SCRIPT: Script = preload("res://scripts/calibration_ui.gd")
const FX_SCRIPT: Script = preload("res://scripts/particle_effects.gd")
const AUDIO_DIR: String = "res://assets/audio/calibration/"

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
    run.call_deferred()


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)


func run() -> void:
    _check_difficulty_table()
    _check_audio_assets()
    _check_cursor_and_zone()
    _check_success_and_fail()
    _check_retry_and_assist()
    _check_timeout_and_stepped()
    _check_ui_and_particles()
    print("CALIBRATION_MINIGAME: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)


# --------------------------------------------------------------------------
func _check_difficulty_table() -> void:
    var game: CalibrationMinigame = CALIBRATION_SCRIPT.new() as CalibrationMinigame
    root.add_child(game)
    var expected_width: Dictionary = {
        "heat_valve": 40.0, "power_node": 30.0, "mirror_node": 20.0, "cooling_node": 25.0
    }
    var expected_speed: Dictionary = {
        "heat_valve": 1.0, "power_node": 1.3, "mirror_node": 1.8, "cooling_node": 1.5
    }
    for device in expected_width.keys():
        check(game.has_device(String(device)), "难度表缺少设备 %s" % device)
        var params: Dictionary = game.get_device_params(String(device))
        check(is_equal_approx(float(params.get("green_zone_width", -1.0)), float(expected_width[device])),
            "%s 的绿区宽度不是 %s%%" % [device, expected_width[device]])
        check(is_equal_approx(float(params.get("cursor_speed", -1.0)), float(expected_speed[device])),
            "%s 的光标速度不是 %sx" % [device, expected_speed[device]])

    # 梯度：宽度严格从宽到窄，速度严格从慢到快
    var rows: Array[Dictionary] = game.difficulty_gradient()
    check(rows.size() == 4, "梯度表不是 4 种设备")
    for index in range(1, rows.size()):
        check(float(rows[index]["green_zone_width"]) < float(rows[index - 1]["green_zone_width"]),
            "绿区宽度没有随难度收窄：第 %d 行" % index)
        check(float(rows[index]["cursor_speed"]) > float(rows[index - 1]["cursor_speed"]),
            "光标速度没有随难度加快：第 %d 行" % index)
    check(String(rows[0]["id"]) == "heat_valve", "最宽绿区不是教学用的热阀")
    check(String(rows[3]["difficulty"]) == "高", "最窄绿区不是高难度的镜面节点")

    # 容忍时间：玩家在绿区停留多久（秒）= 宽度 / 速度，必须逐级变短
    var previous_window: float = 999.0
    for row in rows:
        var window: float = float(row["green_zone_width"]) / 100.0 / (float(row["cursor_speed"]) * game.CURSOR_UNITS_PER_SECOND)
        check(window < previous_window + 0.0001, "%s 的容错窗口没有比上一级更短" % row["name"])
        previous_window = window
    # 教学设备至少要给 0.35 秒的反应窗口，高难度也不能低于 0.12 秒
    var teaching: Dictionary = game.get_device_params("heat_valve")
    var teaching_window: float = float(teaching["green_zone_width"]) / 100.0 / (
        float(teaching["cursor_speed"]) * game.CURSOR_UNITS_PER_SECOND)
    check(teaching_window >= 0.35, "热阀的容错窗口只有 %.2f 秒，太短" % teaching_window)
    var hard: Dictionary = game.get_device_params("mirror_node")
    var hard_window: float = float(hard["green_zone_width"]) / 100.0 / (
        float(hard["cursor_speed"]) * game.CURSOR_UNITS_PER_SECOND)
    check(hard_window >= 0.12, "镜面节点的容错窗口只有 %.2f 秒，不可能达成" % hard_window)
    check(game.particles == null, "未注入粒子系统时不应自动创建")
    game.queue_free()


func _check_audio_assets() -> void:
    var keys: Array[String] = ["heat", "power", "mirror", "cool"]
    for key in keys:
        for kind in ["ambient", "success", "fail"]:
            var path: String = AUDIO_DIR + "calibration_%s_%s.ogg" % [key, kind]
            check(ResourceLoader.exists(path), "缺少音效 %s" % path)
            var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
            if stream == null:
                continue
            check(stream.get_length() > 0.1, "%s 时长为 0" % path)
            if kind == "ambient":
                var ogg: AudioStreamOggVorbis = stream as AudioStreamOggVorbis
                check(ogg != null, "%s 不是 ogg 流" % path)


func _check_cursor_and_zone() -> void:
    var game: CalibrationMinigame = CALIBRATION_SCRIPT.new() as CalibrationMinigame
    game.audio_enabled = false
    root.add_child(game)
    game.start_calibration("heat_valve", {"zone_start": 0.4})
    check(game.calibration_active, "start_calibration 之后没有进入激活状态")
    check(is_equal_approx(game.zone_bounds().x, 0.4), "绿区起点没有采用覆盖值")
    check(is_equal_approx(game.zone_bounds().y, 0.4 + 0.40), "绿区宽度不是 40%")

    # 光标往返：连续推进 6 秒，位置必须始终在 0…1，并且确实来回折返
    var reversed_count: int = 0
    var previous_direction: float = game.cursor_direction
    for _step in 120:
        game.tick(0.05)
        if game.cursor_position < -0.001 or game.cursor_position > 1.001:
            check(false, "光标越界：%.3f" % game.cursor_position)
            break
        if not is_equal_approx(game.cursor_direction, previous_direction):
            reversed_count += 1
            previous_direction = game.cursor_direction
    check(reversed_count >= 2, "光标没有往返（只折返 %d 次）" % reversed_count)

    # 速度倍率：1.8x 的镜面在同样时间内跑得更远
    var fast: CalibrationMinigame = CALIBRATION_SCRIPT.new() as CalibrationMinigame
    fast.audio_enabled = false
    root.add_child(fast)
    fast.start_calibration("mirror_node", {"zone_start": 0.0, "cursor_start": 0.0})
    fast.tick(0.1)
    var fast_distance: float = fast.cursor_position
    game.start_calibration("heat_valve", {"zone_start": 0.0, "cursor_start": 0.0})
    game.tick(0.1)
    check(fast_distance > game.cursor_position * 1.4,
        "镜面节点没有比热阀更快（%.3f vs %.3f）" % [fast_distance, game.cursor_position])
    fast.queue_free()
    game.queue_free()


func _check_success_and_fail() -> void:
    var game: CalibrationMinigame = CALIBRATION_SCRIPT.new() as CalibrationMinigame
    game.audio_enabled = false
    root.add_child(game)
    var completed: Array[Dictionary] = []
    var failed: Array[Dictionary] = []
    game.calibration_complete.connect(func(result: Dictionary) -> void: completed.append(result))
    game.calibration_failed.connect(func(result: Dictionary) -> void: failed.append(result))

    game.start_calibration("power_node", {"zone_start": 0.3})
    check(game.check_calibration_success(0.45, game.params()), "绿区正中判定为失败")
    check(not game.check_calibration_success(0.05, game.params()), "绿区外判定为成功")
    game.set_cursor(0.45)
    var result: Dictionary = game.confirm()
    check(bool(result.get("success", false)) and bool(result.get("resolved", false)), "落点在绿区却没有成功")
    check(completed.size() == 1 and failed.is_empty(), "成功没有发出 calibration_complete")
    check(not game.calibration_active, "成功后没有停止接收输入")
    check(String(result.get("message", "")).contains("成功"), "成功结果没有可读提示")

    # 失败路径
    game.start_calibration("power_node", {"zone_start": 0.3})
    game.set_cursor(0.05)
    var miss: Dictionary = game.confirm()
    check(not bool(miss.get("success", true)), "绿区外却判定成功")
    check(failed.size() == 1 and completed.size() == 1, "失败没有发出 calibration_failed")
    check(int(miss.get("retries_left", 0)) == game.MAX_RETRIES - 1, "失败后剩余重试次数不对")

    # 绕回绿区（跨 1.0）也能正确判定
    var wrapped: Dictionary = {"zone_start": 0.9, "zone_width": 0.2}
    check(game.check_calibration_success(0.95, wrapped), "绕回绿区的尾段判定失败")
    check(game.check_calibration_success(0.05, wrapped), "绕回绿区的头段判定失败")
    check(not game.check_calibration_success(0.5, wrapped), "绕回绿区之外判定成功")
    game.queue_free()


func _check_retry_and_assist() -> void:
    var game: CalibrationMinigame = CALIBRATION_SCRIPT.new() as CalibrationMinigame
    game.audio_enabled = false
    root.add_child(game)
    game.start_calibration("heat_valve", {"zone_start": 0.3})
    var base_width: float = game.zone_bounds().y - game.zone_bounds().x
    game.set_cursor(0.0)
    game.confirm()
    check(game.retry_count == 1, "第一次失败后 retry_count 不是 1")
    game.start_calibration("heat_valve", {"zone_start": 0.3})
    check(is_equal_approx(game.zone_bounds().y - game.zone_bounds().x, base_width), "第二次失败前绿区就被放宽了")
    game.set_cursor(0.0)
    game.confirm()
    check(game.retry_count == 2, "第二次失败后 retry_count 不是 2")
    # 第三次开启：进入辅助模式，绿区放宽
    game.start_calibration("heat_valve", {"zone_start": 0.3})
    var assisted_width: float = game.zone_bounds().y - game.zone_bounds().x
    check(assisted_width > base_width, "连续失败后绿区没有放宽（%.3f → %.3f）" % [base_width, assisted_width])
    check(game.current_state()["assist"] == true, "辅助模式没有反映到状态里")
    # 成功后重试计数清零，辅助模式撤掉
    game.set_cursor(0.3 + assisted_width * 0.5)
    game.confirm()
    check(game.retry_count == 0, "成功后 retry_count 没有清零")
    game.start_calibration("heat_valve", {"zone_start": 0.3})
    check(is_equal_approx(game.zone_bounds().y - game.zone_bounds().x, base_width), "成功后绿区仍然是放宽状态")
    # 换设备不应该继承另一台设备的失败计数
    game.set_cursor(0.0)
    game.confirm()
    game.start_calibration("mirror_node", {"zone_start": 0.4})
    check(game.retry_count == 0, "换设备后仍然继承了失败次数")
    # 连续失败到上限：标记中止，不再无限重试
    game.start_calibration("heat_valve", {"zone_start": 0.3})
    for _index in CalibrationMinigame.MAX_RETRIES:
        game.start_calibration("heat_valve", {"zone_start": 0.3})
        game.set_cursor(0.0)
        var last: Dictionary = game.confirm()
        if bool(last.get("aborted", false)):
            break
    check(game.retry_count >= CalibrationMinigame.MAX_RETRIES, "失败次数没有累计到上限")
    game.queue_free()


func _check_timeout_and_stepped() -> void:
    var game: CalibrationMinigame = CALIBRATION_SCRIPT.new() as CalibrationMinigame
    game.audio_enabled = false
    root.add_child(game)
    var timed_out: Array[Dictionary] = []
    game.calibration_failed.connect(func(result: Dictionary) -> void: timed_out.append(result))
    game.start_calibration("cooling_node", {"zone_start": 0.3, "duration": 0.5})
    for _step in 12:
        game.tick(0.05)
    check(not game.calibration_active, "超时后仍在接收输入")
    check(timed_out.size() == 1 and String(timed_out[0].get("reason", "")) == "timeout", "超时没有发出 reason=timeout")

    # 步进模式：按 E 每次转 1/12，没对上不关闭，对上即锁定
    game.start_calibration("mirror_node", {"zone_start": 0.5, "mode": "stepped"})
    var first: Dictionary = game.confirm()
    check(not bool(first.get("resolved", true)), "步进模式第一次按键就结束（绿区在 0.5，转了 30° 还没到）")
    check(game.calibration_active, "步进模式未对上却关闭了")
    var presses: int = 1
    while game.calibration_active and presses < 14:
        game.confirm()
        presses += 1
    check(not game.calibration_active, "步进模式 14 次按键内没有锁定")
    check(presses >= 3, "步进模式 %d 次按键就完成，步进没有生效" % presses)

    # 步进模式的绿区不会盖住起点，否则一按就结束
    var stepped_starts: Array[float] = []
    for _index in 12:
        game.start_calibration("mirror_node", {"mode": "stepped"})
        stepped_starts.append(game.zone_bounds().x)
    var minimum_start: float = stepped_starts.min()
    check(minimum_start >= 2.0 / float(CalibrationMinigame.STEP_COUNT) - 0.0001,
        "步进模式的绿区起点离 0° 太近（%.3f），一次按键就会完成" % minimum_start)
    game.queue_free()


func _check_ui_and_particles() -> void:
    var game: CalibrationMinigame = CALIBRATION_SCRIPT.new() as CalibrationMinigame
    game.audio_enabled = false
    root.add_child(game)
    var fx: ParticleEffects = FX_SCRIPT.new() as ParticleEffects
    root.add_child(fx)
    game.particles = fx
    var gauge: CalibrationUI = UI_SCRIPT.new() as CalibrationUI
    gauge.size = Vector2(580, 148)
    root.add_child(gauge)

    # UI 只读状态，不改变玩法状态
    game.start_calibration("heat_valve", {"zone_start": 0.35})
    var state: Dictionary = game.current_state()
    gauge.set_state(state)
    check(is_equal_approx(gauge.zone_width, 0.40), "HUD 没有拿到 40%% 的绿区宽度")
    check(gauge.mode == "bar", "热阀没有使用计时条")
    gauge.cursor = gauge.zone_start + 0.05
    check(gauge.is_cursor_in_zone(), "HUD 判定光标在绿区内失败")
    gauge.cursor = 0.02
    check(not gauge.is_cursor_in_zone(), "HUD 判定光标在绿区外失败")
    gauge.flash_result({"success": true})
    check(gauge._flash_time > 0.0, "成功闪示没有触发")
    gauge.flash_result({"success": false})
    check(gauge._flash_time > 0.0, "失败闪示没有触发")
    gauge.queue_free()

    # 5 类粒子事件都能生成，且不无限堆积
    var spawn_points: Array[String] = [
        "heat_valve_success", "power_success", "mirror_success_beam",
        "calibration_fail_flash", "module_attachment_spray"
    ]
    for event in spawn_points:
        check(fx.spawn_event(event, Vector3(1.0, 0.0, 1.0)), "粒子事件 %s 没有实现" % event)
    check(fx.active_effect_count() > 0, "粒子事件没有生成任何节点")
    for _index in 40:
        fx.spawn_event("power_success", Vector3.ZERO)
    check(fx.active_effect_count() <= ParticleEffects.MAX_ACTIVE_EFFECTS,
        "粒子上限没有生效（%d）" % fx.active_effect_count())
    fx.clear_all()
    check(fx.active_effect_count() == 0, "clear_all 之后仍有存活特效")

    # 单个特效的粒子数量有上限，一屏不会塞满
    fx.spawn_event("power_success", Vector3.ZERO)
    var emitter: CPUParticles3D = _first_particles(fx)
    if emitter != null:
        check(emitter.amount <= ParticleEffects.MAX_PARTICLES_PER_EFFECT,
            "单个特效粒子数没有上限（%d）" % emitter.amount)
    game.queue_free()
    fx.queue_free()


func _first_particles(node: Node) -> CPUParticles3D:
    for child in node.find_children("*", "CPUParticles3D", true, false):
        return child as CPUParticles3D
    return null
