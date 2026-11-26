extends "res://tests/test_playtest_solo.gd"

# 接入验收探针（新）：从主菜单正常进入、真实搬运并安装核心，
# 然后只由玩家操作 A 端频率，另一端交给有限速度副控，
# 看是否能在限定时间内走到 charging。
#
# 运行：--script res://tests/test_coupled_solo.gd -- <out> --loopback-test [--gain=7]

var rows: Array = []
var gain: float = 7.0

func sample(tag: String) -> void:
    var m: RefCounted = device.get("calibration") as RefCounted
    rows.append({
        "tag": tag, "t": float(m.get("clock")),
        "progress": float(m.get("progress")), "stage": int(m.get("stage")),
        "x": float(m.call("error_x")), "y": float(m.call("error_y")),
        "stable": bool(m.get("stable_now")), "aux": str(m.get("solo_aux_role")),
        "a": float(m.get("frequency")), "b": float(m.get("preload_value")),
        "phase": str(device.get("phase")), "reason": str(m.get("reason")),
    })

func run() -> void:
    output = OS.get_cmdline_user_args()[0]
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--gain="): gain = float(arg.get_slice("=", 1))
    await boot()

    var entry: bool = await travel("entry", Vector2(-9.25, -1.82))
    var aisle: bool = await travel("maintenance", Vector2(-5, -1.2))
    var align: bool = await travel("stairs", Vector2(1, -1.42))
    var aboard: bool = await travel("board", Vector2(1, 1.42))
    check(entry and aisle and align and aboard and player.position.y > 1.7, "沿真实台阶进入开放甲板")

    await travel("tray", Vector2(.2, 1.42))
    await frames(20)
    await press("pickup")
    await frames(35)
    check(str(device.get("phase")) == "held", "拾取核心")

    await travel("socket", Vector2(-1.22, 2.20))
    await press("deposit")
    await frames(115)
    check(str(device.get("phase")) == "locked", "核心安装并锁定")

    var at_a: bool = await travel("frequency_console", Vector2(2.10, 1.90))
    await press("repair")
    check(at_a and str(player.get("operating_role")) == "frequency", "单人接入 A 端频率")
    var model: RefCounted = device.get("calibration") as RefCounted
    check(str(model.get("solo_aux_role")) == "preload", "副控接管 B 端相位")

    var begin: int = Time.get_ticks_msec()
    var stages: Array = []
    var last_sample: int = begin
    var aux_seen: bool = false
    var fake_peer_seen: bool = false
    var shot_done: bool = false
    var early_shot_done: bool = false
    while Time.get_ticks_msec() - begin < 150000:
        if str(device.get("phase")) != "calibrating":
            break
        var target: float = float(model.call("frequency_goal"))
        var value: float = float(model.get("frequency"))
        var axis: float = clampf((target - value) * gain, -1.0, 1.0)
        stop()
        Input.action_press("move_right" if axis > 0.0 else "move_left", absf(axis))
        if str(model.get("solo_aux_role")) == "preload":
            aux_seen = true
        if int((model.get("users") as Dictionary)["preload"]) != 0:
            fake_peer_seen = true
        if stages.is_empty() or int(stages[-1]) != int(model.get("stage")):
            stages.append(int(model.get("stage")))
        # 两个证据帧：一开始两边偏离时环体两半不同步；锁定阶段 HUD 收敛。
        if not early_shot_done and int(model.get("stage")) == 0 and float(model.get("progress")) < 0.12:
            early_shot_done = true
            await shot("coupled_ring_unstable", 3, 1.64)
        if not shot_done and int(model.get("stage")) == 2 and float(model.get("progress")) > 0.86:
            shot_done = true
            await shot("coupled_stage2", 3)
        if Time.get_ticks_msec() - last_sample > 2000:
            last_sample = Time.get_ticks_msec()
            sample("tick")
        await frames(1)
    stop()
    await frames(5)
    sample("end")

    var elapsed: float = float(Time.get_ticks_msec() - begin) / 1000.0
    var reached: bool = str(device.get("phase")) in ["charging", "stable"]
    check(reached, "单人（玩家 A + 副控 B）完成校准")
    check(elapsed <= 120.0, "校准用时在 120 秒以内")
    check(stages.size() >= 3, "实际推进了三个阶段")
    check(aux_seen, "全程由副控承担 B 端")
    check(not fake_peer_seen, "副控没有伪装成第二个玩家")

    var data: Dictionary = {"gain": gain, "elapsed": elapsed, "stages": stages,
        "checks": checks, "failed": failed, "final": device.call("stage_snapshot"),
        "calibration": model.call("snapshot"), "samples": rows}
    var f: FileAccess = FileAccess.open(output.path_join("coupled-solo.json"), FileAccess.WRITE)
    f.store_string(JSON.stringify(data, "  ")); f.close()
    print("COUPLED_SOLO_RESULT ", JSON.stringify({"passed": failed == 0, "failures": failed,
        "phase": str(device.get("phase")), "elapsed": elapsed, "stages": stages}))
    await finish()
