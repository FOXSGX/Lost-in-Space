extends RefCounted
class_name FrostFieldInteractions

# 可选的现场操作不增加通关门槛；状态与奖励由主机统一结算。
const INTERACTION_RADIUS := 2.8
const SITES := [
    {"id": "landing_terminal", "name": "地表联络终端", "position": Vector2(-159, 103), "kind": "terminal"},
    {"id": "emergency_locker", "name": "应急补给箱", "position": Vector2(-169, 100), "kind": "locker"},
    {"id": "camp_radio", "name": "科考队录音机", "position": Vector2(-125, -63), "kind": "radio"},
    {"id": "field_heater", "name": "损坏的野外供暖炉", "position": Vector2(-55, 49), "kind": "heater"},
    {"id": "weather_scope", "name": "手动气象观测镜", "position": Vector2(-121, -84), "kind": "scope"},
    {"id": "sample_station", "name": "样本隔离台", "position": Vector2(33, 68), "kind": "sample"},
    {"id": "cargo_winch", "name": "运输舱牵引绞盘", "position": Vector2(144, 63), "kind": "winch"},
    {"id": "crew_helmet", "name": "雪中的队员头盔", "position": Vector2(-112, 58), "kind": "helmet"},
    {"id": "west_sign", "name": "倒下的台地路标", "position": Vector2(-122, -23), "kind": "sign"},
    {"id": "north_sign", "name": "倒下的北岸路标", "position": Vector2(49, -64), "kind": "sign"}
]

var controller: Node3D
var states: Dictionary = {}
var jobs: Dictionary = {}
var nodes: Dictionary = {}
var _sync_elapsed := 0.0
var _time := 0.0

func _init(owner: Node3D) -> void:
    controller = owner

func build() -> void:
    reset()
    for site in SITES:
        var id := String(site.id)
        states[id] = {"seen": false, "opened": false, "repaired": false, "boosted": false, "heard": false, "answered": false, "sealed": false, "charges": controller.MAX_PLAYERS, "used_by": []}
        var root := Node3D.new()
        root.name = "FieldSite_" + id
        var point := Vector2(site.position)
        root.position = Vector3(point.x, controller.terrain_height(point), point.y)
        controller._world_root.add_child(root)
        nodes[id] = root
        _build_model(root, String(site.kind))
        var ring := MeshInstance3D.new()
        ring.name = "InteractionRing"
        var ring_mesh := TorusMesh.new()
        ring_mesh.inner_radius = 1.0
        ring_mesh.outer_radius = 1.045
        ring_mesh.rings = 32
        ring_mesh.ring_segments = 8
        ring.mesh = ring_mesh
        ring.position.y = 0.07
        ring.material_override = controller._glow_material(Color("#83e1d2"), 0.75)
        ring.visible = false
        root.add_child(ring)
        var label := Label3D.new()
        label.name = "FieldLabel"
        label.text = String(site.name)
        label.position.y = 2.25
        label.font_size = 40
        label.pixel_size = 0.009
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.outline_size = 10
        label.outline_modulate = Color("#081a25")
        label.modulate = Color("#b8f5e9")
        label.shaded = false
        label.visible = false
        root.add_child(label)
    _apply_visuals()

func reset() -> void:
    for peer_id in jobs:
        var player := controller.players.get(int(peer_id)) as SpacePlayer3D
        if player != null:
            player.show_rescue_animation(false)
    states.clear()
    jobs.clear()
    nodes.clear()
    _sync_elapsed = 0.0
    _time = 0.0

func nearest(player: SpacePlayer3D) -> Dictionary:
    var best: Dictionary = {}
    var distance := INTERACTION_RADIUS
    for site in SITES:
        var node := nodes.get(String(site.id)) as Node3D
        if not is_instance_valid(node):
            continue
        var candidate_distance: float = controller._flat_distance(player.global_position, node.global_position)
        if candidate_distance <= distance:
            distance = candidate_distance
            best = site
    return best

func prompt(player: SpacePlayer3D) -> String:
    if jobs.has(player.peer_id):
        var job: Dictionary = jobs[player.peer_id]
        return "%s · %.1f / %.1f 秒 · 离开或再按 E 中止" % [String(job.label), float(job.elapsed), float(job.duration)]
    var site := nearest(player)
    if site.is_empty():
        return ""
    var state: Dictionary = states.get(String(site.id), {})
    match String(site.kind):
        "terminal": return "[E] 呼叫归航号 · 查询当前任务与路线"
        "locker":
            if not bool(state.get("opened", false)):
                return "[E] 解冻补给箱锁扣 · 留在附近 1.8 秒"
            if state.get("used_by", []).has(player.peer_id):
                return "补给已领取 · 给其他船员留一份"
            return "[E] 领取应急补给 · 剩余 %d 份" % int(state.get("charges", 0))
        "radio": return "[E] 回应并转发给飞船" if bool(state.get("heard", false)) and not bool(state.get("answered", false)) else "[E] 播放科考队录音"
        "heater":
            if not bool(state.get("repaired", false)):
                return "[E] 修理供暖炉 · 留在附近 3 秒"
            if bool(state.get("boosted", false)):
                return "[E] 查看供暖炉 · 强化热源已开启"
            return "[E] 安装电池，扩大热源" if controller._items.count_kind(player.peer_id, "battery") > 0 else "[E] 查看供暖炉 · 需要一枚电池才能强化"
        "scope": return "[E] 手动观测天气 · 留在附近 2 秒"
        "sample":
            if bool(state.get("sealed", false)):
                return "[E] 查看已封存的冰样"
            if controller._items.count_kind(player.peer_id, "sample") == 0:
                return "[E] 查看检测报告 · 紫色冰样按 E 拾取，带来后按 E 封存"
            return "[E] 封存冰样，回收 +20"
        "winch":
            if bool(state.get("opened", false)):
                return "[E] 重读运输舱货单"
            return "[E] 操作绞盘回收货物 · 留在附近 3 秒"
        "helmet": return "[E] 把姓名与留言送回飞船" if bool(state.get("heard", false)) and not bool(state.get("answered", false)) else "[E] 查看队员头盔"
        "sign":
            return "[E] 查看路标与下一段路线" if bool(state.get("repaired", false)) else "[E] 扶正反光路标 · 留在附近 1.2 秒"
    return ""

func interaction_progress(peer_id: int) -> float:
    if not jobs.has(peer_id):
        return 0.0
    var job: Dictionary = jobs[peer_id]
    return clampf(float(job.get("elapsed", 0.0)) / maxf(float(job.get("duration", 1.0)), 0.01), 0.0, 1.0)

func has_interaction_job(peer_id: int) -> bool:
    return jobs.has(peer_id)

func handle_action(peer_id: int, action: String) -> bool:
    if action not in ["repair", "deposit"]:
        return false
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return false
    if jobs.has(peer_id):
        if action == "repair":
            _cancel_job(peer_id)
            _publish()
        return true
    var site := nearest(player)
    if site.is_empty():
        return false
    var id := String(site.id)
    var state: Dictionary = states[id]
    state["seen"] = true
    if action == "deposit":
        if String(site.kind) not in ["radio", "heater", "sample", "helmet"]:
            return false
        _secondary_action(site, player)
        _publish()
        return true
    controller.story_flags["field_interaction_used"] = true
    match String(site.kind):
        "terminal":
            controller._reveal_next_beacon_signal()
            controller._record_journal("归航号联络", "第一座信标是我们恢复地表航线的起点。修复后读旧气象站记录，再追踪裂谷与阵列。电池和冰样可以自选回收，先把人带回来。")
            controller._story_beat("arc_terminal", "回声档案 · 归航号", "终端重新接通归航号。飞船确认失联队伍没有撤离舱，只有一条不断指向冰层下方的回波。", "归航号：听得见你。先找到第一座信标；供暖点和地表设备会帮你走完这段路。", 8.0)
            _route_feedback(player)
        "locker":
            if not bool(state.opened):
                _begin_job(peer_id, site, 1.8, "解冻补给箱")
            else:
                _take_supplies(site, player)
        "radio":
            state["heard"] = true
            controller._reveal_landmark_signal("weather_station")
            controller._record_journal("科考队录音 · 岑夏", "岑夏留在台地记录天气，陆衡去了东北裂谷。信标一亮，风暴就从冰层里升起；他们把观测资料留在旧气象站，盼后来者先读记录。")
            controller._story_beat("arc_radio", "回声档案 · 岑夏的声音", "岑夏把观测资料留在旧气象站，陆衡带着队伍去了裂谷。他们没有约定谁回来，只约定让后来者听见。", "岑夏的录音：陆衡去了裂谷。我把记录留在旧气象站。灯会叫醒冰层里的东西，别只顾着修它。", 8.0)
        "heater":
            if not bool(state.repaired):
                _begin_job(peer_id, site, 3.0, "接回供暖炉线路")
            else:
                _feedback("供暖炉正在补氧回温；安装电池能把热源从 5m 扩大到 8.5m。", Color("#ffc883"))
        "scope":
            if controller.mission_elapsed < float(state.get("next_observation", 0.0)):
                _feedback("观测镜正在归零，稍候再测。")
            else:
                _begin_job(peer_id, site, 2.0, "对准气象观测镜")
        "sample":
            state["heard"] = true
            controller._record_journal("样本检测报告", "所谓晶体回波就是异常冰样的扫描信号。样本是可选回收物，取出后会招来生物；带到这张隔离台按 E 封存可回收 +20，也可以去撤离平台投送。")
            _story("检测台：冰样仍在发出热脉。带走它会引来生物；封进隔离舱，才能把它作为研究资料安全回收。")
        "winch":
            if not bool(state.opened):
                _begin_job(peer_id, site, 3.0, "卷起运输舱钢索")
            else:
                controller._story_beat("arc_transport", "回声档案 · 留给后来者", "货单最后一行不是货物，是名单：药品和氧气给下一队，样本必须封存。有人早就把自己写成了下一队。", "货单旁写着：陆衡，把药和氧气留给回来的人。研究可以等，人不能。——岑夏", 8.0)
        "helmet":
            state["heard"] = true
            controller._record_journal("陆衡的头盔", "陆衡的最后留言：我把岑夏的呼号录进了阵列，它仍在重复，并不代表她还活着。回去时，请替我们回应一次。")
            controller._story_beat("arc_helmet", "回声档案 · 陆衡的头盔", "陆衡没有留下求救坐标。他把岑夏的呼号录进阵列，只希望下一支队伍知道他们曾经来过。", "头盔里是陆衡的声音：阵列重复的是我们留下的录音。如果有人听见，请把我们的名字带回去。", 8.0)
        "sign":
            if not bool(state.repaired):
                _begin_job(peer_id, site, 1.2, "扶正反光路标")
            else:
                _route_feedback(player)
    _publish()
    return true

func _secondary_action(site: Dictionary, player: SpacePlayer3D) -> void:
    var state: Dictionary = states[String(site.id)]
    match String(site.kind):
        "radio", "helmet":
            if not bool(state.heard):
                _feedback("先按 E 听完记录，再决定是否送回飞船。")
                return
            if bool(state.answered):
                _feedback("归航号已收到这段留言，不必重复发送。")
                return
            state["answered"] = true
            controller.story_flags["crew_message_returned"] = true
            controller._record_journal("回应失联科考队", "我们回应了岑夏和陆衡留下的声音，将姓名与现场记录传回归航号。地底仍有回声，但飞船已确认收到他们的故事。")
            controller._story_beat("arc_reply", "回声档案 · 回应", "我们回应了岑夏和陆衡，将姓名与现场记录传回归航号。失联队伍终于从一段噪声变成了可被记住的人。", "你：岑夏、陆衡，我们听见了。归航号：姓名与记录已接收。谢谢你没有把他们留在雪里。", 8.0)
        "heater":
            if not bool(state.repaired):
                _feedback("先修好供暖炉线路，才能安装电池。")
                return
            if bool(state.boosted):
                _feedback("供暖炉已装有电池，无需继续投入。")
                return
            if not _valid_carried_item(player, 1):
                _feedback("先按 E 拾取一枚热能电池，再来按 E 安装；电池会用于供暖。")
                return
            state["boosted"] = true
            _consume_inventory_cargo(player, "battery", 1)
            controller._record_journal("野外供暖炉", "一枚回收电池被留在供暖炉里，换成了更宽的热源。留在这里的能源，能让队伍往返时多一个避风点。")
            _feedback("电池已安装 · 热源扩大到 8.5m · 这枚电池已用于供暖", Color("#ffc883"))
            _pulse(site, Color("#ffbd61"))
        "sample":
            if bool(state.sealed):
                _feedback("隔离舱已经装满；其他冰样请带到撤离平台投送。")
                return
            if not _valid_carried_item(player, 2):
                _feedback("手里没有异常冰样。找到紫色冰样，按 E 拾取后再来封存。")
                return
            state["sealed"] = true
            _consume_inventory_cargo(player, "sample", 2)
            controller.salvage_value += controller.SAMPLE_VALUE
            controller._record_journal("现场封存", "冰样封进科考队留下的隔离舱，脉冲被挡在舱壁内。回收 +20，队员不必继续背着它引来敌人。")
            _feedback("冰样已封存 · 回收价值 +20 · 双手已腾出", Color("#c4b5ff"))
            _pulse(site, Color("#b8a1ff"))

func _consume_inventory_cargo(player: SpacePlayer3D, item: String, kind: int) -> void:
    var reference: int = player.carrying_id
    player.carrying = 0
    player.carrying_id = 0
    controller._items.remove_item(player.peer_id, item, reference)
    controller._consume_lost_cargo(kind, reference)
    controller._items.publish()

func _valid_carried_item(player: SpacePlayer3D, kind: int) -> bool:
    if player.carrying != kind or player.carrying_id <= 0:
        return false
    return controller.taken_crates.has(player.carrying_id) if kind == 1 else controller.taken_samples.has(player.carrying_id)

func _take_supplies(site: Dictionary, player: SpacePlayer3D) -> void:
    var state: Dictionary = states[String(site.id)]
    var used_by: Array = state.used_by
    if used_by.has(player.peer_id) or int(state.charges) <= 0:
        _feedback("给队友的补给已经留好；每名船员限领一份。")
        return
    if player.health >= 5 and player.oxygen >= 99.0 and player.warmth >= 0.99:
        _feedback("生命、氧气和体温充足；需要时再回来领取。")
        return
    player.health = mini(player.health + 1, 5)
    player.oxygen = minf(player.oxygen + 40.0, 100.0)
    player.warmth = minf(player.warmth + 0.25, 1.0)
    used_by.append(player.peer_id)
    state["charges"] = int(state.charges) - 1
    controller._record_journal("应急补给", "箱子里有一份包好的防寒毯、备用氧气和止血贴。岑夏写着：留给下一队人。每名队员领取一份，余下的留给同行者。")
    _feedback("已使用补给 · 生命 +1，氧气 +40，体温 +25%", Color("#9fe8cf"))
    _pulse(site, Color("#8ff1a0"))

func _begin_job(peer_id: int, site: Dictionary, duration: float, label: String) -> void:
    # 同一个装置一次只允许一位船员操作，避免重复结算货物或开箱奖励。
    for job in jobs.values():
        if String(job.id) == String(site.id):
            _feedback("队友正在操作这台设备，请帮他照看附近。")
            return
    jobs[peer_id] = {"id": String(site.id), "duration": duration, "elapsed": 0.0, "label": label}
    var player := controller.players.get(peer_id) as SpacePlayer3D
    player.show_rescue_animation(true)
    _feedback(label + " · 留在设备附近，移动离开或再按 E 可中止", Color("#9fe8cf"))

func _cancel_job(peer_id: int) -> void:
    jobs.erase(peer_id)
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player != null:
        player.show_rescue_animation(false)
    _feedback("操作已中止，物资没有消耗。")

func tick(delta: float) -> void:
    _time += delta
    _update_nearby_visuals()
    if states.is_empty() or not controller.is_host or not controller.game_started or controller.mission_completed or controller.mission_failed:
        return
    var changed := false
    for site in SITES:
        var id := String(site.id)
        if bool(states[id].seen):
            continue
        var point := Vector2(site.position)
        for value in controller.players.values():
            var player := value as SpacePlayer3D
            if player != null and not player.downed and Vector2(player.global_position.x, player.global_position.z).distance_to(point) <= 12.0:
                states[id]["seen"] = true
                changed = true
                break
    for raw_peer_id in jobs.keys().duplicate():
        var peer_id := int(raw_peer_id)
        var player := controller.players.get(peer_id) as SpacePlayer3D
        var job: Dictionary = jobs[peer_id]
        var node := nodes.get(String(job.id)) as Node3D
        if player == null or player.downed or not is_instance_valid(node) or controller._flat_distance(player.global_position, node.global_position) > INTERACTION_RADIUS:
            _cancel_job(peer_id)
            changed = true
            continue
        job["elapsed"] = float(job.elapsed) + delta
        if float(job.elapsed) >= float(job.duration):
            jobs.erase(peer_id)
            player.show_rescue_animation(false)
            _complete_job(String(job.id), player)
            changed = true
    _sync_elapsed += delta
    if changed:
        _publish()
        _sync_elapsed = 0.0
    elif not jobs.is_empty() and _sync_elapsed >= 0.2:
        controller.sync_field_state.rpc(snapshot())
        _sync_elapsed = 0.0

func _complete_job(id: String, player: SpacePlayer3D) -> void:
    var site := _site(id)
    var state: Dictionary = states[id]
    match String(site.kind):
        "locker":
            state["opened"] = true
            _feedback("补给箱已打开 · 需要时按 E 领取，每名船员一份", Color("#9fe8cf"))
        "heater":
            state["repaired"] = true
            controller._record_journal("野外供暖炉", "断开的线路接上了，冰湖西侧恢复一个 5m 热源。手持电池可按 E 加入炉子，换取 8.5m 的供暖范围。")
            _story("暖风又吹出来了。炉壳上有一行划痕：回来时，不要把最后一个人落在冷风里。")
            _feedback("供暖炉已修复 · 新热源可补氧回温", Color("#ffc883"))
        "scope":
            state["next_observation"] = controller.mission_elapsed + 8.0
            state["heard"] = true
            var revealed: int = controller._reveal_signal_echoes(nodes[id].global_position, 2)
            controller._record_journal("手动观测", "没有高频发射的气象观测不会惊动地下生物，能确认附近地面线索。风暴与信标的相位相同，旧气象站记录才是破解它的关键。")
            var weather := "地下异常已处理，风暴正在消退" if controller.anomaly_resolved else ("风暴中，先找热源避风" if controller.storm_active else "预计 %.0f 秒后出现风暴" % maxf(controller.STORM_INTERVAL - controller.storm_elapsed, 0.0))
            _feedback("观测完成 · %s · 新确认 %d 条附近线索" % [weather, revealed], Color("#a9efff"))
        "winch":
            state["opened"] = true
            controller.salvage_value += 12
            controller._record_journal("运输舱货物", "绞盘把冻住的货箱从舱外拖回，里面的零件可回收 +12。货单上写着：把氧气和药留给后来的人，所有样本必须装入隔离舱。")
            _story("绞盘重新转动，冻住的货箱升了起来。货单上写着：把氧气和药留给后来的人。——岑夏")
            _feedback("货物已回收 · 回收价值 +12", Color("#9fe8cf"))
        "sign":
            state["repaired"] = true
            var point := Vector2(site.position)
            controller.map_markers.append({"id": controller.next_marker_id, "kind": "clue", "position": point, "label": String(site.name).replace("倒下的", "")})
            controller.next_marker_id += 1
            if controller.map_markers.size() > 12:
                controller.map_markers.pop_front()
            controller._record_journal("反光路标", "路标已扶正并记在地图上。反光面朝向通道，夜色和风雪里也能认出原路。")
            _route_feedback(player)
    _pulse(site, Color("#8be7dd"))

func _route_feedback(player: SpacePlayer3D) -> void:
    var target: Dictionary = controller._next_navigation_target()
    if target.is_empty() and not controller.beacon_positions.is_empty():
        for index in controller.beacon_positions.size():
            if not controller.activated_beacons.has(index + 1):
                target = {"label": "未修复气象信标", "position": Vector2(controller.beacon_positions[index])}
                break
    var message: String = controller._next_objective_text()
    if not target.is_empty():
        var from := Vector2(player.global_position.x, player.global_position.z)
        var to := Vector2(target.position)
        message += " · %s %.0fm" % [controller._direction_hint(from, to), from.distance_to(to)]
    _feedback(message, Color("#a9efff"))

func snapshot() -> Dictionary:
    return {"sites": states.duplicate(true), "jobs": jobs.duplicate(true)}

func apply_snapshot(data: Dictionary) -> void:
    if data.is_empty():
        return
    for id in data.get("sites", {}):
        if states.has(id):
            states[id] = data.sites[id].duplicate(true)
    var previous_jobs := jobs.keys()
    jobs = data.get("jobs", {}).duplicate(true)
    for peer_id in previous_jobs:
        if not jobs.has(peer_id):
            var player := controller.players.get(int(peer_id)) as SpacePlayer3D
            if player != null:
                player.show_rescue_animation(false)
    for peer_id in jobs:
        var player := controller.players.get(int(peer_id)) as SpacePlayer3D
        if player != null:
            player.show_rescue_animation(true)
    _apply_visuals()

func heat_sources() -> Array:
    var state: Dictionary = states.get("field_heater", {})
    if not bool(state.get("repaired", false)):
        return []
    var boosted := bool(state.get("boosted", false))
    return [{"position": Vector2(_site("field_heater").position), "radius": 8.5 if boosted else 5.0, "label": "强化供暖炉" if boosted else "野外供暖炉"}]

func map_sites() -> Array:
    var points: Array = []
    for site in SITES:
        var state: Dictionary = states.get(String(site.id), {})
        if bool(state.get("seen", false)):
            points.append({"position": Vector2(site.position), "label": String(site.name), "used": bool(state.get("opened", false)) or bool(state.get("repaired", false)) or bool(state.get("heard", false))})
    return points

func _publish() -> void:
    _apply_visuals()
    controller.sync_field_state.rpc(snapshot())
    controller._sync_state.rpc(controller._enemy_snapshot(), controller.enemy_wave_index, controller.enemy_wave_timer, controller.activated_beacons, controller.taken_crates, controller.deposited_resources, controller._vitals_snapshot(), controller.journal_entries, controller.discovered_regions)
    controller.sync_contract_state.rpc(controller.mission_elapsed, controller.salvage_value, controller.knowledge_flags.keys(), controller.taken_samples, controller.scan_revealed_clues)
    controller._broadcast_exploration_state()

func _feedback(message: String, color: Color = Color("#ffcf9f")) -> void:
    controller.show_feedback_rpc.rpc(message, color, 3.5)

func _story(message: String) -> void:
    controller.show_story_rpc.rpc(message, 8.0)

func _pulse(site: Dictionary, color: Color) -> void:
    var node := nodes.get(String(site.id)) as Node3D
    if node != null:
        controller._spawn_particle_burst(node.global_position + Vector3(0, 1.0, 0), color, 10)

func _site(id: String) -> Dictionary:
    for site in SITES:
        if String(site.id) == id:
            return site
    return {}

func _update_nearby_visuals() -> void:
    var player := controller.players.get(controller.multiplayer.get_unique_id()) as SpacePlayer3D
    if player == null:
        return
    for id in nodes:
        var node := nodes[id] as Node3D
        if not is_instance_valid(node):
            continue
        var distance: float = controller._flat_distance(player.global_position, node.global_position)
        var label := node.get_node("FieldLabel") as Label3D
        label.visible = distance <= 10.0 and not controller.is_journal_visible()
        var ring := node.get_node("InteractionRing") as MeshInstance3D
        ring.visible = distance <= INTERACTION_RADIUS and not player.downed and not controller.is_journal_visible()
        var status := node.get_node_or_null("StatusLight") as OmniLight3D
        if status != null:
            status.light_energy = 1.1 + 0.2 * sin(_time * 2.0)
        if id == "weather_scope":
            var sight := node.get_node_or_null("Sight") as Node3D
            if sight != null:
                sight.rotation.y = sin(_time * 0.35) * 0.12

func _apply_visuals() -> void:
    for site in SITES:
        var id := String(site.id)
        var node := nodes.get(id) as Node3D
        if not is_instance_valid(node):
            continue
        var state: Dictionary = states[id]
        var color := Color("#73d8ca")
        var status_text := "E 交互"
        var active := bool(state.repaired) or bool(state.opened) or bool(state.heard)
        match String(site.kind):
            "locker":
                var lid := node.get_node("Lid") as Node3D
                lid.rotation_degrees.x = -65.0 if bool(state.opened) else 0.0
                status_text = "补给 %d 份" % int(state.charges) if bool(state.opened) else "锁扣冻结 · E 解冻"
            "heater":
                color = Color("#ffbd61") if bool(state.repaired) else Color("#ef9b88")
                var heat := node.get_node("HeatLight") as OmniLight3D
                heat.light_energy = 3.0 if bool(state.repaired) else 0.0
                heat.omni_range = 10.0 if bool(state.boosted) else 6.5
                var core := node.get_node("HeatCore") as MeshInstance3D
                core.material_override = controller._glow_material(color, 1.7 if bool(state.repaired) else 0.05)
                var battery := node.get_node("InstalledBattery") as Node3D
                battery.visible = bool(state.boosted)
                status_text = "强化供暖中" if bool(state.boosted) else ("供暖中 · E 安装电池" if bool(state.repaired) else "线路断开 · E 修理")
            "sample":
                var crystal := node.get_node("ContainedSample") as Node3D
                crystal.visible = bool(state.sealed)
                status_text = "冰样已封存" if bool(state.sealed) else "E 查看报告 / 有冰样时封存"
            "winch":
                var cargo := node.get_node("Cargo") as Node3D
                cargo.position.y = 1.1 if bool(state.opened) else 0.3
                status_text = "货物已回收" if bool(state.opened) else "钢索冻结 · E 操作"
            "sign":
                var sign_mesh := node.get_node("Sign") as Node3D
                sign_mesh.rotation_degrees.z = 0.0 if bool(state.repaired) else 65.0
                status_text = "路线已登记" if bool(state.repaired) else "E 扶正路标"
            "radio", "helmet":
                status_text = "已传回飞船 · E 重听" if bool(state.answered) else "E 聆听 / 再按 E 回应"
        var light := node.get_node_or_null("StatusLight") as OmniLight3D
        if light != null:
            light.light_color = Color("#b8e6bb") if active else color
        var label := node.get_node("FieldLabel") as Label3D
        label.text = String(site.name) + "\n" + status_text

func _build_model(root: Node3D, kind: String) -> void:
    _box(root, "Foot", Vector3(1.3, 0.12, 1.05), Vector3(0, 0.06, 0), Color("#3b596b"))
    match kind:
        "terminal":
            _box(root, "Console", Vector3(0.75, 0.85, 0.55), Vector3(0, 0.52, 0), Color("#647c91"))
            var screen := _box(root, "Screen", Vector3(0.65, 0.42, 0.09), Vector3(0, 1.12, 0.15), Color("#70e0ed"), true)
            screen.rotation_degrees.x = -20.0
            _cylinder(root, "Antenna", 0.035, 1.0, Vector3(0.38, 1.05, -0.2), Color("#c1d4df"))
        "locker":
            _box(root, "Crate", Vector3(1.15, 0.6, 0.85), Vector3(0, 0.38, 0), Color("#7b8998"))
            var lid := Node3D.new()
            lid.name = "Lid"
            lid.position = Vector3(0, 0.73, -0.4)
            root.add_child(lid)
            _box(lid, "Top", Vector3(1.2, 0.1, 0.9), Vector3(0, 0, 0.4), Color("#c8d7d9"))
            _box(root, "CrossHorizontal", Vector3(0.48, 0.12, 0.03), Vector3(0, 0.4, 0.44), Color("#8ee5c2"), true)
            _box(root, "CrossVertical", Vector3(0.12, 0.42, 0.03), Vector3(0, 0.4, 0.46), Color("#8ee5c2"), true)
        "radio":
            _box(root, "Table", Vector3(1.35, 0.15, 0.9), Vector3(0, 0.56, 0), Color("#8d7669"))
            _box(root, "Recorder", Vector3(0.65, 0.45, 0.4), Vector3(0, 0.83, 0), Color("#78939e"))
            _cylinder(root, "Receiver", 0.055, 0.85, Vector3(0.25, 1.27, -0.1), Color("#ccd7df"))
            _box(root, "WaveDisplay", Vector3(0.35, 0.16, 0.03), Vector3(-0.04, 0.9, 0.22), Color("#ffd18a"), true)
            _box(root, "Blanket", Vector3(0.9, 0.08, 1.6), Vector3(-0.8, 0.1, 0.3), Color("#965e59"))
        "heater":
            _cylinder(root, "Furnace", 0.5, 0.95, Vector3(0, 0.59, 0), Color("#657a89"))
            _sphere(root, "HeatCore", 0.3, Vector3(0, 1.04, 0), Color("#ef9b88"), true)
            _cylinder(root, "Pipe", 0.09, 0.8, Vector3(-0.48, 1.0, -0.2), Color("#b5cad3"))
            _box(root, "InstalledBattery", Vector3(0.24, 0.5, 0.35), Vector3(0.58, 0.42, 0), Color("#96f6c6"), true)
            var heat := OmniLight3D.new()
            heat.name = "HeatLight"
            heat.position.y = 1.0
            heat.light_color = Color("#ffb45e")
            heat.light_energy = 0.0
            root.add_child(heat)
        "scope":
            for x in [-0.35, 0.35]:
                var leg := _cylinder(root, "Leg", 0.045, 1.15, Vector3(x, 0.65, 0), Color("#a5baca"))
                leg.rotation_degrees.z = x * 30.0
            var sight := Node3D.new()
            sight.name = "Sight"
            sight.position.y = 1.25
            root.add_child(sight)
            var telescope := _cylinder(sight, "ScopeBody", 0.15, 1.0, Vector3.ZERO, Color("#8eb0c4"))
            telescope.rotation_degrees.x = 70.0
            _sphere(sight, "Lens", 0.12, Vector3(0, 0.17, -0.45), Color("#6be4ec"), true)
        "sample":
            _box(root, "LabTable", Vector3(1.5, 0.12, 0.95), Vector3(0, 0.76, 0), Color("#b8c8d3"))
            _box(root, "Legs", Vector3(1.15, 0.6, 0.65), Vector3(0, 0.42, 0), Color("#49667e"))
            _cylinder(root, "Containment", 0.28, 0.65, Vector3(0.38, 1.15, 0), Color("#4c617c"))
            _sphere(root, "ContainedSample", 0.21, Vector3(0.38, 1.58, 0), Color("#c6a3ff"), true)
            _box(root, "ReportScreen", Vector3(0.55, 0.32, 0.07), Vector3(-0.34, 1.02, 0.2), Color("#71dfe3"), true)
        "winch":
            _box(root, "Frame", Vector3(0.3, 1.7, 0.4), Vector3(-0.58, 0.95, 0), Color("#869da9"))
            _box(root, "Arm", Vector3(1.4, 0.15, 0.4), Vector3(0, 1.8, 0), Color("#bba27c"))
            _cylinder(root, "SteelCable", 0.025, 1.3, Vector3(0.38, 1.13, 0), Color("#bed1df"))
            _box(root, "Cargo", Vector3(0.75, 0.5, 0.65), Vector3(0.38, 0.3, 0), Color("#967655"))
            _cylinder(root, "Handle", 0.09, 0.35, Vector3(-0.75, 0.95, 0.18), Color("#ffd18a"))
        "helmet":
            _sphere(root, "Helmet", 0.34, Vector3(0, 0.44, 0), Color("#ccd3d4"))
            _box(root, "Visor", Vector3(0.46, 0.22, 0.1), Vector3(0, 0.43, 0.29), Color("#385d75"))
            _box(root, "NameTag", Vector3(0.26, 0.08, 0.15), Vector3(0.42, 0.14, 0.1), Color("#edc68a"))
            _box(root, "Glove", Vector3(0.18, 0.08, 0.35), Vector3(-0.48, 0.13, 0.2), Color("#888b97"))
        "sign":
            var sign_mesh := Node3D.new()
            sign_mesh.name = "Sign"
            root.add_child(sign_mesh)
            _cylinder(sign_mesh, "Post", 0.07, 1.4, Vector3(0, 0.82, 0), Color("#8d9ba8"))
            _box(sign_mesh, "Reflector", Vector3(1.15, 0.35, 0.12), Vector3(0, 1.4, 0), Color("#ffe3a1"), true)
            _box(sign_mesh, "Arrow", Vector3(0.5, 0.07, 0.02), Vector3(0, 1.4, 0.075), Color("#416776"))
    var status := OmniLight3D.new()
    status.name = "StatusLight"
    status.position = Vector3(0, 1.4, 0.35)
    status.light_color = Color("#73d8ca")
    status.light_energy = 1.1
    status.omni_range = 3.2
    root.add_child(status)

func _box(parent: Node3D, name: String, size: Vector3, position: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return _mesh(parent, name, mesh, position, color, glow)

func _cylinder(parent: Node3D, name: String, radius: float, height: float, position: Vector3, color: Color) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 16
    return _mesh(parent, name, mesh, position, color, false)

func _sphere(parent: Node3D, name: String, radius: float, position: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    return _mesh(parent, name, mesh, position, color, glow)

func _mesh(parent: Node3D, name: String, mesh: Mesh, position: Vector3, color: Color, glow: bool) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = position
    instance.material_override = controller._glow_material(color, 0.85) if glow else controller._material(color)
    parent.add_child(instance)
    return instance
