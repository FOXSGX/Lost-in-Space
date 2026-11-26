extends RefCounted

# Host-owned two-control model. Frequency follows preload_value, so one successful
# button press cannot substitute for complementary control of the two axes.
var frequency: float = 0.20
var preload_value: float = 0.20
var progress: float = 0.0
var clock: float = 0.0
var running: bool = false
var cooperative: bool = false
var users: Dictionary = {"frequency": 0, "preload": 0}
var axes: Dictionary = {"frequency": 0.0, "preload": 0.0}
var heartbeat: Dictionary = {"frequency": -10.0, "preload": -10.0}
var solo_hold_until: float = -1.0
var frozen_preload_goal: float = 0.58
var stable_now: bool = false
var two_operator_seconds: float = 0.0
var reason: String = "等待核心锁定"
var failed: bool = false
var mismatch_seconds: float = 0.0
var armed: bool = false

func begin(count: int) -> void:
    running = true
    cooperative = count > 1
    reason = "分别调整频率与预载"

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
        release(peer_id)
        return true
    if previous != "":
        release(peer_id)
    users[role] = peer_id
    heartbeat[role] = clock
    return true

func release(peer_id: int) -> void:
    var role: String = role_of(peer_id)
    if role == "":
        return
    if not cooperative and role == "preload" and absf(preload_value - preload_goal()) < preload_window():
        frozen_preload_goal = preload_goal()
        solo_hold_until = clock + 24.0
    users[role] = 0
    axes[role] = 0.0

func input_axis(peer_id: int, value: float) -> bool:
    var role: String = role_of(peer_id)
    if role == "":
        return false
    axes[role] = clampf(value, -1.0, 1.0)
    heartbeat[role] = clock
    return true

func preload_goal() -> float:
    return frozen_preload_goal if solo_hold_until > clock and not cooperative else 0.58 + 0.065 * sin(clock * 0.21)

func frequency_goal() -> float:
    return 0.32 + preload_value * 0.30 + 0.055 * sin(clock * 0.40)

func frequency_window() -> float:
    return 0.045 if cooperative else 0.065

func preload_window() -> float:
    return 0.08 if cooperative else 0.11

func tick(delta: float, actor_count: int) -> bool:
    clock += delta
    cooperative = actor_count > 1
    if not running:
        return false
    for role: String in users:
        if clock - float(heartbeat[role]) > 0.55:
            axes[role] = 0.0
    frequency = clampf(frequency + float(axes["frequency"]) * 0.24 * delta, 0.0, 1.0)
    preload_value = clampf(preload_value + float(axes["preload"]) * 0.22 * delta, 0.0, 1.0)
    var distinct: bool = int(users["frequency"]) > 0 and int(users["preload"]) > 0 and int(users["frequency"]) != int(users["preload"])
    var support: bool = distinct if cooperative else (int(users["preload"]) > 0 or solo_hold_until > clock)
    stable_now = support and int(users["frequency"]) > 0 and absf(frequency - frequency_goal()) < frequency_window() and absf(preload_value - preload_goal()) < preload_window()
    if stable_now:
        mismatch_seconds = maxf(0.0, mismatch_seconds - delta * 2.0)
        progress = minf(1.0, progress + delta / (3.6 if cooperative else 5.5))
        if progress > 0.12: armed = true
        if cooperative:
            two_operator_seconds += delta
        reason = "共振收敛 · 保持两端对齐"
    else:
        progress = maxf(0.0, progress - delta * 0.20)
        if armed:
            mismatch_seconds += delta
        if not support:
            reason = "需要另一端预载" if cooperative else "先调好预载，再 E 锁存"
        else:
            reason = "对齐目标刻度 · 偏离会回落"
        if armed and mismatch_seconds >= 8.0:
            failed = true
            running = false
            reason = "失配持续过久，保护停机。核心已保留，E 重新校准。"
            return false
    if progress >= 1.0:
        running = false
        reason = "校准完成"
        return true
    return false

func snapshot() -> Dictionary:
    return {"frequency": frequency, "preload": preload_value, "progress": progress,
        "clock": clock, "running": running, "cooperative": cooperative,
        "users": users.duplicate(), "axes": axes.duplicate(),
        "solo_hold_until": solo_hold_until, "frozen_preload_goal": frozen_preload_goal,
        "stable_now": stable_now, "two_operator_seconds": two_operator_seconds,
        "reason": reason, "frequency_goal": frequency_goal(), "preload_goal": preload_goal(),
        "failed": failed, "mismatch_seconds": mismatch_seconds, "armed": armed}

func apply_snapshot(data: Dictionary) -> void:
    frequency = float(data["frequency"])
    preload_value = float(data["preload"])
    progress = float(data["progress"])
    clock = float(data["clock"])
    running = bool(data["running"])
    cooperative = bool(data["cooperative"])
    users = (data["users"] as Dictionary).duplicate()
    axes = (data["axes"] as Dictionary).duplicate()
    solo_hold_until = float(data["solo_hold_until"])
    frozen_preload_goal = float(data["frozen_preload_goal"])
    stable_now = bool(data["stable_now"])
    two_operator_seconds = float(data["two_operator_seconds"])
    reason = str(data["reason"])
    failed = bool(data.get("failed", false))
    mismatch_seconds = float(data.get("mismatch_seconds", 0.0))
    armed = bool(data.get("armed", false))
