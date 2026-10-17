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

# 腐墟星用自己的感染体脚本（三种丧尸造型）；霜烬星仍然用 enemy_3d.tscn，互不影响。
const RUIN_INFECTED := preload("res://scripts/ruin_infected_3d.gd")
# 废弃超市的外形单独成一个模块；医院和学校仍走下面的通用方盒流程。
const RUIN_MARKET := preload("res://scripts/ruin_market_building.gd")
# 医院也有自己的外形模块：四层病房楼 + 两层门诊翼 + 急救车雨棚。
const RUIN_HOSPITAL := preload("res://scripts/ruin_hospital_building.gd")

# ── 布局 ──
# 建筑只做外壳：体块 + 招牌 + 门口交互点。内部子地图留待下一轮。
const BUILDINGS := [
    # 5 座建筑，按四个象限 + 北侧各放一处，彼此拉开。
    # 出生点在西南、撤离点在东南，所以南侧中间留空作为集散区。
    {"id": "market", "name": "万家福超市", "position": Vector2(-40.0, -24.0), "size": Vector3(24.0, 7.0, 14.0), "accent": Color("#c9a35a")},
    {"id": "hospital", "name": "废弃医院", "position": Vector2(40.0, -30.0), "size": Vector3(26.0, 11.0, 19.0), "accent": Color("#c76b6b")},
    {"id": "school", "name": "废弃学校", "position": Vector2(-62.0, 16.0), "size": Vector3(23.0, 8.0, 15.0), "accent": Color("#6fb4c9")},
    # ── 占位建筑 ──
    # 走通用灰盒流程（外壳 + 屋顶收边 + 屋顶设备 + 招牌 + 门洞）。
    # 之后补建模时，像超市那样在 _build_buildings() 里加一条 id 分支即可。
    {"id": "library", "name": "市立图书馆", "position": Vector2(64.0, 24.0), "size": Vector3(20.0, 10.0, 15.0), "accent": Color("#7f9cd6")},
    {"id": "gas_station", "name": "停业加油站", "position": Vector2(2.0, -44.0), "size": Vector3(14.0, 7.0, 13.0), "accent": Color("#5fa88c")},
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

# ── 环境补光 ──
# 建筑之间几盏极暗的紫色点光。它们不负责照明（真正的主光是 RuinSun），
# 只用来把大块空地压出层次，所以能量刻意压得很低、范围也很小。
const FILL_LIGHTS := [
    {"position": Vector3(0.0, 4.5, 0.0), "energy": 2.0, "range": 26.0, "color": Color("#6b4a8f")},
    {"position": Vector3(-32.0, 3.5, -1.0), "energy": 1.2, "range": 18.0, "color": Color("#5c3f7d")},
    {"position": Vector3(13.0, 3.5, 1.0), "energy": 1.2, "range": 18.0, "color": Color("#6b4a8f")},
    {"position": Vector3(-44.0, 3.0, 14.0), "energy": 0.9, "range": 16.0, "color": Color("#5c3f7d")},
    # 地图扩大后补的两盏，避免新加的占位建筑落在一片死黑的空地上。
    {"position": Vector3(-62.0, 3.5, -30.0), "energy": 1.0, "range": 20.0, "color": Color("#5c3f7d")},
    {"position": Vector3(58.0, 3.5, 34.0), "energy": 1.0, "range": 20.0, "color": Color("#6b4a8f")},
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
var buildings: Dictionary = {}
var food_sites: Dictionary = {}
var zombies: Dictionary = {}
var noise: Dictionary = {}
var taken_food: Array[String] = []
var discovered_buildings: Array[String] = []
var search_jobs: Dictionary = {}
var pending_message := ""
var next_zombie_id := 1
var _spawn_timer := 0.0
var _sync_timer := 0.0
var _spawn_rng := RandomNumberGenerator.new()
var _form_bag: Array = []
var _environment: Environment
var _time := 0.0


func _init(owner: Node3D) -> void:
    controller = owner


func build() -> void:
    reset()
    _build_scaffold()
    _build_buildings()
    _build_food_sites()
    # 不再一次性刷三只：落地后先随机等一会儿，之后逐只出现。
    _spawn_timer = _spawn_rng.randf_range(ZOMBIE_FIRST_DELAY.x, ZOMBIE_FIRST_DELAY.y)


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
    _spawn_timer = 0.0
    _sync_timer = 0.0
    _form_bag.clear()
    _spawn_rng.randomize()
    _environment = null
    _time = 0.0


# ── 构建 ──

func _build_scaffold() -> void:
    # 腐墟星用自己的光照和地面：登陆时霜烬星的世界根会被整体隐藏，
    # 那边的 Environment 和地面一并不可见，所以这里必须自带一套。
    world_root = Node3D.new()
    world_root.name = "RuinWorld3D"
    controller.add_child(world_root)

    # 腐墟星自己的环境：暗紫、低照度、带紫雾。
    # 注意这里同时挂了一份 WorldEnvironment 和一份相机级覆盖（见
    # _apply_camera_environment）。原因是场景里同时存在飞船主舱、霜烬星和
    # 腐墟星三套 WorldEnvironment，谁生效不受控；相机级 environment 才是
    # 唯一确定的覆盖方式，WorldEnvironment 只是给没走到相机覆盖时的兜底。
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#150d1c")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#4a2f5e")
    env.ambient_light_energy = 0.55
    env.fog_enabled = true
    env.fog_light_color = Color("#2a1836")
    env.fog_light_energy = 0.7
    env.fog_density = 0.010
    env.glow_enabled = true
    env.glow_intensity = 0.22
    env.glow_hdr_threshold = 1.15
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    _environment = env
    var environment := WorldEnvironment.new()
    environment.name = "RuinEnvironment"
    environment.environment = env
    world_root.add_child(environment)

    var light := DirectionalLight3D.new()
    light.name = "RuinSun"
    light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
    light.light_energy = 1.20
    light.light_color = Color("#c3b2d6")
    # 方向光阴影在这个场景里只会带来麻烦：环境光是深紫色，阴影区被压成
    # 一块边界生硬的黑斑，玩家会读成「建筑旁边多长了一块黑色几何体」，
    # 而且阴影贴图随镜头移动会让它忽明忽暗。
    # 低模卡通风格本来就不依赖实时投影，接地感交给 art_utils 的接触阴影，
    # 所以这里直接关掉。
    light.shadow_enabled = false
    # 屋顶发黑（像穿模）的根因：
    # DirectionalLight3D 的 shadow max distance 默认是 4000 米，而这张地图
    # 只有 116×80 米，阴影贴图的分辨率几乎全浪费在地图之外。屋顶这种大面积
    # 水平面会出现自阴影黑斑（shadow acne），而且 PSSM 分割随镜头移动，
    # 所以表现为「往上走时最下面那栋的屋顶突然变黑」。
    # 把阴影距离收到地图尺度，并抬高 bias 消除自阴影。
    light.directional_shadow_max_distance = 140.0
    light.shadow_bias = 0.08
    light.shadow_normal_bias = 1.6
    # 环境光是深紫色（#4a2f5e × 0.55），所以完全遮挡的阴影区会压成纯黑，
    # 再叠 ACES 色调映射后变成边缘生硬的黑块，看起来就像建筑多长了一块黑色几何体。
    # 把阴影做成半透明并柔化边缘，让暗部保留一点环境色。
    light.shadow_opacity = 0.5
    light.light_angular_distance = 2.5
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

    # 可见地面比可行走范围再外扩一圈：镜头是正交 28 米、46° 俯角，
    # 走到地图边缘时画面会拍到边界外，没有这圈就会露出背景色（一条黑边）。
    var ground_mesh := BoxMesh.new()
    ground_mesh.size = Vector3(GROUND_EXTENT.x * 2.0 + 60.0, 1.0, GROUND_EXTENT.y * 2.0 + 60.0)
    var ground := MeshInstance3D.new()
    ground.name = "RuinGroundMesh"
    ground.mesh = ground_mesh
    ground.position = Vector3(0.0, -0.5, 0.0)
    ground.material_override = controller._material(Color("#4a4f42"))
    world_root.add_child(ground)
    _build_ground_detail()

    # 建筑之间的暗紫补光
    for raw in FILL_LIGHTS:
        var fill := OmniLight3D.new()
        fill.name = "RuinFill"
        fill.position = Vector3(raw.position)
        fill.light_color = raw.color
        fill.light_energy = float(raw.energy)
        fill.omni_range = float(raw.range)
        world_root.add_child(fill)


## 地面细节层。
## 原来整块地面是一个单色盒子，46° 俯视下没有任何信息量，紫雾一压就糊成一片。
## 这里在同一位置叠一层细分网格，用顶点色画出斑驳、湿痕和靠近建筑的污渍。
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
    for point in [a, b, c, a, c, d]:
        st.set_color(_ground_tint(patch, grain, point))
        st.add_vertex(Vector3(point.x, 0.0, point.y))


func _ground_tint(patch: FastNoiseLite, grain: FastNoiseLite, point: Vector2) -> Color:
    var color := Color("#4a4f42")
    # 大块斑驳：一半压向潮湿的深色，一半提向干燥的浅色
    var low := (patch.get_noise_2d(point.x, point.y) + 1.0) * 0.5
    color = color.lerp(Color("#232a21"), low * 0.75)
    color = color.lerp(Color("#6f7659"), maxf(1.0 - low * 1.5, 0.0) * 0.55)
    # 细颗粒
    var g := grain.get_noise_2d(point.x, point.y)
    if g > 0.0:
        color = color.lerp(color.lightened(0.10), g * 0.55)
    else:
        color = color.lerp(color.darkened(0.10), -g * 0.55)
    # 低洼积水：细噪声的高值处压成近乎黑的湿痕
    if g > 0.42:
        color = color.lerp(Color("#151a16"), clampf((g - 0.42) * 1.6, 0.0, 0.80))
    # 建筑周边的污渍：暗红褐色，离得越近越重，读作积灰、渗液和干涸的血
    for raw in BUILDINGS:
        var center := Vector2(raw.position)
        var size := Vector3(raw.size)
        var reach := maxf(size.x, size.z) * 0.75 + 7.0
        var distance := point.distance_to(center)
        if distance < reach:
            var weight := (1.0 - distance / reach) * 0.65
            color = color.lerp(Color("#4a2224"), weight)
    return color


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
            buildings[id] = {
                "root": root,
                "entry": root.position + Vector3(0.0, 0.0, size.z * 0.5 + 1.6),
                "name": String(raw.name),
                "ring": market.entry_ring,
            }
            continue
        # 医院：四层病房楼 + 两层门诊翼 + 急救车雨棚 + 停机坪。
        # 大门在本地 x=-4 的位置，交互点也要跟着偏过去，否则玩家站在楼中心
        # 会离门口 4 米、超出进入半径。
        if id == "hospital":
            var hospital := RUIN_HOSPITAL.new()
            hospital.build(root, size, accent, controller)
            buildings[id] = {
                "root": root,
                "entry": root.position + Vector3(-4.0, 0.0, size.z * 0.5 + 1.6),
                "name": String(raw.name),
                "ring": hospital.entry_ring,
            }
            continue
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
        # 屋顶压边。
        # 原来屋顶是一整块和墙面同色的平板，正交俯视下就是一大片纯色矩形，
        # 檐口被屏幕底边或 HUD 切到时看起来像 UI 盖住了屋顶。
        # 这里把顶面压暗、再加一圈更亮的收边，让它读起来是「屋顶」而不是一块板。
        _box(root, "Roof", Vector3(size.x + 1.2, 0.6, size.z + 1.2), Vector3(0.0, size.y + 0.1, 0.0), Color("#454c59"))
        # 收边必须是四条边框而不是一块更大的实心板：实心板会从上方把整个屋顶盖住，
        # 反而让屋顶更平。四条边框才能露出中间的深色顶面。
        var rim_y: float = size.y + 0.42
        var roof_half_x: float = (size.x + 1.2) * 0.5
        var roof_half_z: float = (size.z + 1.2) * 0.5
        var rim_thickness := 0.45
        var rim_color := Color("#96a4b6")
        _box(root, "RoofRimN", Vector3(size.x + 1.2, 0.12, rim_thickness), Vector3(0.0, rim_y, -roof_half_z + rim_thickness * 0.5), rim_color)
        _box(root, "RoofRimS", Vector3(size.x + 1.2, 0.12, rim_thickness), Vector3(0.0, rim_y, roof_half_z - rim_thickness * 0.5), rim_color)
        _box(root, "RoofRimW", Vector3(rim_thickness, 0.12, size.z + 1.2 - rim_thickness * 2.0), Vector3(-roof_half_x + rim_thickness * 0.5, rim_y, 0.0), rim_color)
        _box(root, "RoofRimE", Vector3(rim_thickness, 0.12, size.z + 1.2 - rim_thickness * 2.0), Vector3(roof_half_x - rim_thickness * 0.5, rim_y, 0.0), rim_color)
        # 屋顶设备。
        # 俯视正交下一栋建筑只剩一块纯色矩形，玩家会把它读成「盖在画面上的
        # 文字框」而不是屋顶。加上几件屋顶设备后，轮廓和层次一眼可辨。
        var roof_top: float = size.y + 0.48
        _box(root, "RoofVentA", Vector3(1.8, 0.6, 1.8), Vector3(-roof_half_x * 0.42, roof_top + 0.30, -roof_half_z * 0.34), Color("#555d6b"))
        _box(root, "RoofVentA_Cap", Vector3(2.1, 0.12, 2.1), Vector3(-roof_half_x * 0.42, roof_top + 0.62, -roof_half_z * 0.34), Color("#8e9aab"))
        _box(root, "RoofDuct", Vector3(1.1, 0.42, 2.6), Vector3(roof_half_x * 0.46, roof_top + 0.21, roof_half_z * 0.10), Color("#4b5361"))
        _box(root, "RoofHatch", Vector3(1.5, 0.24, 1.5), Vector3(roof_half_x * 0.16, roof_top + 0.12, -roof_half_z * 0.40), Color("#77818f"))
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
    enemy.position = Vector3(point.x, 0.0, point.y)
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
        if camera != null and camera.environment != _environment:
            camera.environment = _environment


func _clear_camera_environment() -> void:
    if _environment == null:
        return
    for peer_id in controller.players.keys():
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player == null:
            continue
        var camera := player._camera
        if camera != null and camera.environment == _environment:
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
    if not controller.is_host:
        return
    _tick_noise(delta)
    _tick_search(delta)
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
