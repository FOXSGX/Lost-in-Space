extends RefCounted
class_name RuinPlanet

# 腐墟星（planet-02）第一人称卡通模块。
#
# 沿用霜烬星的范式：所有几何由代码生成，不引用外部美术资源；
# 沿用 frost_field_interactions.gd 的模块化接口，由 Main3D 持有并驱动。
#
# 视角与归航号主舱一致：眼睛高度、鼠标环视、准星近战。
# 美术使用 ruin_cartoon_art.gd 的奶油白/青蓝/暖橙调色板与倒角网格。
#
# 本模块只负责「星球内容」：建筑外壳、食物点、感染体与噪音规则。
# 建筑内部子地图不在本轮范围内，只保留 enter_building() 入口。
#
# 设计要点：这一关的环境压力不是温度而是声音。
# 「噪音吸引感染体」直接复用 SpaceEnemy3D 已有的 lure 机制，
# 所以不需要另写一套敌人 AI。

# 腐墟星用自己的感染体脚本（三种丧尸造型）；霜烬星仍然用 enemy_3d.tscn，互不影响。
const RUIN_INFECTED := preload("res://scripts/ruin_infected_3d.gd")
# 废弃超市的外形单独成一个模块；医院和学校仍走下面的通用方盒流程。
const RUIN_MARKET := preload("res://scripts/ruin_market_building.gd")
# 医院也有自己的外形模块：四层病房楼 + 两层门诊翼 + 急救车雨棚。
const RUIN_HOSPITAL := preload("res://scripts/ruin_hospital_building.gd")
const RUIN_HOSPITAL_INTERIOR := preload("res://scripts/ruin_hospital_interior.gd")
const RUIN_ENERGY_STATION_INTERIOR := preload("res://scripts/ruin_energy_station_interior.gd")
const RUIN_SCHOOL_INTERIOR := preload("res://scripts/ruin_school_interior.gd")
const RUIN_MARKET_INTERIOR := preload("res://scripts/ruin_market_interior.gd")
# 与归航号主舱一致的精致卡通语言：奶油白、青蓝、暖橙、鼠尾草绿。
const ART := preload("res://scripts/ruin_cartoon_art.gd")
const RUIN_HUD := preload("res://scripts/ruin_hud_3d.gd")

# 第一人称近战：以准星为中心的一个窄锥。距离和角度都比俯视版更紧，
# 因为镜头在眼睛高度，玩家能明确看到自己是否对准。
const MELEE_RANGE := 3.2
const MELEE_MIN_DOT := 0.55
const PLAYER_EYE_HEIGHT := 1.62
# 返航登陆艇的范围与交互半径。
const PAD_RADIUS := 4.2
const PAD_PROMPT_RADIUS := 5.2
# 一局目标：翻找 3 处物资 + 查看 3 栋建筑，完成后登陆艇开放撤离。
const OBJECTIVE_FOOD := 3
const OBJECTIVE_BUILDINGS := 3
const EXTRACTION_HOLD := 3.0

# ── 布局 ──
# 建筑只做外壳：体块 + 招牌 + 门口交互点。内部子地图留待下一轮。
const BUILDINGS := [
    # 5 座建筑，按四个象限 + 北侧各放一处，彼此拉开。
    # 出生点在西南、撤离点在东南，所以南侧中间留空作为集散区。
    {"id": "market", "name": "万家福超市", "position": Vector2(-40.0, -24.0), "size": Vector3(24.0, 7.0, 14.0), "accent": Color("#f0a35d")},
    {"id": "hospital", "name": "废弃医院", "position": Vector2(40.0, -30.0), "size": Vector3(26.0, 11.0, 19.0), "accent": Color("#df8268")},
    {"id": "school", "name": "废弃学校", "position": Vector2(-62.0, 16.0), "size": Vector3(23.0, 8.0, 15.0), "accent": Color("#4f8d97")},
    # ── 占位建筑 ──
    # 走通用灰盒流程（外壳 + 屋顶收边 + 屋顶设备 + 招牌 + 门洞）。
    # 之后补建模时，像超市那样在 _build_buildings() 里加一条 id 分支即可。
    {"id": "library", "name": "市立图书馆", "position": Vector2(64.0, 24.0), "size": Vector3(20.0, 10.0, 15.0), "accent": Color("#9fbf98")},
    {"id": "energy_station", "name": "废弃能源站", "position": Vector2(2.0, -44.0), "size": Vector3(14.0, 7.0, 13.0), "accent": Color("#e0a15b")},
]
const BUILDING_ENTRY_RADIUS := 3.6
const FORCE_TIME := 2.4
const HOSPITAL_QUEST_ITEMS := {
    "patient_records": "镇静实验病历",
    "coolant_stabilizer": "低温稳定剂",
    "energy_access_card": "能源站门禁卡",
}
const NAVIGATION_QUEST_ITEMS := {
    "school_observation_data": "天文观测数据",
    "market_navigation_module": "民用导航模块",
}
const ALL_QUEST_ITEMS := {
    "patient_records": "镇静实验病历",
    "coolant_stabilizer": "低温稳定剂",
    "energy_access_card": "能源站门禁卡",
    "school_observation_data": "天文观测数据",
    "market_navigation_module": "民用导航模块",
}

# ── 食物与物资 ──
# 设计意图：物资都刷在「会发出声音的地方」，翻找会产生噪音脉冲。
const FOOD_SITES := [
    {"id": "food_a", "name": "翻倒的货架", "kind": "canned", "position": Vector2(-12.0, -14.0)},
    {"id": "food_b", "name": "自动售货机", "kind": "water", "position": Vector2(0.0, 12.5)},
    {"id": "food_c", "name": "停摆的冷藏柜", "kind": "canned", "position": Vector2(16.0, -6.0)},
    {"id": "food_d", "name": "抛锚的物资车", "kind": "medical", "position": Vector2(-6.0, 26.0)},
    {"id": "food_e", "name": "破开的储物柜", "kind": "water", "position": Vector2(30.0, 8.0)},
]
const FOOD_SEARCH_RADIUS := 2.8
const FOOD_SEARCH_TIME := 1.6

# ── 环境补光 ──
# 白天场景不再需要暗紫补光；只在广场和两栋主建筑门前留几盏暖色低强度补光，
# 把人物与建筑从地面里"托"出来，不承担主照明。
const FILL_LIGHTS := [
    {"position": Vector3(0.0, 5.0, 8.0), "energy": 1.1, "range": 24.0, "color": Color("#ffd9a4")},
    {"position": Vector3(-40.0, 4.0, -14.0), "energy": 0.7, "range": 18.0, "color": Color("#ffd9a4")},
    {"position": Vector3(40.0, 4.0, -18.0), "energy": 0.7, "range": 18.0, "color": Color("#ffd9a4")},
    {"position": Vector3(-62.0, 3.5, 8.0), "energy": 0.6, "range": 16.0, "color": Color("#ffd9a4")},
    # 东侧图书馆与南侧能源站各留一盏，避免大块空地在逆光时读成一片。
    {"position": Vector3(64.0, 3.5, 16.0), "energy": 0.6, "range": 16.0, "color": Color("#ffd9a4")},
    {"position": Vector3(2.0, 3.5, -36.0), "energy": 0.6, "range": 16.0, "color": Color("#ffd9a4")},
]

# ── 噪音 ──
const NOISE_MAX := 1.0
const NOISE_DECAY := 0.30
const NOISE_SPRINT_PER_SEC := 0.45
const NOISE_ATTACK := 0.25
const NOISE_SEARCH := 0.60
const NOISE_SCAN := 1.00
const NOISE_VISIBLE_THRESHOLD := 0.05

# ── 感染体 ──
# 刷新规则：落地不再一次性放三只，改成按时间随机补充。
# 目标是"不要太高也不要太低"：单人场上稳定在 3 只左右，
# 打掉一只之后还要等十几秒才会补上，中间留出安静潜行的空档。
const ZOMBIE_CAP_BASE := 3                        # 单人上限，每多一名玩家 +1
const ZOMBIE_FIRST_DELAY := Vector2(7.0, 11.0)    # 落地后第一只出现的时间窗
const ZOMBIE_SPAWN_INTERVAL := Vector2(15.0, 22.0)  # 之后的补充间隔
const ZOMBIE_SPAWN_MIN_DISTANCE := 18.0           # 离所有玩家至少这么远
const ZOMBIE_SPAWN_RETRY_DISTANCE := 10.0         # 找不到落点时放宽到这个距离
const ZOMBIE_SPAWN_EDGE_MARGIN := 4.0             # 离地图边缘
const ZOMBIE_LISTEN_RADIUS := 46.0
# 三种造型按 2:1:1 装袋后洗牌抽取，避免连着刷同一种。
const ZOMBIE_FORM_BAG := [0, 0, 1, 2]
# 感染体状态的广播间隔：只在需要新建/删除/改血量时才有用，
# 位置由 SpaceEnemy3D 自己的 sync_transform 平滑同步，不走这条通道。
const ENEMY_SYNC_INTERVAL := 0.8

# ── 独立世界 ──
# 腐墟星用的是自己的世界根：登陆时把霜烬星的世界根整体隐藏，
# 所以光照和地面必须由本模块自己提供，不能借用霜烬星的。
const GROUND_EXTENT := Vector2(80.0, 55.0)
const EXTRACTION_POSITION := Vector2(46.0, 30.0)
const SPAWN_POSITION := Vector2(-46.0, 30.0)

var controller: Node3D
var world_root: Node3D
# 不写 RuinHUD3D 类型：RuinHUD3D 反过来引用 Main3D，会形成类解析环。
var hud
var buildings: Dictionary = {}
var hospital_interior: Node3D
var energy_station_interior: Node3D
var school_interior: Node3D
var market_interior: Node3D
var food_sites: Dictionary = {}
var zombies: Dictionary = {}
var noise: Dictionary = {}
var taken_food: Array[String] = []
var discovered_buildings: Array[String] = []
var unlocked_buildings: Array[String] = []
var quest_items: Dictionary = {}
var search_jobs: Dictionary = {}
var force_jobs: Dictionary = {}
var pending_message := ""
var next_zombie_id := 1
var _spawn_timer := 0.0
var _sync_timer := 0.0
var _spawn_rng := RandomNumberGenerator.new()
var _form_bag: Array = []
var _environment: Environment
var _hospital_environment: Environment
var _energy_environment: Environment
var _school_environment: Environment
var _market_environment: Environment
var _pad_active_ring: MeshInstance3D
var _pad_lights: Array[MeshInstance3D] = []
var _time := 0.0
var _floor_serial := 0


func _init(owner: Node3D) -> void:
    controller = owner


func build() -> void:
    reset()
    _build_scaffold()
    _build_ground_detail()
    _build_ground_grid()
    _build_roads()
    _build_buildings()
    _build_hospital_interior()
    _build_energy_station_interior()
    _build_school_interior()
    _build_market_interior()
    _build_food_sites()
    _build_landing_pad()
    _build_street_dressing()
    _build_ground_scatter()
    _build_horizon()
    _cull_thin_shadow_casters()
    _build_hud()
    # 不再一次性刷三只：落地后先随机等一会儿，之后逐只出现。
    _spawn_timer = _spawn_rng.randf_range(ZOMBIE_FIRST_DELAY.x, ZOMBIE_FIRST_DELAY.y)


func reset() -> void:
    # 建筑、物资和感染体全部挂在 world_root 下（感染体除外，见 _spawn_zombies），
    # 所以释放根节点就能连带清空，不需要逐个遍历。
    if is_instance_valid(world_root):
        world_root.queue_free()
    world_root = null
    if is_instance_valid(hud):
        hud.queue_free()
    hud = null
    for zombie in zombies.values():
        if is_instance_valid(zombie):
            zombie.queue_free()
    buildings.clear()
    hospital_interior = null
    energy_station_interior = null
    school_interior = null
    market_interior = null
    food_sites.clear()
    zombies.clear()
    noise.clear()
    taken_food.clear()
    discovered_buildings.clear()
    unlocked_buildings.clear()
    quest_items.clear()
    search_jobs.clear()
    force_jobs.clear()
    next_zombie_id = 1
    _spawn_timer = 0.0
    _sync_timer = 0.0
    _form_bag.clear()
    _pad_active_ring = null
    _pad_lights.clear()
    _spawn_rng.randomize()
    _environment = null
    _time = 0.0


func clear_run() -> void:
    # 返航时清掉本局感染者与噪音，保留建筑/物资的发现状态。
    # 下一次登陆会重新从登陆艇开始，不会在主舱里看到残留的感染体。
    for zombie in zombies.values():
        if is_instance_valid(zombie):
            zombie.queue_free()
    zombies.clear()
    noise.clear()
    search_jobs.clear()
    force_jobs.clear()
    _spawn_timer = _spawn_rng.randf_range(ZOMBIE_FIRST_DELAY.x, ZOMBIE_FIRST_DELAY.y)
    _sync_timer = 0.0


## 再次登陆时重置一局目标，但保留已经建好的世界几何。
func reset_run() -> void:
    for zombie in zombies.values():
        if is_instance_valid(zombie):
            zombie.queue_free()
    zombies.clear()
    noise.clear()
    search_jobs.clear()
    taken_food.clear()
    discovered_buildings.clear()
    unlocked_buildings.clear()
    force_jobs.clear()
    _refresh_locks()
    for site in food_sites.values():
        if is_instance_valid(site.get("ring")):
            (site.ring as MeshInstance3D).visible = true
    _spawn_timer = _spawn_rng.randf_range(ZOMBIE_FIRST_DELAY.x, ZOMBIE_FIRST_DELAY.y)
    _sync_timer = 0.0


# ── 构建 ──

func _build_scaffold() -> void:
    # 腐墟星用自己的光照和地面：登陆时霜烬星的世界根会被整体隐藏，
    # 那边的 Environment 和地面一并不可见，所以这里必须自带一套。
    world_root = Node3D.new()
    world_root.name = "RuinWorld3D"
    controller.add_child(world_root)

    # 阴天废城：天空、雾和主光全部压低；保留冷青灰和脏暖色的对比。
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#334449")
    sky_material.sky_horizon_color = Color("#8c8777")
    sky_material.sky_curve = 0.42
    sky_material.ground_bottom_color = Color("#30332e")
    sky_material.ground_horizon_color = Color("#56574b")
    sky_material.sun_angle_max = 10.0
    sky_material.sun_curve = 0.08
    var sky := Sky.new()
    sky.sky_material = sky_material

    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#6d7975")
    env.ambient_light_energy = 0.34
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.fog_enabled = true
    env.fog_light_color = Color("#707970")
    env.fog_light_energy = 0.42
    env.fog_density = 0.0085
    env.fog_sky_affect = 0.18
    env.glow_enabled = true
    env.glow_intensity = 0.05
    env.glow_hdr_threshold = 1.5
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = 0.69
    env.tonemap_white = 0.98
    env.adjustment_enabled = true
    env.adjustment_brightness = 0.96
    env.adjustment_saturation = 0.82
    env.adjustment_contrast = 1.14
    _environment = env
    # 室内单独一层相机环境：天光仍很暗，但补一点灰绿色环境光，
    # 避免医院病房在没有吊灯的角落彻底死黑。
    var hospital_env := env.duplicate(true) as Environment
    hospital_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    hospital_env.ambient_light_color = Color("#7f857b")
    hospital_env.ambient_light_energy = 0.52
    hospital_env.tonemap_exposure = 0.78
    hospital_env.adjustment_saturation = 0.78
    hospital_env.fog_density = 0.006
    _hospital_environment = hospital_env
    # 能源站更工业：青绿环境光、略高的对比，保留橙色应急灯。
    var energy_env := env.duplicate(true) as Environment
    energy_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    energy_env.ambient_light_color = Color("#71847d")
    energy_env.ambient_light_energy = 0.72
    energy_env.tonemap_exposure = 0.82
    energy_env.adjustment_saturation = 0.76
    energy_env.adjustment_contrast = 1.18
    energy_env.fog_density = 0.005
    _energy_environment = energy_env
    # 学校：旧荧光灯、灰尘和奶油色墙面，比医院略暖。
    var school_env := env.duplicate(true) as Environment
    school_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    school_env.ambient_light_color = Color("#8b8a78")
    school_env.ambient_light_energy = 1.00
    school_env.tonemap_exposure = 0.94
    school_env.adjustment_saturation = 0.86
    school_env.fog_density = 0.0035
    _school_environment = school_env
    # 超市：冷白荧光灯、低饱和货架和一点暖橙入口灯。
    var market_env := env.duplicate(true) as Environment
    market_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    market_env.ambient_light_color = Color("#7f8a80")
    market_env.ambient_light_energy = 1.00
    market_env.tonemap_exposure = 0.94
    market_env.adjustment_saturation = 0.84
    market_env.fog_density = 0.0030
    _market_environment = market_env
    var environment := WorldEnvironment.new()
    environment.name = "RuinEnvironment"
    environment.environment = env
    world_root.add_child(environment)

    var light := DirectionalLight3D.new()
    light.name = "RuinSun"
    light.rotation_degrees = Vector3(-43.0, -38.0, 0.0)
    light.light_energy = 0.75
    light.light_color = Color("#c6d0c8")
    # 白天场景需要阴影来读出建筑体积；把阴影距离收在地图尺度，
    # 并抬高 bias 避免低模大平面的自阴影黑斑。
    light.shadow_enabled = true
    light.directional_shadow_max_distance = 120.0
    light.shadow_bias = 0.06
    light.shadow_normal_bias = 1.2
    light.shadow_opacity = 0.50
    light.light_angular_distance = 1.6
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

    # 可见地面用水平面片：法线固定朝上，不会被压扁盒体的顶面法线吃掉光照。
    var ground := ART.plane(world_root, "RuinGroundMesh", Vector2(GROUND_EXTENT.x * 2.0 + 60.0, GROUND_EXTENT.y * 2.0 + 60.0), Vector3(0.0, 0.0, 0.0), Color("#9a8059"))
    ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _build_ground_detail()

    for raw in FILL_LIGHTS:
        var fill := OmniLight3D.new()
        fill.name = "RuinFill"
        fill.position = Vector3(raw.position)
        fill.light_color = raw.color
        fill.light_energy = float(raw.energy)
        fill.omni_range = float(raw.range)
        world_root.add_child(fill)


## 地面细节层。
## 第一人称下抬头是天空、低头是铺装；这里用顶点色画出斑驳、湿痕和靠近建筑的浅阴影。
## 只加视觉，不加碰撞。
func _build_ground_detail() -> void:
    var span := Vector2(GROUND_EXTENT.x * 2.0 + 60.0, GROUND_EXTENT.y * 2.0 + 60.0)
    var segments := 72
    var step := Vector2(span.x / float(segments), span.y / float(segments))
    var patch := FastNoiseLite.new()
    patch.seed = 20261017
    patch.frequency = 0.032
    patch.fractal_octaves = 3
    var grain := FastNoiseLite.new()
    grain.seed = 7717
    grain.frequency = 0.29
    grain.fractal_octaves = 2
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for row in segments:
        for col in segments:
            var x0 := -span.x * 0.5 + float(col) * step.x
            var z0 := -span.y * 0.5 + float(row) * step.y
            _push_ground_quad(st, patch, grain, Vector2(x0, z0), step)
    st.generate_normals()
    var detail := MeshInstance3D.new()
    detail.name = "RuinGroundDetail"
    detail.mesh = st.commit()
    # 抬 1 厘米压住底下的单色盒子，避免同面深度打架
    detail.position = Vector3(0.0, 0.01, 0.0)
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 1.0
    detail.material_override = material
    # 地面不参与投影，否则整块地会自己给自己糊上一层阴影
    detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    world_root.add_child(detail)


func _push_ground_quad(st: SurfaceTool, patch: FastNoiseLite, grain: FastNoiseLite, origin: Vector2, step: Vector2) -> void:
    var a := origin
    var b := origin + Vector2(step.x, 0.0)
    var c := origin + step
    var d := origin + Vector2(0.0, step.y)
    # 顶点顺序必须让法线朝上：a→d→c 的叉积是 +Y。
    # 旧顺序 a→b→c 的法线朝下，背面剔除后整层地面细节不可见，
    # 只剩底下那块单色盒子，第一人称看过去就是一片没有信息的奶油色。
    for point in [a, d, c, a, c, b]:
        st.set_normal(Vector3.UP)
        # 顶点色同样按 sRGB 书写；转成线性后再交给 albedo，否则会比地面亮一截。
        var tint := _ground_tint(patch, grain, point)
        st.set_color(tint.srgb_to_linear())
        st.add_vertex(Vector3(point.x, 0.0, point.y))


func _ground_tint(patch: FastNoiseLite, grain: FastNoiseLite, point: Vector2) -> Color:
    # 暖沙色铺地 + 青灰色水洼 + 鼠尾草绿苔痕，和主舱的地板/墙面是同一套低饱和色。
    var color := Color("#9a8059")
    var low := (patch.get_noise_2d(point.x, point.y) + 1.0) * 0.5
    color = color.lerp(Color("#7f6a4d"), low * 0.55)
    color = color.lerp(Color("#b59a70"), maxf(1.0 - low * 1.6, 0.0) * 0.45)
    var g := grain.get_noise_2d(point.x, point.y)
    if g > 0.0:
        color = color.lerp(color.lightened(0.045), g * 0.55)
    else:
        color = color.lerp(color.darkened(0.045), -g * 0.55)
    # 低洼积水：浅青灰，读到"潮"而不是"脏"。
    if g > 0.46:
        color = color.lerp(Color("#6f8f8a"), clampf((g - 0.46) * 1.4, 0.0, 0.55))
    # 建筑周边的接地阴影：只做很轻的一圈暖灰，避免变成一大块棕色地皮。
    for raw in BUILDINGS:
        var center := Vector2(raw.position)
        var size := Vector3(raw.size)
        var reach := maxf(size.x, size.z) * 0.55 + 4.0
        var distance := point.distance_to(center)
        if distance < reach:
            var weight := (1.0 - distance / reach) * 0.14
            color = color.lerp(Color("#877252"), weight)
    return color


func _build_hospital_interior() -> void:
    var interior := RUIN_HOSPITAL_INTERIOR.new() as Node3D
    interior.build(controller, _world())
    hospital_interior = interior


func _build_energy_station_interior() -> void:
    var interior := RUIN_ENERGY_STATION_INTERIOR.new() as Node3D
    interior.build(controller, _world())
    energy_station_interior = interior


func _build_school_interior() -> void:
    var interior := RUIN_SCHOOL_INTERIOR.new() as Node3D
    interior.build(controller, _world())
    school_interior = interior


func _build_market_interior() -> void:
    var interior := RUIN_MARKET_INTERIOR.new() as Node3D
    interior.build(controller, _world())
    market_interior = interior


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
        # 超市有自己的外形模块：一层卖场 + 两层办公楼 + 玻璃店面 + 雨棚 + 挂歪的图标招牌。
        if id == "market":
            var market := RUIN_MARKET.new()
            market.build(root, size, accent, controller)
            _finish_building(root, size, accent, String(raw.name))
            buildings[id] = {
                "root": root,
                "entry": root.position + Vector3(0.0, 0.0, size.z * 0.5 + 1.6),
                "name": String(raw.name),
                "ring": market.entry_ring,
                "lock": root.get_node_or_null("DoorLock"),
            }
            continue
        # 医院：四层病房楼 + 两层门诊翼 + 急救车雨棚 + 停机坪。
        # 大门在本地 x=-4 的位置，交互点也要跟着偏过去，否则玩家站在楼中心
        # 会离门口 4 米、超出进入半径。
        if id == "hospital":
            var hospital := RUIN_HOSPITAL.new()
            hospital.build(root, size, accent, controller)
            _finish_building(root, size, accent, String(raw.name))
            buildings[id] = {
                "root": root,
                "entry": root.position + Vector3(-4.0, 0.0, size.z * 0.5 + 1.6),
                "name": String(raw.name),
                "ring": hospital.entry_ring,
                "lock": root.get_node_or_null("DoorLock"),
            }
            continue
        var ring := _build_cartoon_building(root, id, size, accent)
        buildings[id] = {"root": root, "entry": root.position + Vector3(0.0, 0.0, size.z * 0.5 + 1.6), "name": String(raw.name), "ring": ring, "lock": root.get_node_or_null("DoorLock")}


## 自定义建筑（超市、医院）建完后补一层统一的卡通收尾：
## 接地软阴影 + 门前铺装 + 一圈暖色边灯。几何仍由原模块负责。
func _finish_building(root: Node3D, size: Vector3, accent: Color, _display_name: String) -> void:
    ART.soft_shadow(root, Vector3(0.0, 0.01, 0.0), maxf(size.x, size.z) * 0.68, 0.90)
    ART.block(root, "BaseShadow", Vector3(size.x + 0.3, 0.28, size.z + 0.3), Vector3(0.0, 0.14, 0.0), Color("#7d674a"), 0.05)
    var forecourt := ART.block(root, "Forecourt", Vector3(minf(size.x * 0.55, 12.0), 0.035, 4.6), Vector3(0.0, 0.0175, size.z * 0.5 + 2.2), ART.CREAM_DEEP, 0.03)
    forecourt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for side: float in [-1.0, 1.0]:
        ART.bollard(root, Vector3(side * (size.x * 0.5 + 1.0), 0.035, size.z * 0.5 + 2.2))
    ART.sphere(root, "DoorLamp", Vector3(0.3, 0.3, 0.3), Vector3(0.0, 3.4, size.z * 0.5 + 0.7), ART.LAMP, true, 1.1)
    ART.soft_shadow(root, Vector3(0.0, 0.02, size.z * 0.5 + 2.2), 2.6, 0.25)
    var accent_light := OmniLight3D.new()
    accent_light.name = "EntranceGlow"
    accent_light.light_color = accent
    accent_light.light_energy = 0.35
    accent_light.omni_range = 5.0
    accent_light.position = Vector3(0.0, 2.6, size.z * 0.5 + 1.2)
    root.add_child(accent_light)


## 通用建筑：倒角奶油壳体 + 珊瑚/青蓝屋顶 + 青蓝窗带 + 暖橙雨棚。
## 五个建筑用同一套语言，靠体量、屋顶色和门口小构件区分身份。
## 所有门默认同一把二级弹子锁：黄铜锁板 + 锁芯 + 小锁舌。
func _build_door_lock(parent: Node3D, at: Vector3) -> Node3D:
    var lock := Node3D.new()
    lock.name = "DoorLock"
    lock.position = at
    parent.add_child(lock)
    ART.block(lock, "LockPlate", Vector3(0.26, 0.34, 0.08), Vector3.ZERO, Color("#c9a15b"), 0.03)
    ART.block(lock, "LockCylinder", Vector3(0.16, 0.16, 0.05), Vector3(0.0, -0.02, 0.065), Color("#8a5a2b"), 0.02)
    ART.block(lock, "LockKeyhole", Vector3(0.05, 0.11, 0.025), Vector3(0.0, -0.02, 0.095), ART.INK, 0.01)
    ART.sphere(lock, "LockLED", Vector3(0.028, 0.028, 0.02), Vector3(0.0, 0.12, 0.075), ART.ORANGE, true, 0.45)
    return lock


func _build_cartoon_building(root: Node3D, id: String, size: Vector3, accent: Color) -> MeshInstance3D:
    var body := ART.block(root, "Shell", size, Vector3(0.0, size.y * 0.5, 0.0), ART.CREAM, 0.34)
    body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    ART.block(root, "Plinth", Vector3(size.x + 0.5, 0.55, size.z + 0.5), Vector3(0.0, 0.275, 0.0), ART.SAND_DEEP, 0.12)
    ART.block(root, "BaseShadow", Vector3(size.x + 0.24, 0.24, size.z + 0.24), Vector3(0.0, 0.12, 0.0), Color("#7d674a"), 0.04)
    # 深色勒脚 + 顶部檐口：近看时墙脚和屋顶各有一条明确收边。
    ART.block(root, "BaseBand", Vector3(size.x + 0.2, 0.8, size.z + 0.2), Vector3(0.0, 0.4, 0.0), ART.SAND_DEEP, 0.05)
    ART.block(root, "Cornice", Vector3(size.x + 0.7, 0.26, size.z + 0.7), Vector3(0.0, size.y - 0.18, 0.0), ART.CREAM_LIGHT, 0.06)

    # 建筑碰撞：整块盒体，外墙不可穿过。
    var collision := StaticBody3D.new()
    collision.name = "ShellCollision"
    collision.collision_layer = 2
    collision.collision_mask = 1
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    shape.position = Vector3(0.0, size.y * 0.5, 0.0)
    collision.add_child(shape)
    root.add_child(collision)

    var roof_color: Color = ART.CORAL
    if id == "library":
        roof_color = ART.TEAL
    elif id == "energy_station":
        roof_color = ART.ORANGE
    ART.block(root, "Roof", Vector3(size.x + 1.5, 0.55, size.z + 1.5), Vector3(0.0, size.y + 0.08, 0.0), roof_color, 0.26)
    var rim_y: float = size.y + 0.40
    var rim_x: float = (size.x + 1.5) * 0.5
    var rim_z: float = (size.z + 1.5) * 0.5
    ART.block(root, "RoofRimN", Vector3(size.x + 1.5, 0.14, 0.34), Vector3(0.0, rim_y, -rim_z + 0.17), ART.CREAM_LIGHT, 0.05)
    ART.block(root, "RoofRimS", Vector3(size.x + 1.5, 0.14, 0.34), Vector3(0.0, rim_y, rim_z - 0.17), ART.CREAM_LIGHT, 0.05)
    ART.block(root, "RoofRimW", Vector3(0.34, 0.14, size.z + 1.5), Vector3(-rim_x + 0.17, rim_y, 0.0), ART.CREAM_LIGHT, 0.05)
    ART.block(root, "RoofRimE", Vector3(0.34, 0.14, size.z + 1.5), Vector3(rim_x - 0.17, rim_y, 0.0), ART.CREAM_LIGHT, 0.05)

    # 正立面：窗带 + 门 + 雨棚 + 招牌。窗框和玻璃都做倒角，近看不会像贴纸。
    var front_z: float = size.z * 0.5 + 0.05
    var window_count: int = maxi(2, int(size.x / 4.5))
    var window_width: float = minf(1.7, size.x / float(window_count) - 0.9)
    for index: int in window_count:
        var x: float = -size.x * 0.5 + (float(index) + 0.5) * (size.x / float(window_count))
        if absf(x) < 2.2:
            continue
        ART.block(root, "WindowFrame%d" % index, Vector3(window_width + 0.34, 2.0, 0.14), Vector3(x, size.y * 0.58, front_z), ART.CREAM_LIGHT, 0.04)
        ART.block(root, "WindowGlass%d" % index, Vector3(window_width, 1.66, 0.08), Vector3(x, size.y * 0.58, front_z + 0.05), ART.GLASS, 0.02, true, 0.12)
        ART.block(root, "WindowMullion%d" % index, Vector3(0.07, 1.66, 0.05), Vector3(x, size.y * 0.58, front_z + 0.10), ART.CREAM_LIGHT, 0.01)
        ART.block(root, "WindowSill%d" % index, Vector3(window_width + 0.46, 0.14, 0.30), Vector3(x, size.y * 0.58 - 0.96, front_z + 0.06), ART.SAND, 0.04)
    # 正立面壁柱：把长墙分成几段，近看有节奏。
    # 门洞中心不放假壁柱：它会和门板落在同一个深度平面上，
    # 近距离/移动时出现一条奶油色的 z-fighting 光栅。
    var bay_count: int = window_count + 1
    for index: int in bay_count:
        var bay_x: float = -size.x * 0.5 + (float(index) / float(bay_count)) * size.x
        if absf(bay_x) < 1.9:
            continue
        ART.block(root, "Pilaster%d" % index, Vector3(0.34, size.y - 1.1, 0.20), Vector3(bay_x, size.y * 0.5, front_z + 0.10), ART.CREAM_LIGHT, 0.05)
    # 侧立面各开两扇，第一人称横穿时建筑不是一块纯色墙。
    for side: float in [-1.0, 1.0]:
        for index: int in 2:
            var z: float = -size.z * 0.25 + float(index) * size.z * 0.5
            ART.block(root, "SideFrame%d_%d" % [int(side), index], Vector3(0.12, 1.7, 1.5), Vector3(side * (size.x * 0.5 + 0.02), size.y * 0.56, z), ART.CREAM_LIGHT, 0.04)
            ART.block(root, "SideGlass%d_%d" % [int(side), index], Vector3(0.06, 1.48, 1.28), Vector3(side * (size.x * 0.5 + 0.09), size.y * 0.56, z), ART.GLASS, 0.02, true, 0.10)

    ART.block(root, "DoorRecess", Vector3(2.7, 2.9, 0.16), Vector3(0.0, 1.45, front_z + 0.02), ART.TEAL_DEEP, 0.08)
    ART.block(root, "Door", Vector3(2.2, 2.5, 0.10), Vector3(0.0, 1.25, front_z + 0.16), ART.TEAL, 0.06)
    ART.block(root, "DoorFrameT", Vector3(3.0, 0.18, 0.34), Vector3(0.0, 2.96, front_z + 0.12), ART.ORANGE, 0.04)
    for side: float in [-1.0, 1.0]:
        ART.block(root, "DoorFrame", Vector3(0.18, 3.0, 0.34), Vector3(side * 1.46, 1.5, front_z + 0.12), ART.ORANGE, 0.04)
    ART.sphere(root, "DoorHandle", Vector3(0.1, 0.1, 0.1), Vector3(0.65, 1.25, front_z + 0.22), ART.CREAM_LIGHT)
    _build_door_lock(root, Vector3(0.65, 1.04, front_z + 0.27))
    if id == "library":
        # 图书馆锁死：门缝焊上钢条，外面再加一道横梁，视觉上也别像能撬开。
        for index: int in 4:
            var weld_y: float = 0.42 + float(index) * 0.56
            ART.block(root, "LibraryWeldBar", Vector3(2.55, 0.12, 0.12), Vector3(0.0, weld_y, front_z + 0.27), Color("#435a5b"), 0.02)
            ART.block(root, "LibraryWeldBead", Vector3(0.26, 0.06, 0.04), Vector3(-0.75 + float(index % 2) * 1.5, weld_y + 0.08, front_z + 0.34), ART.ORANGE, 0.01, true, 0.35)
        ART.block(root, "LibraryCrossBeam", Vector3(3.7, 0.30, 0.22), Vector3(0.0, 1.35, front_z + 0.42), ART.CREAM_DEEP, 0.04)
        ART.block(root, "LibrarySealSign", Vector3(1.0, 0.26, 0.06), Vector3(0.0, 2.72, front_z + 0.34), ART.ORANGE, 0.02, true, 0.4)

    # 门两侧壁灯与门头小牌：第一人称贴近门口时，墙面不是一块空白。
    for side: float in [-1.0, 1.0]:
        ART.block(root, "LampBracket", Vector3(0.12, 0.12, 0.26), Vector3(side * 2.0, 2.8, front_z + 0.12), ART.TEAL_DEEP, 0.03)
        ART.sphere(root, "WallLamp", Vector3(0.22, 0.26, 0.22), Vector3(side * 2.0, 2.8, front_z + 0.30), ART.LAMP, true, 1.0)
    ART.block(root, "DoorSign", Vector3(2.4, 0.46, 0.10), Vector3(0.0, 3.95, front_z + 0.14), accent, 0.04, true, 0.25)
    for index: int in 3:
        ART.block(root, "DoorSignMark%d" % index, Vector3(0.32, 0.16, 0.04), Vector3(-0.62 + float(index) * 0.62, 3.95, front_z + 0.22), ART.CREAM_LIGHT, 0.01)

    # 雨棚：暖橙薄板 + 两根奶油支柱。
    var awning := ART.block(root, "Awning", Vector3(3.8, 0.16, 1.7), Vector3(0.0, 3.22, front_z + 0.75), ART.ORANGE, 0.07)
    awning.rotation_degrees.x = -7.0
    for side: float in [-1.0, 1.0]:
        ART.cylinder(root, "AwningPost", 0.06, 3.0, Vector3(side * 1.7, 1.5, front_z + 1.45), ART.CREAM_LIGHT)

    # 招牌色带：用几何条纹代替悬浮文字。
    ART.block(root, "SignBand", Vector3(minf(size.x * 0.55, 7.0), 0.95, 0.26), Vector3(0.0, size.y * 0.78, front_z + 0.05), accent, 0.06, true, 0.35)
    for index: int in 3:
        ART.block(root, "SignStripe%d" % index, Vector3(0.46, 0.34, 0.08), Vector3(-1.1 + float(index) * 1.1, size.y * 0.78, front_z + 0.20), ART.CREAM_LIGHT, 0.02)

    # 屋顶设备：奶油水箱 + 青蓝压边 + 一块玻璃天窗。
    ART.cylinder(root, "WaterTank", 0.8, 1.4, Vector3(-size.x * 0.24, size.y + 1.1, -size.z * 0.18), ART.CREAM_LIGHT, false)
    ART.cylinder(root, "WaterTankBand", 0.83, 0.12, Vector3(-size.x * 0.24, size.y + 1.1, -size.z * 0.18), ART.TEAL)
    ART.block(root, "RoofAC", Vector3(1.4, 0.75, 1.0), Vector3(size.x * 0.26, size.y + 0.65, -size.z * 0.2), ART.CREAM_DEEP, 0.1)
    ART.block(root, "Skylight", Vector3(2.4, 0.12, 1.4), Vector3(size.x * 0.2, size.y + 0.48, size.z * 0.18), ART.GLASS_LIGHT, 0.04, true, 0.12)

    if id == "school":
        # 学校：屋顶加一座小钟楼，远处先认轮廓。
        ART.block(root, "BellTower", Vector3(3.2, 3.4, 3.2), Vector3(-size.x * 0.28, size.y + 1.75, size.z * 0.12), ART.CREAM, 0.18)
        ART.cone(root, "BellRoof", 0.2, 2.3, 2.0, Vector3(-size.x * 0.28, size.y + 4.4, size.z * 0.12), ART.CORAL)
        ART.sphere(root, "Bell", Vector3(0.5, 0.5, 0.5), Vector3(-size.x * 0.28, size.y + 2.35, size.z * 0.12 + 1.65), ART.ORANGE, true, 0.5)
    elif id == "library":
        # 图书馆：门前四根奶油圆柱，屋顶用青蓝区分。
        for index: int in 4:
            ART.cylinder(root, "Column%d" % index, 0.22, 3.1, Vector3(-2.9 + float(index) * 1.95, 1.55, front_z + 2.0), ART.CREAM_LIGHT)
            ART.block(root, "ColumnCap%d" % index, Vector3(0.62, 0.18, 0.62), Vector3(-2.9 + float(index) * 1.95, 3.18, front_z + 2.0), ART.CREAM_LIGHT, 0.05)
    elif id == "energy_station":
        # 能源站：储能柜、充电塔、变压器和顶棚太阳能板，不再有加油机。
        ART.block(root, "EnergyCanopy", Vector3(size.x + 3.0, 0.34, 7.0), Vector3(0.0, 4.2, front_z + 2.6), ART.TEAL, 0.12)
        ART.block(root, "EnergyCanopyTrim", Vector3(size.x + 3.2, 0.12, 7.2), Vector3(0.0, 4.40, front_z + 2.6), ART.ORANGE, 0.04)
        for side: float in [-1.0, 1.0]:
            ART.cylinder(root, "CanopyPost", 0.18, 4.0, Vector3(side * (size.x * 0.5 + 0.4), 2.0, front_z + 5.0), ART.CREAM_LIGHT)
        # 顶棚下的冷白灯带。
        ART.block(root, "CanopyLightStrip", Vector3(size.x + 1.4, 0.05, 0.16), Vector3(0.0, 4.00, front_z + 2.6), Color("#d8e6de"), 0.02, true, 0.55)
        var canopy_light := OmniLight3D.new()
        canopy_light.name = "EnergyCanopyLight"
        canopy_light.light_color = Color("#d8e6de")
        canopy_light.light_energy = 1.25
        canopy_light.omni_range = 8.5
        canopy_light.position = Vector3(0.0, 3.75, front_z + 2.6)
        canopy_light.shadow_enabled = false
        root.add_child(canopy_light)
        # 两组储能柜，替代原来的加油机。
        for index: int in 2:
            var x: float = -3.4 + float(index) * 6.8
            ART.block(root, "EnergyBatteryBase%d" % index, Vector3(1.9, 0.22, 1.25), Vector3(x, 0.11, front_z + 2.25), ART.INK, 0.04)
            ART.block(root, "EnergyBatteryBody%d" % index, Vector3(1.55, 1.75, 0.95), Vector3(x, 1.05, front_z + 2.25), ART.TEAL_DEEP, 0.08)
            ART.block(root, "EnergyBatteryTop%d" % index, Vector3(1.65, 0.12, 1.05), Vector3(x, 1.98, front_z + 2.25), ART.TEAL_LIGHT, 0.03)
            for row: int in 3:
                ART.block(root, "BatteryCell%d_%d" % [index, row], Vector3(1.10, 0.20, 0.06), Vector3(x, 1.34 + float(row) * 0.25, front_z + 2.77), Color("#4d7d78"), 0.02, true, 0.28)
            ART.block(root, "BatteryScreen%d" % index, Vector3(0.42, 0.28, 0.06), Vector3(x, 0.82, front_z + 2.78), ART.INK, 0.02)
            ART.block(root, "BatteryMeter%d" % index, Vector3(0.22, 0.06, 0.03), Vector3(x, 0.82, front_z + 2.82), ART.ORANGE, 0.01, true, 0.5)
            # 充电塔：立柱 + 发光环 + 线缆。
            ART.cylinder(root, "ChargePost%d" % index, 0.12, 2.35, Vector3(x + 2.35, 1.18, front_z + 4.5), ART.TEAL_LIGHT)
            for ring_index: int in 3:
                ART.torus(root, "ChargeRing%d_%d" % [index, ring_index], 0.20, 0.25, Vector3(x + 2.35, 0.55 + float(ring_index) * 0.62, front_z + 4.5), ART.ORANGE, true, 0.65)
            ART.block(root, "ChargeCap%d" % index, Vector3(0.42, 0.12, 0.42), Vector3(x + 2.35, 2.42, front_z + 4.5), ART.CREAM_LIGHT, 0.03)
            ART.block(root, "ChargeWarning%d" % index, Vector3(0.64, 0.10, 0.06), Vector3(x + 2.35, 1.95, front_z + 4.78), ART.ORANGE, 0.02, true, 0.25)
        # 右侧变压器和散热片。
        ART.block(root, "EnergyTransformer", Vector3(1.8, 2.25, 1.3), Vector3(5.6, 1.13, front_z + 1.15), Color("#4c5d5c"), 0.08)
        for fin: int in 5:
            ART.block(root, "TransformerFin%d" % fin, Vector3(0.06, 1.6, 0.9), Vector3(4.62 - float(fin) * 0.14, 1.15, front_z + 1.15), ART.TEAL_LIGHT, 0.01)
        ART.block(root, "TransformerWarning", Vector3(1.4, 0.16, 0.05), Vector3(5.6, 1.7, front_z + 1.82), ART.ORANGE, 0.02, true, 0.3)
        # 顶棚太阳能板和接线管。
        for panel_index: int in 2:
            var panel := ART.block(root, "SolarPanel%d" % panel_index, Vector3(3.8, 0.10, 1.8), Vector3(-2.1 + float(panel_index) * 4.2, 4.52, front_z + 2.5), ART.GLASS, 0.03, true, 0.12)
            panel.rotation_degrees.x = -7.0
        for conduit_index: int in 3:
            var conduit := ART.cylinder(root, "EnergyConduit%d" % conduit_index, 0.045, 3.0, Vector3(-1.0 + float(conduit_index) * 1.0, 3.35, front_z + 1.0), Color("#65706d"))
            conduit.rotation_degrees.x = 90.0
        # 站前入口的橙色能量标识带。
        ART.block(root, "EnergyBoltA", Vector3(0.16, 0.58, 0.05), Vector3(-0.22, 5.65, front_z + 0.30), ART.ORANGE, 0.02, true, 0.6).rotation_degrees.z = -28.0
        ART.block(root, "EnergyBoltB", Vector3(0.16, 0.58, 0.05), Vector3(0.18, 5.65, front_z + 0.30), ART.ORANGE, 0.02, true, 0.6).rotation_degrees.z = 28.0

    ART.soft_shadow(root, Vector3(0.0, 0.012, 0.0), maxf(size.x, size.z) * 0.62, 0.85)
    var forecourt := ART.block(root, "Forecourt", Vector3(minf(size.x * 0.6, 13.0), 0.035, 4.4), Vector3(0.0, 0.0175, size.z * 0.5 + 2.1), ART.CREAM_DEEP, 0.03)
    forecourt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var ring := ART.torus(root, "EntryRing", 1.5, 1.56, Vector3(0.0, 0.08, size.z * 0.5 + 1.6), accent, true, 0.9)
    ring.visible = false
    return ring


func _build_food_sites() -> void:
    for raw in FOOD_SITES:
        var id := String(raw.id)
        var point := Vector2(raw.position)
        var root := Node3D.new()
        root.name = "RuinFood_" + id
        # 物资箱要落在真实地表上：广场 9cm、道路 3.5cm、人行道/店前路 4~6cm。
        # 统一放 y=0 时箱底会埋进铺装，环也会被广场盖住。
        root.position = Vector3(point.x, surface_height(point.x, point.y), point.y)
        _world().add_child(root)
        var kind := String(raw.kind)
        var accent := ART.ORANGE if kind == "canned" else (ART.TEAL_LIGHT if kind == "water" else ART.CORAL)
        ART.block(root, "Crate", Vector3(1.45, 0.9, 1.45), Vector3(0.0, 0.45, 0.0), ART.CREAM, 0.11)
        ART.block(root, "CrateBand", Vector3(1.5, 0.14, 1.5), Vector3(0.0, 0.68, 0.0), ART.TEAL, 0.04)
        ART.block(root, "CrateLid", Vector3(1.2, 0.12, 1.2), Vector3(0.0, 0.98, 0.0), accent, 0.05, true, 0.3)
        # 物资箱本体也要有碰撞，玩家和掉落物不会从箱子里穿过去。
        var crate_body := StaticBody3D.new()
        crate_body.name = "CrateCollision"
        crate_body.collision_layer = 2
        crate_body.collision_mask = 0
        var crate_shape := CollisionShape3D.new()
        var crate_box := BoxShape3D.new()
        crate_box.size = Vector3(1.35, 0.9, 1.35)
        crate_shape.shape = crate_box
        crate_shape.position.y = 0.45
        crate_body.add_child(crate_shape)
        root.add_child(crate_body)
        for index: int in 3:
            var offset := Vector3(-0.34 + float(index) * 0.34, 1.12, 0.0)
            ART.sphere(root, "Goods%d" % index, Vector3(0.22, 0.26, 0.22), offset, accent)
        ART.soft_shadow(root, Vector3(0.0, 0.015, 0.0), 1.15, 0.35)
        var ring := ART.torus(root, "FoodRing", 1.0, 1.05, Vector3(0.0, 0.06, 0.0), accent, true, 0.9)
        ring.visible = false
        food_sites[id] = {"root": root, "name": String(raw.name), "kind": kind, "ring": ring}


# ── 街道、远景与登陆艇 ────────────────────────────────────────

## 铺装分缝：每 6 米一道浅色缝，给第一人称一个稳定的尺度参照。
## 只加视觉，不加碰撞；压在细节层之上、道路之下。
func _build_ground_grid() -> void:
    var seam := Color("#bda57e")
    var half_x: float = GROUND_EXTENT.x - 4.0
    var half_z: float = GROUND_EXTENT.y - 4.0
    var x: float = -72.0
    while x <= 72.0:
        var line := ART.plane(_world(), "PavingSeamX", Vector2(0.05, half_z * 2.0), Vector3(x, 0.03, 0.0), seam)
        line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        x += 8.0
    var z: float = -48.0
    while z <= 48.0:
        var line := ART.plane(_world(), "PavingSeamZ", Vector2(half_x * 2.0, 0.05), Vector3(0.0, 0.03, z), seam)
        line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        z += 8.0
    # 几处浅青积水，打破大面积暖沙色。
    var puddles: Array[Vector3] = [
        Vector3(-28.0, 0.0, 18.0), Vector3(18.0, 0.0, -2.0),
        Vector3(48.0, 0.0, 12.0), Vector3(-56.0, 0.0, -24.0),
    ]
    for index: int in puddles.size():
        var puddle := ART.cylinder(_world(), "Puddle", 1.1 + float(index) * 0.15, 0.014, puddles[index] + Vector3(0.0, 0.028, 0.0), Color("#7fa5a0"))
        puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 视觉铺装的顶面高度。物资箱、掉落物和街具都要落在这个高度上，
## 而不是一律放在 y=0，否则会埋进广场/人行道/店前路。
func surface_height(x: float, z: float) -> float:
    var h := 0.0
    var point := Vector2(x, z)
    if point.distance_to(Vector2(0.0, 6.0)) <= 9.0:
        h = maxf(h, 0.09)
    if absf(z - 6.0) <= 3.6:
        h = maxf(h, 0.035)
    if absf(x) <= 3.2:
        h = maxf(h, 0.035)
    for side: float in [-1.0, 1.0]:
        if absf(z - (6.0 + side * 5.4)) <= 1.5:
            h = maxf(h, 0.04)
        if absf(x - side * 5.0) <= 1.5:
            h = maxf(h, 0.04)
    for raw in BUILDINGS:
        var bpos := Vector2(raw.position)
        var bsize := Vector3(raw.size)
        var front_z := bpos.y + bsize.z * 0.5
        if absf(x - bpos.x) <= minf(bsize.x * 0.6, 13.0) * 0.5 and absf(z - (front_z + 2.2)) <= 2.3:
            h = maxf(h, 0.035)
        if absf(x - bpos.x) <= 2.5 and absf(z - (front_z + 3.6)) <= 3.0:
            h = maxf(h, 0.06)
    return h


## 给铺装加一层薄碰撞，让掉落物和角色站在"看得见的表面"上。
## 只做水平顶面，不加侧面台阶，避免和现有地面碰撞体打架。
func _add_box_floor(size: Vector3, center: Vector3) -> void:
    _floor_serial += 1
    var body := StaticBody3D.new()
    body.name = "RuinFloor%d" % _floor_serial
    body.collision_layer = 2
    body.collision_mask = 0
    body.position = center
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    _world().add_child(body)


func _add_cylinder_floor(radius: float, height: float, center: Vector3) -> void:
    _floor_serial += 1
    var body := StaticBody3D.new()
    body.name = "RuinFloor%d" % _floor_serial
    body.collision_layer = 2
    body.collision_mask = 0
    body.position = center
    var shape := CollisionShape3D.new()
    var cylinder := CylinderShape3D.new()
    cylinder.radius = radius
    cylinder.height = height
    shape.shape = cylinder
    body.add_child(shape)
    _world().add_child(body)


## 一条东西向主街 + 一条南北向支路 + 中央广场。
## 路面只做视觉，不另加碰撞；玩家仍然踩在整块地面碰撞体上。
func _build_roads() -> void:
    var street_color := Color("#6f8783")
    var street_dark := Color("#657d79")
    # 主街：从市场门前穿过广场，再通往医院方向。
    var avenue := ART.plane(_world(), "Avenue", Vector2(GROUND_EXTENT.x * 2.0 - 10.0, 7.2), Vector3(0.0, 0.035, 6.0), street_color)
    avenue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _add_box_floor(Vector3(GROUND_EXTENT.x * 2.0 - 10.0, 0.035, 7.2), Vector3(0.0, 0.0175, 6.0))
    for side: float in [-1.0, 1.0]:
        var curb := ART.block(_world(), "AvenueCurb", Vector3(GROUND_EXTENT.x * 2.0 - 10.0, 0.10, 0.5), Vector3(0.0, 0.05, 6.0 + side * 3.85), ART.CREAM_DEEP, 0.03)
        curb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var sidewalk := ART.plane(_world(), "AvenueSidewalk", Vector2(GROUND_EXTENT.x * 2.0 - 10.0, 3.0), Vector3(0.0, 0.04, 6.0 + side * 5.4), ART.CREAM_DEEP)
        sidewalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _add_box_floor(Vector3(GROUND_EXTENT.x * 2.0 - 10.0, 0.04, 3.0), Vector3(0.0, 0.02, 6.0 + side * 5.4))
    # 南北支路：从能源站经过广场，通往北侧的学校与图书馆之间。
    var cross := ART.plane(_world(), "CrossStreet", Vector2(6.4, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(0.0, 0.035, -4.0), street_dark)
    cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _add_box_floor(Vector3(6.4, 0.035, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(0.0, 0.0175, -4.0))
    for side: float in [-1.0, 1.0]:
        var cross_curb := ART.block(_world(), "CrossCurb", Vector3(0.5, 0.10, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(side * 3.45, 0.05, -4.0), ART.CREAM_DEEP, 0.03)
        cross_curb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var cross_walk := ART.plane(_world(), "CrossSidewalk", Vector2(3.0, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(side * 5.0, 0.04, -4.0), ART.CREAM_DEEP)
        cross_walk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _add_box_floor(Vector3(3.0, 0.04, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(side * 5.0, 0.02, -4.0))
    # 中央广场：圆形铺装 + 一圈青色环，作为玩家认路的地标。
    ART.cylinder(_world(), "Plaza", 9.0, 0.09, Vector3(0.0, 0.045, 6.0), ART.SAND)
    _add_cylinder_floor(9.0, 0.09, Vector3(0.0, 0.045, 6.0))
    ART.torus(_world(), "PlazaRing", 8.55, 8.85, Vector3(0.0, 0.10, 6.0), ART.TEAL)
    ART.torus(_world(), "PlazaRingInner", 4.6, 4.8, Vector3(0.0, 0.10, 6.0), ART.ORANGE)
    # 车道虚线：暖橙色小方块，比白线更符合整套配色。
    for index: int in 11:
        var x: float = -60.0 + float(index) * 12.0
        if absf(x) < 9.5:
            continue
        var dash := ART.plane(_world(), "LaneDash", Vector2(1.6, 0.16), Vector3(x, 0.06, 6.0), ART.ORANGE)
        dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # 斑马线：广场四个方向各铺三条。
    for direction: int in 4:
        var yaw: float = float(direction) * PI * 0.5
        for index: int in 3:
            var stripe := ART.plane(_world(), "Crosswalk", Vector2(2.4, 0.46), Vector3(-1.2 + float(index) * 1.2, 0.06, 10.0), ART.CREAM_LIGHT)
            stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            stripe.rotation_degrees.y = yaw
            var offset := Vector3(0.0, 0.0, 10.0).rotated(Vector3.UP, yaw)
            stripe.position = Vector3(offset.x, 0.06, 6.0 + offset.z)
    # 通往每家店门口的小路
    for raw in BUILDINGS:
        var building_point := Vector2(raw.position)
        var size := Vector3(raw.size)
        var front_z: float = building_point.y + size.z * 0.5
        var path_center := Vector3(building_point.x, 0.06, front_z + 3.6)
        ART.plane(_world(), "ShopPath", Vector2(5.0, 6.0), path_center, ART.CREAM_DEEP)
        _add_box_floor(Vector3(5.0, 0.06, 6.0), Vector3(building_point.x, 0.03, front_z + 3.6))
        # 门前平台：比路面高 3.5cm，和视觉 forecourt 对齐。
        _add_box_floor(Vector3(minf(size.x * 0.6, 13.0), 0.035, 4.6), Vector3(building_point.x, 0.0175, front_z + 2.2))


## 登陆艇：玩家出生点兼返航点。
## 不做飞船模型，只做一块清楚的圆形停机坪、四枚橙色定位灯和一座信标柱，
## 让第一人称落地第一眼就知道"这里可以回去"。
func _build_landing_pad() -> void:
    var pad := Node3D.new()
    pad.name = "RuinLandingPad"
    pad.position = Vector3(SPAWN_POSITION.x, 0.0, SPAWN_POSITION.y)
    _world().add_child(pad)
    ART.cylinder(pad, "PadBase", PAD_RADIUS, 0.12, Vector3(0.0, 0.06, 0.0), ART.CREAM_DEEP)
    _add_cylinder_floor(PAD_RADIUS, 0.12, Vector3(SPAWN_POSITION.x, 0.06, SPAWN_POSITION.y))
    ART.torus(pad, "PadRing", PAD_RADIUS - 0.22, PAD_RADIUS - 0.04, Vector3(0.0, 0.13, 0.0), ART.ORANGE, true, 0.45)
    # 撤离开放后出现的一圈青绿灯带；未开放时隐藏。
    _pad_active_ring = ART.torus(pad, "PadActiveRing", PAD_RADIUS - 0.52, PAD_RADIUS - 0.30, Vector3(0.0, 0.15, 0.0), ART.TEAL_LIGHT, true, 0.9)
    _pad_active_ring.visible = false
    ART.torus(pad, "PadInner", 2.2, 2.34, Vector3(0.0, 0.13, 0.0), ART.TEAL, true, 0.35)
    _pad_lights.clear()
    for index: int in 4:
        var angle: float = TAU * float(index) / 4.0 + PI * 0.25
        var light_position := Vector3(cos(angle) * (PAD_RADIUS - 0.7), 0.2, sin(angle) * (PAD_RADIUS - 0.7))
        var pad_light := ART.sphere(pad, "PadLight%d" % index, Vector3(0.34, 0.22, 0.34), light_position, ART.ORANGE, true, 0.9)
        _pad_lights.append(pad_light)
    # 信标柱：青蓝柱身 + 奶油灯罩，放在停机坪左后方，避免正对镜头挡住城市。
    ART.cylinder(pad, "BeaconPole", 0.10, 2.7, Vector3(-4.6, 1.35, -3.4), ART.TEAL_DEEP)
    ART.sphere(pad, "BeaconLamp", Vector3(0.5, 0.5, 0.5), Vector3(-4.6, 2.8, -3.4), ART.LAMP, true, 1.2)
    ART.torus(pad, "BeaconRing", 0.58, 0.66, Vector3(-4.6, 2.8, -3.4), ART.ORANGE, true, 0.7)
    # 地面上的"归航"箭头，用几何三角形代替文字。
    for index: int in 3:
        var arrow := ART.block(pad, "Arrow%d" % index, Vector3(0.5, 0.02, 1.5), Vector3(-1.2 + float(index) * 1.2, 0.14, 0.4), ART.CREAM_LIGHT, 0.02)
        arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    ART.soft_shadow(pad, Vector3(0.0, 0.01, 0.0), PAD_RADIUS * 1.05, 0.3)


## 街道陈设：路灯、花坛、长椅、树和公交站。
## 只加视觉，不加碰撞；玩家可以从中间穿过去，不会卡住。
func _build_street_dressing() -> void:
    var lamp_positions: Array[Vector3] = [
        Vector3(-70.0, 0.0, 2.0), Vector3(-46.0, 0.0, 2.0), Vector3(-24.0, 0.0, 2.0),
        Vector3(24.0, 0.0, 2.0), Vector3(46.0, 0.0, 2.0), Vector3(70.0, 0.0, 2.0),
        Vector3(-34.0, 0.0, 10.0), Vector3(34.0, 0.0, 10.0),
    ]
    for index: int in lamp_positions.size():
        var lamp_position := lamp_positions[index]
        lamp_position.y = surface_height(lamp_position.x, lamp_position.z)
        var lamp := ART.street_lamp(_world(), lamp_position, 4.2 if index % 2 == 0 else 3.8)
        ART.soft_shadow(lamp, Vector3(0.0, 0.0, 0.0), 0.62, 0.25)

    var planter_positions: Array[Vector3] = [
        Vector3(-12.5, 0.0, 6.0), Vector3(12.5, 0.0, 6.0),
        Vector3(-9.0, 0.0, -7.0), Vector3(9.0, 0.0, -7.0),
        Vector3(-40.0, 0.0, -14.0), Vector3(40.0, 0.0, -18.0),
        Vector3(-62.0, 0.0, 7.0), Vector3(64.0, 0.0, 15.0),
    ]
    for index: int in planter_positions.size():
        var planter_position := planter_positions[index]
        planter_position.y = surface_height(planter_position.x, planter_position.z)
        var planter := ART.planter(_world(), planter_position, 1.5 if index % 2 == 0 else 1.2, index * 17 + 3)
        ART.soft_shadow(planter, Vector3(0.0, 0.0, 0.0), 1.1, 0.28)

    var bench_specs: Array = [
        [Vector3(-6.0, 0.0, 12.0), PI],
        [Vector3(6.0, 0.0, 12.0), PI],
        [Vector3(-6.0, 0.0, 0.0), 0.0],
        [Vector3(6.0, 0.0, 0.0), 0.0],
        [Vector3(-40.0, 0.0, -12.5), PI],
    ]
    for spec: Array in bench_specs:
        var bench_position := Vector3(spec[0])
        bench_position.y = surface_height(bench_position.x, bench_position.z)
        var bench := ART.bench(_world(), bench_position, float(spec[1]))
        ART.soft_shadow(bench, Vector3(0.0, 0.0, 0.0), 1.25, 0.25)

    var tree_positions: Array[Vector3] = [
        Vector3(-22.0, 0.0, -8.0), Vector3(22.0, 0.0, -14.0),
        Vector3(-54.0, 0.0, -6.0), Vector3(54.0, 0.0, 2.0),
        Vector3(-16.0, 0.0, 22.0), Vector3(16.0, 0.0, 22.0),
        Vector3(-70.0, 0.0, 34.0), Vector3(70.0, 0.0, 34.0),
        Vector3(-64.0, 0.0, -26.0), Vector3(64.0, 0.0, -30.0),
        Vector3(-30.0, 0.0, 38.0), Vector3(30.0, 0.0, 38.0),
    ]
    for index: int in tree_positions.size():
        var tree_position := tree_positions[index]
        tree_position.y = surface_height(tree_position.x, tree_position.z)
        var tree := ART.tree(_world(), tree_position, index * 31 + 7, 1.0 + float(index % 3) * 0.12)
        ART.soft_shadow(tree, Vector3(0.0, 0.0, 0.0), 1.5, 0.30)

    # 广场边缘的护柱
    for index: int in 10:
        var angle: float = TAU * float(index) / 10.0
        var bollard_position := Vector3(cos(angle) * 10.4, 0.0, 6.0 + sin(angle) * 10.4)
        bollard_position.y = surface_height(bollard_position.x, bollard_position.z)
        ART.bollard(_world(), bollard_position)

    # 公交站：三根柱子 + 一块奶油顶棚 + 一条长椅，给广场一个生活痕迹。
    var stop := Node3D.new()
    stop.name = "BusStop"
    stop.position = Vector3(14.0, surface_height(14.0, 14.0), 14.0)
    stop.rotation_degrees.y = -20.0
    _world().add_child(stop)
    for side: float in [-1.0, 1.0]:
        ART.cylinder(stop, "StopPost", 0.09, 2.6, Vector3(side * 1.6, 1.3, -0.5), ART.TEAL_DEEP)
    ART.block(stop, "StopRoof", Vector3(4.0, 0.18, 1.8), Vector3(0.0, 2.62, 0.0), ART.CREAM_LIGHT, 0.08)
    ART.block(stop, "StopScreen", Vector3(3.6, 1.4, 0.08), Vector3(0.0, 1.6, -0.85), ART.GLASS, 0.02, true, 0.10)
    ART.bench(stop, Vector3(0.0, 0.0, 0.2), 0.0)
    ART.soft_shadow(stop, Vector3(0.0, 0.0, 0.0), 2.4, 0.30)


## 地面散落物：草丛与碎石。第一人称低头时，空地不再是一整块纯色。
## 全部无碰撞、不投影；只负责把尺度和"这里很久没人打理"读出来。
func _build_ground_scatter() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261028
    var placed := 0
    var attempts := 0
    while placed < 26 and attempts < 200:
        attempts += 1
        var point := Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-46.0, 46.0))
        if not _open_ground(point):
            continue
        var root := Node3D.new()
        root.name = "RuinGrass"
        root.position = Vector3(point.x, 0.0, point.y)
        _world().add_child(root)
        for index: int in 3:
            var blade := ART.cone(root, "Blade%d" % index, 0.0, 0.16, rng.randf_range(0.35, 0.62), Vector3(rng.randf_range(-0.18, 0.18), 0.2, rng.randf_range(-0.18, 0.18)), ART.SAGE_DEEP if index % 2 == 0 else ART.SAGE)
            blade.rotation_degrees.z = rng.randf_range(-14.0, 14.0)
        placed += 1
    placed = 0
    attempts = 0
    while placed < 20 and attempts < 200:
        attempts += 1
        var point := Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-46.0, 46.0))
        if not _open_ground(point):
            continue
        var stone := ART.block(_world(), "RuinStone", Vector3(rng.randf_range(0.25, 0.55), rng.randf_range(0.18, 0.32), rng.randf_range(0.25, 0.5)), Vector3(point.x, 0.12, point.y), ART.SAND_DEEP if placed % 2 == 0 else Color("#7d674a"), 0.06)
        stone.rotation_degrees.y = rng.randf_range(0.0, 360.0)
        stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        placed += 1


func _open_ground(point: Vector2) -> bool:
    # 避开主街、支路、广场和建筑占地。
    if absf(point.y - 6.0) < 5.2 or absf(point.x) < 4.8:
        return false
    if point.distance_to(Vector2(0.0, 6.0)) < 10.8:
        return false
    for raw in BUILDINGS:
        var center := Vector2(raw.position)
        var size := Vector3(raw.size)
        if absf(point.x - center.x) < size.x * 0.5 + 2.2 and absf(point.y - center.y) < size.z * 0.5 + 2.2:
            return false
    return true


## 远景：环状低丘、几栋远处建筑和一圈树。
## 全部无碰撞、不投影，靠雾把地图边缘收住；第一人称下抬头能看到完整天空。
func _build_horizon() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261028
    var hill_parent := Node3D.new()
    hill_parent.name = "RuinHorizon"
    _world().add_child(hill_parent)
    for index: int in 14:
        var angle: float = TAU * float(index) / 14.0 + rng.randf_range(-0.08, 0.08)
        var radius: float = rng.randf_range(96.0, 116.0)
        var point := Vector3(cos(angle) * radius, -1.5, sin(angle) * radius)
        var hill_size := Vector3(rng.randf_range(28.0, 42.0), rng.randf_range(8.0, 15.0), rng.randf_range(24.0, 38.0))
        var hill := ART.sphere(hill_parent, "Hill%d" % index, hill_size, point, ART.SAGE_DEEP if index % 2 == 0 else ART.TEAL)
        hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # 远处城市剪影：奶油/青蓝体块，给地平线一点"这里曾经是殖民城"的读法。
    for index: int in 10:
        var angle: float = TAU * float(index) / 10.0 + 0.22
        var radius: float = rng.randf_range(82.0, 98.0)
        var height: float = rng.randf_range(10.0, 24.0)
        var width: float = rng.randf_range(8.0, 15.0)
        var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
        var distant := ART.block(hill_parent, "DistantBlock%d" % index, Vector3(width, height, width * 0.8), point + Vector3(0.0, height * 0.5, 0.0), ART.CREAM_DEEP if index % 2 == 0 else ART.TEAL, 0.4)
        distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # 地图外圈树线：从地面边缘一直排到远景，遮住可行走范围的硬边。
    for index: int in 22:
        var angle: float = TAU * float(index) / 22.0
        var radius: float = rng.randf_range(78.0, 92.0)
        var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
        var tree := ART.tree(hill_parent, point, index * 13 + 5, rng.randf_range(1.2, 2.0))
        tree.name = "HorizonTree%d" % index


func _build_hud() -> void:
    if hud != null:
        return
    hud = RUIN_HUD.new()
    hud.name = "RuinHUD"
    hud.setup(controller)
    controller.add_child(hud)


## 门框、窗棂、招牌、灯杆这类薄片不投影。
## 它们投出的细影在移动时最容易变成一条条"光栅"；体积感交给建筑主体与贴地软阴影。
func _cull_thin_shadow_casters() -> void:
    if not is_instance_valid(world_root):
        return
    for node in world_root.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        if mesh == null or mesh.mesh == null:
            continue
        var extents := mesh.get_aabb().size
        if minf(extents.x, minf(extents.y, extents.z)) < 0.22:
            mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ── 刷新 ──

func _tick_spawns(delta: float) -> void:
    # 世界被隐藏（已经返航、或还没登陆）时不要继续刷怪。
    if not is_instance_valid(world_root) or not world_root.visible:
        return
    _spawn_timer = maxf(_spawn_timer - delta, 0.0)
    if _spawn_timer > 0.0:
        return
    if zombies.size() >= _zombie_cap():
        # 满员时也继续走计时：玩家清掉一只后仍要等一个间隔才会补上，
        # 否则会变成"打完立刻原地刷新"。
        _spawn_timer = _next_interval()
        return
    if _spawn_one():
        _spawn_timer = _next_interval()
    else:
        # 没找到合适落点（玩家挤在角落或建筑密集），过几秒再试。
        _spawn_timer = 3.0


func _zombie_cap() -> int:
    # 单人 3 只，每多一名玩家 +1。
    return ZOMBIE_CAP_BASE + maxi(controller.connected_ids.size() - 1, 0)


func _next_interval() -> float:
    return _spawn_rng.randf_range(ZOMBIE_SPAWN_INTERVAL.x, ZOMBIE_SPAWN_INTERVAL.y)


func _pick_form() -> int:
    # 用"袋子"而不是纯随机：每袋 2 个步行者 + 1 个鼓胀者 + 1 个爬行者，
    # 洗完再抽，既保证比例又不会连着三只都是同一种。
    if _form_bag.is_empty():
        _form_bag = ZOMBIE_FORM_BAG.duplicate()
        for index in range(_form_bag.size() - 1, 0, -1):
            var other := _spawn_rng.randi_range(0, index)
            var swap: int = int(_form_bag[index])
            _form_bag[index] = _form_bag[other]
            _form_bag[other] = swap
    return int(_form_bag.pop_back())


func _spawn_one() -> bool:
    var point := _pick_spawn_point()
    if point == Vector2.INF:
        return false
    var enemy := RUIN_INFECTED.new() as SpaceEnemy3D
    if enemy == null:
        return false
    enemy.setup_form(_pick_form())
    enemy.setup(next_zombie_id, controller.connected_ids.size())
    # SpaceEnemy3D 的默认标签是霜烬星的「霜噬生物 / 追踪热量」，
    # 在腐墟星必须换掉，否则感染体顶着霜烬星的名字。
    enemy.set_creature_label("感染体", "循声而来 · 空格攻击")
    # 必须挂在 Main3D 下：SpaceEnemy3D.server_tick 用 get_parent() 取控制器来结算伤害。
    enemy.position = Vector3(point.x, surface_height(point.x, point.y), point.y)
    controller.add_child(enemy)
    zombies[next_zombie_id] = enemy
    next_zombie_id += 1
    return true


func _pick_spawn_point() -> Vector2:
    # 先按正常距离撒点；连续找不到再放宽一点，
    # 避免四人分散站开后完全刷不出来。
    for attempt in 24:
        var margin := ZOMBIE_SPAWN_MIN_DISTANCE if attempt < 16 else ZOMBIE_SPAWN_RETRY_DISTANCE
        var point := Vector2(
            _spawn_rng.randf_range(-GROUND_EXTENT.x + ZOMBIE_SPAWN_EDGE_MARGIN, GROUND_EXTENT.x - ZOMBIE_SPAWN_EDGE_MARGIN),
            _spawn_rng.randf_range(-GROUND_EXTENT.y + ZOMBIE_SPAWN_EDGE_MARGIN, GROUND_EXTENT.y - ZOMBIE_SPAWN_EDGE_MARGIN)
        )
        if _inside_building(point):
            continue
        if not _far_from_players(point, margin):
            continue
        return point
    return Vector2.INF


func _inside_building(point: Vector2) -> bool:
    # 建筑内部这一轮还没开放，感染体不能刷在实心体块里。
    for raw in BUILDINGS:
        var center := Vector2(raw.position)
        var size := Vector3(raw.size)
        var half := Vector2(size.x, size.z) * 0.5 + Vector2(2.0, 2.0)
        if absf(point.x - center.x) < half.x and absf(point.y - center.y) < half.y:
            return true
    return false


func _far_from_players(point: Vector2, margin: float) -> bool:
    for peer_id in controller.players.keys():
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player == null:
            continue
        var flat := Vector2(player.global_position.x, player.global_position.z)
        if flat.distance_to(point) < margin:
            return false
    return true


# ── 感染体同步 ──

## 只给同步用的快照。位置只在客户端第一次建出这只感染体时用到，
## 之后靠 SpaceEnemy3D 自己的 sync_transform 平滑跟随。
func enemy_snapshot() -> Array:
    var result: Array = []
    for id in zombies.keys():
        var zombie := zombies[id] as SpaceEnemy3D
        if zombie == null or not is_instance_valid(zombie) or zombie.health <= 0:
            continue
        result.append({
            "id": zombie.enemy_id,
            "form": int(zombie.form),
            "health": zombie.health,
            "position": zombie.global_position,
        })
    return result


## 客户端按主机发来的快照补齐/清理感染体。
## 敌人完全由主机驱动，客户端不自己刷怪，所以这里就是"对齐"。
func apply_enemy_snapshot(entries: Array) -> void:
    var seen: Dictionary = {}
    for raw in entries:
        if not raw is Dictionary:
            continue
        var data: Dictionary = raw
        var id := int(data.get("id", 0))
        if id <= 0:
            continue
        seen[id] = true
        var zombie := zombies.get(id) as SpaceEnemy3D
        if zombie == null or not is_instance_valid(zombie):
            zombie = _spawn_from_snapshot(data)
            if zombie == null:
                continue
        zombie.health = int(data.get("health", zombie.health))
    # 主机那边已经清掉的（被打死）要同步移除，否则客户端会留下打不死的残影。
    for id in zombies.keys():
        if seen.has(int(id)):
            continue
        var stale := zombies[id] as Node
        if is_instance_valid(stale):
            stale.queue_free()
        zombies.erase(id)


func _spawn_from_snapshot(data: Dictionary) -> SpaceEnemy3D:
    var enemy := RUIN_INFECTED.new() as SpaceEnemy3D
    if enemy == null:
        return null
    enemy.setup_form(int(data.get("form", 0)))
    enemy.setup(int(data.get("id", 1)), controller.connected_ids.size())
    enemy.set_creature_label("感染体", "循声而来 · 空格攻击")
    enemy.position = Vector3(data.get("position", Vector3.ZERO))
    controller.add_child(enemy)
    enemy.health = int(data.get("health", enemy.max_health))
    zombies[enemy.enemy_id] = enemy
    next_zombie_id = maxi(next_zombie_id, enemy.enemy_id + 1)
    return enemy


# ── 环境 ──

func _apply_camera_environment() -> void:
    if _environment == null:
        return
    if not is_instance_valid(world_root) or not world_root.visible:
        return
    for peer_id in controller.players.keys():
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player == null:
            continue
        var camera := player._camera
        var target_environment := _environment
        if _hospital_environment != null and hospital_interior != null and is_inside_hospital(player.global_position):
            target_environment = _hospital_environment
        elif _energy_environment != null and energy_station_interior != null and is_inside_energy_station(player.global_position):
            target_environment = _energy_environment
        elif _school_environment != null and school_interior != null and is_inside_school(player.global_position):
            target_environment = _school_environment
        elif _market_environment != null and market_interior != null and is_inside_market(player.global_position):
            target_environment = _market_environment
        if camera != null and camera.environment != target_environment:
            camera.environment = target_environment


func _clear_camera_environment() -> void:
    if _environment == null:
        return
    for peer_id in controller.players.keys():
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player == null:
            continue
        var camera := player._camera
        if camera != null and (camera.environment == _environment or camera.environment == _hospital_environment or camera.environment == _energy_environment or camera.environment == _school_environment or camera.environment == _market_environment):
            camera.environment = null


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
    # 每个端都要跑：客户端也要把自己的镜头切到腐墟星的环境。
    _apply_camera_environment()
    if hud != null:
        hud.tick(delta)
    if not controller.is_host:
        return
    _tick_noise(delta)
    _tick_search(delta)
    _tick_force_jobs(delta)
    _refresh_zombie_registry()
    _tick_spawns(delta)
    _tick_zombies(delta)
    _sync_timer -= delta
    if _sync_timer <= 0.0:
        _sync_timer = ENEMY_SYNC_INTERVAL
        controller.broadcast_ruin_enemies(enemy_snapshot())


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
    if hospital_interior != null and is_inside_hospital(player.global_position):
        var exit_point := hospital_exit_position()
        var exit_distance := player.global_position.distance_to(exit_point)
        if exit_distance <= 3.0 and _in_view(player, exit_point):
            best_distance = exit_distance
            best = {"kind": "hospital_exit", "id": "hospital"}
        for point: Vector3 in hospital_interior.call("locked_door_positions"):
            var door_distance := player.global_position.distance_to(point)
            if door_distance <= 2.0 and door_distance < best_distance and _in_view(player, point):
                best_distance = door_distance
                best = {"kind": "hospital_locked_door", "id": "hospital"}
        if not bool(hospital_interior.call("is_ward_door_open")):
            var ward_point: Vector3 = hospital_interior.call("ward_door_position")
            var ward_distance := player.global_position.distance_to(ward_point)
            if ward_distance <= 2.0 and ward_distance < best_distance and _in_view(player, ward_point):
                best_distance = ward_distance
                best = {"kind": "hospital_ward_door", "id": "hospital"}
        var task_points: Dictionary = hospital_interior.call("task_item_positions")
        for item_id: String in task_points.keys():
            if quest_items.has(item_id):
                continue
            var item_point: Vector3 = task_points[item_id]
            var item_distance := player.global_position.distance_to(item_point)
            if item_distance <= 2.5 and item_distance < best_distance and _in_view(player, item_point):
                best_distance = item_distance
                best = {"kind": "hospital_quest_item", "id": item_id}
    if energy_station_interior != null and is_inside_energy_station(player.global_position):
        var energy_exit := energy_exit_position()
        var energy_distance := player.global_position.distance_to(energy_exit)
        if energy_distance <= 3.2 and energy_distance < best_distance and _in_view(player, energy_exit):
            best_distance = energy_distance
            best = {"kind": "energy_exit", "id": "energy_station"}
        if energy_station_interior.has_method("physics_door_position"):
            var door_point: Vector3 = energy_station_interior.call("physics_door_position")
            var door_distance := player.global_position.distance_to(door_point)
            if door_distance <= 2.4 and door_distance < best_distance and _in_view(player, door_point):
                best_distance = door_distance
                best = {"kind": "energy_physics_door", "id": "energy_station"}
    if school_interior != null and is_inside_school(player.global_position):
        var school_exit := school_exit_position()
        var school_exit_distance := player.global_position.distance_to(school_exit)
        if school_exit_distance <= 3.0 and school_exit_distance < best_distance and _in_view(player, school_exit):
            best_distance = school_exit_distance
            best = {"kind": "school_exit", "id": "school"}
        var school_tasks: Dictionary = school_interior.call("task_item_positions")
        for item_id: String in school_tasks.keys():
            if quest_items.has(item_id):
                continue
            var school_item_point: Vector3 = school_tasks[item_id]
            var school_item_distance := player.global_position.distance_to(school_item_point)
            if school_item_distance <= 2.5 and school_item_distance < best_distance and _in_view(player, school_item_point):
                best_distance = school_item_distance
                best = {"kind": "school_quest_item", "id": item_id}
    if market_interior != null and is_inside_market(player.global_position):
        var market_exit := market_exit_position()
        var market_exit_distance := player.global_position.distance_to(market_exit)
        if market_exit_distance <= 3.0 and market_exit_distance < best_distance and _in_view(player, market_exit):
            best_distance = market_exit_distance
            best = {"kind": "market_exit", "id": "market"}
        var market_tasks: Dictionary = market_interior.call("task_item_positions")
        for item_id: String in market_tasks.keys():
            if quest_items.has(item_id):
                continue
            var market_item_point: Vector3 = market_tasks[item_id]
            var market_item_distance := player.global_position.distance_to(market_item_point)
            if market_item_distance <= 2.5 and market_item_distance < best_distance and _in_view(player, market_item_point):
                best_distance = market_item_distance
                best = {"kind": "market_quest_item", "id": item_id}
    # 第一人称下只把"在视野前方"的目标算作可交互；目标在身后时提示会消失，
    # 但玩家一转身就回来，不会出现"隔着人捡东西"的怪异操作。
    var pad_point := pad_position()
    var pad_distance := player.global_position.distance_to(pad_point)
    if pad_distance <= PAD_PROMPT_RADIUS and _in_view(player, pad_point):
        best_distance = pad_distance
        best = {"kind": "pad", "id": "landing"}
    for id in buildings.keys():
        var entry: Vector3 = buildings[id].entry
        var distance := player.global_position.distance_to(entry)
        if distance <= BUILDING_ENTRY_RADIUS and distance < best_distance and _in_view(player, entry):
            best_distance = distance
            best = {"kind": "building", "id": id}
    for id in food_sites.keys():
        if taken_food.has(id):
            continue
        var site: Dictionary = food_sites[id]
        var distance := player.global_position.distance_to(site.root.position)
        if distance <= FOOD_SEARCH_RADIUS and distance < best_distance and _in_view(player, site.root.position):
            best_distance = distance
            best = {"kind": "food", "id": id}
    return best


## 目标是否在玩家正面约 180° 的视野半球内。
func _in_view(player: SpacePlayer3D, point: Vector3) -> bool:
    var offset := Vector3(point.x - player.global_position.x, 0.0, point.z - player.global_position.z)
    if offset.length() < 0.55:
        return true
    var forward := -player.global_transform.basis.z
    forward.y = 0.0
    if forward.length() < 0.01:
        return true
    return forward.normalized().dot(offset.normalized()) > 0.0


func prompt(player: SpacePlayer3D) -> String:
    if search_jobs.has(player.peer_id):
        var job: Dictionary = search_jobs[player.peer_id]
        return "翻找中 · %.1f / %.1f 秒 · 离开或按 E 中止" % [float(job.elapsed), FOOD_SEARCH_TIME]
    var target := nearest(player)
    if target.is_empty():
        return ""
    if String(target.kind) == "hospital_exit":
        return "[E] 离开医院 · 回到大门"
    if String(target.kind) == "hospital_locked_door":
        return "[E] 病房门 · 已上锁"
    if String(target.kind) == "hospital_ward_door":
        return "[E] 打开病房门"
    if String(target.kind) == "hospital_quest_item":
        return "[E] 取走%s" % quest_item_label(String(target.id))
    if String(target.kind) == "energy_exit":
        return "[E] 离开能源站 · 回到大门"
    if String(target.kind) == "energy_physics_door":
        return "[E] 推开重型维护门"
    if String(target.kind) == "school_exit":
        return "[E] 离开学校 · 回到大门"
    if String(target.kind) == "school_quest_item":
        return "[E] 取走%s" % quest_item_label(String(target.id))
    if String(target.kind) == "market_exit":
        return "[E] 离开超市 · 回到大门"
    if String(target.kind) == "market_quest_item":
        return "[E] 取走%s" % quest_item_label(String(target.id))
    if String(target.kind) == "pad":
        if extraction_ready():
            if controller.extraction_progress > 0.0:
                return "撤离中 · 保持 %.1f / %.1f 秒" % [controller.extraction_progress, EXTRACTION_HOLD]
            return "撤离开放 · 全员站上登陆艇保持 %.0f 秒" % EXTRACTION_HOLD
        return "[E] 紧急返航（%s）" % objective_text()
    if String(target.kind) == "building":
        var name := String(buildings[target.id].name)
        if String(target.id) == "library":
            return "[E] 检查封死的门 · %s" % name
        if is_building_locked(String(target.id)):
            var tool_hint := "撬锁" if has_lockpick(player.peer_id) else "撬锁（缺工具）"
            return "%s · [E] %s · [R] 暴力撬开" % [name, tool_hint]
        if String(target.id) in ["hospital", "energy_station", "school", "market"]:
            return "[E] 进入%s" % name
        return "[E] 查看%s（内部区域尚未开放）" % name
    var site: Dictionary = food_sites[target.id]
    return "[E] 翻找%s · 留在附近 %.1f 秒（会发出声响）" % [String(site.name), FOOD_SEARCH_TIME]


func interaction_progress(peer_id: int) -> float:
    if not search_jobs.has(peer_id):
        return 0.0
    var job: Dictionary = search_jobs[peer_id]
    return clampf(float(job.elapsed) / FOOD_SEARCH_TIME, 0.0, 1.0)


func handle_action(peer_id: int, action: String) -> bool:
    if action != "repair" and action != "ruin_force_door":
        return false
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return false
    if search_jobs.has(peer_id):
        search_jobs.erase(peer_id)
        return true
    var target := nearest(player)
    if target.is_empty():
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("附近没有可以暴力撬开的门。", Color("#ffbd75"), 1.8)
        return false
    if String(target.kind) == "hospital_exit":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("这是出口，不需要撬。", Color("#ffbd75"), 1.6)
        elif controller.is_host:
            controller.exit_hospital(peer_id)
        return true
    if String(target.kind) == "hospital_locked_door":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("门已锁，撬棍也撬不开。", Color("#ffbd75"), 2.0)
        else:
            controller.show_feedback_rpc.rpc("门已锁，打不开。", Color("#ffbd75"), 2.0)
        return true
    if String(target.kind) == "hospital_ward_door":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("这扇门没锁，直接按 E 推开。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            controller.open_hospital_ward_door(peer_id)
        return true
    if String(target.kind) == "hospital_quest_item":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("任务物不用撬，靠近按 E 拿取。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            _collect_hospital_quest_item(peer_id, String(target.id))
        return true
    if String(target.kind) == "energy_exit":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("这是出口，不需要撬。", Color("#ffbd75"), 1.6)
        elif controller.is_host:
            controller.exit_energy_station(peer_id)
        return true
    if String(target.kind) == "energy_physics_door":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("这扇门用身体或 E 推，不需要撬。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            controller.push_energy_door(peer_id)
        return true
    if String(target.kind) == "school_exit":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("这是出口，不需要撬。", Color("#ffbd75"), 1.6)
        elif controller.is_host:
            controller.exit_school(peer_id)
        return true
    if String(target.kind) == "school_quest_item":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("任务物不用撬，靠近按 E 拿取。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            _collect_navigation_quest_item(peer_id, String(target.id), school_interior, "school")
        return true
    if String(target.kind) == "market_exit":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("这是出口，不需要撬。", Color("#ffbd75"), 1.6)
        elif controller.is_host:
            controller.exit_market(peer_id)
        return true
    if String(target.kind) == "market_quest_item":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("任务物不用撬，靠近按 E 拿取。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            _collect_navigation_quest_item(peer_id, String(target.id), market_interior, "market")
        return true
    if String(target.kind) == "pad":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("登陆艇上没有需要撬开的门。", Color("#ffbd75"), 1.8)
            return true
        if extraction_ready():
            controller.show_feedback_rpc.rpc("撤离已开放：全员留在登陆艇上，保持 %.0f 秒。" % EXTRACTION_HOLD, Color("#9ff5c9"), 2.0)
        else:
            controller.return_to_ship.rpc("腐墟星提前返航：%s，回收价值 %d。" % [objective_text(), controller.salvage_value], controller._vitals_snapshot())
        return true
    if String(target.kind) == "building":
        var building_id := String(target.id)
        if building_id == "library":
            if action == "ruin_force_door":
                controller.show_feedback_rpc.rpc("图书馆大门从里面焊死了，撬棍也撬不开。", Color("#ffbd75"), 2.4)
            else:
                controller.show_feedback_rpc.rpc("门缝被焊死，里面还用书架顶住了。打不开。", Color("#ffbd75"), 2.4)
            return true
        if is_building_locked(building_id):
            if action == "ruin_force_door":
                _start_force_job(peer_id, building_id)
            elif has_lockpick(peer_id):
                controller.start_ruin_lockpick(peer_id, building_id)
            else:
                controller.show_feedback_rpc.rpc("门锁需要撬锁工具；没有工具时按 R 可以用撬棍暴力撬开。", Color("#ffbd75"), 2.2)
        else:
            enter_building(peer_id, building_id)
        return true
    if action == "ruin_force_door":
        controller.show_feedback_rpc.rpc("这里没有可以撬开的门。", Color("#ffbd75"), 1.8)
        return true
    search_jobs[peer_id] = {"site_id": String(target.id), "elapsed": 0.0}
    return true


func has_lockpick(peer_id: int) -> bool:
    return controller._items != null and controller._items.count_kind(peer_id, "lockpick") > 0


## 暴力撬门：主机计时，玩家必须留在门口；到时间后直接跳过锁芯。
func _start_force_job(peer_id: int, building_id: String) -> void:
    if force_jobs.has(peer_id):
        return
    force_jobs[peer_id] = {"building_id": building_id, "elapsed": 0.0, "next_sync": 0.0}
    controller.start_ruin_force(peer_id, building_id)


func _tick_force_jobs(delta: float) -> void:
    for peer_id in force_jobs.keys():
        var job: Dictionary = force_jobs[peer_id]
        var player := controller.players.get(int(peer_id)) as SpacePlayer3D
        var building_id := String(job.building_id)
        if player == null or player.downed or not buildings.has(building_id) \
                or player.global_position.distance_to(buildings[building_id].entry) > BUILDING_ENTRY_RADIUS + 1.2:
            force_jobs.erase(peer_id)
            controller.stop_ruin_force(int(peer_id), false)
            continue
        job.elapsed = float(job.elapsed) + delta
        if float(job.elapsed) >= FORCE_TIME:
            force_jobs.erase(peer_id)
            add_noise(int(peer_id), 0.85)
            controller.stop_ruin_force(int(peer_id), true)
            unlock_building(int(peer_id), building_id)
            controller.show_feedback_rpc.rpc("%s 的门被暴力撬开了。" % building_name(building_id), Color("#ffbd75"), 2.2)
            continue
        if float(job.elapsed) >= float(job.next_sync):
            job.next_sync = float(job.elapsed) + 0.1
            controller.sync_ruin_force_progress(int(peer_id), clampf(float(job.elapsed) / FORCE_TIME, 0.0, 1.0))
        force_jobs[peer_id] = job


func is_building_locked(building_id: String) -> bool:
    return buildings.has(building_id) and not unlocked_buildings.has(building_id)


func building_name(building_id: String) -> String:
    if not buildings.has(building_id):
        return ""
    return String(buildings[building_id].name)


func player_near_building(peer_id: int, building_id: String) -> bool:
    if not buildings.has(building_id):
        return false
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return false
    var entry: Vector3 = buildings[building_id].entry
    return player.global_position.distance_to(entry) <= BUILDING_ENTRY_RADIUS + 0.8


func _refresh_locks() -> void:
    for id in buildings.keys():
        var lock: Node3D = buildings[id].get("lock") as Node3D
        if is_instance_valid(lock):
            lock.visible = not unlocked_buildings.has(String(id))


## 主机在玩家完成撬锁后调用。门锁状态进快照，客户端晚加入也能看到门已开。
func unlock_building(peer_id: int, building_id: String) -> void:
    if building_id == "library":
        controller.show_feedback_rpc.rpc("图书馆大门被焊死，无法进入。", Color("#ffbd75"), 2.2)
        return
    if not is_building_locked(building_id):
        return
    unlocked_buildings.append(building_id)
    _refresh_locks()
    enter_building(peer_id, building_id)
    if controller.is_host:
        controller.sync_ruin_progress.rpc(snapshot())


func enter_building(peer_id: int, building_id: String) -> void:
    if not buildings.has(building_id):
        return
    if building_id == "library":
        controller.show_feedback_rpc.rpc("图书馆大门从里面焊死，里面还用书架顶住了。进不去。", Color("#ffbd75"), 2.4)
        return
    var name := String(buildings[building_id].name)
    var first_visit := not discovered_buildings.has(building_id)
    if first_visit:
        discovered_buildings.append(building_id)
        controller._record_journal("发现建筑 · %s" % name, "门是从里面被顶开的。这栋建筑还有可进入的内部结构。")
        controller.show_feedback_rpc.rpc("%s 已登记 · 建筑 %d/%d" % [name, discovered_buildings.size(), OBJECTIVE_BUILDINGS], Color("#9ff5c9"), 2.0)
        if controller.is_host:
            controller.sync_ruin_progress.rpc(snapshot())
    if building_id == "hospital":
        # 医院有独立的四层室内，开门后直接切进去。
        if controller.is_host:
            controller.enter_hospital(peer_id)
        return
    if building_id == "energy_station":
        # 能源站有独立四层工业室内：2F/1F/B1/B2。
        if controller.is_host:
            controller.enter_energy_station(peer_id)
        return
    if building_id == "school":
        if controller.is_host:
            controller.enter_school(peer_id)
        return
    if building_id == "market":
        if controller.is_host:
            controller.enter_market(peer_id)
        return
    if not first_visit:
        controller.show_feedback_rpc.rpc("%s 内部区域尚未开放，本轮只能在外面查看。" % name, Color("#ffbd75"), 2.4)


func hospital_spawn_position() -> Vector3:
    if hospital_interior == null:
        return Vector3.ZERO
    return hospital_interior.call("spawn_position")


func hospital_exit_position() -> Vector3:
    if hospital_interior == null:
        return Vector3.ZERO
    return hospital_interior.call("exit_position")


func is_inside_hospital(point: Vector3) -> bool:
    return hospital_interior != null and bool(hospital_interior.call("is_inside", point))


func energy_spawn_position() -> Vector3:
    if energy_station_interior == null:
        return Vector3.ZERO
    return energy_station_interior.call("spawn_position")


func energy_exit_position() -> Vector3:
    if energy_station_interior == null:
        return Vector3.ZERO
    return energy_station_interior.call("exit_position")


func is_inside_energy_station(point: Vector3) -> bool:
    return energy_station_interior != null and bool(energy_station_interior.call("is_inside", point))


func school_spawn_position() -> Vector3:
    if school_interior == null:
        return Vector3.ZERO
    return school_interior.call("spawn_position")


func school_exit_position() -> Vector3:
    if school_interior == null:
        return Vector3.ZERO
    return school_interior.call("exit_position")


func is_inside_school(point: Vector3) -> bool:
    return school_interior != null and bool(school_interior.call("is_inside", point))


func market_spawn_position() -> Vector3:
    if market_interior == null:
        return Vector3.ZERO
    return market_interior.call("spawn_position")


func market_exit_position() -> Vector3:
    if market_interior == null:
        return Vector3.ZERO
    return market_interior.call("exit_position")


func is_inside_market(point: Vector3) -> bool:
    return market_interior != null and bool(market_interior.call("is_inside", point))


func quest_item_label(item_id: String) -> String:
    return String(ALL_QUEST_ITEMS.get(item_id, item_id))


func quest_item_count() -> int:
    return quest_items.size()


func quest_item_total() -> int:
    return ALL_QUEST_ITEMS.size()


func hospital_quest_hud_text() -> String:
    var records := "✓" if has_quest_item("patient_records") else "○"
    var stabilizer := "✓" if has_quest_item("coolant_stabilizer") else "○"
    var card := "✓" if has_quest_item("energy_access_card") else "○"
    var hospital_count := 0
    for item_id: String in HOSPITAL_QUEST_ITEMS.keys():
        if has_quest_item(item_id):
            hospital_count += 1
    return "任务物 %d/3 · 病历%s 稳定剂%s 门禁卡%s" % [hospital_count, records, stabilizer, card]


func school_quest_hud_text() -> String:
    var observation := "✓" if has_quest_item("school_observation_data") else "○"
    var navigation := "✓" if has_quest_item("market_navigation_module") else "○"
    return "导航线索 · 观测数据%s 民用导航模块%s" % [observation, navigation]


func market_quest_hud_text() -> String:
    return school_quest_hud_text()


func has_quest_item(item_id: String) -> bool:
    return quest_items.has(item_id)


func _collect_hospital_quest_item(peer_id: int, item_id: String) -> void:
    if not controller.is_host or hospital_interior == null or quest_items.has(item_id):
        return
    if not HOSPITAL_QUEST_ITEMS.has(item_id):
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or not is_inside_hospital(player.global_position):
        return
    var points: Dictionary = hospital_interior.call("task_item_positions")
    if not points.has(item_id):
        return
    if player.global_position.distance_to(points[item_id]) > 2.8:
        return
    quest_items[item_id] = true
    hospital_interior.call("collect_task_item", item_id)
    var label := quest_item_label(item_id)
    var hospital_count := 0
    for id: String in HOSPITAL_QUEST_ITEMS.keys():
        if has_quest_item(id):
            hospital_count += 1
    if hospital_count >= HOSPITAL_QUEST_ITEMS.size():
        controller.show_feedback_rpc.rpc("医院支线完成 · 病历 / 稳定剂 / 门禁卡已集齐", Color("#9ff5c9"), 3.0)
        controller._record_journal("医院支线完成", "三件医院线索已集齐：镇静实验病历、低温稳定剂、能源站门禁卡。可以回庇护所向工程师/医生对质，或前往能源站深层。")
    else:
        controller.show_feedback_rpc.rpc("取得任务物 · %s" % label, Color("#9ff5c9"), 2.4)
    match item_id:
        "patient_records":
            controller._record_journal("任务物 · 镇静实验病历", "镇静剂只能压住运动，压不住菌群。医院在爆发初期把感染者固定在病床上反复注射，后来护士也开始重复同样的动作。")
        "coolant_stabilizer":
            controller._record_journal("任务物 · 低温稳定剂", "矿工低温手术用的稳定剂。能让反应堆重启时不过热，但只够撑一次重启。")
        "energy_access_card":
            controller._record_journal("任务物 · 能源站门禁卡", "编号 E-07 的门禁卡。能打开能源站深层泵房和地下二层应急舱。")
    controller.sync_ruin_progress.rpc(snapshot())


func _collect_navigation_quest_item(peer_id: int, item_id: String, interior: Node3D, inside_kind: String) -> void:
    if not controller.is_host or interior == null or quest_items.has(item_id):
        return
    if not NAVIGATION_QUEST_ITEMS.has(item_id):
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return
    var inside := false
    if inside_kind == "school":
        inside = is_inside_school(player.global_position)
    elif inside_kind == "market":
        inside = is_inside_market(player.global_position)
    if not inside:
        return
    var points: Dictionary = interior.call("task_item_positions")
    if not points.has(item_id):
        return
    if player.global_position.distance_to(points[item_id]) > 2.8:
        return
    quest_items[item_id] = true
    interior.call("collect_task_item", item_id)
    var label := quest_item_label(item_id)
    var nav_count := 0
    for id: String in NAVIGATION_QUEST_ITEMS.keys():
        if has_quest_item(id):
            nav_count += 1
    if nav_count >= NAVIGATION_QUEST_ITEMS.size():
        controller.show_feedback_rpc.rpc("导航密钥拼合完成 · 观测数据 + 民用导航模块", Color("#9ff5c9"), 3.2)
        controller._record_journal("导航密钥拼合完成", "学校的菌群扩散观测数据与超市运输无人机导航模块拼合，得到进入能源站循环管网的路线。")
    else:
        controller.show_feedback_rpc.rpc("取得任务物 · %s" % label, Color("#9ff5c9"), 2.4)
    match item_id:
        "school_observation_data":
            controller._record_journal("任务物 · 天文观测数据", "天文台记录到菌群沿能源站循环管网扩散的路线。学生的最后一条广播说：不要往地下走。")
        "market_navigation_module":
            controller._record_journal("任务物 · 民用导航模块", "超市仓库里的旧运输无人机导航模块。保存着殖民城地下管线和能源站应急入口的坐标。")
    controller.sync_ruin_progress.rpc(snapshot())


func _finish_search(peer_id: int, site_id: String) -> void:
    if not food_sites.has(site_id) or taken_food.has(site_id):
        return
    var site: Dictionary = food_sites[site_id]
    var kind := String(site.kind)
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return
    # 医疗包要真正装进物品栏；栏满时不消耗这个物资点，玩家可以先放下东西。
    if kind == "medical":
        if controller._items == null or controller._items.occupied(peer_id) >= CrewItems3D.CAPACITY:
            controller.show_feedback_rpc.rpc("物品栏已满 · 空出一格后再拿医疗包", Color("#ffbd75"), 2.0)
            return
        controller._items.add_item(peer_id, "medical", -1, {}, true)
        controller._items.publish()
    taken_food.append(site_id)
    # 翻找会产生声音——这是这一关最重要的取舍。
    add_noise(peer_id, NOISE_SEARCH)
    if is_instance_valid(site.ring):
        site.ring.visible = false
    # 搜刮价值进入返航结算，让"多翻一处"有可见收益。
    controller.salvage_value += 10
    var text := "罐头"
    var effect := ""
    if kind == "water":
        text = "净水"
        var before := player.oxygen
        player.oxygen = minf(player.oxygen + 25.0, 100.0)
        effect = " · 氧气 +%d" % int(player.oxygen - before)
    elif kind == "medical":
        text = "医疗包"
        effect = " · 已放入物品栏"
    else:
        var before_health := player.health
        player.health = mini(player.health + 1, SpacePlayer3D.MAX_HEALTH)
        effect = " · 生命 +%d" % (player.health - before_health)
    controller.show_feedback_rpc.rpc("翻找%s：获得%s%s（发出声响）" % [String(site.name), text, effect], Color("#d8b98a"), 2.2)
    controller._spawn_particle_burst(site.root.position + Vector3(0.0, 1.0, 0.0), Color("#ffd08a"), 6)
    if controller.is_host:
        controller.sync_ruin_progress.rpc(snapshot())


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


func nearest_zombie_in_aim(player: SpacePlayer3D, limit: float, min_dot: float) -> SpaceEnemy3D:
    # 第一人称近战：从眼睛沿准星方向找一个夹角内、且中间没有墙的目标。
    # 使用玩家的 aim_direction()，服务端能拿到同步过来的朝向与俯仰。
    if player == null:
        return null
    var origin: Vector3 = player.global_position + Vector3.UP * PLAYER_EYE_HEIGHT
    var aim: Vector3 = player.aim_direction()
    var best: SpaceEnemy3D
    var best_distance := limit
    for zombie in zombies.values():
        var candidate := zombie as SpaceEnemy3D
        if candidate == null or not is_instance_valid(candidate) or candidate.health <= 0:
            continue
        var center: Vector3 = candidate.global_position + Vector3.UP * 1.05
        var offset: Vector3 = center - origin
        var distance := offset.length()
        if distance > limit or distance < 0.05:
            continue
        if aim.dot(offset / distance) < min_dot:
            continue
        if not _line_clear(player, origin, center):
            continue
        if distance < best_distance:
            best_distance = distance
            best = candidate
    return best


func _line_clear(player: SpacePlayer3D, from_point: Vector3, to_point: Vector3) -> bool:
    var world := controller.get_world_3d()
    if world == null:
        return true
    var query := PhysicsRayQueryParameters3D.create(from_point, to_point)
    # 只挡墙体和建筑；感染体自己在 layer 1，不参与遮挡判定。
    query.collision_mask = 2
    query.exclude = [player.get_rid()]
    return world.direct_space_state.intersect_ray(query).is_empty()


func map_size() -> Vector2:
    # 与可见地面留 5 米安全边，避免第一人称走到地面外看见虚空。
    return Vector2(GROUND_EXTENT.x * 2.0 - 10.0, GROUND_EXTENT.y * 2.0 - 10.0)


## 一局目标是否完成：翻找 3 处物资并查看 3 栋建筑。
func extraction_ready() -> bool:
    return taken_food.size() >= OBJECTIVE_FOOD and discovered_buildings.size() >= OBJECTIVE_BUILDINGS


func objective_text() -> String:
    return "翻找 %d/%d · 查看建筑 %d/%d" % [taken_food.size(), OBJECTIVE_FOOD, discovered_buildings.size(), OBJECTIVE_BUILDINGS]


## 登陆艇状态：未开放时橙色，开放后青绿灯带 + 灯光转青绿。
func set_extraction_active(active: bool) -> void:
    if is_instance_valid(_pad_active_ring):
        _pad_active_ring.visible = active
    var color: Color = ART.TEAL_LIGHT if active else ART.ORANGE
    var energy: float = 1.1 if active else 0.9
    for light in _pad_lights:
        if is_instance_valid(light):
            light.material_override = ART.material(color, true, energy)


func pad_position() -> Vector3:
    return Vector3(SPAWN_POSITION.x, 0.13, SPAWN_POSITION.y)


func spawn_position(peer_id: int) -> Vector3:
    # 4 个出生点槽位围绕登陆场排开，与霜烬星同样的做法。
    var angle := TAU * float(maxi(peer_id - 1, 0)) / 4.0
    var offset := Vector2(cos(angle), sin(angle)) * 3.5
    return Vector3(SPAWN_POSITION.x + offset.x, 0.13, SPAWN_POSITION.y + offset.y)


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
    if is_instance_valid(hud):
        hud.visible = value and controller.game_started and controller.current_planet_id == "ruin"
    if value:
        # 霜烬星的暴风雪视野遮罩属于霜烬星自己。登陆腐墟星时必须显式关掉：
        # 它是 CanvasLayer 上的 ColorRect，不会因为霜烬星的世界根隐藏而消失，
        # 留着会把整张地图压成只有脚下一圈亮，和本星"地图保持全亮"的设计冲突。
        var overlay = controller._vision_overlay
        if overlay is CanvasItem:
            (overlay as CanvasItem).visible = false
        _apply_camera_environment()
    else:
        _clear_camera_environment()


func snapshot() -> Dictionary:
    return {"taken_food": taken_food, "buildings": discovered_buildings, "unlocked": unlocked_buildings, "noise": noise, "quest_items": quest_items.keys()}


func apply_snapshot(data: Dictionary) -> void:
    taken_food.assign(data.get("taken_food", []))
    discovered_buildings.assign(data.get("buildings", []))
    unlocked_buildings.assign(data.get("unlocked", []))
    unlocked_buildings.erase("library")
    noise = data.get("noise", {})
    quest_items.clear()
    for id in data.get("quest_items", []):
        quest_items[String(id)] = true
        if hospital_interior != null:
            hospital_interior.call("collect_task_item", String(id))
        if school_interior != null:
            school_interior.call("collect_task_item", String(id))
        if market_interior != null:
            market_interior.call("collect_task_item", String(id))
    _refresh_locks()
    for id in taken_food:
        if food_sites.has(id):
            var site: Dictionary = food_sites[id]
            if is_instance_valid(site.ring):
                site.ring.visible = false


func map_sites() -> Array:
    var result: Array = []
    for id in buildings.keys():
        var point: Vector3 = buildings[id].root.position
        result.append({"id": id, "name": String(buildings[id].name), "label": String(buildings[id].name), "position": Vector2(point.x, point.z), "kind": "building", "used": false})
    for id in food_sites.keys():
        if taken_food.has(id):
            continue
        var site_point: Vector3 = food_sites[id].root.position
        result.append({"id": id, "name": String(food_sites[id].name), "label": String(food_sites[id].name), "position": Vector2(site_point.x, site_point.z), "kind": "food", "used": false})
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
