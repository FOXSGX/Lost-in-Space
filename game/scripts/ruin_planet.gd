extends RefCounted
class_name RuinPlanet

# 腐墟星（planet-02）第一人称卡通模块。
#
# 沿用霜烬星的范式：所有几何由代码生成，不引用外部美术资源；
# 沿用 frost_field_interactions.gd 的模块化接口，由 Main3D 持有并驱动。
#
# 视角与归航号主舱一致：眼睛高度、鼠标环视、探索交互。
# 美术使用 ruin_cartoon_art.gd 的奶油白/青蓝/暖橙调色板与倒角网格。
#
# 本模块只负责「星球内容」：建筑外壳、食物点与探索规则。
# 建筑内部子地图不在本轮范围内，只保留 enter_building() 入口。
#



# 废弃超市的外形单独成一个模块；医院和学校仍走下面的通用方盒流程。
const RUIN_MARKET := preload("res://scripts/ruin_market_building.gd")
# 医院也有自己的外形模块：四层病房楼 + 两层门诊翼 + 急救车雨棚。
const RUIN_HOSPITAL := preload("res://scripts/ruin_hospital_building.gd")
const RUIN_HOSPITAL_INTERIOR := preload("res://scripts/ruin_hospital_interior.gd")
const RUIN_ENERGY_STATION_INTERIOR := preload("res://scripts/ruin_energy_station_interior.gd")
const RUIN_SCHOOL_INTERIOR := preload("res://scripts/ruin_school_interior.gd")
const RUIN_MARKET_INTERIOR := preload("res://scripts/ruin_market_interior.gd")
const RUIN_SHELTER_INTERIOR := preload("res://scripts/ruin_shelter_interior.gd")
# 与归航号主舱一致的精致卡通语言：奶油白、青蓝、暖橙、鼠尾草绿。
const ART := preload("res://scripts/ruin_cartoon_art.gd")
const SURFACE := preload("res://scripts/ruin_surface_lib.gd")
const ATMOSPHERE := preload("res://scripts/core/art_atmosphere_kit.gd")
const PHYSICAL := preload("res://scripts/core/physical_link_kit.gd")
const RUIN_HUD := preload("res://scripts/ruin_hud_3d.gd")


const PLAYER_EYE_HEIGHT := 1.62
# 返航登陆艇的范围与交互半径。
const PAD_RADIUS := 4.2
const PAD_PROMPT_RADIUS := 5.2
# 一局目标：翻找 3 处物资 + 查看 3 栋建筑，完成后登陆艇开放撤离。
const OBJECTIVE_FOOD := 3
const OBJECTIVE_BUILDINGS := 3
const EXTRACTION_HOLD := 3.0
const ENERGY_WHEEL_STEP := 0.25

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
    "market_navigation_module": "民用导航模块",
}
const ALL_QUEST_ITEMS := {
    "patient_records": "镇静实验病历",
    "coolant_stabilizer": "低温稳定剂",
    "energy_access_card": "能源站门禁卡",
    "market_navigation_module": "民用导航模块",
    "reactor_core": "星髓点火芯",
}
const QUEST_ITEM_LOCATIONS := {
    "patient_records": "医院 2F 观察室",
    "coolant_stabilizer": "医院 B1 药库",
    "energy_access_card": "医院 1F 保安室",
    "market_navigation_module": "超市 2F 办公室",
    "reactor_core": "能源站 B2 应急舱",
}

# ── 食物与物资 ──
# 设计意图：物资分散在废墟建筑里，翻找后回登陆艇撤离。
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
# 指南的五层布光：主光（唯一阴影）→ 补光 → 轮廓光 → 掠射光 → 可见灯具的实用光。
# 补光只负责把背光面从死黑里托起来，不承担造型。
const FILL_LIGHTS := [
    {"position": Vector3(0.0, 5.0, 8.0), "energy": 0.70, "range": 26.0, "color": Color("#e2c99f")},
    {"position": Vector3(-40.0, 4.0, -14.0), "energy": 0.50, "range": 20.0, "color": Color("#e2c99f")},
    {"position": Vector3(40.0, 4.0, -18.0), "energy": 0.50, "range": 20.0, "color": Color("#e2c99f")},
    {"position": Vector3(-62.0, 3.5, 8.0), "energy": 0.40, "range": 16.0, "color": Color("#e2c99f")},
    {"position": Vector3(64.0, 3.5, 16.0), "energy": 0.40, "range": 16.0, "color": Color("#e2c99f")},
    {"position": Vector3(2.0, 3.5, -36.0), "energy": 0.50, "range": 18.0, "color": Color("#e2c99f")},
    {"position": Vector3(46.0, 3.5, 30.0), "energy": 0.60, "range": 18.0, "color": Color("#e2c99f")},
]

# 掠射光：窄角、贴墙 10–20° 擦面，在 GL 没有 SSAO 的情况下把墙板缝、肋柱与岩石层理打出立体。
const GRAZE_LIGHTS := [
    {"position": Vector3(-38.0, 3.2, -9.0), "target": Vector3(-40.0, 2.2, -16.5), "energy": 2.0, "range": 18.0, "angle": 34.0, "color": Color("#b9c6bf")},
    {"position": Vector3(38.0, 3.4, -12.0), "target": Vector3(40.0, 2.4, -20.5), "energy": 2.0, "range": 18.0, "angle": 34.0, "color": Color("#b9c6bf")},
    {"position": Vector3(-62.0, 3.0, 26.0), "target": Vector3(-62.0, 2.0, 9.0), "energy": 1.8, "range": 16.0, "angle": 34.0, "color": Color("#b9c6bf")},
    {"position": Vector3(2.0, 3.6, -30.0), "target": Vector3(2.0, 1.6, -42.0), "energy": 2.2, "range": 18.0, "angle": 32.0, "color": Color("#d8c3a0")},
]

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
var shelter_interior: Node3D
var food_sites: Dictionary = {}
var taken_food: Array[String] = []
var discovered_buildings: Array[String] = []
var unlocked_buildings: Array[String] = []
var quest_items: Dictionary = {}
var story_flags: Dictionary = {}
var story_plan := ""
var story_stage := "start"
var story_timer := 0.0
var story_ending := ""
var _story_return_timer := -1.0
# 每名玩家最近进入的室内入口/最低层；主机用来兜底“掉出地板”。
var _interior_anchors: Dictionary = {}
var search_jobs: Dictionary = {}
var force_jobs: Dictionary = {}
var pending_message := ""
var _environment: Environment
var _hospital_environment: Environment
var _energy_environment: Environment
var _school_environment: Environment
var _market_environment: Environment
var _shelter_environment: Environment
var _pad_active_ring: MeshInstance3D
var _pad_lights: Array[MeshInstance3D] = []
var _link_flow: ShaderMaterial
var _link_lamps: Array[StandardMaterial3D] = []
var _link_state := ""
var _pad_dial: Node3D
var _pad_dial_value := -1.0
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
    _build_shelter_interior()
    _build_food_sites()
    _build_landing_pad()
    _build_street_dressing()
    _build_ground_scatter()
    _build_street_details()
    _build_atmosphere()
    _build_physical_links()
    _build_horizon()
    _cull_thin_shadow_casters()
    _build_hud()


func reset() -> void:
    # 建筑、物资和世界物件全部挂在 world_root 下，释放根节点即可清空。
    if is_instance_valid(world_root):
        world_root.queue_free()
    world_root = null
    if is_instance_valid(hud):
        hud.queue_free()
    hud = null
    buildings.clear()
    hospital_interior = null
    energy_station_interior = null
    school_interior = null
    market_interior = null
    shelter_interior = null
    story_flags.clear()
    story_plan = ""
    story_stage = "start"
    story_timer = 0.0
    story_ending = ""
    _story_return_timer = -1.0
    food_sites.clear()
    taken_food.clear()
    discovered_buildings.clear()
    unlocked_buildings.clear()
    quest_items.clear()
    search_jobs.clear()
    force_jobs.clear()
    _interior_anchors.clear()
    _pad_active_ring = null
    _pad_lights.clear()
    _link_flow = null
    _link_lamps.clear()
    _link_state = ""
    _pad_dial = null
    _pad_dial_value = -1.0
    _environment = null
    _time = 0.0


func clear_run() -> void:
    # 返航时清掉本局临时状态，保留建筑/物资的发现状态。
    search_jobs.clear()
    force_jobs.clear()
    _interior_anchors.clear()


## 再次登陆时重置一局目标，但保留已经建好的世界几何。
func reset_run() -> void:
    search_jobs.clear()
    taken_food.clear()
    discovered_buildings.clear()
    unlocked_buildings.clear()
    force_jobs.clear()
    _interior_anchors.clear()
    _refresh_locks()
    for site in food_sites.values():
        if is_instance_valid(site.get("ring")):
            (site.ring as MeshInstance3D).visible = true


# ── 构建 ──

func _build_scaffold() -> void:
    # 腐墟星用自己的光照和地面：登陆时霜烬星的世界根会被整体隐藏，
    # 那边的 Environment 和地面一并不可见，所以这里必须自带一套。
    world_root = Node3D.new()
    world_root.name = "RuinWorld3D"
    controller.add_child(world_root)

    # 傍晚阴天：天空、雾和主光保持低天光，但环境光按指南 GL 基线托到能读出结构。
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#2f3f45")
    sky_material.sky_horizon_color = Color("#7d7f74")
    sky_material.sky_curve = 0.50
    sky_material.ground_bottom_color = Color("#2a2b26")
    sky_material.ground_horizon_color = Color("#56574b")
    sky_material.sun_angle_max = 10.0
    sky_material.sun_curve = 0.08
    var sky := Sky.new()
    sky.sky_material = sky_material

    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#7d8a82")
    env.ambient_light_energy = 1.55
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.fog_enabled = true
    env.fog_light_color = Color("#707a72")
    env.fog_light_energy = 0.45
    env.fog_density = 0.0055
    env.fog_sky_affect = 0.22
    env.glow_enabled = true
    env.glow_intensity = 0.06
    env.glow_hdr_threshold = 1.3
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = 0.92
    env.tonemap_white = 1.0
    env.adjustment_enabled = true
    env.adjustment_brightness = 0.98
    env.adjustment_saturation = 0.86
    env.adjustment_contrast = 1.12
    # gl_compatibility 基线：显式关闭 GL 下不存在的屏幕空间效果，避免换渲染器后跑偏。
    env.ssr_enabled = false
    env.ssil_enabled = false
    env.volumetric_fog_enabled = false
    env.sdfgi_enabled = false
    env.ssao_enabled = false
    _environment = env
    # 室内单独一层相机环境：天光仍很暗，但补一点灰绿色环境光，
    # 避免医院病房在没有吊灯的角落彻底死黑。
    var hospital_env := env.duplicate(true) as Environment
    hospital_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    hospital_env.ambient_light_color = Color("#8a8f84")
    hospital_env.ambient_light_energy = 0.45
    hospital_env.tonemap_exposure = 0.88
    hospital_env.adjustment_saturation = 0.82
    hospital_env.fog_density = 0.0045
    _hospital_environment = hospital_env
    # 能源站更工业：青绿环境光、略高的对比，保留橙色应急灯。
    var energy_env := env.duplicate(true) as Environment
    energy_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    energy_env.ambient_light_color = Color("#7f938c")
    energy_env.ambient_light_energy = 0.55
    energy_env.tonemap_exposure = 0.90
    energy_env.adjustment_saturation = 0.80
    energy_env.adjustment_contrast = 1.16
    energy_env.fog_density = 0.0040
    _energy_environment = energy_env
    # 学校：旧荧光灯、灰尘和奶油色墙面，比医院略暖。
    var school_env := env.duplicate(true) as Environment
    school_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    school_env.ambient_light_color = Color("#948f7c")
    school_env.ambient_light_energy = 0.55
    school_env.tonemap_exposure = 0.92
    school_env.adjustment_saturation = 0.88
    school_env.fog_density = 0.0030
    _school_environment = school_env
    # 超市：冷白荧光灯、低饱和货架和一点暖橙入口灯。
    var market_env := env.duplicate(true) as Environment
    market_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    market_env.ambient_light_color = Color("#8a9488")
    market_env.ambient_light_energy = 0.55
    market_env.tonemap_exposure = 0.92
    market_env.adjustment_saturation = 0.86
    market_env.fog_density = 0.0028
    _market_environment = market_env
    # 地下庇护所：暖灯 + 青绿维生灯，比地表更安全、更封闭。
    var shelter_env := env.duplicate(true) as Environment
    shelter_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    shelter_env.ambient_light_color = Color("#96886e")
    shelter_env.ambient_light_energy = 0.55
    shelter_env.tonemap_exposure = 0.90
    shelter_env.adjustment_saturation = 0.88
    shelter_env.fog_density = 0.0035
    _shelter_environment = shelter_env
    var environment := WorldEnvironment.new()
    environment.name = "RuinEnvironment"
    environment.environment = env
    world_root.add_child(environment)

    var light := DirectionalLight3D.new()
    light.name = "RuinKeySun"
    light.rotation_degrees = Vector3(-34.0, -28.0, 0.0)
    light.light_energy = 1.80
    light.light_color = Color("#d6dacb")
    # 唯一开阴影的主光：建立明暗交界与地面投影。
    light.shadow_enabled = true
    light.directional_shadow_max_distance = 110.0
    light.shadow_bias = 0.05
    light.shadow_normal_bias = 1.0
    light.shadow_opacity = 0.62
    light.light_angular_distance = 1.4
    world_root.add_child(light)

    # 轮廓光：从主体斜后上方照边缘，把建筑从灰青天空里剥离；关阴影。
    var rim := DirectionalLight3D.new()
    rim.name = "RuinRimLight"
    rim.rotation_degrees = Vector3(-18.0, 152.0, 0.0)
    rim.light_energy = 0.65
    rim.light_color = Color("#8fb6c2")
    rim.shadow_enabled = false
    world_root.add_child(rim)

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
    var ground := ART.plane(world_root, "RuinGroundMesh", Vector2(GROUND_EXTENT.x * 2.0 + 60.0, GROUND_EXTENT.y * 2.0 + 60.0), Vector3(0.0, 0.0, 0.0), ART.BASE_DIRT, false, 0.0, SURFACE.Family.CONC, 4.0)
    ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var fill_index := 0
    for raw in FILL_LIGHTS:
        var fill := OmniLight3D.new()
        fill.name = "RuinFill%d" % fill_index
        fill_index += 1
        fill.position = Vector3(raw.position)
        fill.light_color = raw.color
        fill.light_energy = float(raw.energy)
        fill.omni_range = float(raw.range)
        fill.shadow_enabled = false
        world_root.add_child(fill)

    var graze_index := 0
    for raw in GRAZE_LIGHTS:
        var graze := SpotLight3D.new()
        graze.name = "RuinGraze%d" % graze_index
        graze_index += 1
        graze.light_color = raw.color
        graze.light_energy = float(raw.energy)
        graze.spot_range = float(raw.range)
        graze.spot_angle = float(raw.angle)
        graze.spot_angle_attenuation = 1.15
        graze.shadow_enabled = false
        graze.position = Vector3(raw.position)
        world_root.add_child(graze)
        graze.look_at(Vector3(raw.target), Vector3.UP)


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
    st.generate_tangents()
    var detail := MeshInstance3D.new()
    detail.name = "RuinGroundDetail"
    detail.mesh = st.commit()
    # 抬 1 厘米压住底下的单色盒子，避免同面深度打架
    detail.position = Vector3(0.0, 0.01, 0.0)
    # 顶点色给宏观色斑；2K 混凝土法线/粗糙度给 1–2 m 的微表面。
    # 大地面走轻量 PBR，避免整屏三平面 4 层 shader 拖慢 GL。
    detail.material_override = SURFACE.pavement(Color.WHITE, Vector3.ONE, "conc", 0.95, true)
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
        st.set_uv(Vector2(point.x, point.y) * 0.42)
        # 顶点色同样按 sRGB 书写；转成线性后再交给 albedo，否则会比地面亮一截。
        var tint := _ground_tint(patch, grain, point)
        st.set_color(tint.srgb_to_linear())
        st.add_vertex(Vector3(point.x, 0.0, point.y))


func _ground_tint(patch: FastNoiseLite, grain: FastNoiseLite, point: Vector2) -> Color:
    # 暗泥炭褐铺地 + 氧化铅灰水渍 + 鼠尾草绿苔痕，和指南 65–75% 低饱和基底一致。
    var color := Color("#665a49")
    var low := (patch.get_noise_2d(point.x, point.y) + 1.0) * 0.5
    color = color.lerp(Color("#554c40"), low * 0.55)
    color = color.lerp(Color("#7a6e5a"), maxf(1.0 - low * 1.6, 0.0) * 0.45)
    var g := grain.get_noise_2d(point.x, point.y)
    if g > 0.0:
        color = color.lerp(color.lightened(0.04), g * 0.55)
    else:
        color = color.lerp(color.darkened(0.04), -g * 0.55)
    # 低洼积水：浅青灰，读到"潮"而不是"脏"。
    if g > 0.46:
        color = color.lerp(Color("#5f7a78"), clampf((g - 0.46) * 1.4, 0.0, 0.55))
    # 建筑周边的接地阴影：只做很轻的一圈暖灰，避免变成一大块棕色地皮。
    for raw in BUILDINGS:
        var center := Vector2(raw.position)
        var size := Vector3(raw.size)
        var reach := maxf(size.x, size.z) * 0.55 + 4.0
        var distance := point.distance_to(center)
        if distance < reach:
            var weight := (1.0 - distance / reach) * 0.14
            color = color.lerp(Color("#554c40"), weight)
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


func _build_shelter_interior() -> void:
    var interior := RUIN_SHELTER_INTERIOR.new() as Node3D
    interior.build(controller, _world())
    shelter_interior = interior


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
    var forecourt := ART.block(root, "Forecourt", Vector3(minf(size.x * 0.55, 12.0), 0.035, 4.6), Vector3(0.0, 0.0175, size.z * 0.5 + 2.2), ART.CONCRETE, 0.03, false, 0.0, SURFACE.Family.CONC)
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
    var plate := ART.block(lock, "LockPlate", Vector3(0.26, 0.36, 0.05), Vector3.ZERO, Color("#c9a15b"), 0.015, false, 0.0, SURFACE.Family.MACH)
    plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    ART.block(lock, "LockCylinder", Vector3(0.15, 0.15, 0.05), Vector3(0.0, -0.02, 0.045), Color("#7a5a32"), 0.02, false, 0.0, SURFACE.Family.MACH)
    ART.block(lock, "LockKeyhole", Vector3(0.045, 0.10, 0.02), Vector3(0.0, -0.02, 0.075), ART.INK, 0.005, false, 0.0, SURFACE.Family.CAST)
    # 锁灯带遮光罩：灯只从罩口露出，避免小圆点直接糊在锁板上。
    ART.block(lock, "LockHood", Vector3(0.09, 0.05, 0.06), Vector3(0.0, 0.135, 0.045), ART.TEAL_DEEP, 0.008, false, 0.0, SURFACE.Family.CAST)
    ART.sphere(lock, "LockLED", Vector3(0.03, 0.03, 0.022), Vector3(0.0, 0.11, 0.075), ART.ORANGE, true, 0.35)
    # 只放两颗真实装配螺栓；指南红线：不无意义地撒螺母。
    for sx: float in [-1.0, 1.0]:
        ART.bolt(lock, "LockBolt", Vector3(sx * 0.095, 0.135, 0.045), 0.016, ART.CREAM_DEEP)
    ART.block(lock, "LockTag", Vector3(0.16, 0.06, 0.015), Vector3(0.0, -0.145, 0.04), ART.ORANGE, 0.004, true, 0.15)
    return lock


func _build_cartoon_building(root: Node3D, id: String, size: Vector3, accent: Color) -> MeshInstance3D:
    # 外壳退成深色内墙，外层另铺带真实凹槽的分板；这样近看不是一整块数学平面。
    var body := ART.block(root, "Shell", size, Vector3(0.0, size.y * 0.5, 0.0), ART.CREAM_DEEP, 0.34, false, 0.0, SURFACE.Family.PAINT_CLEAN)
    body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    ART.block(root, "Plinth", Vector3(size.x + 0.5, 0.55, size.z + 0.5), Vector3(0.0, 0.275, 0.0), ART.SAND_DEEP, 0.12)
    ART.block(root, "BaseShadow", Vector3(size.x + 0.24, 0.24, size.z + 0.24), Vector3(0.0, 0.12, 0.0), Color("#7d674a"), 0.04)
    # 深色勒脚 + 顶部檐口：近看时墙脚和屋顶各有一条明确收边。
    ART.block(root, "BaseBand", Vector3(size.x + 0.2, 0.8, size.z + 0.2), Vector3(0.0, 0.4, 0.0), ART.TEAL_DEEP, 0.05, false, 0.0, SURFACE.Family.PAINT_CLEAN)
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
    var window_centers: Array[float] = []
    for index: int in window_count:
        var x: float = -size.x * 0.5 + (float(index) + 0.5) * (size.x / float(window_count))
        if absf(x) < 2.2:
            continue
        window_centers.append(x)

    # 立面分板：2.4 cm 真实凹槽 + 竖向肋柱，把长墙拆成有节奏的工业立面。
    var sign_width: float = minf(size.x * 0.55, 7.0)
    var front_skip: Array = [
        Rect2(-1.7, 0.0, 3.4, 3.3),
        Rect2(-sign_width * 0.5 - 0.15, size.y * 0.78 - 0.62, sign_width + 0.3, 1.24),
        Rect2(-2.15, 3.02, 4.3, 0.62),
    ]
    for x in window_centers:
        front_skip.append(Rect2(x - window_width * 0.5 - 0.3, size.y * 0.58 - 1.08, window_width + 0.6, 2.16))
    ART.panel_facade(root, "FrontPanels", Vector3(0.0, 0.0, size.z * 0.5 + 0.02), Vector3.RIGHT, Vector3.UP, size.x, size.y, 3.1, 2.45, 0.032, [ART.CREAM_DEEP, ART.SAND_DEEP, ART.CREAM_DEEP, ART.CREAM], 11 + id.length(), front_skip)
    var back_skip: Array = []
    for x in window_centers:
        back_skip.append(Rect2(x - window_width * 0.5 - 0.3, size.y * 0.58 - 1.08, window_width + 0.6, 2.16))
    ART.panel_facade(root, "BackPanels", Vector3(0.0, 0.0, -size.z * 0.5 - 0.02), Vector3.LEFT, Vector3.UP, size.x, size.y, 3.1, 2.45, 0.032, [ART.SAND_DEEP, ART.CREAM_DEEP, ART.CREAM_DEEP, ART.CREAM], 23 + id.length(), back_skip)
    for side: float in [-1.0, 1.0]:
        var side_skip: Array = []
        for index: int in 2:
            var z: float = -size.z * 0.25 + float(index) * size.z * 0.5
            var u: float = z if side < 0.0 else -z
            side_skip.append(Rect2(u - 0.85, size.y * 0.56 - 0.95, 1.7, 1.9))
        var side_right := Vector3(0.0, 0.0, 1.0) if side < 0.0 else Vector3(0.0, 0.0, -1.0)
        ART.panel_facade(root, "SidePanels%s" % ("L" if side < 0.0 else "R"), Vector3(side * (size.x * 0.5 + 0.02), 0.0, 0.0), side_right, Vector3.UP, size.z, size.y, 2.9, 2.45, 0.032, [ART.CREAM_DEEP, ART.SAND_DEEP, ART.CREAM], 37 + id.length() + int(side) * 7, side_skip)

    for index in window_centers.size():
        var x: float = window_centers[index]
        var y: float = size.y * 0.58
        ART.block(root, "WindowReveal%d" % index, Vector3(window_width + 0.38, 2.04, 0.06), Vector3(x, y, front_z - 0.03), ART.TEAL_DEEP, 0.02, false, 0.0, SURFACE.Family.PAINT_WORN)
        var glass := ART.block(root, "WindowGlass%d" % index, Vector3(window_width, 1.66, 0.05), Vector3(x, y, front_z + 0.02), ART.GLASS, 0.02)
        glass.material_override = SURFACE.glass(ART.GLASS)
        ART.block(root, "WindowMullion%d" % index, Vector3(0.07, 1.70, 0.06), Vector3(x, y, front_z + 0.06), ART.CREAM_LIGHT, 0.01)
        ART.block(root, "WindowSill%d" % index, Vector3(window_width + 0.5, 0.12, 0.34), Vector3(x, y - 0.98, front_z + 0.08), ART.SAND, 0.03, false, 0.0, SURFACE.Family.CONC)
        # 部分窗户钉上封板：这是“废墟”最便宜也最可信的一条语言，但只出现在少数窗户上。
        if index % 3 == 1:
            ART.block(root, "WindowBoardA%d" % index, Vector3(window_width * 0.92, 0.22, 0.04), Vector3(x, y + 0.26, front_z + 0.09), ART.SAND_DEEP, 0.008, false, 0.0, SURFACE.Family.PAINT_WORN).rotation_degrees.z = 4.0
            ART.block(root, "WindowBoardB%d" % index, Vector3(window_width * 0.92, 0.22, 0.04), Vector3(x, y - 0.18, front_z + 0.09), ART.SAND_DEEP, 0.008, false, 0.0, SURFACE.Family.PAINT_WORN).rotation_degrees.z = -3.0
    # 侧立面各开两扇，第一人称横穿时建筑不是一块纯色墙。
    for side: float in [-1.0, 1.0]:
        for index: int in 2:
            var z: float = -size.z * 0.25 + float(index) * size.z * 0.5
            ART.block(root, "SideFrame%d_%d" % [int(side), index], Vector3(0.12, 1.7, 1.5), Vector3(side * (size.x * 0.5 + 0.02), size.y * 0.56, z), ART.CREAM_LIGHT, 0.04)
            ART.block(root, "SideGlass%d_%d" % [int(side), index], Vector3(0.06, 1.48, 1.28), Vector3(side * (size.x * 0.5 + 0.09), size.y * 0.56, z), ART.GLASS, 0.02, true, 0.10)

    # 门：凹进的门洞 + 门槛 + 门板分缝 + 踢脚 + 铰链 + 闭门器。门锁由 _build_door_lock() 负责。
    ART.block(root, "DoorRecess", Vector3(2.7, 2.9, 0.18), Vector3(0.0, 1.45, front_z + 0.02), ART.INK, 0.08, false, 0.0, SURFACE.Family.CAST)
    var door := ART.block(root, "Door", Vector3(2.2, 2.5, 0.12), Vector3(0.0, 1.25, front_z + 0.16), ART.TEAL, 0.06, false, 0.0, SURFACE.Family.PAINT_WORN)
    door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    ART.block(root, "DoorThreshold", Vector3(2.4, 0.06, 0.34), Vector3(0.0, 0.03, front_z + 0.18), ART.SAND_DEEP, 0.012, false, 0.0, SURFACE.Family.CONC)
    ART.block(root, "DoorKickPlate", Vector3(2.0, 0.22, 0.04), Vector3(0.0, 0.26, front_z + 0.225), ART.CREAM_DEEP, 0.01, false, 0.0, SURFACE.Family.MACH)
    for seam_index: int in 3:
        ART.block(root, "DoorSeam", Vector3(2.06, 0.02, 0.02), Vector3(0.0, 0.85 + float(seam_index) * 0.62, front_z + 0.228), ART.TEAL_DEEP, 0.004, false, 0.0, SURFACE.Family.PAINT_WORN)
    for hinge_side: float in [-1.0, 1.0]:
        for hinge_index: int in 3:
            ART.block(root, "DoorHinge", Vector3(0.07, 0.16, 0.05), Vector3(hinge_side * 1.06, 0.55 + float(hinge_index) * 0.72, front_z + 0.235), ART.CREAM_LIGHT, 0.008, false, 0.0, SURFACE.Family.MACH)
    ART.block(root, "DoorCloser", Vector3(0.34, 0.10, 0.14), Vector3(0.0, 2.36, front_z + 0.235), ART.INK, 0.015, false, 0.0, SURFACE.Family.CAST)
    var handle := ART.cylinder(root, "DoorHandleArm", 0.035, 0.26, Vector3(0.62, 1.22, front_z + 0.26), ART.CREAM_LIGHT, false, 0.0, SURFACE.Family.MACH)
    handle.rotation_degrees.z = 90.0
    ART.sphere(root, "DoorHandle", Vector3(0.11, 0.11, 0.11), Vector3(0.62, 1.22, front_z + 0.25), ART.CREAM_LIGHT)
    ART.block(root, "DoorFrameT", Vector3(3.0, 0.18, 0.34), Vector3(0.0, 2.96, front_z + 0.12), ART.CREAM_LIGHT, 0.04, false, 0.0, SURFACE.Family.PAINT_CLEAN)
    for side: float in [-1.0, 1.0]:
        ART.block(root, "DoorFrame", Vector3(0.18, 3.0, 0.34), Vector3(side * 1.46, 1.5, front_z + 0.12), ART.CREAM_LIGHT, 0.04, false, 0.0, SURFACE.Family.PAINT_CLEAN)
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

    # 雨棚：暖橙薄板 + 两根奶油支柱 + 斜撑 + 织物肋 + 滴水沿。
    var awning := ART.block(root, "Awning", Vector3(3.8, 0.16, 1.7), Vector3(0.0, 3.22, front_z + 0.75), ART.TEAL, 0.07, false, 0.0, SURFACE.Family.PAINT_CLEAN)
    awning.rotation_degrees.x = -7.0
    ART.block(root, "AwningDrip", Vector3(3.86, 0.10, 0.08), Vector3(0.0, 3.13, front_z + 1.58), ART.TEAL_DEEP, 0.02, false, 0.0, SURFACE.Family.PAINT_CLEAN)
    for rib_index: int in 5:
        ART.block(root, "AwningRib", Vector3(0.035, 0.035, 1.62), Vector3(-1.5 + float(rib_index) * 0.75, 3.17, front_z + 0.75), ART.CREAM_LIGHT, 0.008, false, 0.0, SURFACE.Family.MACH).rotation_degrees.x = -7.0
    for side: float in [-1.0, 1.0]:
        ART.cylinder(root, "AwningPost", 0.06, 3.0, Vector3(side * 1.7, 1.5, front_z + 1.45), ART.CREAM_LIGHT, false, 0.0, SURFACE.Family.MACH)
        ART.block(root, "AwningBracket", Vector3(0.06, 0.06, 0.62), Vector3(side * 1.7, 2.86, front_z + 1.16), ART.CREAM_DEEP, 0.01, false, 0.0, SURFACE.Family.MACH).rotation_degrees.x = 36.0
        ART.block(root, "AwningPostFoot", Vector3(0.20, 0.05, 0.20), Vector3(side * 1.7, 0.025, front_z + 1.45), ART.SAND_DEEP, 0.012, false, 0.0, SURFACE.Family.CONC)

    # 招牌色带：用几何条纹代替悬浮文字；加背板与铆钉交代装配。
    ART.block(root, "SignBack", Vector3(sign_width + 0.12, 1.07, 0.10), Vector3(0.0, size.y * 0.78, front_z + 0.00), ART.TEAL_DEEP, 0.02, false, 0.0, SURFACE.Family.CAST)
    ART.block(root, "SignBand", Vector3(sign_width, 0.95, 0.26), Vector3(0.0, size.y * 0.78, front_z + 0.05), accent, 0.06, true, 0.35)
    for index: int in 3:
        ART.block(root, "SignStripe%d" % index, Vector3(0.46, 0.34, 0.08), Vector3(-1.1 + float(index) * 1.1, size.y * 0.78, front_z + 0.20), ART.CREAM_LIGHT, 0.02)
    for index: int in 4:
        ART.block(root, "SignRivet", Vector3(0.05, 0.05, 0.03), Vector3(-sign_width * 0.5 + 0.12 + float(index) * (sign_width - 0.24) / 3.0, size.y * 0.78 + 0.40, front_z + 0.10), ART.CREAM_LIGHT, 0.006, false, 0.0, SURFACE.Family.MACH)

    # 屋顶设备：车削水箱 + 压边 + 空调外机 + 天窗；每件都有基座和地脚。
    ART.block(root, "RoofCurbTank", Vector3(1.9, 0.16, 1.9), Vector3(-size.x * 0.24, size.y + 0.16, -size.z * 0.18), ART.SAND_DEEP, 0.02, false, 0.0, SURFACE.Family.CONC)
    ART.lathe(root, "WaterTank", PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.82, 0.02), Vector2(0.84, 0.12), Vector2(0.80, 1.30), Vector2(0.72, 1.38), Vector2(0.0, 1.38)]), 20, Vector3(-size.x * 0.24, size.y + 0.24, -size.z * 0.18), ART.CREAM_LIGHT, SURFACE.Family.PAINT_CLEAN)
    ART.torus(root, "WaterTankBand", 0.82, 0.88, Vector3(-size.x * 0.24, size.y + 0.86, -size.z * 0.18), ART.TEAL, false, 0.0, SURFACE.Family.PAINT_WORN)
    ART.lathe(root, "WaterTankCap", PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.74, 0.02), Vector2(0.66, 0.14), Vector2(0.30, 0.22), Vector2(0.0, 0.24)]), 20, Vector3(-size.x * 0.24, size.y + 1.62, -size.z * 0.18), ART.TEAL_DEEP, SURFACE.Family.PAINT_WORN)
    ART.block(root, "RoofCurbAC", Vector3(1.7, 0.14, 1.3), Vector3(size.x * 0.26, size.y + 0.16, -size.z * 0.2), ART.SAND_DEEP, 0.02, false, 0.0, SURFACE.Family.CONC)
    ART.block(root, "RoofAC", Vector3(1.4, 0.75, 1.0), Vector3(size.x * 0.26, size.y + 0.65, -size.z * 0.2), ART.CREAM_DEEP, 0.1, false, 0.0, SURFACE.Family.PAINT_CLEAN)
    for grille_index: int in 4:
        ART.block(root, "ACGrille", Vector3(1.16, 0.04, 0.05), Vector3(size.x * 0.26, size.y + 0.42 + float(grille_index) * 0.11, -size.z * 0.2 + 0.52), ART.INK, 0.006, false, 0.0, SURFACE.Family.CAST)
    ART.block(root, "SkylightCurb", Vector3(2.7, 0.14, 1.7), Vector3(size.x * 0.2, size.y + 0.20, size.z * 0.18), ART.SAND_DEEP, 0.02, false, 0.0, SURFACE.Family.CONC)
    var skylight := ART.block(root, "Skylight", Vector3(2.4, 0.10, 1.4), Vector3(size.x * 0.2, size.y + 0.30, size.z * 0.18), ART.GLASS_LIGHT, 0.04)
    skylight.material_override = SURFACE.glass(ART.GLASS_LIGHT)
    # 屋顶检修梯：两根方钢轨 + 圆钢踏棍 + 护笼，交代“怎么上屋顶”。
    for side: float in [-1.0, 1.0]:
        ART.block(root, "RoofLadderRail", Vector3(0.06, 3.2, 0.06), Vector3(size.x * 0.5 + 0.10, size.y + 1.4, -size.z * 0.5 + 2.4 + side * 0.34), ART.TEAL_DEEP, 0.01, false, 0.0, SURFACE.Family.MACH)
    for rung_index: int in 7:
        ART.block(root, "RoofLadderRung", Vector3(0.05, 0.05, 0.72), Vector3(size.x * 0.5 + 0.10, size.y + 0.22 + float(rung_index) * 0.42, -size.z * 0.5 + 2.4), ART.TEAL_LIGHT, 0.008, false, 0.0, SURFACE.Family.MACH)

    if id == "school":
        # 学校：屋顶加一座小钟楼，远处先认轮廓。
        ART.block(root, "BellTower", Vector3(3.2, 3.4, 3.2), Vector3(-size.x * 0.28, size.y + 1.75, size.z * 0.12), ART.CREAM, 0.18)
        ART.cone(root, "BellRoof", 0.2, 2.3, 2.0, Vector3(-size.x * 0.28, size.y + 4.4, size.z * 0.12), ART.CORAL)
        ART.sphere(root, "Bell", Vector3(0.5, 0.5, 0.5), Vector3(-size.x * 0.28, size.y + 2.35, size.z * 0.12 + 1.65), ART.ORANGE, true, 0.5)
        # 学校整栋封闭：门洞钉木板和钢条，不再作为可进入建筑。
        ART.block(root, "SchoolSealBoardA", Vector3(2.7, 0.32, 0.12), Vector3(0.0, 1.15, front_z + 0.36), ART.SAND_DEEP, 0.02).rotation_degrees.z = 4.0
        ART.block(root, "SchoolSealBoardB", Vector3(2.7, 0.32, 0.12), Vector3(0.0, 1.78, front_z + 0.36), ART.SAND_DEEP, 0.02).rotation_degrees.z = -3.0
        ART.block(root, "SchoolSealBrace", Vector3(0.14, 2.2, 0.14), Vector3(-0.72, 1.45, front_z + 0.44), ART.TEAL_DEEP, 0.02).rotation_degrees.z = 18.0
        ART.block(root, "SchoolSealBrace", Vector3(0.14, 2.2, 0.14), Vector3(0.72, 1.45, front_z + 0.44), ART.TEAL_DEEP, 0.02).rotation_degrees.z = -18.0
        ART.block(root, "SchoolSealSign", Vector3(1.2, 0.34, 0.08), Vector3(0.0, 2.62, front_z + 0.40), ART.ORANGE, 0.02, true, 0.4)
    elif id == "library":
        # 图书馆：门前四根奶油圆柱，屋顶用青蓝区分。
        for index: int in 4:
            ART.cylinder(root, "Column%d" % index, 0.22, 3.1, Vector3(-2.9 + float(index) * 1.95, 1.55, front_z + 2.0), ART.CREAM_LIGHT)
            ART.block(root, "ColumnCap%d" % index, Vector3(0.62, 0.18, 0.62), Vector3(-2.9 + float(index) * 1.95, 3.18, front_z + 2.0), ART.CREAM_LIGHT, 0.05)
    elif id == "energy_station":
        # 能源站：储能柜、充电塔、变压器和顶棚太阳能板，不再有加油机。
        ART.block(root, "EnergyCanopy", Vector3(size.x + 3.0, 0.34, 7.0), Vector3(0.0, 4.2, front_z + 2.6), ART.TEAL, 0.12)
        ART.block(root, "EnergyCanopyTrim", Vector3(size.x + 3.2, 0.12, 7.2), Vector3(0.0, 4.40, front_z + 2.6), ART.CREAM_LIGHT, 0.04)
        for side: float in [-1.0, 1.0]:
            ART.i_beam(root, "CanopyPost", 4.0, 0.30, 0.26, 0.035, 0.035, Vector3(side * (size.x * 0.5 + 0.4), 0.0, front_z + 5.0), ART.TEAL_DEEP, 0.0)
            ART.block(root, "CanopyBrace", Vector3(0.06, 0.06, 1.55), Vector3(side * (size.x * 0.5 + 0.4), 3.42, front_z + 4.30), ART.TEAL_LIGHT, 0.01, false, 0.0, SURFACE.Family.MACH).rotation_degrees.x = 42.0
        ART.block(root, "CanopyGutter", Vector3(size.x + 3.2, 0.10, 0.12), Vector3(0.0, 4.02, front_z + 6.02), ART.SAND_DEEP, 0.015, false, 0.0, SURFACE.Family.MACH)
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
        # 排风塔 + 星髓晶簇 + 菌群：能源站是爆发原点，外景也要能读出本星生态。
        var stack_x: float = size.x * 0.5 + 1.8
        ART.lathe(root, "EnergyVentStack", PackedVector2Array([
            Vector2(0.0, 0.0), Vector2(0.66, 0.0), Vector2(0.63, 0.10), Vector2(0.44, 0.18),
            Vector2(0.40, 4.60), Vector2(0.54, 4.82), Vector2(0.52, 5.02), Vector2(0.0, 5.02),
        ]), 18, Vector3(stack_x, 0.0, front_z + 3.2), ART.TEAL_DEEP, SURFACE.Family.PAINT_WORN)
        for band: int in 3:
            ART.torus(root, "VentStackBand", 0.41, 0.47, Vector3(stack_x, 0.80 + float(band) * 1.40, front_z + 3.2), ART.ORANGE, false, 0.0, SURFACE.Family.PAINT_ACCENT)
        ART.crystal_cluster(root, "EnergyStarMarrow", Vector3(stack_x - 0.95, 0.0, front_z + 3.35), 0.85, 1301)
        ART.fungus_cluster(root, "EnergyVentFungus", Vector3(stack_x - 0.55, 0.02, front_z + 3.85), Vector3(0.2, 0.0, -0.6), 0.85, 1302, true)
        ART.mycelium_patch(root, "EnergyVentMycelium", Vector3(stack_x - 1.25, 0.02, front_z + 3.05), 1.2, 1303)

    # 落水管：从檐口到地面，带管卡与落水口；承力/排水关系一眼可读。
    for corner: Array in [[-1.0, -1.0], [1.0, -1.0], [-1.0, 1.0], [1.0, 1.0]]:
        var px: float = float(corner[0]) * (size.x * 0.5 - 0.22)
        var pz: float = float(corner[1]) * (size.z * 0.5 - 0.22)
        ART.pipe_run(root, "Downpipe", [Vector3(px, 0.28, pz), Vector3(px, size.y - 0.30, pz)], 0.055, ART.TEAL_DEEP, SURFACE.Family.MACH, true)
        ART.block(root, "DownpipeShoe", Vector3(0.22, 0.10, 0.22), Vector3(px, 0.16, pz), ART.SAND_DEEP, 0.01, false, 0.0, SURFACE.Family.CONC)

    # 女儿墙断茬 + 外露钢筋：先有完整屋顶收边，再局部打断，读作“后来塌的”。
    for index: int in 3:
        var chunk := ART.block(root, "ParapetChunk%d" % index, Vector3(0.9, 0.30, 0.34), Vector3(-rim_x + 1.3 + float(index) * 1.45, rim_y + 0.15, rim_z - 0.17), ART.CREAM_DEEP, 0.03, false, 0.0, SURFACE.Family.CONC)
        chunk.rotation_degrees.z = float(index % 2) * 5.0 - 2.0
        ART.cylinder(root, "Rebar%d" % index, 0.012, 0.62, Vector3(-rim_x + 1.4 + float(index) * 1.45, rim_y + 0.46, rim_z - 0.18), ART.CORAL, false, 0.0, SURFACE.Family.CAST).rotation_degrees = Vector3(0.0, 0.0, 14.0 - float(index) * 9.0)

    ART.soft_shadow(root, Vector3(0.0, 0.012, 0.0), maxf(size.x, size.z) * 0.62, 0.85)
    # 接地：径向暗晕 + 两圈碎石，消除“直角插进地里”的展台感。
    ATMOSPHERE.build_ground_skirt(root, "BuildingSkirt", Vector3(0.0, 0.0, 0.0), Vector2(size.x + 3.4, size.z + 3.4), Color(0.035, 0.033, 0.030), 0.62)
    ATMOSPHERE.build_gravel_cluster(root, "BuildingGravelA", Vector3(size.x * 0.5 + 0.7, 0.0, size.z * 0.5 + 0.5), 0.95, 11, 700 + id.length() * 13)
    ATMOSPHERE.build_gravel_cluster(root, "BuildingGravelB", Vector3(-size.x * 0.5 - 0.6, 0.0, -size.z * 0.5 - 0.5), 0.85, 9, 800 + id.length() * 17)
    var forecourt := ART.block(root, "Forecourt", Vector3(minf(size.x * 0.6, 13.0), 0.035, 4.4), Vector3(0.0, 0.0175, size.z * 0.5 + 2.1), ART.CONCRETE, 0.03, false, 0.0, SURFACE.Family.CONC)
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
    var seam := Color("#7a7060")
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
        var puddle := ART.cylinder(_world(), "Puddle", 1.1 + float(index) * 0.15, 0.014, puddles[index] + Vector3(0.0, 0.028, 0.0), Color("#5f7a78"))
        puddle.material_override = SURFACE.wet()
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
    var street_color := Color("#474b49")
    var street_dark := Color("#3f4443")
    var walk_color := ART.CONCRETE
    # 主街：从市场门前穿过广场，再通往医院方向。
    var avenue := ART.plane(_world(), "Avenue", Vector2(GROUND_EXTENT.x * 2.0 - 10.0, 7.2), Vector3(0.0, 0.035, 6.0), street_color, false, 0.0, SURFACE.Family.CONC, 3.2)
    avenue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _add_box_floor(Vector3(GROUND_EXTENT.x * 2.0 - 10.0, 0.035, 7.2), Vector3(0.0, 0.0175, 6.0))
    for side: float in [-1.0, 1.0]:
        var curb := ART.block(_world(), "AvenueCurb", Vector3(GROUND_EXTENT.x * 2.0 - 10.0, 0.10, 0.5), Vector3(0.0, 0.05, 6.0 + side * 3.85), ART.SAND_DEEP, 0.03, false, 0.0, SURFACE.Family.CONC)
        curb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var sidewalk := ART.plane(_world(), "AvenueSidewalk", Vector2(GROUND_EXTENT.x * 2.0 - 10.0, 3.0), Vector3(0.0, 0.04, 6.0 + side * 5.4), walk_color, false, 0.0, SURFACE.Family.CONC, 2.0)
        sidewalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _add_box_floor(Vector3(GROUND_EXTENT.x * 2.0 - 10.0, 0.04, 3.0), Vector3(0.0, 0.02, 6.0 + side * 5.4))
    # 南北支路：从能源站经过广场，通往北侧的学校与图书馆之间。
    var cross := ART.plane(_world(), "CrossStreet", Vector2(6.4, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(0.0, 0.035, -4.0), street_dark, false, 0.0, SURFACE.Family.CONC, 3.2)
    cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _add_box_floor(Vector3(6.4, 0.035, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(0.0, 0.0175, -4.0))
    for side: float in [-1.0, 1.0]:
        var cross_curb := ART.block(_world(), "CrossCurb", Vector3(0.5, 0.10, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(side * 3.45, 0.05, -4.0), ART.SAND_DEEP, 0.03, false, 0.0, SURFACE.Family.CONC)
        cross_curb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var cross_walk := ART.plane(_world(), "CrossSidewalk", Vector2(3.0, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(side * 5.0, 0.04, -4.0), walk_color, false, 0.0, SURFACE.Family.CONC, 2.0)
        cross_walk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _add_box_floor(Vector3(3.0, 0.04, GROUND_EXTENT.y * 2.0 - 12.0), Vector3(side * 5.0, 0.02, -4.0))
    # 中央广场：圆形铺装 + 一圈青色环，作为玩家认路的地标。
    ART.cylinder(_world(), "Plaza", 9.0, 0.09, Vector3(0.0, 0.045, 6.0), ART.CONCRETE, false, 0.0, SURFACE.Family.CONC)
    _add_cylinder_floor(9.0, 0.09, Vector3(0.0, 0.045, 6.0))
    ART.torus(_world(), "PlazaRing", 8.55, 8.85, Vector3(0.0, 0.10, 6.0), ART.TEAL)
    ART.torus(_world(), "PlazaRingInner", 4.6, 4.8, Vector3(0.0, 0.10, 6.0), ART.ORANGE, false, 0.0, SURFACE.Family.PAINT_ACCENT)
    # 车道虚线：暖橙色小方块，比白线更符合整套配色；只有可操作/警示件才用橙。
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
        ART.plane(_world(), "ShopPath", Vector2(5.0, 6.0), path_center, ART.CONCRETE, false, 0.0, SURFACE.Family.CONC, 2.0)
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
    # 停机坪：车削圆盘 + 倒角边缘 + 系留环 + 地面导引箭头。
    ART.lathe(pad, "PadBase", PackedVector2Array([
        Vector2(0.0, 0.0), Vector2(PAD_RADIUS - 0.10, 0.0), Vector2(PAD_RADIUS, 0.02),
        Vector2(PAD_RADIUS - 0.05, 0.12), Vector2(0.0, 0.12),
    ]), 40, Vector3.ZERO, ART.CONCRETE, SURFACE.Family.CONC)
    _add_cylinder_floor(PAD_RADIUS, 0.12, Vector3(SPAWN_POSITION.x, 0.06, SPAWN_POSITION.y))
    ART.torus(pad, "PadRing", PAD_RADIUS - 0.22, PAD_RADIUS - 0.04, Vector3(0.0, 0.13, 0.0), ART.ORANGE, true, 0.22)
    # 撤离开放后出现的一圈青绿灯带；未开放时隐藏。
    _pad_active_ring = ART.torus(pad, "PadActiveRing", PAD_RADIUS - 0.52, PAD_RADIUS - 0.30, Vector3(0.0, 0.15, 0.0), ART.TEAL_LIGHT, true, 0.55)
    _pad_active_ring.visible = false
    ART.torus(pad, "PadInner", 2.2, 2.34, Vector3(0.0, 0.13, 0.0), ART.TEAL, true, 0.22)
    for index: int in 6:
        var angle: float = TAU * float(index) / 6.0
        ART.torus(pad, "TieDownRing", 0.10, 0.16, Vector3(cos(angle) * (PAD_RADIUS - 1.25), 0.125, sin(angle) * (PAD_RADIUS - 1.25)), ART.CREAM_LIGHT, false, 0.0, SURFACE.Family.MACH)
    _pad_lights.clear()
    for index: int in 4:
        var angle: float = TAU * float(index) / 4.0 + PI * 0.25
        var light_position := Vector3(cos(angle) * (PAD_RADIUS - 0.7), 0.18, sin(angle) * (PAD_RADIUS - 0.7))
        ART.block(pad, "PadLightHousing%d" % index, Vector3(0.34, 0.18, 0.34), light_position, ART.TEAL_DEEP, 0.02, false, 0.0, SURFACE.Family.CAST)
        var pad_light := ART.sphere(pad, "PadLight%d" % index, Vector3(0.24, 0.16, 0.24), light_position + Vector3(0.0, 0.12, 0.0), ART.ORANGE, true, 0.9)
        _pad_lights.append(pad_light)
    # 信标柱：车削柱身 + 法兰 + 灯罩，放在停机坪左后方，避免正对镜头挡住城市。
    ART.lathe(pad, "BeaconPole", PackedVector2Array([
        Vector2(0.0, 0.0), Vector2(0.20, 0.0), Vector2(0.18, 0.08), Vector2(0.10, 0.18),
        Vector2(0.085, 2.55), Vector2(0.12, 2.62), Vector2(0.0, 2.64),
    ]), 16, Vector3(-4.6, 0.0, -3.4), ART.TEAL_DEEP, SURFACE.Family.PAINT_CLEAN)
    ART.sphere(pad, "BeaconLamp", Vector3(0.46, 0.46, 0.46), Vector3(-4.6, 2.86, -3.4), ART.LAMP, true, 1.0)
    ART.cone(pad, "BeaconHood", 0.06, 0.30, 0.18, Vector3(-4.6, 3.12, -3.4), ART.TEAL_DEEP, SURFACE.Family.PAINT_CLEAN)
    ART.torus(pad, "BeaconRing", 0.42, 0.48, Vector3(-4.6, 2.86, -3.4), ART.ORANGE, true, 0.55)
    # 地面上的"归航"箭头，用几何三角形代替文字。
    for index: int in 3:
        var arrow := ART.block(pad, "Arrow%d" % index, Vector3(0.5, 0.02, 1.5), Vector3(-1.2 + float(index) * 1.2, 0.14, 0.4), ART.CREAM_LIGHT, 0.02)
        arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # 2 组货箱 + 2 只油桶，用捆扎带固定；给出“这里有人补给过”的痕迹。
    for index: int in 2:
        var crate_at := Vector3(3.2, 0.14, -0.6 - float(index) * 1.1)
        ART.block(pad, "PadCrate%d" % index, Vector3(0.9, 0.62, 0.8), crate_at + Vector3(0.0, 0.31, 0.0), ART.CONCRETE, 0.05, false, 0.0, SURFACE.Family.PAINT_WORN)
        ART.block(pad, "PadCrateBand%d" % index, Vector3(0.94, 0.08, 0.84), crate_at + Vector3(0.0, 0.46, 0.0), ART.ORANGE, 0.008, false, 0.0, SURFACE.Family.PAINT_ACCENT)
    for index: int in 2:
        ART.lathe(pad, "FuelDrum%d" % index, PackedVector2Array([
            Vector2(0.0, 0.0), Vector2(0.30, 0.0), Vector2(0.31, 0.04), Vector2(0.31, 0.80),
            Vector2(0.27, 0.86), Vector2(0.0, 0.86),
        ]), 18, Vector3(-2.4 + float(index) * 0.8, 0.14, -1.8), ART.ORANGE_DEEP, SURFACE.Family.PAINT_ACCENT)
    # 控制台：实体表盘 + 3 盏状态灯 + 贴壁图示铭牌，读目标/撤离状态。
    var console_root := Node3D.new()
    console_root.name = "PadControlConsole"
    console_root.position = Vector3(-2.6, 0.14, 2.4)
    pad.add_child(console_root)
    ART.block(console_root, "ConsolePlinth", Vector3(0.92, 0.34, 0.62), Vector3(0.0, 0.17, 0.0), ART.CONCRETE, 0.02, false, 0.0, SURFACE.Family.CONC)
    ART.block(console_root, "ConsoleBody", Vector3(0.80, 0.56, 0.52), Vector3(0.0, 0.56, 0.0), ART.TEAL_DEEP, 0.035, false, 0.0, SURFACE.Family.PAINT_WORN)
    ART.block(console_root, "ConsoleTop", Vector3(0.86, 0.06, 0.58), Vector3(0.0, 0.86, 0.0), ART.CREAM_LIGHT, 0.015, false, 0.0, SURFACE.Family.MACH)
    _pad_dial = PHYSICAL.build_live_dial(console_root, "PadObjectiveDial", Vector3(0.0, 0.90, -0.06), Vector3(-10.0, 0.0, 0.0), 0.16, 0.0, 1.0)
    for index: int in 3:
        _link_lamps.append(PHYSICAL.build_status_lamp(console_root, "PadStatusLamp%d" % index, Vector3(-0.22 + float(index) * 0.22, 0.90, 0.22), 0.05, SURFACE.surface(ART.INK, SURFACE.Family.CAST)))
    PHYSICAL.build_diagram_plaque(console_root, "PadSchematic", Vector3(0.0, 1.02, 0.30), Vector3(-14.0, 0.0, 0.0), Vector2(0.78, 0.32), [
        {"num": 1, "icon": "lock", "col": Color(1.0, 0.55, 0.12)},
        {"num": 2, "icon": "cart", "col": Color(0.30, 0.85, 1.0)},
        {"num": 3, "icon": "gate", "col": Color(0.30, 1.0, 0.65)},
    ])
    ART.soft_shadow(pad, Vector3(0.0, 0.01, 0.0), PAD_RADIUS * 1.05, 0.3)
    ATMOSPHERE.build_ground_skirt(pad, "PadSkirt", Vector3(0.0, 0.0, 0.0), Vector2(PAD_RADIUS * 2.5, PAD_RADIUS * 2.5), Color(0.030, 0.030, 0.028), 0.60)
    ATMOSPHERE.build_gravel_cluster(pad, "PadGravelA", Vector3(PAD_RADIUS - 0.2, 0.0, 1.4), 0.9, 9, 1201)
    ATMOSPHERE.build_gravel_cluster(pad, "PadGravelB", Vector3(-PAD_RADIUS + 0.2, 0.0, -1.6), 0.8, 8, 1202)


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
    while placed < 38 and attempts < 260:
        attempts += 1
        var point := Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-46.0, 46.0))
        if not _open_ground(point):
            continue
        var root := Node3D.new()
        root.name = "RuinGrass"
        root.position = Vector3(point.x, 0.0, point.y)
        _world().add_child(root)
        for index: int in 3:
            var blade := ART.cone(root, "Blade%d" % index, 0.0, 0.16, rng.randf_range(0.35, 0.62), Vector3(rng.randf_range(-0.18, 0.18), 0.2, rng.randf_range(-0.18, 0.18)), ART.SAGE_DEEP if index % 2 == 0 else ART.SAGE, SURFACE.Family.FOLIAGE)
            blade.rotation_degrees.z = rng.randf_range(-14.0, 14.0)
        placed += 1
    placed = 0
    attempts = 0
    while placed < 30 and attempts < 260:
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


## 街道细节：雨水篦子、井盖、修补条、裂缝、配电箱、消防栓、倒下的路牌、碎石与菌斑。
## 只加视觉，不加碰撞；位置避开主路中心与建筑入口。
func _build_street_details() -> void:
    var drains: Array[Vector3] = [
        Vector3(12.0, 0.0, 9.62), Vector3(-18.0, 0.0, 9.62),
        Vector3(12.0, 0.0, 2.38), Vector3(-18.0, 0.0, 2.38),
    ]
    for point in drains:
        ART.drain_grate(_world(), "StormDrain", Vector3(point.x, surface_height(point.x, point.z) + 0.004, point.z), Vector2(0.72, 0.42))
    for point: Vector3 in [Vector3(0.0, 0.0, 0.0), Vector3(-30.0, 0.0, 12.0), Vector3(22.0, 0.0, -4.0)]:
        var manhole := ART.lathe(_world(), "ManholeCover", PackedVector2Array([
            Vector2(0.0, 0.0), Vector2(0.42, 0.0), Vector2(0.44, 0.02), Vector2(0.42, 0.045),
            Vector2(0.32, 0.055), Vector2(0.0, 0.055),
        ]), 20, Vector3(point.x, surface_height(point.x, point.z) + 0.004, point.z), ART.INK, SURFACE.Family.CAST)
        manhole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # 沥青修补条：同一路面上的“后来补过”的色差，比随机噪点更像真实街道。
    var patches := [
        {"pos": Vector3(-8.0, 0.0, 6.0), "size": Vector2(6.0, 2.6), "yaw": 3.0},
        {"pos": Vector3(26.0, 0.0, 6.4), "size": Vector2(4.0, 2.0), "yaw": -2.0},
        {"pos": Vector3(-50.0, 0.0, -4.0), "size": Vector2(2.6, 6.0), "yaw": 1.0},
    ]
    for raw: Dictionary in patches:
        var patch := ART.plane(_world(), "AsphaltPatch", raw.size, Vector3((raw.pos as Vector3).x, 0.042, (raw.pos as Vector3).z), Color("#3b4542"), false, 0.0, SURFACE.Family.CONC, 2.6)
        patch.rotation_degrees.y = float(raw.yaw)
        patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # 裂缝：只做细长深色片，不抢主视觉。
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261125
    for index: int in 7:
        var at := Vector3(rng.randf_range(-64.0, 64.0), 0.046, rng.randf_range(-36.0, 30.0))
        if absf(at.z - 6.0) < 4.6 or absf(at.x) < 4.2:
            continue
        var crack := ART.plane(_world(), "PavementCrack", Vector2(rng.randf_range(1.2, 3.4), 0.045), at, Color("#262c2b"))
        crack.rotation_degrees.y = rng.randf_range(0.0, 180.0)
        crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    # 配电箱：底座 + 柜体 + 百叶 + 警告牌 + 落地导管。
    var cabinet := Node3D.new()
    cabinet.name = "UtilityCabinet"
    cabinet.position = Vector3(-52.0, surface_height(-52.0, 10.2), 10.2)
    cabinet.rotation_degrees.y = -90.0
    _world().add_child(cabinet)
    ART.block(cabinet, "CabinetPlinth", Vector3(1.25, 0.18, 0.78), Vector3(0.0, 0.09, 0.0), ART.CONCRETE, 0.02, false, 0.0, SURFACE.Family.CONC)
    ART.block(cabinet, "CabinetBody", Vector3(1.10, 1.70, 0.64), Vector3(0.0, 1.02, 0.0), ART.TEAL_DEEP, 0.035, false, 0.0, SURFACE.Family.PAINT_WORN)
    ART.block(cabinet, "CabinetDoor", Vector3(0.94, 1.46, 0.06), Vector3(0.0, 1.08, 0.34), ART.TEAL, 0.02, false, 0.0, SURFACE.Family.PAINT_WORN)
    for vent_index: int in 5:
        ART.block(cabinet, "CabinetVent", Vector3(0.64, 0.035, 0.03), Vector3(0.0, 0.62 + float(vent_index) * 0.09, 0.38), ART.INK, 0.006, false, 0.0, SURFACE.Family.CAST)
    ART.block(cabinet, "CabinetWarning", Vector3(0.40, 0.12, 0.03), Vector3(0.0, 1.62, 0.39), ART.ORANGE, 0.006, true, 0.12)
    ART.pipe_run(cabinet, "CabinetConduit", [Vector3(0.36, 0.10, 0.0), Vector3(0.36, -0.28, 0.48), Vector3(0.36, -0.34, 1.10)], 0.045, ART.TEAL_DEEP, SURFACE.Family.MACH, true)

    # 消防栓：两颗，暖橙只给可操作/安全件。
    for at: Vector3 in [Vector3(-34.0, 0.0, 10.6), Vector3(30.0, 0.0, 10.6)]:
        var hydrant := Node3D.new()
        hydrant.name = "Hydrant"
        hydrant.position = Vector3(at.x, surface_height(at.x, at.z), at.z)
        _world().add_child(hydrant)
        ART.lathe(hydrant, "HydrantBody", PackedVector2Array([
            Vector2(0.0, 0.0), Vector2(0.20, 0.0), Vector2(0.19, 0.06), Vector2(0.13, 0.16),
            Vector2(0.115, 0.56), Vector2(0.08, 0.62), Vector2(0.0, 0.64),
        ]), 14, Vector3.ZERO, ART.ORANGE, SURFACE.Family.PAINT_ACCENT)
        ART.lathe(hydrant, "HydrantCap", PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.02), Vector2(0.06, 0.12), Vector2(0.0, 0.14)]), 12, Vector3(0.0, 0.64, 0.0), ART.ORANGE_DEEP, SURFACE.Family.PAINT_ACCENT)
        for side: float in [-1.0, 1.0]:
            ART.cylinder(hydrant, "HydrantNozzle", 0.055, 0.20, Vector3(side * 0.18, 0.40, 0.0), ART.CREAM_LIGHT, false, 0.0, SURFACE.Family.MACH).rotation_degrees.z = 90.0

    # 倒下的路牌：杆体横倒、牌面贴地，交代“这里没人维护”。
    var fallen := Node3D.new()
    fallen.name = "FallenStreetSign"
    fallen.position = Vector3(-20.0, surface_height(-20.0, 10.8), 10.8)
    fallen.rotation_degrees.y = 18.0
    _world().add_child(fallen)
    var pole := ART.cylinder(fallen, "SignPole", 0.045, 2.6, Vector3(0.0, 0.25, 0.0), ART.TEAL_DEEP, false, 0.0, SURFACE.Family.MACH)
    pole.rotation_degrees.z = 82.0
    var plate := ART.block(fallen, "SignPlate", Vector3(0.92, 0.56, 0.05), Vector3(1.1, 0.30, 0.42), ART.CREAM_LIGHT, 0.02, false, 0.0, SURFACE.Family.PAINT_WORN)
    plate.rotation_degrees = Vector3(0.0, 24.0, 78.0)
    for mark_index: int in 2:
        ART.block(fallen, "SignPlateMark", Vector3(0.58, 0.08, 0.03), Vector3(1.1, 0.34 + float(mark_index) * 0.14, 0.46), ART.ORANGE, 0.006, false, 0.0, SURFACE.Family.PAINT_ACCENT)

    # 碎石堆与菌斑：城市边缘保持干净，只沿排水口/背阴墙脚出现少量。
    ART.rubble_field(_world(), "StreetRubbleWest", Vector3(-70.0, 0.0, 8.0), 1.4, 9, 901, 1.0)
    ART.rubble_field(_world(), "StreetRubbleEast", Vector3(68.0, 0.0, -8.0), 1.2, 7, 902, 0.9)
    ART.rubble_field(_world(), "StreetRubbleNorth", Vector3(-12.0, 0.0, -22.0), 1.6, 8, 903, 1.1)
    ART.fungus_cluster(_world(), "DrainFungusA", Vector3(12.0, surface_height(12.0, 9.4) + 0.01, 9.4), Vector3.UP, 0.62, 501, true)
    ART.fungus_cluster(_world(), "DrainFungusB", Vector3(-18.0, surface_height(-18.0, 2.6) + 0.01, 2.6), Vector3.UP, 0.50, 502, true)
    ART.mycelium_patch(_world(), "DrainMycelium", Vector3(12.0, surface_height(12.0, 9.2) + 0.012, 9.2), 0.55, 503)


## 环境微动态：广场与登陆艇的缓飘尘、井盖蒸汽、能源站排风蒸汽、顶棚极淡假体积光。
func _build_atmosphere() -> void:
    ATMOSPHERE.build_ambient_motes(_world(), "PlazaDustMotes", Vector3(0.0, 2.2, 6.0), Vector3(10.0, 2.4, 8.0), Color(0.78, 0.80, 0.70), 24, 0.05)
    ATMOSPHERE.build_ambient_motes(_world(), "PadDustMotes", Vector3(SPAWN_POSITION.x, 1.8, SPAWN_POSITION.y), Vector3(6.0, 2.0, 6.0), Color(0.80, 0.82, 0.72), 16, 0.045)
    ATMOSPHERE.build_steam_vent(_world(), "ManholeSteam", Vector3(0.0, 0.12, 0.0), Vector3(0.15, 1.0, 0.10), Color(0.82, 0.85, 0.80), 8, 0.24)
    ATMOSPHERE.build_steam_vent(_world(), "EnergyVentSteam", Vector3(2.0, 5.1, -37.2), Vector3(0.20, 1.0, -0.15), Color(0.84, 0.88, 0.84), 10, 0.30)
    ATMOSPHERE.build_godray_cone(_world(), "EnergyCanopyShaft", Vector3(2.0, 4.0, -34.6), Vector3(0.0, -1.0, 0.12), 3.6, 0.9, 2.2, Color(0.88, 0.92, 0.82), 0.09)


## 物理因果：能源站→城区的装甲导管、状态灯与贴壁图示铭牌。
## 状态只读既有玩法变量（目标进度 / 撤离开放 / 剧情标记），不新增权威。
func _build_physical_links() -> void:
    var jacket := SURFACE.surface(ART.TEAL_DEEP, SURFACE.Family.PAINT_WORN, {"rough_paint": 0.52})
    _link_flow = PHYSICAL.make_flow_material(Color(0.28, 0.86, 1.0), 0.55, 0.55, 8.0)
    var points: Array[Vector3] = [
        Vector3(6.2, 0.20, -37.0), Vector3(8.6, 0.20, -30.0),
        Vector3(8.6, 0.20, -12.0), Vector3(8.6, 0.20, -2.0),
    ]
    PHYSICAL.build_conduit_run(_world(), "EnergyCityConduit", points, 0.075, jacket, _link_flow, Vector3(0.0, 0.06, 0.0), true)
    var housing := SURFACE.surface(ART.INK, SURFACE.Family.CAST)
    for index: int in 3:
        var at: Vector3 = points[mini(index + 1, points.size() - 1)]
        _link_lamps.append(PHYSICAL.build_status_lamp(_world(), "EnergyCityLamp%d" % index, at + Vector3(0.0, 0.36, 0.0), 0.075, housing))
    PHYSICAL.build_diagram_plaque(_world(), "EnergyCitySchematic", Vector3(7.4, 1.15, -34.0), Vector3(0.0, -90.0, 0.0), Vector2(0.90, 0.36), [
        {"num": 1, "icon": "lock", "col": Color(1.0, 0.55, 0.12)},
        {"num": 2, "icon": "cart", "col": Color(0.30, 0.85, 1.0)},
        {"num": 3, "icon": "gate", "col": Color(0.30, 1.0, 0.65)},
    ])
    _update_physical_links(true)


## 只读现有状态更新导管/灯/表盘；每帧只在数值变化时写参数。
func _update_physical_links(force := false) -> void:
    var objective := clampf(float(taken_food.size() + discovered_buildings.size()) / float(OBJECTIVE_FOOD + OBJECTIVE_BUILDINGS), 0.0, 1.0)
    if _pad_dial != null and (force or absf(objective - _pad_dial_value) > 0.004):
        PHYSICAL.set_dial_value(_pad_dial, objective)
        _pad_dial_value = objective
    var ready := extraction_ready()
    var state := "active" if ready else ("ready" if objective > 0.0 else "locked")
    if not force and state == _link_state:
        return
    _link_state = state
    PHYSICAL.set_flow_state(_link_flow, state)
    for lamp in _link_lamps:
        PHYSICAL.set_lamp_state(lamp, state)



func _build_horizon() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261028
    var hill_parent := Node3D.new()
    hill_parent.name = "RuinHorizon"
    _world().add_child(hill_parent)
    # 远景低丘：面化岩块 + 层理，不再是“球 + 噪声”。
    for index: int in 14:
        var angle: float = TAU * float(index) / 14.0 + rng.randf_range(-0.08, 0.08)
        var radius: float = rng.randf_range(96.0, 116.0)
        var hill_size := Vector3(rng.randf_range(28.0, 42.0), rng.randf_range(8.0, 15.0), rng.randf_range(24.0, 38.0))
        var point := Vector3(cos(angle) * radius, hill_size.y * 0.5 - 2.0, sin(angle) * radius)
        ART.rock_chunk(hill_parent, "Hill%d" % index, hill_size, 2000 + index * 13, point, 12,
            Color("#5c5648"), Color("#3c3a33"), Color("#6f685a"))
    # 远处城市剪影：保留体块，但加女儿墙/水塔/竖向分缝，阅读成“殖民城”，不是一堆方盒。
    for index: int in 10:
        var angle: float = TAU * float(index) / 10.0 + 0.22
        var radius: float = rng.randf_range(82.0, 98.0)
        var height: float = rng.randf_range(10.0, 24.0)
        var width: float = rng.randf_range(8.0, 15.0)
        var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
        var distant := ART.block(hill_parent, "DistantBlock%d" % index, Vector3(width, height, width * 0.8), point + Vector3(0.0, height * 0.5, 0.0), ART.CREAM_DEEP if index % 2 == 0 else ART.TEAL, 0.4, false, 0.0, SURFACE.Family.PAINT_CLEAN)
        distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        ART.block(hill_parent, "DistantParapet%d" % index, Vector3(width + 0.8, 0.30, width * 0.8 + 0.8), point + Vector3(0.0, height + 0.15, 0.0), ART.SAND_DEEP, 0.06, false, 0.0, SURFACE.Family.PAINT_CLEAN).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        if index % 3 == 0:
            ART.lathe(hill_parent, "DistantTank%d" % index, PackedVector2Array([
                Vector2(0.0, 0.0), Vector2(1.1, 0.0), Vector2(1.0, 0.20), Vector2(0.9, 2.0), Vector2(0.0, 2.1),
            ]), 12, point + Vector3(width * 0.18, height + 0.30, 0.0), ART.CREAM_LIGHT, SURFACE.Family.PAINT_CLEAN).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # 北侧广播塔：全图唯一一处远距红点，作为方向锚；塔身有交叉斜撑和拉索。
    var tower_root := Node3D.new()
    tower_root.name = "CollapsedRadioTower"
    tower_root.position = Vector3(0.0, 0.0, -88.0)
    hill_parent.add_child(tower_root)
    ART.lathe(tower_root, "Mast", PackedVector2Array([
        Vector2(0.0, 0.0), Vector2(0.55, 0.0), Vector2(0.45, 6.0), Vector2(0.30, 12.0),
        Vector2(0.16, 18.0), Vector2(0.10, 21.0), Vector2(0.0, 21.2),
    ]), 8, Vector3.ZERO, ART.TEAL_DEEP, SURFACE.Family.PAINT_WORN)
    for arm_index: int in 4:
        var arm_y: float = 4.0 + float(arm_index) * 4.2
        ART.block(tower_root, "TowerArm", Vector3(3.2 - float(arm_index) * 0.55, 0.10, 0.10), Vector3(0.0, arm_y, 0.0), ART.TEAL_LIGHT, 0.01, false, 0.0, SURFACE.Family.MACH)
        ART.pipe_run(tower_root, "TowerGuy", [Vector3(0.0, arm_y, 0.0), Vector3(3.4 - float(arm_index) * 0.5, 0.0, 0.0)], 0.018, ART.TEAL_DEEP, SURFACE.Family.MACH, false)
        ART.pipe_run(tower_root, "TowerGuy", [Vector3(0.0, arm_y, 0.0), Vector3(-3.4 + float(arm_index) * 0.5, 0.0, 0.0)], 0.018, ART.TEAL_DEEP, SURFACE.Family.MACH, false)
    ART.sphere(tower_root, "TowerAviationLight", Vector3(0.34, 0.34, 0.34), Vector3(0.0, 21.4, 0.0), Color("#d24a3a"), true, 0.7)
    # 地图外圈树线：从地面边缘一直排到远景，遮住可行走范围的硬边。
    for index: int in 16:
        var angle: float = TAU * float(index) / 16.0
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
        elif _shelter_environment != null and shelter_interior != null and is_inside_shelter(player.global_position):
            target_environment = _shelter_environment
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
        if camera != null and (camera.environment == _environment or camera.environment == _hospital_environment or camera.environment == _energy_environment or camera.environment == _school_environment or camera.environment == _market_environment or camera.environment == _shelter_environment):
            camera.environment = null


func _world() -> Node3D:
    return world_root




func tick(delta: float) -> void:
    _time += delta
    # 每个端都要跑：客户端也要把自己的镜头切到腐墟星的环境。
    _apply_camera_environment()
    _update_physical_links()
    if hud != null:
        hud.tick(delta)
    if not controller.is_host:
        return
    _tick_void_recovery()
    _tick_search(delta)
    _tick_force_jobs(delta)
    _tick_story(delta)


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
        var secret_point: Vector3 = energy_station_interior.call("secret_door_position")
        var secret_distance := player.global_position.distance_to(secret_point)
        if secret_distance <= 2.6 and secret_distance < best_distance and _in_view(player, secret_point):
            best_distance = secret_distance
            best = {"kind": "energy_secret_door", "id": "shelter"}
        if energy_station_interior.has_method("task_item_positions"):
            var energy_tasks: Dictionary = energy_station_interior.call("task_item_positions")
            for item_id: String in energy_tasks.keys():
                if quest_items.has(item_id):
                    continue
                var core_point: Vector3 = energy_tasks[item_id]
                var core_distance := player.global_position.distance_to(core_point)
                if core_distance <= 2.6 and core_distance < best_distance and _in_view(player, core_point):
                    best_distance = core_distance
                    best = {"kind": "energy_quest_item", "id": item_id}
        if story_plan == "doctor" and not bool(story_flags.get("pump_shutdown", false)):
            var pump_point: Vector3 = energy_station_interior.call("pump_console_position")
            var pump_distance := player.global_position.distance_to(pump_point)
            if pump_distance <= 2.6 and pump_distance < best_distance and _in_view(player, pump_point):
                best_distance = pump_distance
                best = {"kind": "energy_pump_console", "id": "colony_pump"}
        if story_plan == "doctor" and bool(story_flags.get("pump_shutdown", false)) and story_ending == "":
            var reactor_point: Vector3 = energy_station_interior.call("reactor_console_position")
            var reactor_distance := player.global_position.distance_to(reactor_point)
            if reactor_distance <= 2.6 and reactor_distance < best_distance and _in_view(player, reactor_point):
                best_distance = reactor_distance
                best = {"kind": "energy_reactor_console", "id": "reactor"}
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
    if shelter_interior != null and is_inside_shelter(player.global_position):
        var shelter_exit := shelter_exit_position()
        var shelter_distance := player.global_position.distance_to(shelter_exit)
        if shelter_distance <= 3.0 and shelter_distance < best_distance and _in_view(player, shelter_exit):
            best_distance = shelter_distance
            best = {"kind": "shelter_exit", "id": "shelter"}
        var npcs: Dictionary = shelter_npc_positions()
        for npc_id: String in npcs.keys():
            var npc_point: Vector3 = npcs[npc_id]
            var npc_distance := player.global_position.distance_to(npc_point)
            if npc_distance <= 2.5 and npc_distance < best_distance and _in_view(player, npc_point):
                best_distance = npc_distance
                best = {"kind": "shelter_npc", "id": npc_id}
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
    if String(target.kind) == "energy_secret_door":
        return "[E] 使用门禁通讯 · 庇护所"
    if String(target.kind) == "energy_quest_item":
        return "[E] 取走%s" % quest_item_label(String(target.id))
    if String(target.kind) == "energy_pump_console":
        return "[E] 转动手轮 · 关闭菌群泵 %d%%" % int(round(float(story_flags.get("pump_wheel", 0.0)) * 100.0))
    if String(target.kind) == "energy_reactor_console":
        return "[E] 转动手轮 · 重启主反应堆 %d%%" % int(round(float(story_flags.get("reactor_wheel", 0.0)) * 100.0))
    if String(target.kind) == "shelter_exit":
        return "[E] 离开庇护所 · 回到能源站"
    if String(target.kind) == "shelter_npc":
        return "[E] 与%s交谈" % ("老工程师" if String(target.id) == "engineer" else "年轻医生")
    if String(target.kind) == "school_exit":
        return "[E] 离开学校 · 回到大门"
    if String(target.kind) == "school_quest_item":
        return "[E] 取走%s" % quest_item_label(String(target.id))
    if String(target.kind) == "market_exit":
        return "[E] 离开超市 · 回到大门"
    if String(target.kind) == "market_quest_item":
        return "[E] 取走%s" % quest_item_label(String(target.id))
    if String(target.kind) == "pad":
        if story_plan == "engineer":
            return "[E] 登艇撤离 · 星球即将毁灭"
        if story_plan == "leave":
            return "[E] 隐瞒真相 · 直接离开"
        if story_plan == "doctor" and story_ending == "":
            return "还不能走 · 先关闭菌群泵并重启反应堆"
        if extraction_ready():
            if controller.extraction_progress > 0.0:
                return "撤离中 · 保持 %.1f / %.1f 秒" % [controller.extraction_progress, EXTRACTION_HOLD]
            return "撤离开放 · 全员站上登陆艇保持 %.0f 秒" % EXTRACTION_HOLD
        return "[E] 紧急返航（%s）" % objective_text()
    if String(target.kind) == "building":
        var name := String(buildings[target.id].name)
        if String(target.id) == "library":
            return "[E] 检查封死的门 · %s" % name
        if String(target.id) == "school":
            return "学校大门被木板封死，无法进入"
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
    if String(target.kind) == "energy_secret_door":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("这是门禁通讯，不需要撬；按 E 呼叫里面的人。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            open_shelter_dialogue(peer_id, "")
        return true
    if String(target.kind) == "energy_quest_item":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("任务物不用撬，靠近按 E 拿取。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            _collect_energy_core(peer_id)
        return true
    if String(target.kind) == "energy_pump_console":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("控制台不需要撬。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            _turn_energy_wheel(peer_id, "pump")
        return true
    if String(target.kind) == "energy_reactor_console":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("控制台不需要撬。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            _turn_energy_wheel(peer_id, "reactor")
        return true
    if String(target.kind) == "shelter_exit":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("这是出口，不需要撬。", Color("#ffbd75"), 1.6)
        elif controller.is_host:
            controller.exit_shelter(peer_id)
        return true
    if String(target.kind) == "shelter_npc":
        if action == "ruin_force_door":
            controller.show_feedback_rpc.rpc("别拿撬棍对着人。按 E 交谈。", Color("#ffbd75"), 1.8)
        elif controller.is_host:
            open_shelter_dialogue(peer_id, String(target.id))
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
        if story_plan == "engineer" and story_ending == "":
            finish_story_ending("engineer")
            return true
        if story_plan == "leave" and story_ending == "":
            finish_story_ending("leave")
            return true
        if story_plan == "doctor" and story_ending == "":
            if not bool(story_flags.get("reactor_restarted", false)):
                controller.show_feedback_rpc.rpc("还不能走：先关闭 B1 菌群泵，再回 B2 重启主反应堆。", Color("#ffbd75"), 2.6)
            elif not bool(story_flags.get("launch_key", false)):
                controller.show_feedback_rpc.rpc("还不能走：回庇护所/配电间门外通讯，领取跃迁钥匙。", Color("#ffbd75"), 2.8)
            else:
                finish_story_ending("true")
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
        if building_id == "school":
            controller.show_feedback_rpc.rpc("学校已经封死，木板和钢条钉在门外，进不去。", Color("#ffbd75"), 2.4)
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
    if building_id == "school":
        controller.show_feedback_rpc.rpc("学校已经封死，木板和钢条钉在门外，进不去。", Color("#ffbd75"), 2.4)
        return
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
    if building_id == "school":
        controller.show_feedback_rpc.rpc("学校已经封死，木板和钢条钉在门外，进不去。", Color("#ffbd75"), 2.4)
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


func shelter_spawn_position() -> Vector3:
    if shelter_interior == null:
        return Vector3.ZERO
    return shelter_interior.call("spawn_position")


func shelter_exit_position() -> Vector3:
    if shelter_interior == null:
        return Vector3.ZERO
    return shelter_interior.call("exit_position")


func is_inside_shelter(point: Vector3) -> bool:
    return shelter_interior != null and bool(shelter_interior.call("is_inside", point))


## 主机记录玩家最近进入的室内入口与最低楼层；用于掉出地板后的兜底。
func note_interior_entry(peer_id: int, spawn: Vector3, base_y: float) -> void:
    _interior_anchors[peer_id] = {"spawn": spawn, "base": base_y}


func clear_interior_entry(peer_id: int) -> void:
    _interior_anchors.erase(peer_id)


func _tick_void_recovery() -> void:
    if not controller.is_host:
        return
    for peer_id: int in controller.players:
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player == null or player.downed or player.lava_dead:
            continue
        var anchor: Dictionary = _interior_anchors.get(peer_id, {})
        if not anchor.is_empty():
            var anchor_spawn: Vector3 = anchor.get("spawn", Vector3.ZERO)
            # 只在室内平面附近兜底；玩家被正常传送/走到别的建筑时不能误拉回。
            var planar := Vector2(player.global_position.x - anchor_spawn.x, player.global_position.z - anchor_spawn.z)
            if planar.length() <= 30.0 and player.global_position.y < float(anchor.get("base", 0.0)) - 2.5:
                controller.recover_ruin_player(peer_id, anchor_spawn)
        elif player.global_position.y < -5.0:
            # 没有室内锚点却掉到地面以下：回登陆艇，避免无限下落。
            controller.recover_ruin_player(peer_id, pad_position() + Vector3(0.0, 0.4, 2.5))


func shelter_npc_positions() -> Dictionary:
    if shelter_interior == null:
        return {}
    return shelter_interior.call("npc_positions")


func energy_secret_return_position() -> Vector3:
    if energy_station_interior == null:
        return Vector3.ZERO
    var level: Vector3 = energy_station_interior.call("level_position", 2)
    return level + Vector3(0.0, 0.15, -8.1)


func quest_item_label(item_id: String) -> String:
    return String(ALL_QUEST_ITEMS.get(item_id, item_id))


func quest_item_count() -> int:
    return quest_items.size()


func quest_item_total() -> int:
    return ALL_QUEST_ITEMS.size()


func quest_intel_unlocked() -> bool:
    return bool(story_flags.get("quest_intel", false)) or not quest_items.is_empty()


func quest_item_hud_text() -> String:
    var lines: Array[String] = ["任务物品 %d/%d" % [quest_items.size(), ALL_QUEST_ITEMS.size()]]
    for item_id: String in ALL_QUEST_ITEMS:
        var mark := "✓" if has_quest_item(item_id) else "○"
        lines.append("%s %s · %s" % [mark, String(ALL_QUEST_ITEMS[item_id]), String(QUEST_ITEM_LOCATIONS.get(item_id, "未知位置"))])
    return "\n".join(lines)


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
    return market_quest_hud_text()


func market_quest_hud_text() -> String:
    var navigation := "✓" if has_quest_item("market_navigation_module") else "○"
    return "导航线索 · 民用导航模块%s" % navigation


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
    controller._update_hud()
    var label := quest_item_label(item_id)
    var hospital_count := 0
    for id: String in HOSPITAL_QUEST_ITEMS.keys():
        if has_quest_item(id):
            hospital_count += 1
    if hospital_count >= HOSPITAL_QUEST_ITEMS.size():
        controller.show_feedback_rpc.rpc("医院支线完成 · 病历 / 稳定剂 / 门禁卡已集齐", Color("#9ff5c9"), 3.0)
        controller._record_journal("医院支线完成", "三件医院线索已集齐：镇静实验病历、低温稳定剂、能源站门禁卡。可以回配电间门外通过门禁通讯向工程师/医生对质，或前往能源站深层。")
    else:
        controller.show_feedback_rpc.rpc("取得任务物 · %s" % label, Color("#9ff5c9"), 2.4)
    match item_id:
        "patient_records":
            controller._record_journal("任务物 · 镇静实验病历", "镇静剂只能压住运动，压不住菌群。医院在爆发初期把病人固定在病床上反复注射，后来护士也开始重复同样的动作。")
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
    if inside_kind == "market":
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
    controller._update_hud()
    var label := quest_item_label(item_id)
    var nav_count := 0
    for id: String in NAVIGATION_QUEST_ITEMS.keys():
        if has_quest_item(id):
            nav_count += 1
    if nav_count >= NAVIGATION_QUEST_ITEMS.size():
        controller.show_feedback_rpc.rpc("导航密钥完成 · 民用导航模块", Color("#9ff5c9"), 3.2)
        controller._record_journal("导航密钥拼合完成", "超市运输无人机导航模块保存着离开腐墟星的安全跃迁路线。")
    else:
        controller.show_feedback_rpc.rpc("取得任务物 · %s" % label, Color("#9ff5c9"), 2.4)
    match item_id:
        "market_navigation_module":
            controller._record_journal("任务物 · 民用导航模块", "超市仓库里的旧运输无人机导航模块。保存着殖民城地下管线和能源站应急入口的坐标。")
    controller.sync_ruin_progress.rpc(snapshot())


func _collect_energy_core(peer_id: int) -> void:
    if not controller.is_host or energy_station_interior == null or quest_items.has("reactor_core"):
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or not is_inside_energy_station(player.global_position):
        return
    if not has_quest_item("energy_access_card"):
        controller.show_feedback_rpc.rpc("应急舱锁着 · 需要能源站门禁卡 E-07", Color("#ffbd75"), 2.4)
        return
    var points: Dictionary = energy_station_interior.call("task_item_positions")
    if not points.has("reactor_core") or player.global_position.distance_to(points["reactor_core"]) > 2.8:
        return
    quest_items["reactor_core"] = true
    energy_station_interior.call("collect_task_item", "reactor_core")
    controller._update_hud()
    controller.show_feedback_rpc.rpc("取得任务物 · 星髓点火芯", Color("#9ff5c9"), 2.2)
    controller._record_journal("任务物 · 星髓点火芯", "从 B2 应急弹射舱取出的点火芯。它是星髓菌群的代谢结晶，不是普通电池；没有低温稳定剂就会在重启时过热。")
    _refresh_story_stage()
    controller.sync_ruin_progress.rpc(snapshot())


func story_ready() -> bool:
    return has_quest_item("coolant_stabilizer") \
        and has_quest_item("market_navigation_module") \
        and has_quest_item("reactor_core")


func story_missing_text() -> String:
    var missing: Array[String] = []
    if not has_quest_item("coolant_stabilizer"):
        missing.append("低温稳定剂（医院 B1）")
    if not has_quest_item("energy_access_card"):
        missing.append("E-07 门禁卡（医院 1F）")
    if not has_quest_item("reactor_core"):
        missing.append("星髓点火芯（能源站 B2）")
    if not has_quest_item("market_navigation_module"):
        missing.append("民用导航模块（超市 2F）")
    return "还缺：" + "、".join(missing)


func story_objective_text() -> String:
    if story_ending != "":
        return string_ending_title(story_ending)
    if story_plan == "engineer":
        return "快速重启 · 在 %02d:%02d 前登艇" % [int(story_timer / 60.0), int(story_timer) % 60]
    if story_plan == "doctor":
        if not bool(story_flags.get("pump_shutdown", false)):
            return "医生的方案 · 能源站 B1 泵房：关闭菌群泵"
        if not bool(story_flags.get("reactor_restarted", false)):
            return "菌群泵已关闭 · 能源站 B2 反应堆控制台：转动手轮重启主反应堆"
        if not bool(story_flags.get("launch_key", false)):
            return "反应堆已重启 · 回庇护所/配电间门外通讯，领取跃迁钥匙"
        return "跃迁钥匙已到手 · 回登陆艇撤离"
    if story_plan == "leave":
        return "隐瞒真相 · 回登陆艇直接离开"
    if not bool(story_flags.get("met_engineer", false)) or not bool(story_flags.get("met_doctor", false)):
        return "能源站 1F · 核心井北侧：到配电间门外使用门禁通讯\n分别和老工程师、年轻医生通话"
    if story_ready():
        return "点火三件套已齐 · 回配电间门外用门禁通讯决定撤离方案"
    # 推荐顺序，但仍然允许玩家自由探索；只把"下一步最该做什么"说清楚。
    if not has_quest_item("coolant_stabilizer"):
        return "医院 B1 西侧药库：取低温稳定剂\n医院 1F 保安室：拿 E-07 门禁卡"
    if not has_quest_item("energy_access_card") and not has_quest_item("reactor_core"):
        return "能源站 B2 应急舱：取星髓点火芯\n路线：1F 西侧楼梯 → B1 → B2，需要 E-07 门禁卡"
    if not has_quest_item("reactor_core"):
        return "能源站 B2 应急舱：取星髓点火芯\n路线：1F 西侧楼梯 → B1 → B2"
    if not has_quest_item("market_navigation_module"):
        return "超市 2F 办公室：取民用导航模块"
    return "搜集撤离三件套 · " + story_missing_text()


func story_hud_text() -> String:
    return "剧情：" + story_objective_text()


func string_ending_title(id: String) -> String:
    match id:
        "engineer":
            return "结局 · 快速重启：星球毁灭"
        "true":
            return "结局 · 关闭菌群泵：星球保住"
        "leave":
            return "结局 · 隐瞒真相：迫降未知星球"
        "destroyed":
            return "结局 · 超时：地表彻底沦陷"
    return "结局 · " + id


func _refresh_story_stage() -> void:
    if story_ending != "":
        return
    if story_ready() and story_plan == "":
        story_stage = "ready"


func _needs_launch_key() -> bool:
    return story_plan == "doctor" \
        and bool(story_flags.get("reactor_restarted", false)) \
        and not bool(story_flags.get("launch_key", false))


func _grant_launch_key(peer_id: int) -> void:
    if not _needs_launch_key():
        return
    story_flags["launch_key"] = true
    story_stage = "extraction"
    if controller._items != null:
        controller._items.add_item(peer_id, "launch_key", -1, {}, true)
        controller._items.publish()
    set_extraction_active(true)
    controller.show_feedback_rpc.rpc("取得关键道具 · 跃迁钥匙 · 回登陆艇撤离", Color("#9ff5c9"), 4.0)
    controller._record_journal("关键道具 · 跃迁钥匙", "庇护所联络人把跃迁钥匙交给你。登陆艇的跃迁电池已经充满，现在回登陆艇才算真正离开腐墟星。")
    controller.sync_ruin_progress.rpc(snapshot())


func open_shelter_dialogue(peer_id: int, npc_id: String = "") -> void:
    if not controller.is_host or shelter_interior == null:
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return
    var inside := is_inside_shelter(player.global_position)
    var near_intercom := false
    if energy_station_interior != null:
        var door_point: Vector3 = energy_station_interior.call("secret_door_position")
        near_intercom = player.global_position.distance_to(door_point) <= 3.2
    if not inside and not near_intercom:
        return
    # 第一次接通门禁通讯后，任务栏才显示六件任务道具及其位置。
    story_flags["quest_intel"] = true
    controller._update_hud()
    var engineer := npc_id == "engineer"
    var doctor := npc_id == "doctor"
    if not engineer and not doctor:
        var engineer_met := bool(story_flags.get("met_engineer", false))
        var doctor_met := bool(story_flags.get("met_doctor", false))
        if not engineer_met:
            npc_id = "engineer"
        elif not doctor_met:
            npc_id = "doctor"
        else:
            var talk_count := int(story_flags.get("shelter_talk_count", 0))
            npc_id = "engineer" if talk_count % 2 == 0 else "doctor"
        engineer = npc_id == "engineer"
    if inside:
        var npcs: Dictionary = shelter_npc_positions()
        if not npcs.has(npc_id):
            return
        if player.global_position.distance_to(npcs[npc_id]) > 3.0:
            return
    var met_key := "met_engineer" if engineer else "met_doctor"
    var met := bool(story_flags.get(met_key, false))
    var both_met := bool(story_flags.get("met_engineer", false)) and bool(story_flags.get("met_doctor", false))
    var body := ""
    var options: Array[String] = []
    if _needs_launch_key():
        body = "反应堆已经平稳重启，登陆艇电池正在充电。\n但跃迁钥匙还在我手里——没有它，你走不了。\n回来拿钥匙，再回登陆艇。"
        options = ["领取跃迁钥匙"]
        controller.show_ruin_dialogue(peer_id, npc_id, "【当前目标】" + story_objective_text().replace("\n", "  ·  ") + "\n\n" + body, options)
        return
    if not met:
        if engineer:
            body = "你终于从地表下来了。登陆艇的跃迁电池已经死了，这颗星上只有能源站的主反应堆还能给它充电。\n反应堆在爆发时紧急停堆，点火芯弹进了 B2 应急舱——用医院 1F 的 E-07 门禁卡能开。还要医院 B1 的低温稳定剂，不然点火芯会过热；学校天文台和超市仓库的导航件拼成导航密钥，船才跳得出去。\n别信医生那套‘先关泵’——我们没有时间。"
        else:
            body = "别急着听工程师的。点火芯是星髓菌群的代谢结晶，不是一块干净电池；重启会把地下菌群一起激活，三十年前那次喷发就是这么来的。\n医院 B1 有低温稳定剂，1F 有 E-07 门禁卡，2F 的镇静实验病历能证明镇静剂对菌群无效。学校和超市的导航件也带上，那是我们唯一的出路。\n先关掉 B1 的菌群泵，再重启，星球还有救。"
        options = ["我会回来"]
    elif story_ready() and not both_met:
        body = "点火芯、稳定剂、导航密钥都在你手上，但先和另一边把话谈完。\n撤离方案需要工程师和医生都在场——一个知道反应堆怎么点，一个知道点了之后会发生什么。"
        options = ["我会回来"]
    elif story_ready():
        if engineer:
            body = "点火三件套齐了。现在就能重启。医生会说会激活菌群，但她没有证据。\n你选哪条路？"
            if has_quest_item("patient_records"):
                body += "\n还有那张病历……当年签字同意深层钻探的人是我。等这次结束，我会给你一个交代。"
        else:
            body = "核心、稳定剂、导航密钥都在你手上。先关 B1 菌群泵，再回 B2 重启，然后回登陆艇。\n工程师的方案更快，但会把整颗星球烧掉。"
        options = ["按工程师方案：立即重启", "按医生方案：先关菌群泵", "隐瞒真相：直接离开"]
    else:
        body = "东西还没齐。\n" + story_missing_text()
        if engineer and has_quest_item("patient_records"):
            body += "\n还有那张病历……当年签字同意钻探的人是我。等这次结束，我会给你一个交代。"
        options = ["继续搜索"]
    controller.show_ruin_dialogue(peer_id, npc_id, "【当前目标】" + story_objective_text().replace("\n", "  ·  ") + "\n\n" + body, options)


func choose_shelter_dialogue(peer_id: int, npc_id: String, index: int) -> void:
    if not controller.is_host:
        return
    story_flags["shelter_talk_count"] = int(story_flags.get("shelter_talk_count", 0)) + 1
    var met_key := "met_engineer" if npc_id == "engineer" else "met_doctor"
    if not bool(story_flags.get(met_key, false)):
        story_flags[met_key] = true
        if story_stage == "start":
            story_stage = "explore"
        if not bool(story_flags.get("met_engineer", false)) or not bool(story_flags.get("met_doctor", false)):
            controller.show_feedback_rpc.rpc("庇护所已建立联系 · 继续搜集点火三件套", Color("#9ff5c9"), 2.4)
        else:
            controller.show_feedback_rpc.rpc("庇护所已建立联系 · 工程师和医生都在等你带回点火三件套", Color("#9ff5c9"), 2.4)
        controller.hide_ruin_dialogue(peer_id)
        _refresh_story_stage()
        controller.sync_ruin_progress.rpc(snapshot())
        return
    if _needs_launch_key():
        if index == 0:
            _grant_launch_key(peer_id)
        controller.hide_ruin_dialogue(peer_id)
        return
    if not story_ready():
        controller.hide_ruin_dialogue(peer_id)
        return
    if not (bool(story_flags.get("met_engineer", false)) and bool(story_flags.get("met_doctor", false))):
        controller.hide_ruin_dialogue(peer_id)
        return
    if index == 2:
        _apply_story_plan("leave")
    elif index == 0:
        _apply_story_plan("engineer" if npc_id == "engineer" else "doctor")
    elif index == 1:
        _apply_story_plan("doctor" if npc_id == "engineer" else "engineer")
    controller.hide_ruin_dialogue(peer_id)


func _apply_story_plan(plan: String) -> void:
    if story_ending != "":
        return
    story_plan = plan
    match plan:
        "engineer":
            story_stage = "restart"
            story_timer = 180.0
            set_extraction_active(true)
            controller.show_feedback_rpc.rpc("工程师方案启动 · 反应堆正在重启，180 秒内登艇", Color("#ffbd75"), 4.0)
            controller._record_journal("方案 · 快速重启", "老工程师坚持立刻重启。主反应堆开始过载，地下菌群被激活；必须在他给出的 180 秒内回到登陆艇。")
        "doctor":
            story_stage = "pump"
            controller.show_feedback_rpc.rpc("医生方案 · 先去 B1 关闭菌群泵，再重启反应堆", Color("#9ff5c9"), 4.0)
            controller._record_journal("方案 · 先关菌群泵", "医生要求先手动关闭 B1 的菌群泵，阻断菌群随循环系统上涌；然后才允许重启主反应堆。")
        "leave":
            story_stage = "leave"
            set_extraction_active(true)
            controller.show_feedback_rpc.rpc("隐瞒真相 · 直接登艇离开，不重启反应堆", Color("#ffbd75"), 4.0)
            controller._record_journal("方案 · 隐瞒真相", "不重启反应堆，也不关闭菌群泵。带着三件套和导航密钥直接离开，飞船能源不足，只能迫降附近星球。")
    controller.sync_ruin_progress.rpc(snapshot())


func _turn_energy_wheel(peer_id: int, kind: String) -> void:
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or energy_station_interior == null or not is_inside_energy_station(player.global_position):
        return
    if kind == "reactor" and not bool(story_flags.get("pump_shutdown", false)):
        controller.show_feedback_rpc.rpc("菌群泵还没关闭，反应堆手轮被机械锁死。", Color("#ffbd75"), 2.2)
        return
    var console_point: Vector3 = energy_station_interior.call("pump_console_position") if kind == "pump" else energy_station_interior.call("reactor_console_position")
    if player.global_position.distance_to(console_point) > 2.8:
        return
    var key := "pump_wheel" if kind == "pump" else "reactor_wheel"
    var progress := clampf(float(story_flags.get(key, 0.0)) + ENERGY_WHEEL_STEP, 0.0, 1.0)
    story_flags[key] = progress
    energy_station_interior.call("turn_energy_wheel", kind, progress)
    if progress < 0.999:
        controller.show_feedback_rpc.rpc("转动手轮 · %d%%" % int(round(progress * 100.0)), Color("#ffd28a"), 0.7)
        controller.sync_ruin_progress.rpc(snapshot())
        return
    if kind == "pump":
        _shutdown_colony_pump(peer_id)
    else:
        _restart_reactor_after_pump(peer_id)


func _shutdown_colony_pump(peer_id: int) -> void:
    if story_plan != "doctor" or bool(story_flags.get("pump_shutdown", false)):
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or not is_inside_energy_station(player.global_position):
        return
    story_flags["pump_shutdown"] = true
    story_stage = "reactor"
    controller.show_feedback_rpc.rpc("菌群泵已关闭 · 回 B2 重启主反应堆", Color("#9ff5c9"), 3.0)
    controller._record_journal("菌群泵已关闭", "B1 菌群泵停机。地下菌群暂时停止随循环系统上涌；现在重启反应堆不会引发二次喷发。")
    controller.sync_ruin_progress.rpc(snapshot())


func _restart_reactor_after_pump(peer_id: int) -> void:
    if story_plan != "doctor" or not bool(story_flags.get("pump_shutdown", false)):
        controller.show_feedback_rpc.rpc("菌群泵还没关闭，不能重启。", Color("#ffbd75"), 2.4)
        return
    if bool(story_flags.get("reactor_restarted", false)):
        controller.show_feedback_rpc.rpc("主反应堆已经重启 · 回登陆艇撤离。", Color("#9ff5c9"), 2.4)
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or not is_inside_energy_station(player.global_position):
        return
    # 重启不是终点：登陆艇还要从反应堆接收充电，玩家必须回艇按 E 才算离开。
    story_flags["reactor_restarted"] = true
    story_stage = "return_dialogue"
    set_extraction_active(false)
    controller.show_feedback_rpc.rpc("主反应堆平稳重启 · 回配电间门外通讯领取跃迁钥匙", Color("#9ff5c9"), 4.0)
    controller._record_journal("主反应堆已重启", "菌群泵停机后反应堆平稳重启，登陆艇的跃迁电池开始充电。但跃迁钥匙还在庇护所联络人手里，必须先回去通讯。")
    controller.sync_ruin_progress.rpc(snapshot())


func finish_story_ending(ending_id: String) -> void:
    if story_ending != "":
        return
    story_ending = ending_id
    story_stage = "ended"
    story_timer = 0.0
    _story_return_timer = 6.0
    controller.ending_choice = ending_id
    var title := string_ending_title(ending_id)
    var body := ""
    match ending_id:
        "engineer":
            body = "反应堆粗暴重启，点火芯过热，地表在几分钟内被菌群二次喷发吞没。登陆艇在冲击波前升空，腐墟星从星图上消失。"
        "true":
            body = "菌群泵停机后反应堆平稳重启，星髓点火芯给登陆艇充满跃迁电池。地下菌群退回深层，殖民城保住了。工程师承认了当年的签字，医生把样本留在原地。"
        "leave":
            body = "你没有重启反应堆，点火芯也没能给登陆艇充电。登陆艇带着导航密钥强行离开，但能源不足，只能迫降附近星球。"
        "destroyed":
            body = "倒计时结束，反应堆熔毁引发菌群喷发。登陆艇没能起飞，腐墟星地表彻底沦陷。"
    controller.show_feedback_rpc.rpc(title, Color("#ffbd75") if ending_id != "true" else Color("#9ff5c9"), 6.0)
    controller._record_journal(title, body)
    controller.sync_ruin_progress.rpc(snapshot())


func _tick_story(delta: float) -> void:
    if not controller.is_host:
        return
    if story_ending != "":
        if _story_return_timer > 0.0:
            _story_return_timer -= delta
            if _story_return_timer <= 0.0:
                _story_return_timer = -1.0
                var title := string_ending_title(story_ending)
                controller.return_to_ship.rpc("腐墟星 · %s" % title, controller._vitals_snapshot())
        return
    if story_plan == "engineer" and story_stage == "restart":
        story_timer = maxf(0.0, story_timer - delta)
        if story_timer <= 0.0:
            finish_story_ending("destroyed")


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
    if story_plan == "engineer" or story_plan == "leave":
        return true
    if story_plan == "doctor" and bool(story_flags.get("reactor_restarted", false)):
        return bool(story_flags.get("launch_key", false))
    if story_ending != "":
        return true
    return taken_food.size() >= OBJECTIVE_FOOD and discovered_buildings.size() >= OBJECTIVE_BUILDINGS


func objective_text() -> String:
    return story_objective_text()


## 登陆艇状态：未开放时橙色，开放后青绿灯带 + 灯光转青绿。
func set_extraction_active(active: bool) -> void:
    if is_instance_valid(_pad_active_ring):
        _pad_active_ring.visible = active
    var color: Color = ART.TEAL_LIGHT if active else ART.ORANGE
    var energy: float = 1.1 if active else 0.9
    for light in _pad_lights:
        if is_instance_valid(light):
            light.material_override = ART.material(color, true, energy)
    _update_physical_links(true)


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
        # 返航/收起世界时暂停微尘与蒸汽，避免在主舱里空转。
        for particle in world_root.find_children("*", "CPUParticles3D", true, false):
            (particle as CPUParticles3D).emitting = value
        # 感染体挂在 Main3D 下而不是 world_root 下，需要单独处理。
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
    return {
        "taken_food": taken_food,
        "buildings": discovered_buildings,
        "unlocked": unlocked_buildings,
        "quest_items": quest_items.keys(),
        "story": {
            "flags": story_flags.duplicate(true),
            "plan": story_plan,
            "stage": story_stage,
            "timer": story_timer,
            "ending": story_ending,
        },
    }


func apply_snapshot(data: Dictionary) -> void:
    taken_food.assign(data.get("taken_food", []))
    discovered_buildings.assign(data.get("buildings", []))
    unlocked_buildings.assign(data.get("unlocked", []))
    unlocked_buildings.erase("library")
    quest_items.clear()
    for id in data.get("quest_items", []):
        quest_items[String(id)] = true
        if hospital_interior != null:
            hospital_interior.call("collect_task_item", String(id))
        if school_interior != null:
            school_interior.call("collect_task_item", String(id))
        if market_interior != null:
            market_interior.call("collect_task_item", String(id))
        if energy_station_interior != null:
            energy_station_interior.call("collect_task_item", String(id))
    var story: Dictionary = data.get("story", {})
    story_flags = (story.get("flags", {}) as Dictionary).duplicate(true)
    story_plan = String(story.get("plan", ""))
    story_stage = String(story.get("stage", "start"))
    story_timer = float(story.get("timer", 0.0))
    story_ending = String(story.get("ending", ""))
    if story_ending != "":
        _story_return_timer = -1.0
    # 客户端也要看到登陆艇已开放：工程师/离开方案，或医生方案已重启反应堆。
    set_extraction_active(story_plan in ["engineer", "leave"] or bool(story_flags.get("launch_key", false)))
    if energy_station_interior != null:
        energy_station_interior.call("turn_energy_wheel", "pump", float(story_flags.get("pump_wheel", 0.0)))
        energy_station_interior.call("turn_energy_wheel", "reactor", float(story_flags.get("reactor_wheel", 0.0)))
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
