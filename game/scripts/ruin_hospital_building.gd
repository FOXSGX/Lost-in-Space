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
var accent := Color("#c76b6b")
var entry_ring: MeshInstance3D

const WALL := Color("#a89c80")
const WALL_DARK := Color("#94886d")
const PLINTH := Color("#6b6450")
const ROOF := Color("#585244")
const RIM := Color("#b5ab92")
const METAL := Color("#5f5949")
const METAL_LIGHT := Color("#9b9380")
const FRAME := Color("#b1a890")
const GLASS := Color("#242a2e")
const HOLE := Color("#1c1a16")
const RED := Color("#a83f3f")
const WHITE := Color("#ded6c0")
const RUST := Color("#7a5140")
const WOOD := Color("#5a4a3a")
const WOOD_DOOR := Color("#6b5140")
const WOOD_DARK := Color("#4a3628")

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
    _build_surface_age()
    _build_wall_stains()
    _build_damage()
    _build_collision(size)
    var half_z: float = size.z * 0.5
    entry_ring = _mesh(root, "EntryRing", _torus(1.5, 1.56), Vector3(-4.0, 0.08, half_z + 1.6), accent, true)
    entry_ring.visible = false


# ── 主体 ──
func _build_tower() -> void:
    _box("TowerBody", Vector3(TOWER_W, TOWER_H, DEPTH), Vector3(TOWER_X, TOWER_H * 0.5, 0.0), WALL)
    _box("TowerPlinth", Vector3(TOWER_W + 0.4, 0.7, DEPTH + 0.4), Vector3(TOWER_X, 0.35, 0.0), PLINTH)
    # 楼层腰线：四层
    _box("TowerBandA", Vector3(TOWER_W + 0.4, 0.26, DEPTH + 0.4), Vector3(TOWER_X, FLOOR, 0.0), PLINTH)
    _box("TowerBandB", Vector3(TOWER_W + 0.4, 0.26, DEPTH + 0.4), Vector3(TOWER_X, FLOOR * 2.0, 0.0), PLINTH)
    _box("TowerBandC", Vector3(TOWER_W + 0.4, 0.26, DEPTH + 0.4), Vector3(TOWER_X, FLOOR * 3.0, 0.0), PLINTH)
    # 顶部檐口
    _box("TowerCornice", Vector3(TOWER_W + 0.5, 0.34, DEPTH + 0.5), Vector3(TOWER_X, TOWER_H - 0.3, 0.0), PLINTH)


func _build_wing() -> void:
    var depth := WING_Z1 - WING_Z0
    var center_z := (WING_Z0 + WING_Z1) * 0.5
    _box("WingBody", Vector3(WING_W, WING_H, depth), Vector3(WING_X, WING_H * 0.5, center_z), WALL_DARK)
    _box("WingPlinth", Vector3(WING_W + 0.4, 0.6, depth + 0.4), Vector3(WING_X, 0.3, center_z), PLINTH)
    _box("WingBand", Vector3(WING_W + 0.4, 0.24, depth + 0.4), Vector3(WING_X, 3.7, center_z), PLINTH)
    _box("WingCornice", Vector3(WING_W + 0.45, 0.3, depth + 0.45), Vector3(WING_X, WING_H - 0.3, center_z), PLINTH)


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
            _window(Vector3(x, y, DEPTH * 0.5 + 0.05), Vector2(1.25, 1.6), Vector3(0, 0, 0))
    # 病房楼西侧
    for floor in 4:
        var y := 1.9 + float(floor) * FLOOR
        for index in 6:
            _window_side(Vector3(-TOWER_W * 0.5 + TOWER_X - 0.05, y, -7.6 + float(index) * 3.0), Vector2(1.2, 1.6))
    # 病房楼背面
    for floor in 4:
        var y := 1.9 + float(floor) * FLOOR
        for index in 6:
            _window(Vector3(-10.8 + float(index) * 2.9, y, -DEPTH * 0.5 - 0.05), Vector2(1.25, 1.6), Vector3(0, 180, 0))
    # 门诊翼：正面两层三扇、东侧两层三扇
    for floor in 2:
        var y := 1.9 + float(floor) * 3.4
        for index in 3:
            _window(Vector3(6.2 + float(index) * 2.4, y, WING_Z1 + 0.05), Vector2(1.3, 1.7), Vector3.ZERO)
    for floor in 2:
        var y := 1.9 + float(floor) * 3.4
        for index in 3:
            _window_side(Vector3(WING_X + WING_W * 0.5 + 0.05, y, -7.0 + float(index) * 3.4), Vector2(1.3, 1.7))


func _window(at: Vector3, size: Vector2, rotation: Vector3) -> void:
    var pane := _box("Window", Vector3(size.x, size.y, 0.08), at, GLASS)
    pane.rotation_degrees = rotation
    var sill := _box("Sill", Vector3(size.x + 0.22, 0.14, 0.16), at + Vector3(0.0, -size.y * 0.5 - 0.10, 0.04), FRAME)
    sill.rotation_degrees = rotation


func _window_side(at: Vector3, size: Vector2) -> void:
    _box("WindowSide", Vector3(0.08, size.y, size.x), at, GLASS)
    _box("SillSide", Vector3(0.16, 0.14, size.x + 0.22), at + Vector3(0.04, -size.y * 0.5 - 0.10, 0.0), FRAME)


# ── 入口：玻璃门 + 雨棚 + 红十字 ──
func _build_entrance() -> void:
    var z: float = DEPTH * 0.5
    # 门洞：做成带门套的老式双开门，不是玻璃自动门
    # 门洞内部只用一块很薄的暗面当背景，别做成实心盒子，
    # 否则门和门套会被整个吞进去，正面看只剩一个黑洞。
    _box("EntranceRecess", Vector3(3.7, 3.3, 0.12), Vector3(-4.0, 1.65, z - 0.06), HOLE)
    _box("EntranceFrameL", Vector3(0.22, 3.45, 0.30), Vector3(-5.95, 1.72, z + 0.08), PLINTH)
    _box("EntranceFrameR", Vector3(0.22, 3.45, 0.30), Vector3(-2.05, 1.72, z + 0.08), PLINTH)
    _box("EntranceFrameT", Vector3(4.12, 0.24, 0.30), Vector3(-4.0, 3.44, z + 0.08), PLINTH)
    # 门槛石
    _box("EntranceStep", Vector3(4.4, 0.14, 0.9), Vector3(-4.0, 0.07, z + 0.55), PLINTH)
    # 两扇木门：左扇关着，右扇虚掩着往里开
    _wood_door("DoorL", Vector3(-5.75, 1.52, z + 0.02), 0.0, 1.0)
    _wood_door("DoorR", Vector3(-2.25, 1.52, z + 0.02), -19.0, -1.0)
    # 门楣上的旧灯罩（早就没电了）
    _box("DoorLamp", Vector3(0.55, 0.22, 0.28), Vector3(-4.0, 3.72, z + 0.24), METAL)

    # 雨棚
    _box("HospitalCanopy", Vector3(7.2, 0.30, 3.6), Vector3(-4.0, 4.05, z + 1.7), WALL_DARK)
    _box("CanopyEdge", Vector3(7.2, 0.36, 0.16), Vector3(-4.0, 3.90, z + 3.45), PLINTH)
    _cyl("CanopyPostL", 0.15, 3.9, Vector3(-7.1, 1.95, z + 3.1), FRAME)
    _cyl("CanopyPostR", 0.15, 3.9, Vector3(-0.9, 1.95, z + 3.1), FRAME)

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

    # 门口坡道
    _box("EntranceRamp", Vector3(5.6, 0.10, 1.4), Vector3(-4.0, 0.05, z + 2.2), PLINTH)


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
    # 上下两块凹板
    _box_to(hinge, "PanelTop", Vector3(width - 0.42, 1.05, 0.03), Vector3(cx, 0.66, 0.06), WOOD_DARK)
    _box_to(hinge, "PanelBottom", Vector3(width - 0.42, 0.90, 0.03), Vector3(cx, -0.58, 0.06), WOOD_DARK)
    # 把手与锈掉的合页
    _box_to(hinge, "Handle", Vector3(0.09, 0.09, 0.24), Vector3(cx - facing * 0.55, 0.02, 0.12), METAL_LIGHT)
    _box_to(hinge, "HingeTop", Vector3(0.10, 0.22, 0.16), Vector3(0.0, 0.95, 0.0), RUST)
    _box_to(hinge, "HingeBottom", Vector3(0.10, 0.22, 0.16), Vector3(0.0, -0.95, 0.0), RUST)
    # 掉漆：露出底下发白的旧漆
    _box_to(hinge, "PeelA", Vector3(0.46, 0.58, 0.02), Vector3(cx + facing * 0.22, -0.95, 0.06), WALL_DARK)
    _box_to(hinge, "PeelB", Vector3(0.22, 0.30, 0.02), Vector3(cx - facing * 0.30, 0.20, 0.06), WALL_DARK)
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

    # 门口的血迹与拖痕
    var dry := Color("#3a1013")
    var blood := Color("#4e1519")
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


func _make_material(color: Color, glow: bool) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.72
    if glow:
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = 0.12
        material.roughness = 0.4
    return material


func _torus(inner: float, outer: float) -> TorusMesh:
    var mesh := TorusMesh.new()
    mesh.inner_radius = inner
    mesh.outer_radius = outer
    mesh.rings = 28
    mesh.ring_segments = 8
    return mesh
