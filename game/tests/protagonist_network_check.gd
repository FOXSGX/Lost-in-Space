extends SceneTree

const MAIN_SCENE := preload("res://scenes/main_3d.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var mode := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
    var game := MAIN_SCENE.instantiate() as Main3D
    root.add_child(game)
    await process_frame
    if mode == "host":
        game._create_host()
    elif mode == "client":
        await create_timer(0.4).timeout
        game._address_edit.text = "127.0.0.1"
        game._join_host()
    else:
        push_error("需要 host 或 client 参数")
        quit(2)
        return
    await create_timer(2.0).timeout
    if game.players.size() < 2:
        push_error("联机角色未生成：%s，玩家数量 %d" % [mode, game.players.size()])
        quit(1)
        return
    for player in game.players.values():
        if player.get_node_or_null("ProtagonistVisual") == null:
            push_error("联机角色缺少 3D 外观：" + mode)
            quit(1)
            return
    if mode == "host":
        await create_timer(0.3).timeout
        game.set_revive_visual.rpc(1, true)
        await create_timer(0.8).timeout
        game.set_revive_visual.rpc(1, false)
    else:
        await create_timer(0.2).timeout
        var host_player := game.players.get(1) as SpacePlayer3D
        if host_player == null or not host_player._visual._rescuing:
            push_error("客户端未收到救援动作同步")
            quit(1)
            return
    print("联机主角检查通过：", mode)
    quit(0)
