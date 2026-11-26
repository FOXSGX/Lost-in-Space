extends RefCounted

# ═══════════════════════════════════════════════════════════════════════════
# 双向耦合共振校准（M3）
#
# 两套控制量，互相影响：
#   A = 共振频率（A 端设备）      frequency
#   B = 核心相位（B 端设备）      preload_value
# 两个机械偏差：
#   X = A − (base_x + bx·B + lx·L)
#   Y = B − (base_y − by·A − ly·L)
# A 上推同时抬高 X 与 Y；B 上推压低 X、抬高 Y。所以任何一方单独把自己那侧
# 的偏差调零，都会把另一侧推离零位，必须互相补偿。L 是真实蓄能负载。
#
# 工程约束（对应任务书 §8.2）：
#   · 积分固定子步长，与渲染/物理帧率无关；
#   · 输入走速度+阻尼（二阶），松手仍有余速，可反向刹车；
#   · 所有量有界，均衡点唯一，不存在数值爆炸；
#   · 稳定判定同时要求 X 与 Y 落在窗口内；
#   · 失稳有宽限期与保护停机，可重试，不吞掉已安装核心。
#
# 本文件不依赖任何场景节点，可无渲染单测（tests/test_coupled_model.gd）。
# ═══════════════════════════════════════════════════════════════════════════

# ── 可调参数 ──────────────────────────────────────────────────────────────
const STEP := 1.0 / 120.0          # 固定积分步长（保证与帧率无关）
const MAX_SUBSTEP := 0.10          # 单帧最多补 0.1 s，避免卡顿后积分爆冲

const ACCEL := 1.05                # 控制输入加速度
const DAMP := 3.0                  # 阻尼（越大越"稳"，越小越"飘"）
const MAX_SPEED := 0.36            # 控制量最大变化速度
const BRAKE_GAIN := 1.9            # 反向输入时额外的刹车增益

# 耦合：bx/by 是"对方的控制量对自己偏差的影响"
const COUPLING := 1.0              # 总耦合强度（0 = 两台独立设备，1 = 设计值）
const BX := 0.48                   # B 对 X 的影响
const BY := 0.52                   # A 对 Y 的影响
const BASE_X := 0.26
const BASE_Y := 0.77
const LOAD_X := 0.32               # 负载对 X 均衡位置的推动
const LOAD_Y := 0.28

# 窗口与进度
const WINDOW_COOP := 0.075         # 双人稳定窗口（X/Y 绝对值）
const WINDOW_SOLO := 0.085         # 单人略宽
const HOLD_FOR_STAGE := [5.0, 4.5, 3.5]   # 三个阶段各自需要的稳定时长
# 完美操作下三个阶段合计约 4.19/PROGRESS_RATE 秒；0.16 → 约 26 秒理论下限，
# 真人配合通常在 40–70 秒。
const PROGRESS_RATE := 0.16
const ARM_AFTER := 0.12            # 进度超过此值后才开始计失配
const FAIL_AFTER := 8.0            # 失配持续多久保护停机
const DECAY_RATE := 0.18           # 不稳定时进度回落速度

# 单人副控（有限速度、有限精度、不代替玩家）
const AUX_MAX_SPEED := 0.17        # 只有玩家的一半左右
const AUX_GAIN := 2.2
const AUX_LAG := 0.25              # 副控的反应延迟（一阶惯性）
const AUX_DEADBAND := 0.012        # 容差：不会把误差压到恰好为零
const AUX_AUTHORITY_MIN := 0.15    # 玩家那侧完全跑飞时，副控只剩这么多权限

# ── 状态 ──────────────────────────────────────────────────────────────────
var frequency: float = 0.20          # A：频率
var preload_value: float = 0.20          # B：核心相位
var a_speed: float = 0.0
var b_speed: float = 0.0
var load: float = 0.0              # L：真实蓄能负载 0..1
var progress: float = 0.0          # 0..1
var stage: int = 0                 # 0 初始同步 / 1 充能升载 / 2 稳定锁定
var clock: float = 0.0
var running: bool = false
var cooperative: bool = false
var stable_now: bool = false
var stable_seconds: float = 0.0    # 当前阶段已连续稳定多久
var stage_seconds: float = 0.0     # 当前阶段累计稳定（跨抖动累加）
var mismatch_seconds: float = 0.0
var two_operator_seconds: float = 0.0   # 两个不同 peer 同时在操作且稳定累计
var armed: bool = false
var failed: bool = false
var reason: String = "等待核心锁定"
var users: Dictionary = {"frequency": 0, "preload": 0}
var axes: Dictionary = {"frequency": 0.0, "preload": 0.0}
var heartbeat: Dictionary = {"frequency": -10.0, "preload": -10.0}
var solo_aux_role: String = ""     # 单人时由副控接管的那一端（""=无）
var solo_aux_axis: float = 0.0
var _aux_lag_axis: float = 0.0
var _accumulator: float = 0.0

# ── 生命周期 ──────────────────────────────────────────────────────────────
func begin(count: int) -> void:
    running = true
    failed = false
    cooperative = count > 1
    clock = 0.0
    progress = 0.0
    stage = 0
    load = 0.0
    stable_now = false
    stable_seconds = 0.0
    stage_seconds = 0.0
    mismatch_seconds = 0.0
    two_operator_seconds = 0.0
    armed = false
    a_speed = 0.0
    b_speed = 0.0
    _aux_lag_axis = 0.0
    users = {"frequency": 0, "preload": 0}
    axes = {"frequency": 0.0, "preload": 0.0}
    heartbeat = {"frequency": -10.0, "preload": -10.0}
    solo_aux_role = ""
    solo_aux_axis = 0.0
    reason = "两端一起调，别让对方跑飞"

func reset_keeps_core() -> void:
    # 保护停机后重试：保留核心，清空模型，不重置已安装状态。
    var was_coop: bool = cooperative
    begin(2 if was_coop else 1)

func role_of(peer_id: int) -> String:
    for role: String in users:
        if int(users[role]) == peer_id:
            return role
    return ""

func claim(peer_id: int, role: String) -> bool:
    if not running or not users.has(role):
        return false
    if int(users[role]) != 0 and int(users[role]) != peer_id:
        return false
    var previous: String = role_of(peer_id)
    if previous == role:
        return true
    release(peer_id)
    users[role] = peer_id
    heartbeat[role] = clock
    return true

func release(peer_id: int) -> void:
    var role: String = role_of(peer_id)
    if role == "":
        return
    users[role] = 0
    axes[role] = 0.0
    # 单人时释放的那一端立刻交给副控，不锁存、不需要第二个人。
    _update_aux_role()

func input_axis(peer_id: int, value: float) -> bool:
    var role: String = role_of(peer_id)
    if role == "":
        return false
    axes[role] = clampf(value, -1.0, 1.0)
    heartbeat[role] = clock
    return true

# ── 耦合与均衡 ────────────────────────────────────────────────────────────
func target_a() -> float:
    return BASE_X + BX * COUPLING * preload_value + LOAD_X * load

func target_b() -> float:
    return maxf(0.0, BASE_Y - BY * COUPLING * frequency - LOAD_Y * load)

func error_x() -> float:
    return frequency - target_a()

func error_y() -> float:
    return preload_value - target_b()

func window() -> float:
    return WINDOW_COOP if cooperative else WINDOW_SOLO

# 兼容旧调用方的命名
func frequency_goal() -> float:
    return clampf(target_a(), 0.0, 1.0)

func preload_goal() -> float:
    return clampf(target_b(), 0.0, 1.0)

func frequency_window() -> float:
    return window()

func preload_window() -> float:
    return window()

# ── 单人副控 ──────────────────────────────────────────────────────────────
func _update_aux_role() -> void:
    if cooperative or not running:
        solo_aux_role = ""
        solo_aux_axis = 0.0
        return
    var controlled := ""
    for role: String in users:
        if int(users[role]) != 0:
            controlled = role
            break
    if controlled == "":
        # 玩家还没上任何一台设备：副控不擅自开工。
        solo_aux_role = ""
        solo_aux_axis = 0.0
        return
    solo_aux_role = "preload" if controlled == "frequency" else "frequency"

func _drive_aux(h: float) -> void:
    if solo_aux_role == "":
        solo_aux_axis = 0.0
        _aux_lag_axis = 0.0
        return
    var own_error: float = error_y() if solo_aux_role == "preload" else error_x()
    var other_error: float = error_x() if solo_aux_role == "preload" else error_y()
    # 玩家那侧越跑飞，副控权限越低：单人也不能放着不管。
    var authority: float = clampf(1.0 - absf(other_error) / 0.35, AUX_AUTHORITY_MIN, 1.0)
    var desire: float = 0.0
    if absf(own_error) > AUX_DEADBAND:
        desire = clampf(-own_error * AUX_GAIN, -1.0, 1.0) * authority
    # 一阶惯性：副控不会瞬间修正
    var alpha: float = clampf(h / maxf(AUX_LAG, 0.001), 0.0, 1.0)
    _aux_lag_axis += (desire - _aux_lag_axis) * alpha
    solo_aux_axis = clampf(_aux_lag_axis, -1.0, 1.0)

# ── 积分 ──────────────────────────────────────────────────────────────────
func clamp_state() -> void:
    frequency = clampf(frequency, 0.0, 1.0)
    preload_value = clampf(preload_value, 0.0, 1.0)
    if frequency <= 0.0 and a_speed < 0.0:
        a_speed = 0.0
    if frequency >= 1.0 and a_speed > 0.0:
        a_speed = 0.0
    if preload_value <= 0.0 and b_speed < 0.0:
        b_speed = 0.0
    if preload_value >= 1.0 and b_speed > 0.0:
        b_speed = 0.0

func _step(h: float) -> void:
    var axis_a: float = float(axes["frequency"])
    var axis_b: float = float(axes["preload"])
    if solo_aux_role == "frequency":
        axis_a = solo_aux_axis
    elif solo_aux_role == "preload":
        axis_b = solo_aux_axis

    # 输入 → 加速度；反向输入同时提供刹车，避免"按反了也没用"的糊手感
    a_speed += (axis_a * ACCEL - a_speed * DAMP) * h
    if signf(axis_a) != 0.0 and signf(a_speed) != 0.0 and signf(axis_a) != signf(a_speed):
        a_speed += axis_a * BRAKE_GAIN * h
    b_speed += (axis_b * ACCEL - b_speed * DAMP) * h
    if signf(axis_b) != 0.0 and signf(b_speed) != 0.0 and signf(axis_b) != signf(b_speed):
        b_speed += axis_b * BRAKE_GAIN * h

    a_speed = clampf(a_speed, -MAX_SPEED, MAX_SPEED)
    b_speed = clampf(b_speed, -MAX_SPEED, MAX_SPEED)
    frequency += a_speed * h
    preload_value += b_speed * h
    clamp_state()

# ── 主循环 ────────────────────────────────────────────────────────────────
# 返回 true 表示本帧完成校准。
func tick(delta: float, actor_count: int) -> bool:
    clock += delta
    cooperative = actor_count > 1
    _update_aux_role()
    if not running:
        return false

    # 心跳：超时未发轴的那一端视为松手（掉线/离开设备）
    for role: String in users:
        if clock - float(heartbeat[role]) > 0.55:
            axes[role] = 0.0

    _accumulator += minf(delta, MAX_SUBSTEP)
    var steps: int = 0
    while _accumulator >= STEP and steps < 64:
        _accumulator -= STEP
        steps += 1
        _drive_aux(STEP)
        _step(STEP)
    if steps == 0:
        _drive_aux(minf(delta, MAX_SUBSTEP))

    _update_load_and_stage(delta)
    _update_stability(delta)
    if progress >= 1.0:
        running = false
        reason = "校准完成 · 共振稳定"
        return true
    return false

func _update_load_and_stage(delta: float) -> void:
    var previous_stage: int = stage
    if progress >= 0.72:
        stage = 2
    elif progress >= 0.34:
        stage = 1
    else:
        stage = 0
    if stage != previous_stage:
        stage_seconds = 0.0
        stable_seconds = 0.0
    # 负载跟随真实进度（不是随机数、不是固定计时），失稳时进度回落、负载随之下降
    load = clampf(progress / 0.72, 0.0, 1.0) * 0.85 + 0.05

func _update_stability(delta: float) -> void:
    var ex: float = error_x()
    var ey: float = error_y()
    var w: float = window()
    var both_sides: bool = false
    if cooperative:
        both_sides = int(users["frequency"]) > 0 and int(users["preload"]) > 0 \
            and int(users["frequency"]) != int(users["preload"])
    else:
        both_sides = int(users["frequency"]) > 0 or int(users["preload"]) > 0
    stable_now = both_sides and absf(ex) < w and absf(ey) < w

    if stable_now:
        stable_seconds += delta
        mismatch_seconds = maxf(0.0, mismatch_seconds - delta * 2.0)
        if cooperative and int(users["frequency"]) > 0 and int(users["preload"]) > 0 \
                and int(users["frequency"]) != int(users["preload"]):
            two_operator_seconds += delta
        var need: float = float(HOLD_FOR_STAGE[mini(stage, HOLD_FOR_STAGE.size() - 1)])
        # 阶段内按"累计稳定时间"推进，抖动不会把整个阶段重置
        stage_seconds = minf(stage_seconds + delta, need)
        var rate: float = 1.0 / need
        if stage == 2:
            rate *= 1.25   # 收尾稍快，避免机械重复
        progress = minf(1.0, progress + delta * rate * PROGRESS_RATE)
        if progress > ARM_AFTER:
            armed = true
        if stage == 0:
            reason = "两端靠近绿区 · 对方一动你的指针也会动"
        elif stage == 1:
            reason = "负载上升 · 均衡点在移动，跟着补偿"
        else:
            reason = "锁定中 · 一起稳住"
    else:
        progress = maxf(0.0, progress - delta * DECAY_RATE)
        stage_seconds = maxf(0.0, stage_seconds - delta * 2.0)
        if armed:
            mismatch_seconds += delta
        if not both_sides:
            reason = "只有一端在操作 · 另一端没人管" if cooperative else "先接入一台设备"
        else:
            reason = "偏离稳定带 · 你调那边，这边也会被带偏"
        if armed and mismatch_seconds >= FAIL_AFTER:
            failed = true
            running = false
            reason = "持续失配，保护停机。核心已保留，E 重新校准。"

# ── 快照（ENet 权威端同步用） ──────────────────────────────────────────────
# 这个字典会整包进 20 Hz 的 unreliable_ordered RPC。ENet 的 MTU 是 1392 字节，
# 超过会被直接丢掉（日志里能看到 "Sending ... bytes unreliably which is above the MTU"），
# 所以浮点统一保留 3 位，够显示和插值，不要按 double 打印。
func _r(value: float) -> float:
    return snappedf(value, 0.001)

func snapshot() -> Dictionary:
    return {
        "frequency": _r(frequency), "preload": _r(preload_value),
        "load": _r(load), "progress": _r(progress), "stage": stage,
        "clock": _r(clock), "running": running, "cooperative": cooperative,
        "users": users.duplicate(), "axes": axes.duplicate(),
        "stable_now": stable_now, "stable_seconds": _r(stable_seconds),
        "mismatch_seconds": _r(mismatch_seconds), "armed": armed, "failed": failed,
        "reason": reason, "error_x": _r(error_x()), "error_y": _r(error_y()),
        "target_a": _r(target_a()), "target_b": _r(target_b()), "window": _r(window()),
        "solo_aux_role": solo_aux_role, "solo_aux_axis": _r(solo_aux_axis),
        "two_operator_seconds": _r(two_operator_seconds),
    }

func apply_snapshot(data: Dictionary) -> void:
    frequency = float(data.get("frequency", 0.2))
    preload_value = float(data.get("preload_value", data.get("preload", 0.2)))
    a_speed = float(data.get("a_speed", 0.0))
    b_speed = float(data.get("b_speed", 0.0))
    load = float(data.get("load", 0.0))
    progress = float(data.get("progress", 0.0))
    stage = int(data.get("stage", 0))
    clock = float(data.get("clock", 0.0))
    running = bool(data.get("running", false))
    cooperative = bool(data.get("cooperative", false))
    users = (data.get("users", {}) as Dictionary).duplicate()
    axes = (data.get("axes", {}) as Dictionary).duplicate()
    stable_now = bool(data.get("stable_now", false))
    stable_seconds = float(data.get("stable_seconds", 0.0))
    mismatch_seconds = float(data.get("mismatch_seconds", 0.0))
    armed = bool(data.get("armed", false))
    failed = bool(data.get("failed", false))
    reason = str(data.get("reason", ""))
    solo_aux_role = str(data.get("solo_aux_role", ""))
    solo_aux_axis = float(data.get("solo_aux_axis", 0.0))
    clamp_state()
