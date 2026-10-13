extends RefCounted
class_name RuinPlanet

# 腐墟星（planet-02）灰盒模块。
#
# 沿用霜烬星的范式：所有几何由代码生成，不引用外部美术资源；
# 沿用 frost_field_interactions.gd 的模块化接口，由 Main3D 持有并驱动。
#
# 本模块只负责「星球内容」：建筑外壳、食物点、感染体与噪音规则。
# 建筑内部子地图不在本轮范围内，只保留 enter_building() 入口。
#
# 设计要点：这一关的环境压力不是温度而是声音。
# 「噪音吸引感染体」直接复用 SpaceEnemy3D 已有的 lure 机制，
# 所以不需要另写一套敌人 AI。

const ENEMY_SCENE := preload("res://scenes/enemy_3d.tscn")

# ── 布局 ──
# 建筑只做外壳：体块 + 招牌 + 门口交互点。内部子地图留待下一轮。
const BUILDINGS := [
    {"id": "market", "name": "废弃超市", "position": Vector2(-30.0, -17.0), "size": Vector3(20.0, 7.0, 14.0), "accent": Color("#c9a35a")},
    {"id": "hospital", "name": "废弃医院", "position": Vector2(28.0, -20.0), "size": Vector3(15.0, 11.0, 17.0), "accent": Color("#c76b6b")},
    {"id": "school", "name": "废弃学校", "position": Vector2(-26.0, 19.0), "size": Vector3(23.0, 8.0, 15.0), "accent": Color("#6fb4c9")},
]
const BUILDING_ENTRY_RADIUS := 3.6

# ── 食物与物资 ──
# 设计意图：物资都刷在「会发出声音的地方」，翻找会产生噪音脉冲。
const FOOD_SITES := [
    {"id": "food_a", "name": "翻倒的货架", "kind": "canned", "position": Vector2(-12.0, -14.0)},
    {"id": "food_b", "name": "自动售货机", "kind": "water", "position": Vector2(6.0, 12.0)},
    {"id": "food_c", "name": "停摆的冷藏柜", "kind": "canned", "position": Vector2(16.0, -6.0)},
    {"id": "food_d", "name": "抛锚的物资车", "kind": "medical", "position": Vector2(-6.0, 26.0)},
    {"id": "food_e", "name": "破开的储物柜", "kind": "water", "position": Vector2(30.0, 8.0)},
]
const FOOD_SEARCH_RADIUS := 2.8
const FOOD_SEARCH_TIME := 1.6

# ── 噪音 ──
const NOISE_MAX := 1.0
const NOISE_DECAY := 0.30
const NOISE_SPRINT_PER_SEC := 0.45
const NOISE_ATTACK := 0.25
const NOISE_SEARCH := 0.60
const NOISE_SCAN := 1.00
const NOISE_VISIBLE_THRESHOLD := 0.05

# ── 感染体 ──
const ZOMBIE_COUNT_BASE := 2
const ZOMBIE_SPAWN_MIN_DISTANCE := 26.0
const ZOMBIE_LISTEN_RADIUS := 46.0

# ── 独立世界 ──
# 腐墟星用的是自己的世界根：登陆时把霜烬星的世界根整体隐藏，
# 所以光照和地面必须由本模块自己提供，不能借用霜烬星的。
const GROUND_EXTENT := Vector2(58.0, 40.0)
const EXTRACTION_POSITION := Vector2(46.0, 30.0)
const SPAWN_POSITION := Vector2(-46.0, 30.0)

var controller: Node3D
var world_root: Node3D
var buildings: Dictionary = {}
var food_sites: Dictionary = {}
var zombies: Dictionary = {}
var noise: Dictionary = {}
var taken_food: Array[String] = []
var discovered_buildings: Array[String] = []
var search_jobs: Dictionary = {}
var pending_message := ""
var next_zombie_id := 1
var _time := 0.0


func _init(owner: Node3D) -> void:
    controller = owner


func build() -> void:
    reset()
    _build_scaffold()
    _build_buildings()
    _build_food_sites()
    _spawn_zombies()


func reset() -> void:
    # 建筑、物资和感染体全部挂在 world_root 下（感染体除外，见 _spawn_zombies），
    # 所以释放根节点就能连带清空，不需要逐个遍历。
    if is_instance_valid(world_root):
        world_root.queue_free()
    world_root = null
    for zombie in zombies.values():
        if is_instance_valid(zombie):
            zombie.queue_free()
    buildings.clear()
    food_sites.clear()
    zombies.clear()
    noise.clear()
    taken_food.clear()
    discovered_buildings.clear()
    search_jobs.clear()
    next_zombie_id = 1
    _time = 0.0


# ── 构建 ──

func _build_scaffold() -> void:
    # 腐墟星用自己的光照和地面：登陆时霜烬星的世界根会被整体隐藏，
    # 那边的 Environment 和地面一并不可见，所以这里必须自带一套。
    world_root = Node3D.new()
    world_root.name = "RuinWorld3D"
    controller.add_child(world_root)

    var light := DirectionalLight3D.new()
    light.name = "RuinSun"
    light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
    light.light_energy = 1.05
    light.light_color = Color("#c8d2b4")
    light.shadow_enabled = true
    world_root.add_child(light)

    var ground_body := StaticBody3D.new()
    ground_body.name = "RuinGround"
    ground_body.collision_layer = 2
    ground_body.collision_mask = 1
    var ground_shape := CollisionShape3D.new()
    var ground_box := BoxShape3D.new()
    ground_box.size = Vector3(GROUND_EXTENT.x * 2.0, 1.0, GROUND_EXTENT.y * 2.0)
    ground_shape.shape = ground_box
    ground_shape.position = Vector3(0.0, -0.5, 0.0)
    ground_body.add_child(ground_shape)
    world_root.add_child(ground_body)

    var ground_mesh := BoxMesh.new()
    ground_mesh.size = Vector3(GROUND_EXTENT.x * 2.0, 1.0, GROUND_EXTENT.y * 2.0)
    var ground := MeshInstance3D.new()
    ground.name = "RuinGroundMesh"
    ground.mesh = ground_mesh
    ground.position = Vector3(0.0, -0.5, 0.0)
    ground.material_override = controller._material(Color("#4a4f42"))
    world_root.add_child(ground)


func _build_buildings() -> void:
    for raw in BUILDINGS:
        var id := String(raw.id)
        var point := Vector2(raw.position)
        var root := Node3D.new()
        root.name = "RuinBuilding_" + id
        root.position = Vector3(point.x, 0.0, point.y)
        _world().add_child(root)
        var size := Vector3(raw.size)
        var accent: Color = raw.accent
        # 主体
        _box(root, "Shell", size, Vector3(0.0, size.y * 0.5, 0.0), Color("#7d8794"))
        # 建筑必须有碰撞体，否则玩家会直接穿过外墙。
        var body := StaticBody3D.new()
        body.name = "ShellCollision"
        body.collision_layer = 2
        body.collision_mask = 1
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = size
        shape.shape = box
        shape.position = Vector3(0.0, size.y * 0.5, 0.0)
        body.add_child(shape)
        root.add_child(body)
        # 屋顶压边
        _box(root, "Roof", Vector3(size.x + 1.2, 0.6, size.z + 1.2), Vector3(0.0, size.y + 0.1, 0.0), Color("#5b636e"))
        # 招牌与门洞
        _box(root, "Sign", Vector3(size.x * 0.42, 1.5, 0.4), Vector3(0.0, size.y * 0.72, size.z * 0.5 + 0.3), accent, true)
        _box(root, "Doorway", Vector3(3.0, 3.2, 0.6), Vector3(0.0, 1.6, size.z * 0.5 + 0.3), Color("#2f3742"))
        # 门口交互环
        var ring := _mesh(root, "EntryRing", _torus(1.5, 1.56), Vector3(0.0, 0.08, size.z * 0.5 + 1.6), accent, true)
        ring.visible = false
        buildings[id] = {"root": root, "entry": root.position + Vector3(0.0, 0.0, size.z * 0.5 + 1.6), "name": String(raw.name), "ring": ring}


func _build_food_sites() -> void:
    for raw in FOOD_SITES:
        var id := String(raw.id)
        var point := Vector2(raw.position)
        var root := Node3D.new()
        root.name = "RuinFood_" + id
        root.position = Vector3(point.x, 0.0, point.y)
        _world().add_child(root)
        var kind := String(raw.kind)
        var accent := Color("#d8b98a") if kind == "canned" else (Color("#8fd0e8") if kind == "water" else Color("#c99ad8"))
        _box(root, "Crate", Vector3(1.5, 1.0, 1.5), Vector3(0.0, 0.5, 0.0), Color("#6c6257"))
        _box(root, "Goods", Vector3(1.1, 0.5, 1.1), Vector3(0.0, 1.2, 0.0), accent, true)
        var ring := _mesh(root, "FoodRing", _torus(1.0, 1.05), Vector3(0.0, 0.06, 0.0), accent, true)
        ring.visible = false
        food_sites[id] = {"root": root, "name": String(raw.name), "kind": kind, "ring": ring}


func _spawn_zombies() -> void:
    if not controller.is_host:
        return
    # controller 是 Node3D，它的成员是 Variant，必须显式标注类型，
    # 否则本工程「把 Variant 推断警告当错误」的规则会让整个脚本编译失败。
    var count: int = ZOMBIE_COUNT_BASE + controller.connected_ids.size()
    # 感染体在出生点外圈生成。
    # 曾经按距原点的固定半径生成，地图缩小后它们会落在 50~80 米外，
    # 玩家打死身边那一只之后就再也够不到，表现为"只能打第一个"。
    for index in count:
        var angle := TAU * float(index) / float(count)
        var radius := 11.0 + float(index) * 3.5
        var point := SPAWN_POSITION + Vector2(cos(angle), sin(angle)) * radius
        var enemy := ENEMY_SCENE.instantiate() as SpaceEnemy3D
        enemy.setup(next_zombie_id, controller.connected_ids.size())
        # SpaceEnemy3D 是两颗星球共用的，默认标签写的是霜烬星的「霜噬生物 / 追踪热量」，
        # 在腐墟星必须换掉，否则感染体顶着霜烬星的名字。
        enemy.set_creature_label("感染体", "循声而来 · 空格攻击")
        # 必须挂在 Main3D 下：SpaceEnemy3D.server_tick 用 get_parent() 取控制器来结算伤害。
        enemy.position = Vector3(point.x, 0.0, point.y)
        controller.add_child(enemy)
        zombies[next_zombie_id] = enemy
        next_zombie_id += 1


func _world() -> Node3D:
    return world_root


# ── 噪音 ──

func add_noise(peer_id: int, amount: float) -> void:
    if not controller.is_host:
        return
    var current := float(noise.get(peer_id, 0.0))
    noise[peer_id] = clampf(current + amount, 0.0, NOISE_MAX)


func noise_level(peer_id: int) -> float:
    return float(noise.get(peer_id, 0.0))


func loudest_noise() -> Dictionary:
    var best_level := 0.0
    var best_position := Vector3.ZERO
    for peer_id in noise.keys():
        var level := float(noise[peer_id])
        if level <= best_level or level < NOISE_VISIBLE_THRESHOLD:
            continue
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player == null:
            continue
        best_level = level
        best_position = player.global_position
    return {"position": best_position, "level": best_level}


# ── 每帧 ──

func tick(delta: float) -> void:
    _time += delta
    if not controller.is_host:
        return
    _tick_noise(delta)
    _tick_search(delta)
    _tick_zombies(delta)


func _tick_noise(delta: float) -> void:
    for peer_id in noise.keys():
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player == null or player.downed:
            noise[peer_id] = maxf(float(noise[peer_id]) - NOISE_DECAY * 2.0 * delta, 0.0)
            continue
        # 冲刺本身就在制造噪音——这是本关 Shift 的代价。
        if player.sprinting and player.velocity.length() > 0.2:
            add_noise(peer_id, NOISE_SPRINT_PER_SEC * delta)
        noise[peer_id] = maxf(float(noise[peer_id]) - NOISE_DECAY * delta, 0.0)


func _tick_search(delta: float) -> void:
    for peer_id in search_jobs.keys():
        var job: Dictionary = search_jobs[peer_id]
        var player := controller.players.get(peer_id) as SpacePlayer3D
        var site: Dictionary = food_sites.get(String(job.site_id), {})
        if player == null or player.downed or site.is_empty():
            search_jobs.erase(peer_id)
            continue
        var site_position: Vector3 = site.root.position
        if player.global_position.distance_to(site_position) > FOOD_SEARCH_RADIUS + 0.6:
            search_jobs.erase(peer_id)
            continue
        job.elapsed = float(job.elapsed) + delta
        if float(job.elapsed) >= FOOD_SEARCH_TIME:
            search_jobs.erase(peer_id)
            _finish_search(peer_id, String(job.site_id))
        else:
            search_jobs[peer_id] = job


func _tick_zombies(delta: float) -> void:
    _refresh_zombie_registry()
    var noise_info := loudest_noise()
    var lure_active := float(noise_info.level) > 0.0
    var lure_position: Vector3 = noise_info.position
    for id in zombies.keys():
        var zombie := zombies[id] as SpaceEnemy3D
        if zombie == null or not is_instance_valid(zombie):
            zombies.erase(id)
            continue
        # server_tick 内部已经处理移动、位置同步和伤害结算，这里不要再重复调用一次。
        zombie.server_tick(delta, controller.players, lure_position, lure_active, controller.storm_active)


func _refresh_zombie_registry() -> void:
    # 注册表会因为节点被 queue_free（延迟生效）而变脏：死掉的那只还留在表里，
    # 而活着的那几只如果一旦被误判为无效就会被永久移除——表现为"其他怪静止不动、
    # 走到身边也打不到"。这里每帧从场景树重建一次，保证表里永远只有活着的感染体。
    var alive: Dictionary = {}
    for child in controller.get_children():
        var enemy := child as SpaceEnemy3D
        if enemy == null or not is_instance_valid(enemy):
            continue
        if enemy.health <= 0:
            continue
        alive[enemy.enemy_id] = enemy
    zombies = alive


# ── 交互 ──

func nearest(player: SpacePlayer3D) -> Dictionary:
    if player == null:
        return {}
    var best: Dictionary = {}
    var best_distance := INF
    for id in buildings.keys():
        var entry: Vector3 = buildings[id].entry
        var distance := player.global_position.distance_to(entry)
        if distance <= BUILDING_ENTRY_RADIUS and distance < best_distance:
            best_distance = distance
            best = {"kind": "building", "id": id}
    for id in food_sites.keys():
        if taken_food.has(id):
            continue
        var site: Dictionary = food_sites[id]
        var distance := player.global_position.distance_to(site.root.position)
        if distance <= FOOD_SEARCH_RADIUS and distance < best_distance:
            best_distance = distance
            best = {"kind": "food", "id": id}
    return best


func prompt(player: SpacePlayer3D) -> String:
    if search_jobs.has(player.peer_id):
        var job: Dictionary = search_jobs[player.peer_id]
        return "翻找中 · %.1f / %.1f 秒 · 离开或按 E 中止" % [float(job.elapsed), FOOD_SEARCH_TIME]
    var target := nearest(player)
    if target.is_empty():
        return ""
    if String(target.kind) == "building":
        var name := String(buildings[target.id].name)
        return "[E] 进入%s（内部区域尚未开放）" % name
    var site: Dictionary = food_sites[target.id]
    return "[E] 翻找%s · 留在附近 %.1f 秒（会发出声响）" % [String(site.name), FOOD_SEARCH_TIME]


func interaction_progress(peer_id: int) -> float:
    if not search_jobs.has(peer_id):
        return 0.0
    var job: Dictionary = search_jobs[peer_id]
    return clampf(float(job.elapsed) / FOOD_SEARCH_TIME, 0.0, 1.0)


func handle_action(peer_id: int, action: String) -> bool:
    if action != "repair":
        return false
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return false
    if search_jobs.has(peer_id):
        search_jobs.erase(peer_id)
        return true
    var target := nearest(player)
    if target.is_empty():
        return false
    if String(target.kind) == "building":
        enter_building(peer_id, String(target.id))
        return true
    search_jobs[peer_id] = {"site_id": String(target.id), "elapsed": 0.0}
    return true


func enter_building(peer_id: int, building_id: String) -> void:
    # 内部子地图本轮不实现：只登记发现并给出提示，保证接口先立起来。
    if not buildings.has(building_id):
        return
    var name := String(buildings[building_id].name)
    if not discovered_buildings.has(building_id):
        discovered_buildings.append(building_id)
        controller._record_journal("发现建筑 · %s" % name, "门是从里面被顶开的。里面很暗，需要等内部探索系统接入后再进去。")
    controller.show_feedback_rpc.rpc("%s 内部区域尚未开放，本轮只能在外面查看。" % name, Color("#ffbd75"), 2.4)


func _finish_search(peer_id: int, site_id: String) -> void:
    if not food_sites.has(site_id) or taken_food.has(site_id):
        return
    var site: Dictionary = food_sites[site_id]
    taken_food.append(site_id)
    # 翻找会产生声音——这是这一关最重要的取舍。
    add_noise(peer_id, NOISE_SEARCH)
    if is_instance_valid(site.ring):
        site.ring.visible = false
    var kind := String(site.kind)
    var text := "罐头"
    if kind == "water":
        text = "净水"
    elif kind == "medical":
        text = "医疗包"
    controller.show_feedback_rpc.rpc("翻找%s：获得%s（发出声响）" % [String(site.name), text], Color("#d8b98a"), 2.2)


# ── 对外数据 ──

func nearest_zombie(from_position: Vector3, limit: float) -> SpaceEnemy3D:
    # 感染体不在 Main3D 的 enemies 字典里，攻击判定必须通过这个方法查询，
    # 否则在腐墟星上按空格永远只会提示"超出射程"。
    var best: SpaceEnemy3D
    var best_distance := limit
    for zombie in zombies.values():
        var candidate := zombie as SpaceEnemy3D
        # 必须跳过已经死掉的感染体：queue_free() 是延迟生效的，
        # 如果还把它当成最近目标，后续每一次攻击都会打在尸体上。
        if candidate == null or not is_instance_valid(candidate) or candidate.health <= 0:
            continue
        var distance := Vector2(from_position.x, from_position.z).distance_to(Vector2(candidate.global_position.x, candidate.global_position.z))
        if distance <= best_distance:
            best_distance = distance
            best = candidate
    return best


func spawn_position(peer_id: int) -> Vector3:
    # 4 个出生点槽位围绕登陆场排开，与霜烬星同样的做法。
    var angle := TAU * float(maxi(peer_id - 1, 0)) / 4.0
    var offset := Vector2(cos(angle), sin(angle)) * 3.5
    return Vector3(SPAWN_POSITION.x + offset.x, 0.0, SPAWN_POSITION.y + offset.y)


func extraction_position() -> Vector3:
    return Vector3(EXTRACTION_POSITION.x, 0.0, EXTRACTION_POSITION.y)


func set_visible(value: bool) -> void:
    if is_instance_valid(world_root):
        world_root.visible = value
        # 感染体挂在 Main3D 下而不是 world_root 下，需要单独处理。
        for zombie in zombies.values():
            if is_instance_valid(zombie):
                zombie.visible = value
                zombie.set_physics_process(value)


func snapshot() -> Dictionary:
    return {"taken_food": taken_food, "buildings": discovered_buildings, "noise": noise}


func apply_snapshot(data: Dictionary) -> void:
    taken_food.assign(data.get("taken_food", []))
    discovered_buildings.assign(data.get("buildings", []))
    noise = data.get("noise", {})
    for id in taken_food:
        if food_sites.has(id):
            var site: Dictionary = food_sites[id]
            if is_instance_valid(site.ring):
                site.ring.visible = false


func map_sites() -> Array:
    var result: Array = []
    for id in buildings.keys():
        result.append({"id": id, "name": String(buildings[id].name), "position": buildings[id].root.position, "kind": "building"})
    for id in food_sites.keys():
        if taken_food.has(id):
            continue
        result.append({"id": id, "name": String(food_sites[id].name), "position": food_sites[id].root.position, "kind": "food"})
    return result


# ── 网格辅助（与 frost_field_interactions.gd 保持同一写法）──

func _torus(inner: float, outer: float) -> TorusMesh:
    var mesh := TorusMesh.new()
    mesh.inner_radius = inner
    mesh.outer_radius = outer
    mesh.rings = 28
    mesh.ring_segments = 8
    return mesh


func _box(parent: Node3D, name: String, size: Vector3, position: Vector3, color: Color, glow := false) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return _mesh(parent, name, mesh, position, color, glow)


func _mesh(parent: Node3D, name: String, mesh: Mesh, position: Vector3, color: Color, glow: bool) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = position
    instance.material_override = controller._glow_material(color, 0.85) if glow else controller._material(color)
    parent.add_child(instance)
    return instance
