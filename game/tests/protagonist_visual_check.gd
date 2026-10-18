extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player_3d.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var player := PLAYER_SCENE.instantiate() as SpacePlayer3D
    player.setup(1, Color("#35c5c4"))
    root.add_child(player)
    await process_frame
    var visual := player.get_node_or_null("ProtagonistVisual") as ProtagonistVisual
    assert(visual != null, "主角视觉场景必须加载")
    assert(visual.find_child("Helmet", true, false) != null, "头盔网格缺失")
    assert(visual.find_child("Visor", true, false) != null, "面罩网格缺失")
    assert(visual.find_child("Backpack", true, false) != null, "背包网格缺失")
    assert(visual.find_child("YellowShoulder", true, false) != null, "肩标网格缺失")
    visual.update_state(0.016, Vector2.RIGHT, false, false, true, 5)
    assert(visual.get_node("Body/CarriedBattery").visible, "拾取后携带物需显示")
    visual.update_state(0.016, Vector2.ZERO, true, false, false, 0)
    assert(not visual.get_node("Body/CarriedBattery").visible, "投送后携带物需隐藏")
    visual.update_state(0.016, Vector2.ZERO, false, false, false, 2)
    player.show_attack_animation()
    print("主角场景、网格和状态反馈检查通过")
    quit(0)
