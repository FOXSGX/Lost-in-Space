extends RefCounted

# 腐墟星「废弃超市」的外形。
#
# 只属于 planet-02，不改通用建筑生成，医院和学校仍然走原来的方盒流程。
#
# 造型参考了废土/生存类游戏里常见的大型超市：
#   - 主体不是一整块方盒，而是「一层大卖场 + 一端两层办公楼」的高低错落，
#     两段不同高度 + 一道楼层腰线，俯视一眼就能和另外两栋方块楼分开；
#   - 正立面是一条通长的玻璃店面，其中几块碎了、一块用木板钉死；
#   - 入口上方是外挑的雨棚和招牌，雨棚有一侧下垂；
#   - 屋顶有空调机组、风管、检修口、水箱和楼梯间，不是一块平板；
#   - 门前有停车位划线、弯掉的路灯、散落的购物车和托盘。
#
# 尺寸约定：root 在建筑中心，正面朝 +Z；size 只用来取占地进深，
# 玩家实际能站的门口仍然是 root.position + (0, 0, size.z/2 + 1.6)。

var controller: Node3D
var root: Node3D
var accent := Color("#c9a35a")
var entry_ring: MeshInstance3D

const SHELL := Color("#7d8794")
const SHELL_DARK := Color("#6e7783")
const PLINTH := Color("#4e5561")
const ROOF := Color("#454c59")
const RIM := Color("#96a4b6")
const METAL := Color("#555d6b")
const METAL_LIGHT := Color("#8e9aab")
const FRAME := Color("#8b95a3")
const GLASS := Color("#1b2531")
const HOLE := Color("#20262b")
const AWNING := Color("#7d4038")
const RUST := Color("#7a5140")
const WOOD := Color("#5a4a3a")


func build(building_root: Node3D, size: Vector3, accent_color: Color, owner: Node3D) -> void:
    root = building_root
    accent = accent_color
    controller = owner

    var half_z: float = size.z * 0.5
    _build_two_story_block()
    _build_main_hall()
    _build_storefront(half_z)
    _build_entrance(half_z)
    _build_roofs()
    _build_wall_details()
    _build_surface_age()
    _build_stains(half_z)
    _build_damage(half_z)
    _build_side_props(half_z)
    _build_parking_lot()
    _build_collision(size)
    entry_ring = _mesh(root, "EntryRing", _torus(1.5, 1.56), Vector3(0.0, 0.08, half_z + 1.6), accent, true)
    entry_ring.visible = false


# ── 两层办公楼（西端） ──
func _build_two_story_block() -> void:
    _box("BlockBody", Vector3(8.0, 10.2, 14.0), Vector3(-8.0, 5.1, 0.0), SHELL_DARK)
    _box("BlockPlinth", Vector3(8.5, 0.7, 14.4), Vector3(-8.0, 0.35, 0.0), PLINTH)
    # 楼层腰线：读作两层，而不是一栋高一点的仓库
    _box("BlockBand", Vector3(8.5, 0.34, 14.4), Vector3(-8.0, 6.5, 0.0), PLINTH)

    # 二层窗带（正面）
    _box("BlockGlassBand", Vector3(7.2, 1.4, 0.10), Vector3(-8.0, 8.3, 7.02), GLASS)
    for index in 4:
        var x := -10.7 + float(index) * 1.8
        _box("BlockMullion%d" % index, Vector3(0.12, 1.5, 0.12), Vector3(x, 8.3, 7.06), FRAME)
    _box("BlockSill", Vector3(7.6, 0.16, 0.22), Vector3(-8.0, 7.5, 7.05), FRAME)

    # 侧面窗：只留一扇，其余用暗色块暗示已经封死
    _box("BlockSideGlass", Vector3(0.10, 1.3, 5.6), Vector3(-12.03, 8.3, 0.0), GLASS)
    for index in 2:
        _box("BlockSideMullion%d" % index, Vector3(0.12, 1.4, 0.12), Vector3(-12.06, 8.3, -1.85 + float(index) * 3.7), FRAME)

    # 外墙缺口：一块板没了，露出黑腔和几根钢筋
    _box("BlockHole", Vector3(2.4, 2.1, 0.08), Vector3(-4.7, 3.9, 7.02), HOLE)
    _box("BlockHoleSide", Vector3(0.08, 1.7, 2.2), Vector3(-4.04, 4.1, 5.6), HOLE)
    for index in 3:
        var rebar := _cyl("Rebar%d" % index, 0.035, 0.9, Vector3(-4.05, 4.6, 6.2 + float(index) * 0.5), RUST)
        rebar.rotation_degrees = Vector3(0.0, 0.0, 64.0 + float(index) * 8.0)

    # 一层：侧门、办公室小窗、墙上空调，打破这面长墙的空白
    _box("BlockDoor", Vector3(1.5, 2.5, 0.12), Vector3(-8.0, 1.25, 7.02), HOLE)
    _box("BlockDoorFrameL", Vector3(0.12, 2.6, 0.18), Vector3(-8.8, 1.3, 7.06), FRAME)
    _box("BlockDoorFrameR", Vector3(0.12, 2.6, 0.18), Vector3(-7.2, 1.3, 7.06), FRAME)
    _box("BlockDoorLintel", Vector3(1.72, 0.14, 0.18), Vector3(-8.0, 2.6, 7.06), FRAME)
    _box("BlockOfficeWindow", Vector3(1.2, 1.0, 0.10), Vector3(-10.7, 2.5, 7.02), GLASS)
    _box("BlockACUnit", Vector3(1.0, 0.75, 0.45), Vector3(-5.4, 3.1, 7.28), METAL)


# ── 一层大卖场（东段） ──
func _build_main_hall() -> void:
    _box("HallBody", Vector3(16.0, 6.4, 14.0), Vector3(4.0, 3.2, 0.0), SHELL)
    _box("HallPlinth", Vector3(16.4, 0.7, 14.4), Vector3(4.0, 0.35, 0.0), PLINTH)
    # 竖向壁柱：把 16 米长的墙分成几段，避免一整个大平面
    for index in 3:
        _box("HallPilaster%d" % index, Vector3(0.5, 6.0, 0.5), Vector3(6.0 + float(index) * 3.4, 3.1, 6.95), SHELL_DARK)
    # 顶部檐口
    _box("HallCornice", Vector3(16.4, 0.34, 0.5), Vector3(4.0, 6.2, 6.95), PLINTH)


# ── 正立面：玻璃店面 ──
func _build_storefront(half_z: float) -> void:
    var z: float = half_z + 0.04
    # 店面底色带
    _box("ShopBand", Vector3(13.0, 3.6, 0.14), Vector3(3.6, 2.2, z - 0.02), HOLE)
    # 玻璃分格：右侧四格，左边靠门一格
    var panels := [
        Vector3(2.9, 2.4, z),
        Vector3(4.9, 2.4, z),
        Vector3(6.9, 2.4, z),
        Vector3(8.9, 2.4, z),
        Vector3(-3.0, 2.4, z),
    ]
    for index in panels.size():
        var at: Vector3 = panels[index]
        # 倒数第二格是碎的：留空，用斜钉的木板表示已经封住
        if index == 3:
            _box("BoardA", Vector3(0.18, 2.6, 0.08), at + Vector3(-0.1, 0.1, 0.06), WOOD).rotation_degrees = Vector3(0.0, 0.0, 24.0)
            _box("BoardB", Vector3(0.18, 2.6, 0.08), at + Vector3(0.1, 0.1, 0.08), WOOD).rotation_degrees = Vector3(0.0, 0.0, -19.0)
            continue
        # 第二格只剩上半截，下缘挂着一片歪掉的玻璃
        if index == 1:
            _box("ShopGlassStub", Vector3(1.8, 1.5, 0.08), at + Vector3(0.0, 0.95, 0.0), GLASS)
            _box("ShopGlassShard", Vector3(0.55, 1.0, 0.05), at + Vector3(-0.3, -0.1, 0.02), Color("#5f707c")).rotation_degrees = Vector3(0.0, 0.0, 16.0)
            continue
        # 门左边那格整块没了，只剩一个黑框
        if index == 4:
            continue
        _box("ShopGlass%d" % index, Vector3(1.8, 2.8, 0.08), at + Vector3(0.0, 0.15, 0.0), GLASS)
    # 竖框与窗台
    for index in 6:
        var x := 1.9 + float(index) * 2.0
        _box("ShopMullion%d" % index, Vector3(0.12, 3.4, 0.12), Vector3(x, 2.2, z + 0.06), FRAME)
    _box("ShopSill", Vector3(1.9, 0.16, 0.2), Vector3(-3.0, 0.95, z + 0.05), FRAME)
    _box("ShopSillMain", Vector3(9.2, 0.16, 0.2), Vector3(5.9, 0.95, z + 0.05), FRAME)


# ── 入口、雨棚、招牌 ──
func _build_entrance(half_z: float) -> void:
    var z: float = half_z + 0.04
    # 门洞
    _box("DoorRecess", Vector3(3.4, 3.2, 0.45), Vector3(0.0, 1.6, z + 0.12), HOLE)
    _box("DoorFrameL", Vector3(0.14, 3.3, 0.22), Vector3(-1.75, 1.65, z + 0.24), FRAME)
    _box("DoorFrameR", Vector3(0.14, 3.3, 0.22), Vector3(1.75, 1.65, z + 0.24), FRAME)
    _box("DoorFrameT", Vector3(3.64, 0.16, 0.22), Vector3(0.0, 3.34, z + 0.24), FRAME)
    _build_doors(half_z)

    # 雨棚：断成两截，右侧那截塌得更厉害，边缘还挂着一片撕下来的布
    var canopy_a := _box("CanopyA", Vector3(4.6, 0.28, 3.2), Vector3(-0.9, 3.98, half_z + 1.9), AWNING)
    canopy_a.rotation_degrees = Vector3(0.0, 0.0, 1.6)
    var canopy_b := _box("CanopyB", Vector3(3.4, 0.26, 3.2), Vector3(3.3, 3.72, half_z + 1.9), AWNING)
    canopy_b.rotation_degrees = Vector3(0.0, 0.0, 9.0)
    _box("CanopyEdgeA", Vector3(4.6, 0.34, 0.16), Vector3(-0.9, 3.80, half_z + 3.46), PLINTH)
    _box("CanopyEdgeB", Vector3(3.4, 0.32, 0.16), Vector3(3.3, 3.42, half_z + 3.46), PLINTH).rotation_degrees = Vector3(0.0, 0.0, 9.0)
    var torn := _box("CanopyTornStrip", Vector3(0.9, 1.1, 0.05), Vector3(4.5, 2.95, half_z + 3.30), AWNING)
    torn.rotation_degrees = Vector3(-12.0, 6.0, -7.0)
    var post_a := _cyl("CanopyPostA", 0.13, 3.9, Vector3(-2.7, 1.95, half_z + 3.1), FRAME)
    post_a.rotation_degrees = Vector3(0.0, 0.0, -1.5)
    var post_b := _cyl("CanopyPostB", 0.13, 3.75, Vector3(5.1, 1.85, half_z + 3.1), FRAME)
    post_b.rotation_degrees = Vector3(0.0, 0.0, 4.5)

    # 招牌：不再写名字，改成一块挂在两颗吊杆上的旧牌子，
    # 右侧吊杆断了，所以整块牌歪向一边、还吊着一小截断链。
    var sign_root := Node3D.new()
    sign_root.name = "HangingSign"
    sign_root.position = Vector3(1.2, 5.15, half_z + 0.62)
    sign_root.rotation_degrees = Vector3(-4.0, 0.0, -7.0)
    root.add_child(sign_root)
    _box_to(sign_root, "SignBack", Vector3(4.2, 1.50, 0.22), Vector3.ZERO, PLINTH)
    _box_to(sign_root, "SignFace", Vector3(3.95, 1.28, 0.10), Vector3(0.0, 0.0, 0.13), accent, true)
    _box_to(sign_root, "SignFrameT", Vector3(4.2, 0.09, 0.26), Vector3(0.0, 0.71, 0.02), PLINTH)
    _box_to(sign_root, "SignFrameB", Vector3(4.2, 0.09, 0.26), Vector3(0.0, -0.71, 0.02), PLINTH)
    _box_to(sign_root, "SignFrameL", Vector3(0.09, 1.41, 0.26), Vector3(-2.06, 0.0, 0.02), PLINTH)
    _box_to(sign_root, "SignFrameR", Vector3(0.09, 1.41, 0.26), Vector3(2.06, 0.0, 0.02), PLINTH)
    # 图标：Tabler Icons 的 shopping-cart（MIT 许可），见 assets/icons/LICENSES.md
    var icon := load("res://assets/icons/shopping-cart.svg") as Texture2D
    if icon != null:
        var plate := MeshInstance3D.new()
        plate.name = "SignIcon"
        var quad := QuadMesh.new()
        quad.size = Vector2(1.25, 1.25)
        plate.mesh = quad
        plate.position = Vector3(0.0, 0.0, 0.20)
        var icon_material := StandardMaterial3D.new()
        icon_material.albedo_texture = icon
        icon_material.albedo_color = Color("#2b2110")
        icon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        # 不加光照：牌面图标在暗紫环境里也要能看清
        icon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        icon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
        plate.material_override = icon_material
        sign_root.add_child(plate)
    # 烧糊的角落
    _box_to(sign_root, "SignBurn", Vector3(0.62, 0.36, 0.05), Vector3(-1.66, 0.36, 0.20), Color("#1d1712"))

    # 吊杆：左侧还连着，右侧只剩墙上的一截，牌子因此歪着
    _rod(Vector3(-0.68, 6.24, half_z + 0.05), Vector3(-0.79, 6.15, half_z + 0.62), 0.05, FRAME)
    _rod(Vector3(3.52, 6.24, half_z + 0.05), Vector3(3.42, 6.04, half_z + 0.30), 0.05, RUST)
    # 断口下面垂着的一小截链子和吊环
    _rod(Vector3(3.38, 5.64, half_z + 0.62), Vector3(3.36, 5.34, half_z + 0.62), 0.03, RUST)
    var link := _mesh(root, "BrokenLink", _torus(0.05, 0.09), Vector3(3.36, 5.27, half_z + 0.62), RUST, false)
    link.rotation_degrees = Vector3(90.0, 0.0, 0.0)
    # 掉在地上的招牌碎片
    var fallen := _box("SignFragment", Vector3(1.7, 0.12, 0.5), Vector3(-6.2, 0.12, half_z + 2.2), accent)
    fallen.rotation_degrees = Vector3(0.0, 27.0, 6.0)


## 做旧层。
## 单色方盒墙面在俯视下就是一块干净的板子，怎么加摆件都像新的。
## 这里在六个可见立面外侧各铺一层细分网格，用顶点色画出：
## 墙脚积灰、檐下阴影、竖向雨痕、斑驳水渍、掉漆露出的浅色底层。
## 只做视觉，不参与碰撞。
func _build_surface_age() -> void:
    var front_n := Vector3(0.0, 0.0, 1.0)
    var back_n := Vector3(0.0, 0.0, -1.0)
    var east_n := Vector3(1.0, 0.0, 0.0)
    var west_n := Vector3(-1.0, 0.0, 0.0)
    _facade("AgeHallFront", Vector3(4.0, 3.2, 7.0) + front_n * 0.015, Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 16.0, 6.4, 11)
    _facade("AgeHallBack", Vector3(4.0, 3.2, -7.0) + back_n * 0.015, Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 16.0, 6.4, 23)
    _facade("AgeHallEast", Vector3(12.0, 3.2, 0.0) + east_n * 0.015, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), 14.0, 6.4, 37)
    _facade("AgeBlockFront", Vector3(-8.0, 5.1, 7.0) + front_n * 0.015, Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 8.0, 10.2, 53)
    _facade("AgeBlockBack", Vector3(-8.0, 5.1, -7.0) + back_n * 0.015, Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 8.0, 10.2, 71)
    _facade("AgeBlockWest", Vector3(-12.0, 5.1, 0.0) + west_n * 0.015, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 14.0, 10.2, 89)


func _facade(node_name: String, center: Vector3, right: Vector3, up: Vector3, width: float, height: float, seed_value: int) -> void:
    # 顶点间距要明显小于噪声波长，否则相邻顶点一亮一暗，
    # 整面墙会读成灰白格纹而不是做旧。
    var cols := 48
    var rows := 22
    var step_u := width / float(cols)
    var step_v := height / float(rows)
    # 法线显式给成朝外：不要让 generate_normals() 从顶点顺序里推，
    # 六个立面朝右/朝左各不相同，推错的那几面会背光发黑。
    var outward: Vector3 = right.cross(up).normalized()
    var streak := FastNoiseLite.new()
    streak.seed = seed_value
    streak.frequency = 0.75
    var patch := FastNoiseLite.new()
    patch.seed = seed_value + 17
    patch.frequency = 0.28
    patch.fractal_octaves = 3
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for row in rows:
        for col in cols:
            var u0 := -width * 0.5 + float(col) * step_u
            var v0 := -height * 0.5 + float(row) * step_v
            var quad := [
                center + right * u0 + up * v0,
                center + right * (u0 + step_u) + up * v0,
                center + right * (u0 + step_u) + up * (v0 + step_v),
                center + right * u0 + up * (v0 + step_v),
            ]
            for point in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
                # 用顶点自己的 u，而不是整格共用一个值：
                # 每格一个颜色会让墙面读成瓷砖格。
                var u_point: float = (point - center).dot(right)
                st.set_color(_wall_tint(streak, patch, u_point, point.y, height))
                st.set_normal(outward)
                st.add_vertex(point)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = st.commit()
    var material := StandardMaterial3D.new()
    # 顶点色只当作"明暗倍率"用（围绕 1.0），底色交给 albedo_color。
    # 这样墙面色值和后面的方盒墙面完全一致，不会因为色彩空间换算发白或发黑。
    material.albedo_color = SHELL
    material.vertex_color_use_as_albedo = true
    material.roughness = 1.0
    # 双面：避免个别立面因为朝向不同被剔除掉
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    # 这层是贴在墙面上的"皮肤"，离墙只有 1.5 厘米。
    # 不关接收阴影的话，墙自身的阴影会在皮肤上投出一片细密的格子。
    material.disable_receive_shadows = true
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(instance)


func _wall_tint(streak: FastNoiseLite, patch: FastNoiseLite, u: float, height_above_ground: float, wall_height: float) -> Color:
    var tint := Color(1.0, 1.0, 1.0)
    # 墙脚积灰：越靠近地面越脏
    var grime := clampf(1.0 - height_above_ground / 2.8, 0.0, 1.0)
    tint = tint.lerp(Color(0.46, 0.49, 0.54), grime * 0.82)
    # 檐下阴影
    var eave := clampf((height_above_ground - (wall_height - 1.6)) / 1.6, 0.0, 1.0)
    tint = tint.lerp(Color(0.58, 0.61, 0.66), eave * 0.55)
    # 竖向雨痕：只随水平位置变化，所以是竖条
    # 两个频率叠在一起，避免雨痕变成等距的竖条纹（那会像压型钢板）
    var run := streak.get_noise_1d(u * 2.6) * 0.72 + streak.get_noise_1d(u * 8.5 + 11.0) * 0.28
    if run > 0.05:
        tint = tint.lerp(Color(0.70, 0.73, 0.78), clampf((run - 0.05) * 0.9, 0.0, 0.55))
    # 大块水渍与污斑
    var blot := patch.get_noise_2d(u * 1.15, height_above_ground * 1.15)
    if blot > -0.05:
        tint = tint.lerp(Color(0.74, 0.77, 0.82), (blot + 0.05) * 0.5)
    # 掉漆：露出下面更浅的一层
    if blot < -0.40:
        tint = tint.lerp(Color(0.97, 0.97, 0.96), clampf((-blot - 0.40) * 0.9, 0.0, 0.45))
    # 墙脚霉斑
    if grime > 0.30 and blot < -0.1:
        tint = tint.lerp(Color(0.40, 0.45, 0.42), (blot + 0.1) * -0.7 + grime * 0.14)
    return tint


## 血渍、海报、涂鸦。
## 血迹分三档：干涸的近黑红、较新的暗红、被拖拽出来的浅红。
func _build_stains(half_z: float) -> void:
    var dry := Color("#3a1013")
    var blood := Color("#4e1519")
    var fresh := Color("#6b1d22")
    var wall_z: float = half_z + 0.03

    # 办公楼正面：有人从门口一路滑坐到地上
    _box("BloodSlide", Vector3(0.32, 2.2, 0.03), Vector3(-6.35, 1.50, wall_z), blood)
    _box("BloodSlide2", Vector3(0.18, 1.7, 0.03), Vector3(-6.05, 1.30, wall_z + 0.01), fresh)
    _box("BloodSlide3", Vector3(0.12, 0.9, 0.03), Vector3(-6.52, 0.75, wall_z + 0.01), fresh)
    _box("BloodPool", Vector3(1.5, 0.34, 0.05), Vector3(-6.2, 0.24, wall_z), dry)
    # 门左侧的抓痕
    for index in 4:
        _box("BloodClaw%d" % index, Vector3(0.10, 0.55, 0.03), Vector3(-2.35 + float(index) * 0.16, 1.45, wall_z), fresh).rotation_degrees = Vector3(0.0, 0.0, -14.0)
    # 门框上的手印
    for index in 5:
        var finger := _box("BloodFinger%d" % index, Vector3(0.07, 0.13, 0.03), Vector3(-1.55 + float(index) * 0.10, 1.28 + float(index % 2) * 0.05, wall_z), dry)
        finger.rotation_degrees = Vector3(0.0, 0.0, float(index) * 7.0 - 14.0)
    _box("BloodPalm", Vector3(0.30, 0.26, 0.03), Vector3(-1.28, 1.20, wall_z), dry)

    # 钉死的那格窗下：喷溅
    for index in 7:
        var at := Vector3(8.2 + float(index % 3) * 0.55, 0.7 + float(index / 3) * 0.62, wall_z)
        var size := Vector3(0.16 + float(index % 2) * 0.10, 0.12 + float(index % 3) * 0.06, 0.03)
        _box("BloodSpray%d" % index, size, at, blood if index % 2 == 0 else fresh)
    _box("BloodSprayBig", Vector3(0.55, 0.40, 0.03), Vector3(9.1, 1.05, wall_z), blood)

    # 地面：门口的血泊 + 向停车区拖行的痕迹
    _cyl("BloodFloorPool", 1.30, 0.014, Vector3(1.6, 0.02, half_z + 1.5), dry)
    _cyl("BloodFloorPool2", 0.70, 0.014, Vector3(3.4, 0.02, half_z + 2.4), blood)
    for index in 4:
        var trail := _box("BloodTrail%d" % index, Vector3(0.45, 0.02, 0.16), Vector3(2.2 + float(index) * 0.85, 0.03, half_z + 2.2 + float(index) * 0.75), blood)
        trail.rotation_degrees = Vector3(0.0, -28.0, 0.0)
    # 门前台阶上的干涸血点
    for index in 5:
        _box("BloodDrop%d" % index, Vector3(0.20, 0.02, 0.16), Vector3(0.2 - float(index) * 0.55, 0.03, half_z + 0.9), dry).rotation_degrees = Vector3(0.0, float(index * 47 % 90), 0.0)

    # 东墙上的一片擦痕：有人被拖过墙角
    _box("BloodWipeEast", Vector3(0.03, 0.85, 2.4), Vector3(12.03, 1.05, 4.4), blood)
    _box("BloodWipeEast2", Vector3(0.03, 0.45, 1.5), Vector3(12.04, 0.55, 4.7), fresh)

    # 旧海报：一张完整、一张撕掉一半
    _box("PosterA", Vector3(0.95, 1.25, 0.02), Vector3(-2.9, 2.85, wall_z), Color("#b9b3a2")).rotation_degrees = Vector3(0.0, 0.0, 2.0)
    _box("PosterB", Vector3(0.85, 0.62, 0.02), Vector3(6.4, 3.05, wall_z), Color("#a8a293")).rotation_degrees = Vector3(0.0, 0.0, -3.0)
    _box("PosterB2", Vector3(0.52, 0.30, 0.02), Vector3(6.6, 2.55, wall_z), Color("#9b9587")).rotation_degrees = Vector3(0.0, 0.0, 26.0)

    # 涂鸦：几道横竖线，读作"有人在这里留过字"
    for index in 3:
        _box("Graffiti%d" % index, Vector3(1.1 - float(index) * 0.2, 0.07, 0.02), Vector3(-9.6 + float(index) * 0.5, 2.0 + float(index) * 0.35, wall_z), Color("#2b2f33"))


# ── 墙面细节：管线、外机、烟熏 ──
func _build_wall_details() -> void:
    # 东侧长墙原来是一整片空白，加两台外机、一根落水管把它切断
    _box("EastAC_A", Vector3(0.4, 0.85, 1.15), Vector3(12.12, 4.3, -1.8), METAL)
    _box("EastAC_B", Vector3(0.4, 0.85, 1.15), Vector3(12.12, 4.3, 2.2), METAL)
    _cyl("DownpipeE", 0.09, 6.1, Vector3(12.06, 3.05, 6.4), FRAME)
    _cyl("DownpipeW", 0.09, 6.1, Vector3(-12.06, 3.05, 6.4), FRAME)
    # 屋檐下的烟熏痕：几道横向暗带，让新楼的立面脏一点
    _box("SootA", Vector3(6.2, 0.45, 0.05), Vector3(4.6, 5.85, 7.03), Color("#3f4650"))
    _box("SootB", Vector3(3.4, 0.30, 0.05), Vector3(9.4, 5.55, 7.03), Color("#454c56"))
    _box("SillSoot", Vector3(6.8, 0.22, 0.05), Vector3(-8.0, 7.38, 7.03), Color("#444b55"))
    _box("RustStreak", Vector3(0.34, 1.5, 0.04), Vector3(-5.2, 3.3, 7.04), Color("#4a3a32"))


# ── 大门 ──
## 两扇玻璃推拉门：左扇关着，右扇脱轨卡在一旁，玻璃上有裂纹。
## 原来的门洞只是块黑面，正面看过去分不清"门"和"洞"。
func _build_doors(half_z: float) -> void:
    var door_z: float = half_z + 0.34
    # 上下轨道与地垫
    _box("DoorTrackTop", Vector3(3.5, 0.10, 0.16), Vector3(0.0, 3.10, door_z), FRAME)
    _box("DoorTrackBottom", Vector3(3.5, 0.05, 0.16), Vector3(0.0, 0.03, door_z), FRAME)
    _box("DoorMat", Vector3(2.6, 0.02, 0.95), Vector3(0.0, 0.02, door_z + 0.62), Color("#2c333a"))
    # 左扇：关着
    _door_leaf("DoorLeafL", Vector3(-0.81, 1.56, door_z), 0.0, 0.0, false)
    # 右扇：脱轨滑到一边，还歪着
    _door_leaf("DoorLeafR", Vector3(1.22, 1.54, door_z), 9.0, 3.0, true)
    # 门内侧的一小段不锈钢防撞条
    _box("DoorKickPlateL", Vector3(1.5, 0.55, 0.03), Vector3(-0.81, 0.45, door_z + 0.04), METAL_LIGHT)


func _door_leaf(node_name: String, at: Vector3, yaw: float, roll: float, cracked: bool) -> Node3D:
    var leaf := Node3D.new()
    leaf.name = node_name
    leaf.position = at
    leaf.rotation_degrees = Vector3(0.0, yaw, roll)
    root.add_child(leaf)
    var width := 1.62
    var height := 2.96
    var bar := 0.07
    _box_to(leaf, "FrameL", Vector3(bar, height, bar), Vector3(-width * 0.5, 0.0, 0.0), FRAME)
    _box_to(leaf, "FrameR", Vector3(bar, height, bar), Vector3(width * 0.5, 0.0, 0.0), FRAME)
    _box_to(leaf, "FrameT", Vector3(width, bar, bar), Vector3(0.0, height * 0.5, 0.0), FRAME)
    _box_to(leaf, "FrameB", Vector3(width, 0.11, bar), Vector3(0.0, -height * 0.5, 0.0), FRAME)
    # 玻璃（偏冷，比纯黑多一点反射感）
    _box_to(leaf, "Pane", Vector3(width - 0.13, height - 0.18, 0.03), Vector3.ZERO, Color("#2b3a48"))
    # 中横档：超市推拉门的常见做法，也让"门"和"洞"区分开
    _box_to(leaf, "MidRail", Vector3(width - 0.10, 0.06, 0.06), Vector3(0.0, -0.55, 0.02), FRAME)
    # 竖向长把手
    _box_to(leaf, "Handle", Vector3(0.05, 0.9, 0.05), Vector3(width * 0.5 - 0.16, 0.0, 0.07), METAL_LIGHT)
    if cracked:
        _box_to(leaf, "CrackA", Vector3(0.035, 0.95, 0.02), Vector3(-0.12, 0.25, 0.03), Color("#8b98a4")).rotation_degrees = Vector3(0.0, 0.0, 26.0)
        _box_to(leaf, "CrackB", Vector3(0.035, 0.75, 0.02), Vector3(0.14, -0.35, 0.03), Color("#8b98a4")).rotation_degrees = Vector3(0.0, 0.0, -38.0)
        _box_to(leaf, "HoleShard", Vector3(0.42, 0.5, 0.02), Vector3(0.3, 0.55, 0.03), HOLE)
    return leaf


# ── 屋顶 ──
## 破损：屋顶破洞、东南角塌掉一块、满地碎砖碎玻璃、一根倒下的路灯。
## 这些是"破旧"的主要来源，都贴着原有结构放，不改变体块轮廓。
func _build_damage(half_z: float) -> void:
    # 卖场屋顶的破洞。屋顶上表面在 y=6.90，所以洞和翻卷的铁皮都必须写在这之上，
    # 否则会整块埋进屋顶板里、从外面完全看不见。
    _box("RoofHole", Vector3(2.9, 0.10, 2.5), Vector3(7.4, 6.93, 2.0), HOLE)
    _box("RoofTearS", Vector3(3.1, 0.16, 0.5), Vector3(7.4, 7.02, 0.62), ROOF).rotation_degrees = Vector3(9.0, 0.0, 0.0)
    _box("RoofTearN", Vector3(3.1, 0.16, 0.5), Vector3(7.4, 7.00, 3.38), ROOF).rotation_degrees = Vector3(-7.0, 0.0, 0.0)
    _box("RoofTearW", Vector3(0.5, 0.16, 2.7), Vector3(5.82, 7.01, 2.0), ROOF).rotation_degrees = Vector3(0.0, 0.0, 8.0)
    _box("RoofTearE", Vector3(0.5, 0.16, 2.7), Vector3(8.98, 6.98, 2.0), ROOF).rotation_degrees = Vector3(0.0, 0.0, -10.0)
    # 洞里露出的两根梁
    _box("RoofBeamA", Vector3(3.3, 0.14, 0.18), Vector3(7.4, 6.98, 1.35), RUST)
    _box("RoofBeamB", Vector3(3.3, 0.14, 0.18), Vector3(7.4, 6.96, 2.75), RUST)

    # 东南角塌掉一块：正面和侧面各留一个暗腔，角上再支几根钢筋
    _box("CornerHoleS", Vector3(2.1, 3.4, 0.08), Vector3(10.9, 1.70, half_z + 0.05), HOLE)
    _box("CornerHoleE", Vector3(0.08, 3.4, 2.1), Vector3(12.05, 1.70, 5.9), HOLE)
    # 角上塌下来的碎块堆在墙根
    _box("CornerChunkA", Vector3(1.1, 0.7, 1.0), Vector3(11.4, 0.35, half_z + 0.9), PLINTH).rotation_degrees = Vector3(0.0, 18.0, 6.0)
    _box("CornerChunkB", Vector3(0.8, 0.5, 0.8), Vector3(12.2, 0.25, half_z + 0.4), SHELL_DARK).rotation_degrees = Vector3(0.0, -24.0, 10.0)
    for index in 3:
        var bar := _cyl("CornerRebar%d" % index, 0.028, 0.8, Vector3(11.7 - float(index) * 0.22, 2.85, half_z - 0.35), RUST)
        bar.rotation_degrees = Vector3(0.0, 0.0, 58.0 + float(index) * 10.0)

    # 墙脚的碎砖堆
    var rubble := [
        Vector3(-9.0, 0.16, half_z + 0.55), Vector3(-8.2, 0.13, half_z + 0.95),
        Vector3(-4.6, 0.18, half_z + 0.70), Vector3(9.6, 0.15, half_z + 0.60),
        Vector3(11.0, 0.20, half_z + 1.10), Vector3(-11.2, 0.14, half_z + 1.30),
        Vector3(6.4, 0.12, half_z + 1.55),
    ]
    for index in rubble.size():
        var size := Vector3(0.55 + float(index % 3) * 0.18, 0.32 + float(index % 2) * 0.12, 0.5 + float(index % 4) * 0.12)
        var at: Vector3 = rubble[index]
        _box("Rubble%d" % index, size, at, PLINTH if index % 2 == 0 else SHELL_DARK).rotation_degrees = Vector3(
            float(index * 7 % 30) - 15.0, float(index * 41 % 90), float(index * 11 % 24) - 12.0)

    # 门前地上的碎玻璃
    for index in 7:
        var x := 1.2 + float(index) * 1.25
        var shard := _box("GlassShard%d" % index, Vector3(0.42, 0.02, 0.30), Vector3(x, 0.03, half_z + 1.2 + float(index % 3) * 0.45), Color("#5f707c"))
        shard.rotation_degrees = Vector3(0.0, float(index * 53 % 180), 0.0)

    # 门前一小滩积水
    _cyl("Puddle", 1.5, 0.012, Vector3(-2.4, 0.02, half_z + 2.6), Color("#252b33"))

    # 正面墙上的一道斜裂缝，三段折线拼出来
    var crack_z: float = half_z + 0.05
    _box("CrackA", Vector3(0.75, 0.09, 0.04), Vector3(1.15, 5.05, crack_z), HOLE).rotation_degrees = Vector3(0.0, 0.0, 38.0)
    _box("CrackB", Vector3(0.95, 0.09, 0.04), Vector3(1.75, 4.25, crack_z), HOLE).rotation_degrees = Vector3(0.0, 0.0, -32.0)
    _box("CrackC", Vector3(0.70, 0.08, 0.04), Vector3(2.15, 3.55, crack_z), HOLE).rotation_degrees = Vector3(0.0, 0.0, 24.0)

    # 倒下的路灯：灯杆平躺在停车区
    var fallen_pole := _cyl("FallenPole", 0.13, 6.0, Vector3(1.6, 0.16, 11.6), METAL)
    fallen_pole.rotation_degrees = Vector3(0.0, 0.0, 90.0)
    _box("FallenLampHead", Vector3(0.8, 0.22, 0.42), Vector3(4.4, 0.26, 11.6), Color("#3a4048")).rotation_degrees = Vector3(0.0, 0.0, 12.0)

    # 一台从屋顶掉下来的空调外机
    _box("FallenAC", Vector3(1.7, 0.65, 1.5), Vector3(13.4, 0.34, 3.4), METAL).rotation_degrees = Vector3(6.0, 22.0, 4.0)
    _box("FallenACCap", Vector3(1.9, 0.12, 1.7), Vector3(13.4, 0.70, 3.4), METAL_LIGHT).rotation_degrees = Vector3(6.0, 22.0, 4.0)


func _build_roofs() -> void:
    # 大卖场屋顶
    _box("HallRoof", Vector3(16.6, 0.5, 14.6), Vector3(4.0, 6.65, 0.0), ROOF)
    _box("HallRimN", Vector3(16.6, 0.12, 0.45), Vector3(4.0, 6.92, -7.08), RIM)
    # 南侧压檐在破洞位置断开，露出缺口
    _box("HallRimSW", Vector3(9.9, 0.12, 0.45), Vector3(0.67, 6.92, 7.08), RIM)
    _box("HallRimSE", Vector3(3.3, 0.12, 0.45), Vector3(10.63, 6.92, 7.08), RIM)
    _box("HallRimW", Vector3(0.45, 0.12, 13.7), Vector3(-4.28, 6.92, 0.0), RIM)
    _box("HallRimE", Vector3(0.45, 0.12, 13.7), Vector3(12.28, 6.92, 0.0), RIM)
    # 屋顶设备：机组、风管、检修口、排风
    _box("AC_A", Vector3(2.1, 0.75, 2.1), Vector3(8.4, 7.28, -3.6), METAL)
    _box("AC_A_Cap", Vector3(2.4, 0.14, 2.4), Vector3(8.4, 7.72, -3.6), METAL_LIGHT)
    _box("AC_B", Vector3(1.7, 0.65, 1.7), Vector3(0.4, 7.22, -4.6), METAL).rotation_degrees = Vector3(0.0, 0.0, 11.0)
    _box("AC_B_Cap", Vector3(1.95, 0.12, 1.95), Vector3(0.4, 7.60, -4.6), METAL_LIGHT)
    _box("RoofDuct", Vector3(1.1, 0.45, 3.2), Vector3(5.6, 7.12, 1.8), Color("#4b5361"))
    _box("RoofHatch", Vector3(1.6, 0.26, 1.6), Vector3(10.4, 7.03, 4.2), Color("#77818f"))
    _box("RoofStack", Vector3(0.7, 1.1, 0.7), Vector3(2.6, 7.45, 5.2), METAL)

    # 两层楼屋顶
    _box("BlockRoof", Vector3(8.6, 0.5, 14.6), Vector3(-8.0, 10.45, 0.0), ROOF)
    _box("BlockRimN", Vector3(8.6, 0.12, 0.45), Vector3(-8.0, 10.72, -7.08), RIM)
    _box("BlockRimS", Vector3(8.6, 0.12, 0.45), Vector3(-8.0, 10.72, 7.08), RIM)
    _box("BlockRimW", Vector3(0.45, 0.12, 13.7), Vector3(-12.28, 10.72, 0.0), RIM)
    _box("BlockRimE", Vector3(0.45, 0.12, 13.7), Vector3(-3.72, 10.72, 0.0), RIM)
    # 楼梯间 + 水箱 + 排气管
    _box("StairHouse", Vector3(2.8, 2.3, 2.4), Vector3(-10.4, 11.85, -4.6), Color("#6b7076"))
    _box("StairDoor", Vector3(0.9, 1.7, 0.1), Vector3(-10.4, 11.55, -3.38), HOLE)
    _box("StairCap", Vector3(3.1, 0.16, 2.7), Vector3(-10.4, 13.08, -4.6), METAL_LIGHT)
    _cyl("WaterTank", 1.15, 2.4, Vector3(-9.2, 11.9, 3.4), Color("#5a6068"))
    _cyl("WaterTankCap", 1.2, 0.18, Vector3(-9.2, 13.2, 3.4), METAL_LIGHT)
    _cyl("VentPipe", 0.32, 1.5, Vector3(-5.6, 11.45, 3.0), METAL)


# ── 侧面杂物 ──
func _build_side_props(half_z: float) -> void:
    # 西侧垃圾箱
    _box("Dumpster", Vector3(1.9, 1.25, 2.6), Vector3(-13.6, 0.63, 2.6), Color("#3f6b52"))
    var lid := _box("DumpsterLid", Vector3(2.0, 0.14, 2.7), Vector3(-13.6, 1.32, 2.5), Color("#39594a"))
    lid.rotation_degrees = Vector3(-6.0, 12.0, 0.0)
    # 托盘与货箱
    _box("PalletA", Vector3(1.7, 0.16, 1.3), Vector3(10.6, 0.09, half_z + 2.4), WOOD)
    _box("PalletB", Vector3(1.5, 0.16, 1.2), Vector3(10.9, 0.26, half_z + 2.5), WOOD)
    _box("CrateA", Vector3(1.0, 0.9, 1.0), Vector3(10.7, 0.8, half_z + 2.5), Color("#6c6257"))
    _box("CrateB", Vector3(0.8, 0.7, 0.8), Vector3(-11.5, 0.35, half_z + 2.2), Color("#5f5749"))


# ── 门前停车区 ──
func _build_parking_lot() -> void:
    # 车位划线：只是贴地的浅色细条，不参与碰撞
    for index in 6:
        var x := -8.5 + float(index) * 3.0
        _box("ParkLine%d" % index, Vector3(0.12, 0.012, 4.6), Vector3(x, 0.03, 12.2), Color("#8b93a0"))
    _box("ParkLineBack", Vector3(15.2, 0.012, 0.12), Vector3(-1.0, 0.03, 14.5), Color("#8b93a0"))

    # 两盏路灯，一盏弯了、灯头是黑的
    _pole(Vector3(-8.5, 0.0, 13.4), 0.0)
    _pole(Vector3(7.5, 0.0, 13.4), 7.0)

    # 两辆购物车
    _cart(Vector3(2.4, 0.0, 10.9), 14.0)
    _cart(Vector3(3.4, 0.0, 11.2), -8.0)
    # 一辆翻倒的购物车
    var tipped := Node3D.new()
    tipped.name = "TippedCart"
    tipped.position = Vector3(-4.6, 0.0, 12.4)
    tipped.rotation_degrees = Vector3(0.0, 32.0, 96.0)
    root.add_child(tipped)
    _box_to(tipped, "Basket", Vector3(0.86, 0.52, 0.58), Vector3(0.0, 0.62, 0.0), METAL_LIGHT)
    _box_to(tipped, "Handle", Vector3(0.84, 0.06, 0.06), Vector3(0.0, 1.0, 0.34), FRAME)

    # 收车围栏
    _box("CorralRailA", Vector3(0.07, 0.9, 2.6), Vector3(5.2, 0.45, 11.4), FRAME)
    _box("CorralRailB", Vector3(0.07, 0.9, 2.6), Vector3(7.9, 0.45, 11.4), FRAME)
    _box("CorralBar", Vector3(2.8, 0.07, 0.07), Vector3(6.55, 0.88, 10.15), FRAME)


func _pole(at: Vector3, bend: float) -> void:
    var pole := _cyl("LampPole", 0.13, 6.4, at + Vector3(0.0, 3.2, 0.0), METAL)
    pole.rotation_degrees = Vector3(0.0, 0.0, bend)
    var head := _box("LampHead", Vector3(0.85, 0.22, 0.42), at + Vector3(0.0, 6.35, -0.35), Color("#3a4048"))
    head.rotation_degrees = Vector3(0.0, 0.0, bend)


func _cart(at: Vector3, yaw: float) -> void:
    var cart := Node3D.new()
    cart.name = "ShoppingCart"
    cart.position = at
    cart.rotation_degrees = Vector3(0.0, yaw, 0.0)
    root.add_child(cart)
    _box_to(cart, "Basket", Vector3(0.86, 0.52, 0.58), Vector3(0.0, 0.62, 0.0), METAL_LIGHT)
    _box_to(cart, "BasketBase", Vector3(0.9, 0.08, 0.62), Vector3(0.0, 0.36, 0.0), METAL)
    _box_to(cart, "Handle", Vector3(0.84, 0.06, 0.06), Vector3(0.0, 1.0, 0.34), FRAME)
    _box_to(cart, "HandlePostL", Vector3(0.06, 0.4, 0.06), Vector3(-0.42, 0.84, 0.34), FRAME)
    _box_to(cart, "HandlePostR", Vector3(0.06, 0.4, 0.06), Vector3(0.42, 0.84, 0.34), FRAME)
    for sx in [-1.0, 1.0]:
        for sz in [-1.0, 1.0]:
            _box_to(cart, "Wheel", Vector3(0.12, 0.12, 0.12), Vector3(sx * 0.34, 0.06, sz * 0.24), Color("#2b3036"))


func _build_collision(size: Vector3) -> void:
    # 两段不同高度分开给碰撞，和外观一致
    _collider("HallCollision", Vector3(16.0, 6.4, 14.0), Vector3(4.0, 3.2, 0.0))
    _collider("BlockCollision", Vector3(8.0, 10.2, 14.0), Vector3(-8.0, 5.1, 0.0))


func _collider(node_name: String, size: Vector3, at: Vector3) -> void:
    var body := StaticBody3D.new()
    body.name = node_name
    body.collision_layer = 2
    body.collision_mask = 1
    body.position = at
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    root.add_child(body)


# ── 构件辅助 ──

func _box(node_name: String, size: Vector3, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
    return _box_to(root, node_name, size, at, color, glow)


func _box_to(parent: Node3D, node_name: String, size: Vector3, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return _mesh(parent, node_name, mesh, at, color, glow)


func _cyl(node_name: String, radius: float, height: float, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 12
    return _mesh(root, node_name, mesh, at, color, glow)


## 两点之间连一根圆柱，用来做吊杆、断链这类小构件。
func _rod(from: Vector3, to: Vector3, radius: float, color: Color) -> MeshInstance3D:
    var offset := to - from
    var length := offset.length()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = maxf(length, 0.01)
    mesh.radial_segments = 8
    var instance := MeshInstance3D.new()
    instance.name = "Rod"
    instance.mesh = mesh
    instance.transform = Transform3D(Basis(Quaternion(Vector3.UP, offset.normalized())), (from + to) * 0.5)
    instance.material_override = _make_material(color, false)
    root.add_child(instance)
    return instance


func _mesh(parent: Node3D, node_name: String, mesh: Mesh, at: Vector3, color: Color, glow: bool) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = at
    instance.material_override = _make_material(color, glow)
    parent.add_child(instance)
    return instance


## 预览工程里没有 Main3D 的材质工厂，这里按游戏里同样的参数自己建一份：
## 普通件 roughness 0.72，发光件加 0.85 的自发光。
func _make_material(color: Color, glow: bool) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.72
    if glow:
        material.emission_enabled = true
        material.emission = color
        # 0.85 的发光在 ACES 下会把金色招牌烧成白色，招牌就废了
        material.emission_energy_multiplier = 0.30
        material.roughness = 0.4
    return material


func _torus(inner: float, outer: float) -> TorusMesh:
    var mesh := TorusMesh.new()
    mesh.inner_radius = inner
    mesh.outer_radius = outer
    mesh.rings = 28
    mesh.ring_segments = 8
    return mesh
