extends "res://tests/unit/test_case.gd"

const MODEL: Script = preload("res://scripts/resonance_calibration.gd")

func test_two_buttons_do_not_solve() -> void:
    var model: RefCounted = MODEL.new() as RefCounted
    model.call("begin", 2)
    assert_true(model.call("claim", 1, "frequency"))
    assert_true(model.call("claim", 2, "preload"))
    for i: int in range(600): model.call("tick", 1.0 / 60.0, 2)
    assert_almost_eq(float(model.get("progress")), 0.0)
    assert_false(model.get("failed"), "Initial learning has no failure timer")

func test_control_exclusion_and_release() -> void:
    var model: RefCounted = MODEL.new() as RefCounted
    model.call("begin", 2)
    model.call("claim", 1, "frequency")
    assert_false(model.call("claim", 2, "frequency"))
    model.call("release", 1)
    assert_true(model.call("claim", 2, "frequency"))
    assert_eq(model.call("role_of", 1), "")

func test_failure_keeps_a_reason_and_replicates() -> void:
    var model: RefCounted = MODEL.new() as RefCounted
    model.call("begin", 2)
    model.call("claim", 1, "frequency")
    model.call("claim", 2, "preload")
    model.set("preload_value", float(model.call("preload_goal")))
    model.set("frequency", float(model.call("frequency_goal")))
    for i: int in range(40): model.call("tick", 1.0 / 60.0, 2)
    assert_true(model.get("armed"))
    model.set("frequency", 0.0)
    for i: int in range(490): model.call("tick", 1.0 / 60.0, 2)
    assert_true(model.get("failed"))
    assert_true("E" in str(model.get("reason")))
    var replica: RefCounted = MODEL.new() as RefCounted
    replica.call("apply_snapshot", model.call("snapshot"))
    assert_true(replica.get("failed"))

func test_single_player_latch_has_one_actor() -> void:
    var model: RefCounted = MODEL.new() as RefCounted
    model.call("begin", 1)
    model.call("claim", 1, "preload")
    model.set("preload_value", float(model.call("preload_goal")))
    model.call("release", 1)
    assert_true(float(model.get("solo_hold_until")) > 0.0)
    assert_eq((model.get("users") as Dictionary)["preload"], 0)
    assert_false(model.get("cooperative"))

func test_frequency_depends_on_preload() -> void:
    var model: RefCounted = MODEL.new() as RefCounted
    var before: float = float(model.call("frequency_goal"))
    model.set("preload_value", 0.8)
    assert_true(float(model.call("frequency_goal")) > before + 0.1)
