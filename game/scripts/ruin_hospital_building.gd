extends RefCounted

# 腐墟星「废弃医院」外形（预览版，尚未写入项目）。
#
# 造型参考废土题材里常见的综合医院：
#   - 主体是三层病房楼，一端接一栋两层的门诊翼，再往外挑一个急救车雨棚，
#     三个体块高低不同，俯视不是一块方盒；
#   - 正立面一条通长的窄窗带（病房楼的典型读法），每隔一层一道腰线；
#   - 入口是玻璃门 + 外挑雨棚，雨棚上方是红色十字标志；
#   - 翼楼屋顶做成直升机停机坪（圆圈 + H），从俯视看是整颗星最像医院的一处；
#   - 墙面做旧、碎裂的窗、地上的血迹和翻倒的担架。

var controller: Node3D
var root: Node3D
var accent := Color("#a34f4f")
var entry_ring: MeshInstance3D

const SURFACE := preload("res://scripts/ruin_surface_lib.gd")
const ART := preload("res://scripts/ruin_cartoon_art.gd")
const ATMOSPHERE := preload("res://scripts/core/art_atmosphere_kit.gd")

const WALL := Color("#878e88")
const WALL_DARK := Color("#7d857f")
const PLINTH := Color("#5f665f")
const ROOF := Color("#8a4f3e")
const RIM := Color("#b9c0b8")
const METAL := Color("#2e5259")
const METAL_LIGHT := Color("#6b9294")
const FRAME := Color("#1d363c")
const GLASS := Color("#4b6f72")
const HOLE := Color("#1b2629")
const RED := Color("#93453b")
const WHITE := Color("#c7c9c2")
const RUST := Color("#83503d")
const WOOD := Color("#735034")
const WOOD_DOOR := Color("#855a3a")
const WOOD_DARK := Color("#553c2a")

# 体块
const TOWER_X := -4.0
const TOWER_W := 18.0
const TOWER_H := 13.2
const DEPTH := 19.0
const WING_X := 9.0
const WING_W := 8.0
const WING_Z0 := -9.5
const WING_Z1 := 1.5
const WING_H := 7.6
const FLOOR := 3.3


func build(building_root: Node3D, size: Vector3, accent_color: Color, owner: Node3D) -> void:
    root = building_root
    accent = accent_color
    controller = owner
    _build_tower()
    _build_wing()
    _build_windows()
    _build_entrance()
    _build_ambulance_bay()
    _build_roofs()
    # 卡通改版保留建筑体块、破洞和担架，去掉整面做旧与水渍层；
    # 血迹改成低饱和珊瑚色，读作"这里出过事"，但不把画面压回暗紫恐怖片。
    _build_damage()
    _build_collision(size)
    # 接地与排水：医院体量大，更需要一圈径向暗晕和碎石把楼“按”进地面。
    ATMOSPHERE.build_ground_skirt(root, "BuildingSkirt", Vector3(0.0, 0.0, 0.0), Vector2(size.x + 3.6, size.z + 3.6), Color(0.035, 0.033, 0.030), 0.62)
    ATMOSPHERE.build_gravel_cluster(root, "BuildingGravelA", Vector3(size.x * 0.5 + 0.6, 0.0, size.z * 0.5 + 0.2), 1.05, 11, 811)
    ATMOSPHERE.build_gravel_cluster(root, "BuildingGravelB", Vector3(-size.x * 0.5 - 0.6, 0.0, -size.z * 0.5 - 0.4), 0.9, 9, 812)
    for corner: Array in [[-1.0, 1.0], [1.0, -1.0]]:
        var px: float = float(corner[0]) * (size.x * 0.5 - 0.24)
        var pz: float = float(corner[1]) * (size.z * 0.5 - 0.24)
        ART.pipe_run(root, "HospitalDownpipe", [Vector3(px, 0.28, pz), Vector3(px, 8.5, pz)], 0.055, METAL, SURFACE.Family.MACH, true)
    var half_z: float = size.z * 0.5
    entry_ring = _mesh(root, "EntryRing", _torus(1.5, 1.56), Vector3(-4.0, 0.08, half_z + 1.6), accent, true)
    entry_ring.visible = false


# ── 主体 ──
func _build_tower() -> void:
    _box("TowerBody", Vector3(TOWER_W, TOWER_H, DEPTH), Vector3(TOWER_X, TOWER_H * 0.5, 0.0), WALL)
    _box("TowerPlinth", Vector3(TOWER_W + 0.4, 0.7, DEPTH + 0.4), Vector3(TOWER_X, 0.35, 0.0), PLINTH)
    # 楼层腰线：四层
    _box("TowerBandA", Vector3(TOWER_W + 0.4, 0.26, DEPTH + 0.4), Vector3(TOWER_X, FLOOR, 0.0), RIM)
    _box("TowerBandB", Vector3(TOWER_W + 0.4, 0.26, DEPTH + 0.4), Vector3(TOWER_X, FLOOR * 2.0, 0.0), RIM)
    _box("TowerBandC", Vector3(TOWER_W + 0.4, 0.26, DEPTH + 0.4), Vector3(TOWER_X, FLOOR * 3.0, 0.0), RIM)
    # 顶部檐口
    _box("TowerCornice", Vector3(TOWER_W + 0.5, 0.34, DEPTH + 0.5), Vector3(TOWER_X, TOWER_H - 0.3, 0.0), RIM)
    # 竖向壁柱：把 18 m 长的病房楼立面拆成有节奏的 5 段，近看不再是一整块平墙。
    for rib_x: float in [-11.6, -6.6, -1.6, 3.4]:
        _box("TowerRib", Vector3(0.26, TOWER_H - 1.1, 0.16), Vector3(rib_x, TOWER_H * 0.5, DEPTH * 0.5 + 0.06), WALL_DARK)


func _build_wing() -> void:
    var depth := WING_Z1 - WING_Z0
    var center_z := (WING_Z0 + WING_Z1) * 0.5
    _box("WingBody", Vector3(WING_W, WING_H, depth), Vector3(WING_X, WING_H * 0.5, center_z), WALL_DARK)
    _box("WingPlinth", Vector3(WING_W + 0.4, 0.6, depth + 0.4), Vector3(WING_X, 0.3, center_z), PLINTH)
    _box("WingBand", Vector3(WING_W + 0.4, 0.24, depth + 0.4), Vector3(WING_X, 3.7, center_z), PLINTH)
    _box("WingCornice", Vector3(WING_W + 0.45, 0.3, depth + 0.45), Vector3(WING_X, WING_H - 0.3, center_z), RIM)


# ── 窗 ──
func _build_windows() -> void:
    # 病房楼正立面：四层，每层七扇窄窗
    for floor in 4:
        var y := 1.9 + float(floor) * FLOOR
        for index in 7:
            var x := -11.4 + float(index) * 2.5
            # 一层中间那格正好在门洞里，画上去会穿进门框
            if floor == 0 and absf(x + 4.0) < 2.2:
                continue
            # 顶层右侧两格在塌掉的墙洞里，跟着一起没了
            if floor == 3 and x > 0.0 and x < 4.2:
                continue
            _window(Vector3(x, y, DEPTH * 0.5 + 0.12), Vector2(1.25, 1.6), Vector3(0, 0, 0))
    # 病房楼西侧
    for floor in 4:
        var y := 1.9 + float(floor) * FLOOR
        for index in 6:
            _window_side(Vector3(-TOWER_W * 0.5 + TOWER_X - 0.12, y, -7.6 + float(index) * 3.0), Vector2(1.2, 1.6))
    # 病房楼背面
    for floor in 4:
        var y := 1.9 + float(floor) * FLOOR
        for index in 6:
            _window(Vector3(-10.8 + float(index) * 2.9, y, -DEPTH * 0.5 - 0.12), Vector2(1.25, 1.6), Vector3(0, 180, 0))
    # 门诊翼：正面两层三扇、东侧两层三扇
    for floor in 2:
        var y := 1.9 + float(floor) * 3.4
        for index in 3:
            _window(Vector3(6.2 + float(index) * 2.4, y, WING_Z1 + 0.12), Vector2(1.3, 1.7), Vector3.ZERO)
    for floor in 2:
        var y := 1.9 + float(floor) * 3.4
        for index in 3:
            _window_side(Vector3(WING_X + WING_W * 0.5 + 0.12, y, -7.0 + float(index) * 3.4), Vector2(1.3, 1.7))


func _window(at: Vector3, size: Vector2, rotation: Vector3) -> void:
    # 窗洞是真凹进去的：外框比玻璃大一圈，玻璃退 5 cm，近看有厚度和阴影。
    var normal := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, deg_to_rad(rotation.y))
    var reveal := _box("WindowReveal", Vector3(size.x + 0.22, size.y + 0.20, 0.10), at - normal * 0.05, HOLE)
    reveal.rotation_degrees = rotation
    var pane := _box("Window", Vector3(size.x, size.y, 0.08), at, GLASS)
    pane.rotation_degrees = rotation
    var sill := _box("Sill", Vector3(size.x + 0.22, 0.14, 0.16), at + Vector3(0.0, -size.y * 0.5 - 0.10, 0.04), RIM)
    sill.rotation_degrees = rotation


func _window_side(at: Vector3, size: Vector2) -> void:
    _box("WindowSide", Vector3(0.08, size.y, size.x), at, GLASS)
    _box("SillSide", Vector3(0.16, 0.14, size.x + 0.22), at + Vector3(0.04, -size.y * 0.5 - 0.10, 0.0), FRAME)


# ── 入口：门楼、双开木门、雨棚、红十字 ──
func _build_entrance() -> void:
    var z: float = DEPTH * 0.5
    # 门洞暗面：离开墙面几厘米，避免共面 z-fighting。
    _box("EntranceRecess", Vector3(3.7, 3.3, 0.02), Vector3(-4.0, 1.65, z + 0.02), HOLE)
    # 门楼：两根侧壁柱 + 柱础 + 柱帽 + 过梁 + 檐部。给主入口一个真正的“门楼”剪影。
    for side: float in [-1.0, 1.0]:
        var px: float = -4.0 + side * 2.35
        _box("EntrancePilasterBase", Vector3(0.82, 0.35, 0.95), Vector3(px, 0.175, z + 0.35), PLINTH)
        _box("EntrancePilaster", Vector3(0.55, 4.45, 0.75), Vector3(px, 2.35, z + 0.35), WALL_DARK)
        _box("EntrancePilasterCap", Vector3(0.78, 0.20, 0.95), Vector3(px, 4.55, z + 0.35), RIM)
    _box("EntranceLintel", Vector3(5.6, 0.55, 0.70), Vector3(-4.0, 4.45, z + 0.35), WALL_DARK)
    _box("EntranceCornice", Vector3(5.9, 0.20, 0.85), Vector3(-4.0, 4.82, z + 0.38), RIM)
    # 门楣招牌：红十字 + 三条几何色带，不写文字。
    _box("EntranceSignBack", Vector3(2.8, 0.58, 0.06), Vector3(-4.0, 4.45, z + 0.73), PLINTH)
    _box("EntranceSignFace", Vector3(2.55, 0.44, 0.03), Vector3(-4.0, 4.45, z + 0.77), RIM)
    _box("EntranceSignCrossV", Vector3(0.13, 0.34, 0.03), Vector3(-4.82, 4.45, z + 0.80), RED, true)
    _box("EntranceSignCrossH", Vector3(0.34, 0.13, 0.03), Vector3(-4.82, 4.45, z + 0.80), RED, true)
    for index: int in 3:
        _box("EntranceSignBar%d" % index, Vector3(0.72, 0.06, 0.03), Vector3(-4.20 + float(index) * 0.36, 4.38 + float(index) * 0.07, z + 0.80), WALL_DARK)
    # 门套与门洞内衬
    _box("EntranceFrameL", Vector3(0.22, 3.45, 0.30), Vector3(-5.95, 1.72, z + 0.08), PLINTH)
    _box("EntranceFrameR", Vector3(0.22, 3.45, 0.30), Vector3(-2.05, 1.72, z + 0.08), PLINTH)
    _box("EntranceFrameT", Vector3(4.12, 0.24, 0.30), Vector3(-4.0, 3.44, z + 0.08), PLINTH)
    _box("EntranceRevealL", Vector3(0.10, 3.15, 0.40), Vector3(-5.86, 1.60, z + 0.18), WALL_DARK)
    _box("EntranceRevealR", Vector3(0.10, 3.15, 0.40), Vector3(-2.14, 1.60, z + 0.18), WALL_DARK)
    # 门顶亮子：旧铁丝玻璃 + 竖棂
    _box("EntranceTransomFrame", Vector3(3.72, 0.52, 0.18), Vector3(-4.0, 3.17, z + 0.12), PLINTH)
    var transom := _box("EntranceTransom", Vector3(3.42, 0.38, 0.05), Vector3(-4.0, 3.17, z + 0.18), GLASS)
    transom.material_override = SURFACE.glass(GLASS)
    for index: int in 5:
        _box("EntranceTransomMullion%d" % index, Vector3(0.05, 0.42, 0.05), Vector3(-5.25 + float(index) * 0.62, 3.17, z + 0.22), METAL_LIGHT)
    # 门楣下的小招牌：从门口抬头就能读到“这里是医院”，不用文字。
    _box("EntranceDoorSign", Vector3(2.2, 0.32, 0.06), Vector3(-4.0, 3.62, z + 0.22), PLINTH)
    _box("EntranceDoorSignFace", Vector3(2.0, 0.22, 0.03), Vector3(-4.0, 3.62, z + 0.26), RIM)
    _box("EntranceDoorSignCrossV", Vector3(0.08, 0.18, 0.02), Vector3(-4.72, 3.62, z + 0.29), RED, true)
    _box("EntranceDoorSignCrossH", Vector3(0.18, 0.08, 0.02), Vector3(-4.72, 3.62, z + 0.29), RED, true)
    for index: int in 3:
        _box("EntranceDoorSignBar%d" % index, Vector3(0.42, 0.04, 0.02), Vector3(-4.25 + float(index) * 0.30, 3.58 + float(index) * 0.04, z + 0.29), WALL_DARK)

    # 门槛石、两级台阶、盲道与门垫
    _box("EntranceStep", Vector3(4.6, 0.14, 0.55), Vector3(-4.0, 0.07, z + 0.32), PLINTH)
    _box("EntranceStep2", Vector3(5.0, 0.07, 0.70), Vector3(-4.0, 0.035, z + 0.92), PLINTH)
    _box("EntranceTactile", Vector3(4.2, 0.02, 0.18), Vector3(-4.0, 0.072, z + 1.16), RIM)
    _box("EntranceMat", Vector3(2.9, 0.02, 0.90), Vector3(-4.0, 0.152, z + 0.46), Color("#232a2a"))
    # 两扇木门：左扇关着，右扇虚掩着往里开
    _wood_door("DoorL", Vector3(-5.75, 1.52, z + 0.10), 0.0, 1.0)
    _wood_door("DoorR", Vector3(-2.25, 1.52, z + 0.10), -19.0, -1.0)
    # 所有门先默认同一把二级弹子锁：右扇门上的黄铜锁板 + 锁芯 + 锁孔。
    var lock := Node3D.new()
    lock.name = "DoorLock"
    lock.position = Vector3(-2.55, 1.18, z + 0.17)
    root.add_child(lock)
    _box_to(lock, "LockPlate", Vector3(0.26, 0.34, 0.07), Vector3.ZERO, Color("#c9a15b"))
    _box_to(lock, "LockCylinder", Vector3(0.16, 0.16, 0.05), Vector3(0.0, -0.02, 0.05), Color("#8a5a2b"))
    _box_to(lock, "LockKeyhole", Vector3(0.05, 0.11, 0.025), Vector3(0.0, -0.02, 0.08), HOLE)
    _box_to(lock, "LockLED", Vector3(0.05, 0.05, 0.02), Vector3(0.0, 0.12, 0.06), RED, true)
    # 门侧壁灯：实体托架 + 灯罩 + 暖色实用光。
    for side: float in [-1.0, 1.0]:
        var lx: float = -4.0 + side * 2.55
        _box("EntranceLampBracket", Vector3(0.08, 0.08, 0.52), Vector3(lx, 3.12, z + 0.34), METAL)
        _cyl("EntranceLampShade", 0.22, 0.16, Vector3(lx, 3.06, z + 0.68), METAL_LIGHT)
        _box("EntranceLampBulb", Vector3(0.20, 0.09, 0.20), Vector3(lx, 2.98, z + 0.68), Color("#e8c98a"), true)
        var lamp := OmniLight3D.new()
        lamp.name = "EntranceLampLight"
        lamp.light_color = Color("#e8c98a")
        lamp.light_energy = 0.45
        lamp.omni_range = 4.8
        lamp.shadow_enabled = false
        lamp.position = Vector3(lx, 2.90, z + 0.72)
        root.add_child(lamp)
    # 门禁面板：与实体门锁分开，只做视觉。
    _box("EntranceIntercom", Vector3(0.20, 0.34, 0.07), Vector3(-6.10, 1.40, z + 0.20), METAL)
    _box("EntranceIntercomButtonA", Vector3(0.055, 0.055, 0.02), Vector3(-6.10, 1.46, z + 0.24), RIM, true)
    _box("EntranceIntercomButtonB", Vector3(0.055, 0.055, 0.02), Vector3(-6.10, 1.34, z + 0.24), RIM, true)
    _box("EntranceIntercomLED", Vector3(0.035, 0.035, 0.02), Vector3(-6.10, 1.56, z + 0.24), Color("#7fe0c0"), true)

    # 雨棚：钢框 + 奶油底面 + 斜撑 + 排水沟 + 两盏罩灯。
    _box("HospitalCanopy", Vector3(7.2, 0.30, 3.6), Vector3(-4.0, 4.05, z + 1.7), WALL_DARK)
    _box("CanopySoffit", Vector3(6.9, 0.06, 3.3), Vector3(-4.0, 3.90, z + 1.7), RIM)
    _box("CanopyEdge", Vector3(7.2, 0.36, 0.16), Vector3(-4.0, 3.90, z + 3.45), PLINTH)
    _box("CanopyGutter", Vector3(7.4, 0.12, 0.14), Vector3(-4.0, 4.12, z + 3.50), METAL)
    # 雨棚前檐招牌：从街道高度也能读到红十字与三条图示色带。
    _box("CanopyFasciaSign", Vector3(3.0, 0.46, 0.08), Vector3(-4.0, 4.02, z + 3.55), PLINTH)
    _box("CanopyFasciaFace", Vector3(2.8, 0.34, 0.03), Vector3(-4.0, 4.02, z + 3.60), RIM)
    _box("CanopyFasciaCrossV", Vector3(0.10, 0.28, 0.03), Vector3(-5.02, 4.02, z + 3.63), RED, true)
    _box("CanopyFasciaCrossH", Vector3(0.28, 0.10, 0.03), Vector3(-5.02, 4.02, z + 3.63), RED, true)
    for index: int in 3:
        _box("CanopyFasciaBar%d" % index, Vector3(0.58, 0.05, 0.03), Vector3(-4.40 + float(index) * 0.40, 4.02, z + 3.63), WALL_DARK)
    for side: float in [-1.0, 1.0]:
        _box("CanopyBracket", Vector3(0.08, 0.08, 1.25), Vector3(-4.0 + side * 2.9, 3.55, z + 0.95), METAL_LIGHT).rotation_degrees.x = 38.0
        ART.i_beam(root, "CanopyPost", 3.9, 0.26, 0.22, 0.03, 0.03, Vector3(-4.0 + side * 3.1, 0.0, z + 3.1), METAL, 0.0)
        _box("CanopyPostBase", Vector3(0.38, 0.06, 0.34), Vector3(-4.0 + side * 3.1, 0.03, z + 3.1), PLINTH)
    for index: int in 2:
        var lx: float = -5.2 + float(index) * 2.4
        _box("CanopyLightHousing%d" % index, Vector3(0.9, 0.08, 0.26), Vector3(lx, 3.88, z + 1.55), METAL)
        _box("CanopyLightPanel%d" % index, Vector3(0.78, 0.03, 0.18), Vector3(lx, 3.83, z + 1.55), Color("#e8d6b0"), true)
        var downlight := OmniLight3D.new()
        downlight.name = "CanopyDownlight"
        downlight.light_color = Color("#e8d6b0")
        downlight.light_energy = 0.40
        downlight.omni_range = 5.0
        downlight.shadow_enabled = false
        downlight.position = Vector3(lx, 3.60, z + 1.60)
        root.add_child(downlight)

    # 红十字：挂在托架上，左边那根托架脱开了，所以整块牌歪着往下坠
    var cross := Node3D.new()
    cross.name = "CrossSign"
    cross.position = Vector3(-4.0, 6.95, z + 0.07)
    cross.rotation_degrees = Vector3(-1.0, 0.0, -9.0)
    root.add_child(cross)
    _box_to(cross, "CrossBack", Vector3(2.6, 2.6, 0.10), Vector3.ZERO, Color("#565e66"))
    _box_to(cross, "CrossV", Vector3(0.82, 2.20, 0.14), Vector3(0.0, 0.0, 0.05), RED, true)
    _box_to(cross, "CrossH", Vector3(2.05, 0.82, 0.14), Vector3(0.0, 0.0, 0.06), RED, true)
    # 左上角撕掉一块，露出底下的黑背板；中间掉了一小块漆
    _box_to(cross, "CrossChip", Vector3(0.55, 0.50, 0.16), Vector3(-0.98, 0.96, 0.07), HOLE).rotation_degrees = Vector3(0.0, 0.0, 16.0)
    _box_to(cross, "CrossPeel", Vector3(0.40, 0.28, 0.02), Vector3(0.70, 0.28, 0.10), WALL_DARK)
    # 托架：右边还连着，左边只剩墙上的一小截
    _rod(Vector3(-2.95, 8.10, z + 0.02), Vector3(-2.98, 7.98, z + 0.09), 0.05, METAL)
    _rod(Vector3(-5.05, 8.10, z + 0.02), Vector3(-4.88, 7.90, z + 0.05), 0.05, RUST)
    # 脱开那侧垂下来的一截钢丝
    _rod(Vector3(-4.62, 6.10, z + 0.22), Vector3(-4.74, 5.74, z + 0.20), 0.025, RUST)

    # 门口坡道、接地、碎石与街具
    _box("EntranceRamp", Vector3(5.6, 0.08, 1.2), Vector3(-4.0, 0.04, z + 2.10), PLINTH)
    ART.bollard(root, Vector3(-7.05, 0.0, z + 1.55))
    ART.bollard(root, Vector3(-0.95, 0.0, z + 1.55))
    ART.planter(root, Vector3(-6.95, 0.0, z + 1.15), 1.0, 5)
    ATMOSPHERE.build_ground_skirt(root, "EntranceSkirt", Vector3(-4.0, 0.0, z + 1.10), Vector2(9.0, 5.0), Color(0.035, 0.033, 0.030), 0.55)
    ATMOSPHERE.build_gravel_cluster(root, "EntranceGravel", Vector3(-6.9, 0.0, z + 1.35), 0.7, 7, 921)
    ART.soft_shadow(root, Vector3(-4.0, 0.01, z + 0.85), 3.2, 0.40)
    # 一具担架车停在入口右侧（不挡门口交互点）。
    var gurney := Node3D.new()
    gurney.name = "EntranceGurney"
    gurney.position = Vector3(-0.55, 0.0, z + 1.70)
    gurney.rotation_degrees.y = -8.0
    root.add_child(gurney)
    ART.block(gurney, "GurneyFrame", Vector3(0.72, 0.10, 1.95), Vector3(0.0, 0.62, 0.0), METAL_LIGHT, 0.02, false, 0.0, SURFACE.Family.MACH)
    ART.block(gurney, "GurneyMattress", Vector3(0.68, 0.12, 1.85), Vector3(0.0, 0.73, 0.0), Color("#b8b2a0"), 0.04, false, 0.0, SURFACE.Family.PAINT_CLEAN)
    for sx: float in [-1.0, 1.0]:
        for sz: float in [-0.72, 0.72]:
            ART.cylinder(gurney, "GurneyWheel", 0.10, 0.05, Vector3(sx * 0.30, 0.10, sz), Color("#1f2626"), false, 0.0, SURFACE.Family.CAST).rotation_degrees.z = 90.0
    ART.block(gurney, "GurneyRail", Vector3(0.68, 0.04, 0.05), Vector3(0.0, 0.88, -0.92), METAL, 0.01, false, 0.0, SURFACE.Family.MACH)


## 木门：以合页为轴，门板朝 facing 方向展开，带上下两块凹板和一把铁把手。
func _wood_door(node_name: String, hinge_at: Vector3, yaw: float, facing: float) -> Node3D:
    var hinge := Node3D.new()
    hinge.name = node_name
    hinge.position = hinge_at
    hinge.rotation_degrees = Vector3(0.0, yaw, 0.0)
    root.add_child(hinge)
    var width := 1.72
    var height := 2.90
    var cx := facing * width * 0.5
    _box_to(hinge, "Slab", Vector3(width, height, 0.10), Vector3(cx, 0.0, 0.0), WOOD_DOOR)
    # 门扇工艺：门梃/冒头、下凹板、上铁丝玻璃、推杆、踢脚板、合页、闭门器、编号牌与磨损。
    # 静态小件全部合批成一个网格，避免一扇门十几条 draw call。
    var entries: Array = []
    var metal := METAL_LIGHT
    # 门梃与冒头
    for sx: float in [-1.0, 1.0]:
        entries.append({"size": Vector3(0.10, height - 0.10, 0.035), "position": Vector3(cx + sx * (width * 0.5 - 0.07), 0.0, 0.055), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    entries.append({"size": Vector3(width - 0.12, 0.10, 0.035), "position": Vector3(cx, height * 0.5 - 0.07, 0.055), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    entries.append({"size": Vector3(width - 0.12, 0.10, 0.035), "position": Vector3(cx, -height * 0.5 + 0.07, 0.055), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    entries.append({"size": Vector3(width - 0.12, 0.09, 0.035), "position": Vector3(cx, 0.02, 0.055), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    # 下部凹板 + 四周凸边
    var panel_y := -0.58
    entries.append({"size": Vector3(width - 0.46, 0.92, 0.012), "position": Vector3(cx, panel_y, 0.058), "color": Color("#4e3423"), "family": SURFACE.Family.PAINT_WORN})
    entries.append({"size": Vector3(width - 0.38, 0.035, 0.022), "position": Vector3(cx, panel_y + 0.47, 0.066), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    entries.append({"size": Vector3(width - 0.38, 0.035, 0.022), "position": Vector3(cx, panel_y - 0.47, 0.066), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    for sx2: float in [-1.0, 1.0]:
        entries.append({"size": Vector3(0.035, 0.92, 0.022), "position": Vector3(cx + sx2 * (width * 0.5 - 0.23), panel_y, 0.066), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    # 上亮子：窗框 + 铁丝网
    var win_y := 0.62
    for sx3: float in [-1.0, 1.0]:
        entries.append({"size": Vector3(0.04, 1.02, 0.03), "position": Vector3(cx + sx3 * 0.58, win_y, 0.066), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
        entries.append({"size": Vector3(0.012, 0.92, 0.012), "position": Vector3(cx + sx3 * 0.19, win_y, 0.075), "color": metal, "family": SURFACE.Family.MACH})
    entries.append({"size": Vector3(1.20, 0.04, 0.03), "position": Vector3(cx, win_y + 0.49, 0.066), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    entries.append({"size": Vector3(1.20, 0.04, 0.03), "position": Vector3(cx, win_y - 0.49, 0.066), "color": WOOD_DARK, "family": SURFACE.Family.PAINT_WORN})
    entries.append({"size": Vector3(0.012, 0.92, 0.012), "position": Vector3(cx, win_y, 0.075), "color": metal, "family": SURFACE.Family.MACH})
    # 推杆、踢脚板与合页
    entries.append({"size": Vector3(width * 0.72, 0.055, 0.055), "position": Vector3(cx, -0.10, 0.105), "color": metal, "family": SURFACE.Family.MACH})
    for sx4: float in [-1.0, 1.0]:
        entries.append({"size": Vector3(0.05, 0.14, 0.055), "position": Vector3(cx + sx4 * width * 0.32, -0.10, 0.082), "color": metal, "family": SURFACE.Family.MACH})
    entries.append({"size": Vector3(width - 0.18, 0.28, 0.03), "position": Vector3(cx, -height * 0.5 + 0.20, 0.062), "color": metal, "family": SURFACE.Family.MACH})
    for hy: float in [-1.05, 0.0, 1.05]:
        entries.append({"size": Vector3(0.10, 0.22, 0.16), "position": Vector3(0.0, hy, 0.0), "color": RUST, "family": SURFACE.Family.CAST})
    # 闭门器 + 编号牌（三颗圆点）
    entries.append({"size": Vector3(0.18, 0.10, 0.11), "position": Vector3(cx - 0.34, 1.16, 0.09), "color": Color("#2a3634"), "family": SURFACE.Family.CAST})
    entries.append({"size": Vector3(0.42, 0.04, 0.04), "position": Vector3(cx + 0.02, 1.12, 0.12), "color": metal, "family": SURFACE.Family.MACH})
    entries.append({"size": Vector3(0.18, 0.11, 0.015), "position": Vector3(cx + 0.54, 0.98, 0.070), "color": RIM, "family": SURFACE.Family.PAINT_CLEAN})
    for dot: int in 3:
        entries.append({"size": Vector3(0.022, 0.022, 0.012), "position": Vector3(cx + 0.485 + float(dot) * 0.055, 0.98, 0.080), "color": HOLE, "family": SURFACE.Family.CAST})
    # 掉漆：真实接触位置（底边、把手旁），不是随机撒脏
    entries.append({"size": Vector3(0.46, 0.58, 0.02), "position": Vector3(cx + facing * 0.22, -0.95, 0.058), "color": WALL_DARK, "family": SURFACE.Family.PAINT_WORN})
    entries.append({"size": Vector3(0.22, 0.30, 0.02), "position": Vector3(cx - facing * 0.30, 0.20, 0.058), "color": WALL_DARK, "family": SURFACE.Family.PAINT_WORN})
    ART.batch_boxes(hinge, "DoorLeafDetail_" + node_name, entries, 0.006, true)
    # 铁丝玻璃
    var glass := _box_to(hinge, "DoorGlass_" + node_name, Vector3(1.12, 0.92, 0.02), Vector3(cx, win_y, 0.058), GLASS)
    glass.material_override = SURFACE.glass(GLASS)
    # 拉手：实体底座 + 杠杆 + 指挡
    var handle := Node3D.new()
    handle.name = "Handle"
    handle.position = Vector3(cx - facing * 0.50, -0.02, 0.10)
    hinge.add_child(handle)
    _box_to(handle, "HandleBack", Vector3(0.10, 0.24, 0.02), Vector3.ZERO, Color("#2a3634"))
    _box_to(handle, "HandleLever", Vector3(0.24, 0.04, 0.04), Vector3(-facing * 0.10, 0.06, 0.06), METAL_LIGHT)
    _box_to(handle, "HandleGrip", Vector3(0.05, 0.10, 0.05), Vector3(-facing * 0.20, 0.06, 0.06), METAL_LIGHT)
    return hinge


# ── 急救车雨棚 ──
func _build_ambulance_bay() -> void:
    _box("BayRoof", Vector3(7.6, 0.34, 7.4), Vector3(9.0, 4.30, 5.4), ROOF)
    _box("BayRim", Vector3(7.8, 0.12, 0.4), Vector3(9.0, 4.42, 9.0), RIM)
    for x in [5.6, 9.0, 12.4]:
        _cyl("BayColumn", 0.16, 4.2, Vector3(x, 2.1, 8.9), FRAME)
    # 急救车
    _box("AmbulanceBody", Vector3(2.15, 1.85, 4.2), Vector3(9.0, 1.25, 5.0), WHITE)
    _box("AmbulanceStripe", Vector3(2.17, 0.28, 3.2), Vector3(9.0, 1.05, 5.1), RED)
    _box("AmbulanceCab", Vector3(1.95, 1.25, 1.5), Vector3(9.0, 0.95, 2.5), Color("#c9ced4"))
    _box("AmbulanceWindshield", Vector3(1.7, 0.6, 0.08), Vector3(9.0, 1.25, 1.78), GLASS)
    _box("AmbulanceLightBar", Vector3(1.2, 0.18, 0.3), Vector3(9.0, 2.25, 2.6), RED, true)
    for side in [-1.0, 1.0]:
        for depth in [-1.4, 1.3]:
            _box("AmbulanceWheel", Vector3(0.28, 0.55, 0.55), Vector3(9.0 + side * 1.02, 0.3, 5.1 + depth), Color("#262b31"))
    # 地面上的急救车位标线与油渍
    _box("BayLine", Vector3(2.8, 0.012, 4.6), Vector3(9.0, 0.03, 5.0), Color("#8b93a0"))
    _cyl("BayStain", 1.1, 0.012, Vector3(11.0, 0.02, 6.6), Color("#232830"))


# ── 屋顶 ──
func _build_roofs() -> void:
    # 病房楼屋顶
    _box("TowerRoof", Vector3(TOWER_W + 0.6, 0.5, DEPTH + 0.6), Vector3(TOWER_X, TOWER_H + 0.25, 0.0), ROOF)
    _box("TowerRimN", Vector3(TOWER_W + 0.6, 0.12, 0.45), Vector3(TOWER_X, TOWER_H + 0.52, -DEPTH * 0.5 - 0.08), RIM)
    _box("TowerRimS", Vector3(TOWER_W + 0.6, 0.12, 0.45), Vector3(TOWER_X, TOWER_H + 0.52, DEPTH * 0.5 + 0.08), RIM)
    _box("TowerRimW", Vector3(0.45, 0.12, DEPTH + 0.15), Vector3(TOWER_X - TOWER_W * 0.5 - 0.08, TOWER_H + 0.52, 0.0), RIM)
    _box("TowerRimE", Vector3(0.45, 0.12, DEPTH + 0.15), Vector3(TOWER_X + TOWER_W * 0.5 + 0.08, TOWER_H + 0.52, 0.0), RIM)
    _box("StairHouse", Vector3(3.4, 2.7, 3.0), Vector3(-1.8, TOWER_H + 1.85, -6.2), Color("#7f8892"))
    _box("StairDoor", Vector3(1.0, 1.9, 0.1), Vector3(-1.8, TOWER_H + 1.45, -4.68), HOLE)
    _box("StairCap", Vector3(3.7, 0.16, 3.3), Vector3(-1.8, TOWER_H + 3.28, -6.2), RIM)
    _cyl("WaterTank", 1.35, 2.6, Vector3(-11.2, TOWER_H + 1.8, -5.0), Color("#6b7480"))
    _cyl("WaterTankCap", 1.4, 0.18, Vector3(-11.2, TOWER_H + 3.2, -5.0), METAL_LIGHT)
    _box("AC_A", Vector3(2.2, 0.8, 2.2), Vector3(-10.15, TOWER_H + 0.85, 3.8), METAL)
    _box("AC_A_Cap", Vector3(2.45, 0.14, 2.45), Vector3(-10.15, TOWER_H + 1.32, 3.8), METAL_LIGHT)
    _box("AC_B", Vector3(1.8, 0.7, 1.8), Vector3(-5.15, TOWER_H + 0.8, 4.8), METAL)
    _cyl("Antenna", 0.09, 3.4, Vector3(-6.2, TOWER_H + 2.2, 5.6), METAL)

    # 门诊翼屋顶：直升机停机坪
    var wing_depth := WING_Z1 - WING_Z0
    var wing_center_z := (WING_Z0 + WING_Z1) * 0.5
    _box("WingRoof", Vector3(WING_W + 0.6, 0.45, wing_depth + 0.6), Vector3(WING_X, WING_H + 0.22, wing_center_z), ROOF)
    _box("WingRimN", Vector3(WING_W + 0.6, 0.12, 0.4), Vector3(WING_X, WING_H + 0.47, WING_Z0 - 0.08), RIM)
    _box("WingRimS", Vector3(WING_W + 0.6, 0.12, 0.4), Vector3(WING_X, WING_H + 0.47, WING_Z1 + 0.08), RIM)
    _box("WingRimE", Vector3(0.4, 0.12, wing_depth + 0.15), Vector3(WING_X + WING_W * 0.5 + 0.08, WING_H + 0.47, wing_center_z), RIM)
    _cyl("HelipadDisc", 3.45, 0.04, Vector3(WING_X, WING_H + 0.48, wing_center_z), Color("#2f3742"))
    # TorusMesh 默认就躺在 XZ 平面上，不要再绕 X 转 90°，否则会立起来变成一个环
    _mesh(root, "HelipadRing", _torus(3.22, 3.40), Vector3(WING_X, WING_H + 0.51, wing_center_z), WHITE, false)
    # 停机坪的 H
    _box("HelipadHL", Vector3(0.30, 0.03, 2.6), Vector3(WING_X - 0.92, WING_H + 0.52, wing_center_z), WHITE)
    _box("HelipadHR", Vector3(0.30, 0.03, 2.6), Vector3(WING_X + 0.92, WING_H + 0.52, wing_center_z), WHITE)
    _box("HelipadHBar", Vector3(1.54, 0.03, 0.30), Vector3(WING_X, WING_H + 0.52, wing_center_z), WHITE)


# ── 做旧 ──
func _build_surface_age() -> void:
    _facade("AgeTowerFront", Vector3(TOWER_X, TOWER_H * 0.5, DEPTH * 0.5 + 0.015), Vector3(1, 0, 0), Vector3(0, 1, 0), TOWER_W, TOWER_H, 13)
    _facade("AgeTowerBack", Vector3(TOWER_X, TOWER_H * 0.5, -DEPTH * 0.5 - 0.015), Vector3(-1, 0, 0), Vector3(0, 1, 0), TOWER_W, TOWER_H, 29)
    _facade("AgeTowerWest", Vector3(TOWER_X - TOWER_W * 0.5 - 0.015, TOWER_H * 0.5, 0.0), Vector3(0, 0, 1), Vector3(0, 1, 0), DEPTH, TOWER_H, 47)
    var wing_depth := WING_Z1 - WING_Z0
    _facade("AgeWingFront", Vector3(WING_X, WING_H * 0.5, WING_Z1 + 0.015), Vector3(1, 0, 0), Vector3(0, 1, 0), WING_W, WING_H, 61)
    _facade("AgeWingEast", Vector3(WING_X + WING_W * 0.5 + 0.015, WING_H * 0.5, (WING_Z0 + WING_Z1) * 0.5), Vector3(0, 0, -1), Vector3(0, 1, 0), wing_depth, WING_H, 79)


func _facade(node_name: String, center: Vector3, right: Vector3, up: Vector3, width: float, height: float, seed_value: int) -> void:
    var cols := 48
    var rows := 22
    var step_u := width / float(cols)
    var step_v := height / float(rows)
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
                var u_point: float = (point - center).dot(right)
                st.set_color(_wall_tint(streak, patch, u_point, point.y, height))
                st.set_normal(outward)
                st.add_vertex(point)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = st.commit()
    var material := StandardMaterial3D.new()
    material.albedo_color = WALL
    material.vertex_color_use_as_albedo = true
    material.roughness = 1.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.disable_receive_shadows = true
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(instance)


func _wall_tint(streak: FastNoiseLite, patch: FastNoiseLite, u: float, height_above_ground: float, wall_height: float) -> Color:
    var tint := Color(1.0, 1.0, 1.0)
    var grime := clampf(1.0 - height_above_ground / 2.8, 0.0, 1.0)
    tint = tint.lerp(Color(0.52, 0.50, 0.44), grime * 0.88)
    var eave := clampf((height_above_ground - (wall_height - 1.6)) / 1.6, 0.0, 1.0)
    tint = tint.lerp(Color(0.63, 0.61, 0.52), eave * 0.5)
    var run := streak.get_noise_1d(u * 2.6) * 0.72 + streak.get_noise_1d(u * 8.5 + 11.0) * 0.28
    if run > 0.05:
        tint = tint.lerp(Color(0.74, 0.72, 0.63), clampf((run - 0.05) * 0.9, 0.0, 0.5))
    var blot := patch.get_noise_2d(u * 1.15, height_above_ground * 1.15)
    if blot > -0.05:
        tint = tint.lerp(Color(0.82, 0.80, 0.71), (blot + 0.05) * 0.5)
    if blot < -0.32:
        tint = tint.lerp(Color(0.98, 0.96, 0.88), clampf((-blot - 0.32) * 0.9, 0.0, 0.55))
    if grime > 0.30 and blot < -0.1:
        tint = tint.lerp(Color(0.50, 0.53, 0.45), (blot + 0.1) * -0.7 + grime * 0.14)
    return tint


# ── 破损与血迹 ──
## 墙面上的血痕与污渍。
## 做旧层给的是均匀的脏，这里补的是"有事件感"的痕迹：
## 檐口淌下来的水渍、窗下的水线、门口拖出来的一道血、墙上的手印和喷溅。
func _build_wall_stains() -> void:
    var z: float = DEPTH * 0.5 + 0.05
    var west_x: float = TOWER_X - TOWER_W * 0.5 - 0.05
    var back_z: float = -DEPTH * 0.5 - 0.05
    var wing_east_x: float = WING_X + WING_W * 0.5 + 0.05
    var wing_back_z: float = WING_Z0 - 0.05
    var dry := Color("#3a1013")
    var blood := Color("#4e1519")
    var fresh := Color("#6b1d22")
    var grime := Color("#57503f")
    var rust := Color("#6a4436")

    # 楼层之间的横向积灰：落在两条窗带中间，不会压到玻璃
    _box("BandDirtA", Vector3(4.2, 0.8, 0.04), Vector3(-8.2, 3.9, z), grime)
    _box("BandDirtB", Vector3(5.0, 0.8, 0.04), Vector3(-1.0, 7.2, z), grime)
    _box("BandDirtC", Vector3(3.4, 0.8, 0.04), Vector3(-7.6, 10.5, z), grime)
    # 竖向雨痕只落在窗与窗之间的空档（窗宽 1.25、间距 2.5）
    for drip_x in [-10.15, -5.15, -0.15, 2.35]:
        _box("Drip", Vector3(0.22, 6.2, 0.04), Vector3(drip_x, 9.0, z), grime)
    # 空调外机下面的锈迹
    _box("RustA", Vector3(0.4, 2.6, 0.04), Vector3(-10.15, 11.0, z), rust)
    _box("RustB", Vector3(0.3, 1.8, 0.04), Vector3(-5.15, 10.6, z), rust)

    # 门口：一片横向拖出来的血，旁边还有两道下滑的血痕
    _box("BloodDrag", Vector3(2.6, 0.50, 0.04), Vector3(-1.9, 3.05, z), blood)
    _box("BloodDrag2", Vector3(1.0, 0.28, 0.04), Vector3(-0.3, 3.05, z), dry)
    _box("BloodSmearA", Vector3(0.55, 1.9, 0.04), Vector3(-7.65, 5.6, z), blood)
    _box("BloodSmearB", Vector3(0.30, 1.1, 0.04), Vector3(-7.65, 2.6, z), fresh)
    # 喷溅：门右侧一片点状
    for index in 9:
        var at := Vector3(-0.45 + float(index % 3) * 0.30, 1.35 + float(index / 3) * 0.42, z)
        var size := Vector3(0.14 + float(index % 2) * 0.09, 0.11 + float(index % 3) * 0.05, 0.04)
        _box("Spray%d" % index, size, at, blood if index % 2 == 0 else fresh)
    # 门框上的血手印
    _box("HandPalm", Vector3(0.28, 0.24, 0.04), Vector3(-5.35, 1.55, z), dry)
    for index in 4:
        _box("HandFinger%d" % index, Vector3(0.06, 0.14, 0.04), Vector3(-5.44 + float(index) * 0.08, 1.76, z), dry).rotation_degrees = Vector3(0.0, 0.0, float(index) * 8.0 - 12.0)
    # 窗台上流下来的血
    _box("BloodSillA", Vector3(0.18, 1.0, 0.04), Vector3(2.35, 2.9, z), blood)
    _box("BloodSillB", Vector3(0.12, 0.7, 0.04), Vector3(-10.15, 6.3, z), dry)
    # 墙脚霉斑
    for index in 4:
        var x := -7.65 + float(index) * 3.6
        _box("Mold%d" % index, Vector3(1.3 + float(index % 2) * 0.4, 0.3, 0.04), Vector3(x, 0.92, z), Color("#3f463a"))

    # 门诊翼正面：一小片血和一道水痕
    var wz: float = WING_Z1 + 0.05
    _box("WingBloodA", Vector3(1.0, 0.9, 0.04), Vector3(7.4, 3.2, wz), blood)
    _box("WingBloodB", Vector3(0.5, 0.5, 0.04), Vector3(9.8, 3.3, wz), dry)
    _box("WingDrip", Vector3(0.2, 1.6, 0.04), Vector3(12.4, 4.2, wz), grime)

    # 西立面、背立面、门诊翼东侧与背面同样要有污渍
    for west_z in [-6.1, -0.1, 5.9]:
        _box("WestDrip", Vector3(0.04, 6.0, 0.22), Vector3(west_x, 8.6, west_z), grime)
    _box("WestBand", Vector3(0.04, 0.8, 4.2), Vector3(west_x, 7.2, -2.0), grime)
    _box("WestMold", Vector3(0.04, 0.3, 2.6), Vector3(west_x, 0.92, 2.0), Color("#3f463a"))
    for back_x in [-9.35, -3.55, 2.25]:
        _box("BackDrip", Vector3(0.22, 6.0, 0.04), Vector3(back_x, 8.6, back_z), grime)
    _box("BackBand", Vector3(4.2, 0.8, 0.04), Vector3(-1.0, 3.9, back_z), grime)
    for east_z in [-5.3, -1.9]:
        _box("WingEastDrip", Vector3(0.04, 4.4, 0.2), Vector3(wing_east_x, 5.4, east_z), grime)
    _box("WingEastBand", Vector3(0.04, 0.7, 3.0), Vector3(wing_east_x, 3.3, -4.0), grime)
    _box("WingBackStain", Vector3(5.0, 3.2, 0.04), Vector3(WING_X, 3.0, wing_back_z), grime)
    _box("WingBackBlood", Vector3(1.6, 1.2, 0.04), Vector3(WING_X + 1.5, 1.4, wing_back_z), blood)


func _build_damage() -> void:
    var z: float = DEPTH * 0.5
    # 楼顶东南角塌了一块
    _box("TowerHole", Vector3(3.0, 3.4, 0.10), Vector3(2.4, 11.2, z + 0.05), HOLE)
    _box("TowerHoleSide", Vector3(0.10, 3.4, 3.0), Vector3(TOWER_X + TOWER_W * 0.5 + 0.05, 11.2, 7.8), HOLE)
    for index in 3:
        var bar := _cyl("TowerRebar%d" % index, 0.03, 0.9, Vector3(2.2 - float(index) * 0.35, 12.6, z + 0.10), RUST)
        bar.rotation_degrees = Vector3(0.0, 0.0, 60.0 + float(index) * 9.0)
    # 檐下的烟熏带
    _box("SootBand", Vector3(6.0, 0.42, 0.05), Vector3(-2.0, TOWER_H - 0.55, z + 0.06), Color("#3f3a30"))
    # 正面墙上的一道斜裂缝
    _box("CrackA", Vector3(0.9, 0.10, 0.04), Vector3(0.9, 8.9, z + 0.05), HOLE).rotation_degrees = Vector3(0.0, 0.0, 34.0)
    _box("CrackB", Vector3(1.1, 0.10, 0.04), Vector3(1.6, 8.1, z + 0.05), HOLE).rotation_degrees = Vector3(0.0, 0.0, -28.0)
    _box("CrackC", Vector3(0.8, 0.09, 0.04), Vector3(2.0, 7.4, z + 0.05), HOLE).rotation_degrees = Vector3(0.0, 0.0, 21.0)
    # 墙脚的碎块
    var rubble := [
        Vector3(1.0, 0.15, z + 0.7), Vector3(-8.2, 0.13, z + 0.6),
        Vector3(-10.2, 0.17, z + 0.9), Vector3(7.2, 0.14, 8.6),
    ]
    for index in rubble.size():
        var size := Vector3(0.55 + float(index % 3) * 0.2, 0.30 + float(index % 2) * 0.14, 0.5 + float(index % 4) * 0.14)
        _box("Rubble%d" % index, size, rubble[index], PLINTH if index % 2 == 0 else WALL_DARK).rotation_degrees = Vector3(
            float(index * 9 % 26) - 13.0, float(index * 37 % 90), float(index * 13 % 22) - 11.0)

    # 翻倒的担架
    var gurney := Node3D.new()
    gurney.name = "FallenGurney"
    gurney.position = Vector3(-7.4, 0.0, z + 2.6)
    gurney.rotation_degrees = Vector3(0.0, 28.0, 74.0)
    root.add_child(gurney)
    _box_to(gurney, "Frame", Vector3(1.5, 0.08, 0.6), Vector3.ZERO, METAL_LIGHT)
    _box_to(gurney, "Mattress", Vector3(1.35, 0.12, 0.52), Vector3(0.0, 0.10, 0.0), Color("#b9bfc6"))
    for index in 4:
        _box_to(gurney, "Wheel", Vector3(0.14, 0.14, 0.14), Vector3(-0.6 + float(index % 2) * 1.2, -0.10, -0.22 + float(index / 2) * 0.44), Color("#2b3036"))

    # 门口的血迹与拖痕：卡通化后改成珊瑚红，保留"这里出过事"的叙事但不做恐怖片。
    var dry := Color("#8f4a45")
    var blood := Color("#c25b52")
    _cyl("BloodPool", 1.15, 0.014, Vector3(-3.2, 0.02, z + 2.3), dry)
    _cyl("BloodPool2", 0.6, 0.014, Vector3(-5.4, 0.02, z + 1.2), blood)
    for index in 4:
        var trail := _box("BloodTrail%d" % index, Vector3(0.4, 0.02, 0.16), Vector3(-2.4 + float(index) * 0.9, 0.03, z + 3.2 + float(index) * 0.55), blood)
        trail.rotation_degrees = Vector3(0.0, -22.0, 0.0)
    # 墙面上的手印与喷溅
    _box("BloodWall", Vector3(0.4, 1.7, 0.03), Vector3(-6.9, 1.4, z + 0.05), blood)
    for index in 5:
        _box("BloodSpray%d" % index, Vector3(0.18, 0.14, 0.03), Vector3(-5.9 + float(index % 3) * 0.45, 1.0 + float(index / 3) * 0.4, z + 0.05), dry)

    # 散落的医疗废物箱
    _box("MedBinA", Vector3(0.9, 0.7, 0.7), Vector3(-9.4, 0.35, z + 1.8), Color("#9c5a5a"))
    _box("MedBinB", Vector3(0.7, 0.55, 0.6), Vector3(-10.4, 0.28, z + 2.4), Color("#7f8a92")).rotation_degrees = Vector3(0.0, 24.0, 0.0)


func _build_collision(size: Vector3) -> void:
    _collider("TowerCollision", Vector3(TOWER_W, TOWER_H, DEPTH), Vector3(TOWER_X, TOWER_H * 0.5, 0.0))
    var wing_depth := WING_Z1 - WING_Z0
    _collider("WingCollision", Vector3(WING_W, WING_H, wing_depth), Vector3(WING_X, WING_H * 0.5, (WING_Z0 + WING_Z1) * 0.5))


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
    var bevel := clampf(minf(size.x, minf(size.y, size.z)) * 0.16, 0.004, 0.045)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = ART.chamfer_box(size, bevel)
    instance.position = at
    instance.material_override = _make_material(color, glow)
    parent.add_child(instance)
    return instance


func _cyl(node_name: String, radius: float, height: float, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 12
    return _mesh(root, node_name, mesh, at, color, glow)


## 两点之间连一根圆柱，用来做托架、钢丝这类小构件。
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


## 材质接管：普通件走 2K 家族分层材质，发光件统一软膝，玻璃走专用玻璃材质。
func _make_material(color: Color, glow: bool) -> Material:
    if glow:
        return SURFACE.glow(color, 0.35)
    if color == GLASS:
        return SURFACE.glass(GLASS)
    if color == HOLE:
        return SURFACE.surface(HOLE, SURFACE.Family.CAST)
    return SURFACE.auto_surface(color)


func _torus(inner: float, outer: float) -> TorusMesh:
    var mesh := TorusMesh.new()
    mesh.inner_radius = inner
    mesh.outer_radius = outer
    mesh.rings = 28
    mesh.ring_segments = 8
    return mesh
