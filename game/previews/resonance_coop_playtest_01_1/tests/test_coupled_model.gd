extends SceneTree

# 双向耦合校准模型的无渲染确定性测试。
# 运行：godot --headless --path <project> --script res://tests/test_coupled_model.gd
# 不依赖场景、渲染、输入或网络；只验证模型本身是否满足任务书的可验证条件。

const Model := preload("res://scripts/coupled_calibration.gd")

var failures: int = 0
var passes: int = 0

func check(ok: bool, label: String, detail: String = "") -> void:
    if ok:
        passes += 1
        print("COUPLED_OK   ", label, ("  " + detail) if detail != "" else "")
    else:
        failures += 1
        print("COUPLED_FAIL ", label, ("  " + detail) if detail != "" else "")

func fresh(coop: bool = true) -> RefCounted:
    var m: RefCounted = Model.new()
    m.call("begin", 2 if coop else 1)
    return m

# 用比例控制器把某一端推近它的均衡位置；axis 上限 1。
func drive(m: RefCounted, role: String, gain: float = 6.0) -> void:
    var value: float = float(m.get("frequency") if role == "frequency" else m.get("preload_value"))
    var target: float = float(m.call("target_a" if role == "frequency" else "target_b"))
    m.call("input_axis", int((m.get("users") as Dictionary)[role]), clampf((target - value) * gain, -1.0, 1.0))

func run_for(m: RefCounted, seconds: float, dt: float, both: bool = true, solo_role: String = "") -> float:
    var elapsed: float = 0.0
    while elapsed < seconds - 1e-9:
        if both:
            drive(m, "frequency")
            drive(m, "preload")
        elif solo_role != "":
            drive(m, solo_role)
            m.call("input_axis", int((m.get("users") as Dictionary)[solo_role]), clampf(
                (float(m.call("target_a" if solo_role == "frequency" else "target_b")) -
                 float(m.get("frequency" if solo_role == "frequency" else "preload_value"))) * 6.0, -1.0, 1.0))
        m.call("tick", dt, 2 if bool(m.get("cooperative")) else 1)
        elapsed += dt
    return elapsed

func test_coupling_a_to_b() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    var y0: float = float(m.call("error_y"))
    for _i: int in range(60):
        m.call("input_axis", 1, 1.0)
        m.call("tick", 1.0 / 60.0, 2)
    var y1: float = float(m.call("error_y"))
    check(y1 > y0 + 0.02, "A 单独上推会抬高 Y（影响对方）", "Y %.3f -> %.3f" % [y0, y1])

func test_coupling_b_to_a() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    var x0: float = float(m.call("error_x"))
    for _i: int in range(60):
        m.call("input_axis", 2, 1.0)
        m.call("tick", 1.0 / 60.0, 2)
    var x1: float = float(m.call("error_x"))
    check(x1 < x0 - 0.02, "B 单独上推会压低 X（影响对方）", "X %.3f -> %.3f" % [x0, x1])

func test_both_converge() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    var start: float = float(m.get("clock"))
    var stages_seen: Array = []
    while float(m.get("clock")) - start < 120.0:
        drive(m, "frequency")
        drive(m, "preload")
        var current_stage: int = int(m.get("stage"))
        if stages_seen.is_empty() or int(stages_seen[-1]) != current_stage:
            stages_seen.append(current_stage)
        if bool(m.call("tick", 1.0 / 60.0, 2)):
            break
    var took: float = float(m.get("clock")) - start
    check(float(m.get("progress")) >= 1.0, "两端协作可完成校准",
        "progress=%.2f 用时 %.1fs stage=%d reason=%s" % [float(m.get("progress")), took, int(m.get("stage")), str(m.get("reason"))])
    check(took >= 18.0 and took <= 60.0, "完美操作下校准用时落在几十秒区间", "%.1fs" % took)
    check(stages_seen.size() >= 3, "充能阶段按 0→1→2 依次推进", str(stages_seen))

func test_stop_input_settles() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    for _i: int in range(90):
        m.call("input_axis", 1, 1.0)
        m.call("input_axis", 2, -1.0)
        m.call("tick", 1.0 / 60.0, 2)
    # 松手后应有余速（惯性）继续走一小段，然后停住，而不是永远漂移或发散。
    for _i: int in range(180):
        m.call("tick", 1.0 / 60.0, 2)
    var settle_1: float = absf(float(m.call("error_x"))) + absf(float(m.call("error_y")))
    var speed: float = absf(float(m.get("a_speed"))) + absf(float(m.get("b_speed")))
    for _i: int in range(180):
        m.call("tick", 1.0 / 60.0, 2)
    var settle_2: float = absf(float(m.call("error_x"))) + absf(float(m.call("error_y")))
    check(speed < 0.02, "松手后余速会衰减到零", "speed=%.4f" % speed)
    check(absf(settle_2 - settle_1) < 0.05, "松手后系统停住，不再持续漂移",
        "3s=%.3f 6s=%.3f" % [settle_1, settle_2])
    # 关键：被推到边角后，玩家重新操作仍然能把它拉回稳定带（可恢复性）。
    var recovered: bool = false
    for _i: int in range(60 * 40):
        drive(m, "frequency")
        drive(m, "preload")
        m.call("tick", 1.0 / 60.0, 2)
        if bool(m.get("stable_now")):
            recovered = true
            break
    check(recovered, "推到边角后仍可重新拉回稳定带", "reason=%s" % str(m.get("reason")))

func test_no_input_never_completes() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    for _i: int in range(60 * 60):
        m.call("tick", 1.0 / 60.0, 2)
    check(float(m.get("progress")) < 0.02, "没有输入时永远不会自动完成",
        "progress=%.3f" % float(m.get("progress")))

func test_one_side_only_cannot_complete() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    run_for(m, 90.0, 1.0 / 60.0, false, "frequency")
    check(float(m.get("progress")) < 0.5, "只有一端操作时无法完成",
        "progress=%.3f" % float(m.get("progress")))

func test_wrong_input_fails() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    # 先攒一点进度，让保护停机进入 armed
    var elapsed: float = 0.0
    while elapsed < 20.0 and not bool(m.get("armed")):
        drive(m, "frequency")
        drive(m, "preload")
        m.call("tick", 1.0 / 60.0, 2)
        elapsed += 1.0 / 60.0
    var armed: bool = bool(m.get("armed"))
    # 然后两端同时反向猛推
    var failed: bool = false
    for _i: int in range(60 * 20):
        m.call("input_axis", 1, -1.0)
        m.call("input_axis", 2, 1.0)
        m.call("tick", 1.0 / 60.0, 2)
        if bool(m.get("failed")):
            failed = true
            break
    check(armed and failed, "反向错误操作会触发保护停机",
        "armed=%s failed=%s" % [str(armed), str(failed)])

func test_recovery_after_failure() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    m.call("reset_keeps_core")
    check(bool(m.get("running")) and not bool(m.get("failed")) and float(m.get("progress")) < 0.01,
        "停机后可重新开始且不残留旧状态")

func test_time_step_independence() -> void:
    var a: RefCounted = fresh()
    var b: RefCounted = fresh()
    a.call("claim", 1, "frequency")
    b.call("claim", 1, "frequency")
    for _i: int in range(int(1.2 / (1.0 / 60.0))):
        a.call("input_axis", 1, 1.0)
        a.call("tick", 1.0 / 60.0, 2)
    for _i: int in range(int(1.2 / (1.0 / 144.0))):
        b.call("input_axis", 1, 1.0)
        b.call("tick", 1.0 / 144.0, 2)
    var delta: float = absf(float(a.get("frequency")) - float(b.get("frequency")))
    check(delta < 0.02 and float(a.get("frequency")) < 0.95,
        "1/60 与 1/144 步长结果一致（未饱和区间）", "a=%.4f b=%.4f 差 %.4f" % [
        float(a.get("frequency")), float(b.get("frequency")), delta])

func test_solo_aux_needs_player() -> void:
    var m: RefCounted = fresh(false)
    m.call("claim", 1, "frequency")
    for _i: int in range(60 * 60):
        m.call("tick", 1.0 / 60.0, 1)
    check(float(m.get("progress")) < 0.5, "单人只靠副控不能自动完成",
        "progress=%.3f aux=%s" % [float(m.get("progress")), str(m.get("solo_aux_role"))])

func test_solo_player_plus_aux_completes() -> void:
    var m: RefCounted = fresh(false)
    m.call("claim", 1, "frequency")
    var start: float = float(m.get("clock"))
    var ok: bool = false
    while float(m.get("clock")) - start < 90.0:
        drive(m, "frequency")
        if bool(m.call("tick", 1.0 / 60.0, 1)):
            ok = true
            break
    check(ok or float(m.get("progress")) >= 1.0, "单人（玩家 + 有限速副控）可以完成",
        "progress=%.2f 用时 %.1fs" % [float(m.get("progress")), float(m.get("clock")) - start])

func test_bounds_and_nan() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261020
    var bad: bool = false
    for i: int in range(60 * 120):
        m.call("input_axis", 1, rng.randf_range(-1.0, 1.0))
        m.call("input_axis", 2, rng.randf_range(-1.0, 1.0))
        m.call("tick", rng.randf_range(0.001, 0.05), 2)
        for key: String in ["frequency", "preload_value", "load", "progress"]:
            var v: float = float(m.get(key))
            if is_nan(v) or v < -0.0001 or v > 1.0001:
                bad = true
    check(not bad, "极端随机输入下所有状态量保持有界且非 NaN")

func test_snapshot_roundtrip() -> void:
    var m: RefCounted = fresh()
    m.call("claim", 1, "frequency")
    m.call("claim", 2, "preload")
    for _i: int in range(120):
        drive(m, "frequency")
        drive(m, "preload")
        m.call("tick", 1.0 / 60.0, 2)
    var snap: Dictionary = m.call("snapshot") as Dictionary
    var other: RefCounted = fresh()
    other.call("apply_snapshot", snap)
    var same: bool = absf(float(other.get("frequency")) - float(m.get("frequency"))) < 2e-3 \
        and absf(float(other.get("preload_value")) - float(m.get("preload_value"))) < 2e-3 \
        and absf(float(other.get("progress")) - float(m.get("progress"))) < 2e-3 \
        and int(other.get("stage")) == int(m.get("stage"))
    check(same, "快照可完整还原（权威端 → 客户端）")

func _initialize() -> void:
    test_coupling_a_to_b()
    test_coupling_b_to_a()
    test_both_converge()
    test_stop_input_settles()
    test_no_input_never_completes()
    test_one_side_only_cannot_complete()
    test_wrong_input_fails()
    test_recovery_after_failure()
    test_time_step_independence()
    test_solo_aux_needs_player()
    test_solo_player_plus_aux_completes()
    test_bounds_and_nan()
    test_snapshot_roundtrip()
    print("COUPLED_RESULT ", JSON.stringify({"passes": passes, "failures": failures,
        "passed": failures == 0}))
    quit(0 if failures == 0 else 1)
