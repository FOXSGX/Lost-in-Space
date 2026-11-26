class_name CalibrationMinigame
extends Node

## 共振星校准小游戏：光标往返 → 进入绿区 → 按键锁定。
##
## 4 种设备共用一套机制，只靠“绿区宽度 + 光标速度”拉出难度梯度：
##   热阀 40% / 1.0x（教学） → 电源端 30% / 1.3x（中等）
##   → 镜面节点 20% / 1.8x（高） → 冷却座 25% / 1.5x（中高）
##
## 本类只负责“手感内核”：参数表、光标运动、判定、重试、音效与粒子触发。
## 谁有权推进状态、怎么联网同步，留给调用方（共振星由主机权威的
## ResonanceStage3D 驱动），这样同一套手感可以被其他星球复用。
##
## 用法：
##     calibration_system = CalibrationMinigame.new()
##     add_child(calibration_system)
##     calibration_system.calibration_complete.connect(_on_calibration_complete)
##     var state: Dictionary = calibration_system.start_calibration("heat_valve")
##     ...
##     calibration_system.tick(delta)          # 光标往返 + 倒计时
##     var result: Dictionary = calibration_system.confirm()

signal calibration_complete(result: Dictionary)
signal calibration_failed(result: Dictionary)

const AUDIO_DIR: String = "res://assets/audio/calibration/"
## 1.0x 倍率下光标每秒扫过的行程（整条轨道 = 1.0）。
const CURSOR_UNITS_PER_SECOND: float = 0.85
## 步进模式把整圈分成 12 格。
const STEP_COUNT: int = 12
## 同一设备连续失败到这个次数后标记中止，提示玩家离开设备重来。
const MAX_RETRIES: int = 3
const ASSIST_AFTER_FAILURES: int = 2
const ASSIST_ZONE_MULTIPLIER: float = 1.35
const AMBIENT_DB: float = -7.0
const SFX_DB: float = -3.0
## 绿区左右各留多少余量，避免绿区贴边导致“指针还没进来就要按”。
const ZONE_MARGIN: float = 0.10

## 难度参数表。green_zone_width 是百分比（40 = 轨道宽度的 40%），
## cursor_speed 是相对速度倍率（1.0 = CURSOR_UNITS_PER_SECOND）。
var difficulty_params: Dictionary = {
    "heat_valve": {
        "name": "热阀",
        "difficulty": "教学",
        "green_zone_width": 40.0,
        "cursor_speed": 1.0,
        "mode": "bar",
        "duration": 9.0,
        "audio_key": "heat",
        "success_event": "heat_valve_success",
        "success_sound": "热流涌出",
        "ambient_sound": "热流呼呼",
        "hint": "光标进入绿区时按 E 确认",
        "success_message": "热阀校准成功 · 热流已泄压",
        "fail_message": "热阀偏差过大 · 重新对准"
    },
    "power_node": {
        "name": "电源端",
        "difficulty": "中等",
        "green_zone_width": 30.0,
        "cursor_speed": 1.3,
        "mode": "bar",
        "duration": 8.0,
        "audio_key": "power",
        "success_event": "power_success",
        "success_sound": "电流接通",
        "ambient_sound": "电流滋滋",
        "hint": "光标进入绿区时按 E 确认",
        "success_message": "电源端校准成功 · 回路已接通",
        "fail_message": "电源端偏差过大 · 重新对准"
    },
    "mirror_node": {
        "name": "镜面节点",
        "difficulty": "高",
        "green_zone_width": 20.0,
        "cursor_speed": 1.8,
        "mode": "dial",
        "duration": 9.0,
        "audio_key": "mirror",
        "success_event": "mirror_success_beam",
        "success_sound": "反射锁定",
        "ambient_sound": "高频提示",
        "hint": "指针扫到绿弧时按 E 锁定",
        "success_message": "镜面节点校准成功 · 反射已锁定",
        "fail_message": "镜面角度偏离 · 重新对准"
    },
    "cooling_node": {
        "name": "冷却座",
        "difficulty": "中高",
        "green_zone_width": 25.0,
        "cursor_speed": 1.5,
        "mode": "bar",
        "duration": 8.5,
        "audio_key": "cool",
        "success_event": "module_attachment_spray",
        "success_sound": "冷媒锁定",
        "ambient_sound": "冷媒流动",
        "hint": "光标进入绿区时按 E 确认",
        "success_message": "冷却座校准成功 · 冷媒已锁定",
        "fail_message": "冷却座偏差过大 · 重新对准"
    }
}

var current_device: String = ""
var cursor_position: float = 0.0
var cursor_direction: float = 1.0
var calibration_active: bool = false
var retry_count: int = 0

## 粒子系统（可选注入）。为空时只播音效，不生成粒子。
var particles: ParticleEffects
var audio_enabled: bool = true

var _params: Dictionary = {}
var _mode: String = "bar"
var _speed: float = CURSOR_UNITS_PER_SECOND
var _zone_start: float = 0.0
var _zone_width: float = 0.0
var _remaining: float = 0.0
var _duration: float = 0.0
var _assist_active: bool = false
var _anchor: Vector3 = Vector3.ZERO
var _last_result: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ambient_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _stream_cache: Dictionary = {}


func _ready() -> void:
    _ensure_players()


# --------------------------------------------------------------------------
# 参数表
# --------------------------------------------------------------------------
func device_ids() -> Array[String]:
    var ids: Array[String] = []
    for key in difficulty_params.keys():
        ids.append(String(key))
    return ids


func has_device(device_type: String) -> bool:
    return difficulty_params.has(device_type)


func get_device_params(device_type: String) -> Dictionary:
    if not difficulty_params.has(device_type):
        return {}
    return (difficulty_params[device_type] as Dictionary).duplicate(true)


## 供文档与测试读取的梯度表：宽度从宽到窄、速度从慢到快。
func difficulty_gradient() -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    for device_type in device_ids():
        var params: Dictionary = difficulty_params[device_type]
        rows.append({
            "id": device_type,
            "name": String(params["name"]),
            "difficulty": String(params["difficulty"]),
            "green_zone_width": float(params["green_zone_width"]),
            "cursor_speed": float(params["cursor_speed"])
        })
    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["green_zone_width"]) > float(b["green_zone_width"]))
    return rows


# --------------------------------------------------------------------------
# 开始一次校准
# --------------------------------------------------------------------------
## overrides 可覆盖任意设备参数（绿区、速度、时长、模式、标题、锚点等），
## 供关卡在设计自己的节奏时微调，而不用另建一套参数表。
func start_calibration(device_type: String, overrides: Dictionary = {}) -> Dictionary:
    _ensure_players()
    var resolved: String = device_type
    if not difficulty_params.has(resolved):
        push_warning("CalibrationMinigame: 未知设备 %s，回退到 heat_valve" % device_type)
        resolved = "heat_valve"
    if current_device != "" and current_device != resolved:
        # 换设备就重新开始计数：辅助模式只针对“同一台设备一直失败”。
        retry_count = 0
    current_device = resolved
    var params: Dictionary = get_device_params(resolved)
    for key in overrides.keys():
        params[key] = overrides[key]
    _params = params
    _mode = String(params.get("mode", "bar"))
    # 下限 0.4 秒：再短玩家连反应都没有。压力来自绿区宽度与光标速度，不靠秒表。
    _duration = maxf(float(params.get("duration", 9.0)), 0.4)
    _remaining = _duration
    _anchor = Vector3(params.get("anchor", Vector3.ZERO))
    _last_result = {}
    _zone_width = _resolve_zone_width(params)
    _zone_start = _resolve_zone_start(params, _zone_width)
    calibration_active = true
    start_cursor_oscillation(params)
    _play_ambient(params)
    return current_state()


func _resolve_zone_width(params: Dictionary) -> float:
    var width: float = float(params.get("zone_width", 0.0))
    if width <= 0.0:
        width = clampf(float(params.get("green_zone_width", 30.0)) / 100.0, 0.05, 0.9)
    width = clampf(width, 0.04, 0.9)
    _assist_active = retry_count >= ASSIST_AFTER_FAILURES
    if _assist_active:
        width = minf(width * ASSIST_ZONE_MULTIPLIER, 0.9)
    return width


func _resolve_zone_start(params: Dictionary, width: float) -> float:
    if params.has("zone_start"):
        return clampf(float(params["zone_start"]), 0.0, maxf(1.0 - width, 0.0))
    var lower: float = ZONE_MARGIN
    if _mode == "stepped":
        # 步进模式下光标从 0 起步：绿区不能盖住起点，否则一次按键就结束。
        lower = maxf(lower, 2.0 / float(STEP_COUNT))
    var upper: float = maxf(1.0 - width - ZONE_MARGIN, lower)
    return _rng.randf_range(lower, upper)


## 光标往返：位置 0…1，方向 ±1；速度沿用参数表（或 overrides 直接给 speed）。
func start_cursor_oscillation(params: Dictionary) -> void:
    _speed = _resolve_speed(params)
    cursor_position = clampf(float(params.get("cursor_start", _default_cursor_start())), 0.0, 1.0)
    cursor_direction = -1.0 if bool(params.get("start_reversed", false)) else 1.0


func _resolve_speed(params: Dictionary) -> float:
    if params.has("speed"):
        return maxf(float(params["speed"]), 0.0)
    return maxf(CURSOR_UNITS_PER_SECOND * float(params.get("cursor_speed", 1.0)), 0.0)


func _default_cursor_start() -> float:
    # 步进模式从 0° 开始转，玩家能看到“转了几格，还差几格”。
    return 0.0


# --------------------------------------------------------------------------
# 每帧推进
# --------------------------------------------------------------------------
func tick(delta: float) -> Dictionary:
    if not calibration_active:
        return {"active": false, "timeout": false}
    _remaining = maxf(_remaining - delta, 0.0)
    if _mode != "stepped" and _speed > 0.0:
        _advance_cursor(delta)
    if _remaining <= 0.0:
        var result: Dictionary = on_calibration_fail({"reason": "timeout"})
        return {"active": false, "timeout": true, "result": result}
    return {"active": true, "timeout": false}


func _advance_cursor(delta: float) -> void:
    var step: float = cursor_direction * _speed * delta
    var next_position: float = cursor_position + step
    if next_position >= 1.0:
        next_position = 2.0 - next_position
        cursor_direction = -1.0
    elif next_position <= 0.0:
        next_position = -next_position
        cursor_direction = 1.0
    cursor_position = clampf(next_position, 0.0, 1.0)


# --------------------------------------------------------------------------
# 判定
# --------------------------------------------------------------------------
## 判定一次落点。支持 zone_start + width 跨过 1.0 的绕回情况。
func check_calibration_success(cursor_pos: float, params: Dictionary) -> bool:
    var start: float = float(params.get("zone_start", _zone_start))
    var width: float = float(params.get("zone_width", _zone_width))
    if width <= 0.0:
        return false
    var pos: float = fposmod(cursor_pos, 1.0)
    if start < 0.0:
        start = 0.0
    if start + width <= 1.0:
        return pos >= start and pos <= start + width
    return pos >= start or pos <= start + width - 1.0


## 玩家按下确认键。stepped 模式先转一格再判定；未对上不关闭。
func confirm() -> Dictionary:
    if not calibration_active:
        return {"resolved": false, "success": false, "reason": "inactive"}
    if _mode == "stepped":
        cursor_position = fposmod(cursor_position + 1.0 / float(STEP_COUNT), 1.0)
    var hit: bool = check_calibration_success(cursor_position, _params)
    if _mode == "stepped" and not hit:
        return {
            "resolved": false,
            "success": false,
            "reason": "stepped_miss",
            "cursor": cursor_position,
            "remaining": _remaining
        }
    if hit:
        return on_calibration_success({"cursor": cursor_position})
    return on_calibration_fail({"reason": "out_of_zone", "cursor": cursor_position})


func on_calibration_success(params: Dictionary) -> Dictionary:
    var cursor: float = float(params.get("cursor", cursor_position))
    calibration_active = false
    var retries: int = retry_count
    var was_assisted: bool = _assist_active
    retry_count = 0
    _assist_active = false
    _stop_ambient()
    _play_feedback("success")
    _spawn_feedback_particle("success")
    var result: Dictionary = {
        "resolved": true,
        "success": true,
        "reason": "in_zone",
        "device": current_device,
        "device_name": String(_params.get("name", current_device)),
        "cursor": cursor,
        "zone_start": _zone_start,
        "zone_width": _zone_width,
        "retry_count": retries,
        "assisted": was_assisted,
        "anchor": _anchor,
        "message": String(_params.get("success_message", "校准成功"))
    }
    _last_result = result
    calibration_complete.emit(result)
    return result


func on_calibration_fail(params: Dictionary) -> Dictionary:
    var reason: String = String(params.get("reason", "out_of_zone"))
    calibration_active = false
    retry_count += 1
    var aborted: bool = retry_count >= MAX_RETRIES
    _stop_ambient()
    _play_feedback("fail")
    _spawn_feedback_particle("fail")
    var result: Dictionary = {
        "resolved": true,
        "success": false,
        "reason": reason,
        "aborted": aborted,
        "device": current_device,
        "device_name": String(_params.get("name", current_device)),
        "cursor": cursor_position,
        "zone_start": _zone_start,
        "zone_width": _zone_width,
        "retry_count": retry_count,
        "retries_left": maxi(MAX_RETRIES - retry_count, 0),
        "anchor": _anchor,
        "message": _fail_message(reason, aborted)
    }
    _last_result = result
    calibration_failed.emit(result)
    return result


func _fail_message(reason: String, aborted: bool) -> String:
    if reason == "timeout":
        return "校准超时 · 重新靠近设备再来一次"
    if aborted:
        return "校准中止 · 设备已复位，休息一下再试"
    if retry_count >= ASSIST_AFTER_FAILURES:
        return "%s · 第 %d 次失败，已放宽绿区" % [
            String(_params.get("fail_message", "校准偏差过大")), retry_count + 1]
    return String(_params.get("fail_message", "校准偏差过大"))


func cancel() -> void:
    calibration_active = false
    _remaining = 0.0
    _stop_ambient()


# --------------------------------------------------------------------------
# 状态
# --------------------------------------------------------------------------
func current_state() -> Dictionary:
    return {
        "device": current_device,
        "name": String(_params.get("name", current_device)),
        "difficulty": String(_params.get("difficulty", "")),
        "mode": _mode,
        "cursor": cursor_position,
        "dir": cursor_direction,
        "speed": _speed,
        "zone_start": _zone_start,
        "zone_width": _zone_width,
        "remaining": _remaining,
        "duration": _duration,
        "title": String(_params.get("title", _params.get("name", "设备校准"))),
        "hint": String(_params.get("hint", "光标进入绿区时按 E 确认")),
        "retry_count": retry_count,
        "max_retries": MAX_RETRIES,
        "assist": _assist_active,
        "active": calibration_active,
        "anchor": _anchor
    }


## 外部（HUD、网络权威、测试）写入光标位置。下一次 tick 从这里继续往返。
func set_cursor(position: float) -> void:
    cursor_position = clampf(position, 0.0, 1.0)


func set_remaining(seconds: float) -> void:
    _remaining = maxf(seconds, 0.0)


func is_hit_now() -> bool:
    return calibration_active and check_calibration_success(cursor_position, _params)


func zone_bounds() -> Vector2:
    return Vector2(_zone_start, _zone_start + _zone_width)


func last_result() -> Dictionary:
    return _last_result.duplicate(true)


func params() -> Dictionary:
    return _params.duplicate(true)


# --------------------------------------------------------------------------
# 音效
# --------------------------------------------------------------------------
func _ensure_players() -> void:
    if _ambient_player == null or not is_instance_valid(_ambient_player):
        _ambient_player = AudioStreamPlayer.new()
        _ambient_player.name = "CalibrationAmbient"
        _ambient_player.bus = "Master"
        _ambient_player.volume_db = AMBIENT_DB
        add_child(_ambient_player)
    if _sfx_player == null or not is_instance_valid(_sfx_player):
        _sfx_player = AudioStreamPlayer.new()
        _sfx_player.name = "CalibrationSfx"
        _sfx_player.bus = "Master"
        _sfx_player.volume_db = SFX_DB
        add_child(_sfx_player)


func _load_stream(path: String, loop: bool) -> AudioStream:
    if not audio_enabled or path.is_empty() or not ResourceLoader.exists(path):
        return null
    var cache_key: String = "%s|%s" % [path, str(loop)]
    if _stream_cache.has(cache_key):
        return _stream_cache[cache_key] as AudioStream
    var stream: AudioStream = load(path) as AudioStream
    if stream == null:
        return null
    var ogg: AudioStreamOggVorbis = stream as AudioStreamOggVorbis
    if ogg != null:
        ogg.loop = loop
    _stream_cache[cache_key] = stream
    return stream


func _play_ambient(params: Dictionary) -> void:
    _ensure_players()
    var key: String = String(params.get("audio_key", ""))
    if key.is_empty() or _ambient_player == null:
        return
    var stream: AudioStream = _load_stream(AUDIO_DIR + "calibration_%s_ambient.ogg" % key, true)
    if stream == null:
        return
    _ambient_player.stream = stream
    _ambient_player.play()


func _stop_ambient() -> void:
    if _ambient_player != null and is_instance_valid(_ambient_player):
        _ambient_player.stop()


func _play_feedback(kind: String) -> void:
    _ensure_players()
    var key: String = String(_params.get("audio_key", ""))
    if key.is_empty() or _sfx_player == null:
        return
    var stream: AudioStream = _load_stream(AUDIO_DIR + "calibration_%s_%s.ogg" % [key, kind], false)
    if stream == null:
        return
    _sfx_player.stream = stream
    _sfx_player.play()


# --------------------------------------------------------------------------
# 粒子
# --------------------------------------------------------------------------
func _spawn_feedback_particle(kind: String) -> void:
    if particles == null or not is_instance_valid(particles):
        return
    var event: String = String(_params.get("success_event", "")) if kind == "success" else "calibration_fail_flash"
    if event.is_empty():
        return
    particles.spawn_event(event, _anchor)
