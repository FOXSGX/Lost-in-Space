extends "res://tests/input_driver.gd"

var network: Node
var stable_evidence: Dictionary={}
var peer_mode: String=""
var shared: String

func wait_for(predicate: Callable,seconds: float=30) -> bool:
    var until: int=Time.get_ticks_msec()+int(seconds*1000)
    while not predicate.call() and Time.get_ticks_msec()<until:await frames(1)
    return bool(predicate.call())

func marker(name_text: String) -> void:
    var file: FileAccess=FileAccess.open(shared.path_join(name_text),FileAccess.WRITE)
    file.store_string(str(OS.get_process_id()));file.close()

func exists(name_text: String) -> bool:return FileAccess.file_exists(shared.path_join(name_text))

func board() -> bool:
    var a: bool=await travel("entry",Vector2(-9.25,-1.82))
    var b: bool=await travel("aisle",Vector2(-5,-1.2))
    var c: bool=await travel("stairs",Vector2(1,-1.42))
    var d: bool=await travel("board",Vector2(1,1.42))
    return a and b and c and d and player.position.y>1.7

func run() -> void:
    await boot();network=scene.get("session") as Node;shared=output.get_base_dir()
    peer_mode="host" if OS.get_cmdline_user_args().has("--host") else "client"
    var connected: bool=await wait_for(func() -> bool:return (scene.get("actors") as Dictionary).size()==2 and str(network.get("mode"))==peer_mode)
    check(connected,"真实 ENet %s 已连接另一进程" % peer_mode)
    if not connected:await finish();return
    if peer_mode=="host":await host_flow()
    else:await client_flow()
    await finish()

func host_flow() -> void:
    check(await board(),"主机角色经真实台阶登车")
    await shot("00_host_aboard",6)
    await travel("tray",Vector2(.2,1.42));await press("pickup");await frames(35)
    check(str(device.get("phase"))=="held" and int(device.get("carrier_id"))==1,"主机权威记录核心由船员 1 持有")
    check(await wait_for(func() -> bool:return exists("client-steal.checked")),"客户端抢占与重复 nonce 检查完成")
    await travel("socket",Vector2(-1.22,2.20));await press("deposit")
    check(await wait_for(func() -> bool:return str(device.get("phase"))=="locked",8),"主机安装后两端可开始校准")
    await travel("frequency_console",Vector2(2.10,1.90));await press("repair")
    check(str(player.get("operating_role"))=="frequency","主机承担 A 端频率调谐")
    var model: RefCounted=device.get("calibration") as RefCounted
    check(await wait_for(func() -> bool:return int((model.get("users") as Dictionary)["preload"])>1),"另一真实 peer 占用 B 端预载")
    await frames(65)
    check(float(model.get("progress"))<.01,"两端只按 E、不调整参数，不能完成任务")
    marker("both-seated.marker")
    var shot_done: bool=false
    var until: int=Time.get_ticks_msec()+35000
    while str(device.get("phase"))=="calibrating" and Time.get_ticks_msec()<until:
        var error: float=float(model.call("frequency_goal"))-float(model.get("frequency"))
        stop();Input.action_press("move_right" if error>0 else "move_left",minf(1,absf(error)*18))
        await frames(1)
        if not shot_done and float(model.get("progress"))>.45:
            await shot("01_complementary_controls",3);shot_done=true
    stop();await frames(3)
    check(str(device.get("phase"))=="charging","不同操作者连续协调参数后进入充能")
    await shot("02_coop_charging",3)
    check(await wait_for(func() -> bool:return str(device.get("phase"))=="stable",10),"真实双客户端合作完成共振稳定")
    stable_evidence=device.call("stage_snapshot") as Dictionary
    check(float((stable_evidence["calibration"] as Dictionary)["two_operator_seconds"])>=3.5,"稳定积累来自真实不同 peer 的互补操作")
    await shot("03_host_stable",8);marker("host-stable.marker")
    check(await wait_for(func() -> bool:return exists("late-join.json"),35),"第三进程晚加入快照已记录")
    await frames(60)
    Input.action_press("reset_preview");await frames(2);Input.action_release("reset_preview");await frames(10)
    check(str(device.get("phase"))=="free" and int(device.get("epoch"))==1,"主机复位设备而不重建网络会话")
    marker("host-reset.marker")
    check(await wait_for(func() -> bool:return int(device.get("carrier_id"))>1,25),"客户端通过真实 RPC 取得重置后的同一核心")
    marker("host-ownership-observed.marker")
    check(await wait_for(func() -> bool:return (scene.get("actors") as Dictionary).size()==1 and int(device.get("carrier_id"))==0,15),"客户端断线后主机释放物品与控制席")
    await frames(65)
    check(str(device.get("phase"))=="free" and (device.get("core") as RigidBody3D).linear_velocity.length()<.2,"断线释放的核心落稳且样板仍可重试")

func client_flow() -> void:
    await frames(65)
    check(await board(),"客户端使用同一角色控制逻辑实际登车")
    check(await wait_for(func() -> bool:return str(device.get("phase"))=="held" and int(device.get("carrier_id"))==1),"客户端收到主机持芯的权威快照")
    await press("pickup");await frames(12)
    var ack: Array=network.get("acknowledgements") as Array
    check(not ack.is_empty() and not bool((ack[-1] as Dictionary)["ok"]),"客户端不能抢走主机手中的核心")
    network.rpc_id(1,"request_stage_action","pickup",701,int(device.get("revision")),int(network.get("sequence")))
    await frames(18)
    check(not ack.is_empty() and str((ack[-1] as Dictionary)["code"])=="REPLAYED_COMMAND","相同 nonce 经真实 RPC 被拒绝")
    marker("client-steal.checked")
    await travel("preload_console",Vector2(-1.35,1.74))
    check(await wait_for(func() -> bool:return str(device.get("phase"))=="locked"),"客户端观察安装与机械锁定同步")
    for _attempt: int in range(4):
        await press("repair");await frames(12)
        if str(player.get("operating_role"))=="preload":break
    check(str(player.get("operating_role"))=="preload","客户端承担 B 端锁爪预载")
    check(await wait_for(func() -> bool:return exists("both-seated.marker")),"A/B 角色互补就绪")
    var model: RefCounted=device.get("calibration") as RefCounted
    var perturbed: bool=false;var error_test: bool=false
    var until: int=Time.get_ticks_msec()+35000
    while str(device.get("phase"))=="calibrating" and Time.get_ticks_msec()<until:
        var error: float=float(model.call("preload_goal"))-float(model.get("preload_value"))
        stop();Input.action_press("move_up" if error>0 else "move_down",minf(1,absf(error)*18))
        await frames(1)
        if not perturbed and float(model.get("progress"))>.27:
            var before: float=float(model.get("progress"));perturbed=true
            stop();Input.action_press("move_up")
            var peak: float=before;var outside: bool=false
            for _j: int in range(90):
                await frames(1)
                peak=maxf(peak,float(model.get("progress")))
                if absf(float(model.get("preload_value"))-float(model.call("preload_goal")))>float(model.call("preload_window")):outside=true
            stop();await frames(10)
            error_test=outside and float(model.get("progress"))<peak-.03
            print("COOP_PERTURBATION ",JSON.stringify({"before":before,"peak":peak,"after":model.get("progress"),"outside_window":outside}))
            await shot("01_preload_mismatch",3)
    stop();await frames(3)
    check(perturbed and error_test,"B 端故意偏离预载使共同进度回落，恢复后可继续")
    check(await wait_for(func() -> bool:return str(device.get("phase"))=="stable",12),"客户端收到相同稳定成功状态")
    stable_evidence=device.call("stage_snapshot") as Dictionary
    check(int(stable_evidence["activation_count"])==1 and int(network.get("snapshots_received"))>30,"连续快照同步且成功只结算一次")
    await shot("02_client_stable",8)
    network.call("send_action","reset",0,int(device.get("revision")))
    var reset_nonce: int=int(network.get("sequence"))
    await wait_for(func() -> bool:return not ack.is_empty() and int((ack[-1] as Dictionary)["nonce"])==reset_nonce,5)
    check(not ack.is_empty() and str((ack[-1] as Dictionary)["code"])=="HOST_RESET_ONLY" and str(device.get("phase"))=="stable","客户端不能擅自执行主机复位")
    check(await wait_for(func() -> bool:return int(device.get("epoch"))==1,40),"主机复位在客户端同步且保留会话")
    await travel("reset_tray",Vector2(.2,1.42));await press("pickup");await frames(15)
    check(int(device.get("carrier_id"))==int(player.get("peer_id")),"客户端可拾取并同步自身核心归属")
    marker("client-carrying.marker")
    check(await wait_for(func() -> bool:return exists("host-ownership-observed.marker")),"主机已观测客户端归属后再断线")
    # Process exit below closes ENet after scene teardown, not before physics callbacks.

func finish() -> void:
    var data: Dictionary={"pid":OS.get_process_id(),"mode":peer_mode,"peer_id":player.get("peer_id"),"passed":failed==0,"stable_evidence":stable_evidence,"snapshots_received":network.get("snapshots_received"),"snapshots_sent":network.get("snapshots_sent"),"acks":network.get("acknowledgements"),"commands":network.get("commands"),"rejected_poses":network.get("rejected_poses")}
    var file: FileAccess=FileAccess.open(output.path_join("network.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
    await super.finish()
