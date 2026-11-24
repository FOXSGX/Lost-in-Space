extends Node3D
class_name RuinInfectedVisual

# 腐墟星「感染体」低模造型（只属于 planet-02，霜烬星不使用）。
#
# 这一版按用户要求改成明确的丧尸读法。判断"像不像丧尸"靠的是四条硬信号，
# 少一条就会读成别的怪物：
#   1. 人形：肩、肘、膝的关节关系必须成立，不能是团块。
#   2. 双臂前伸：这是丧尸最强的识别点，也是第一人称近景最好认的轮廓。
#   3. 头颅垂斜 + 张口：脸必须有黑洞洞的眼窝和张开的下颌。
#   4. 破衣服与伤口：撕开的殖民队工装、露出的肋骨、干涸的血。
#
# 真菌寄生只作为"这一关独有的那点东西"保留：肩背一小丛菌核 + 两根发光菌柄，
# 不再当主体，否则会读成真菌怪物而不是丧尸。
#
# 三种形态仍是 圆 / 宽 / 长 三种近景剪影。相机现在在 1.62 米眼高，
# 玩家能贴近看清脸、肋骨和菌丝，形状仍然比细节优先：
#   步行者 walker —— 站立、双臂前伸；鼓胀者 bloater —— 极宽；爬行者 crawler —— 极低极长。

enum Form { WALKER, BLOATER, CRAWLER }

const FACET := preload("res://scripts/ruin_facet_mesh.gd")
const ART := preload("res://scripts/art_utils.gd")

const PALETTE := {
    "skin": "#8fb9a5",          # 尸皮：低饱和青绿，亮到能在奶油色建筑前读出轮廓
    "skin_deep": "#6f9a86",     # 凹陷、眼窝周边、背光面
    "blood": "#8a3c36",         # 干涸的血：低饱和暗红
    "wound": "#c06458",         # 新鲜的伤口与暴露组织
    "bone": "#d8c9a8",          # 露出的肋骨、下颌骨
    "teeth": "#f3ead4",
    "coverall": "#4b6b74",      # 撕裂的殖民队工装：青蓝
    "coverall_dark": "#3a545c",
    "strap": "#2f4850",
    "boot": "#3a545c",
    "glass": "#26414a",         # 空洞的眼窝与口腔
    "mycelium": "#f0e7d0",      # 菌丝：骨白
    "mycelium_dark": "#d6c8a8",
    "spore": "#d8e46b",         # 孢子发光：全模型唯一的高饱和色
    "gold": "#f0a35d",          # 殖民队队标：暖橙
    "danger": "#ff7a5c",        # 危险环，跨星球一致：红＝敌对
}

# 发光强度必须压低：线性色调映射下超过 1 会直接烧成白色。
const GLOW_POD := 0.55
const GLOW_SAC := 0.35
const GLOW_EYE := 0.60
const GLOW_DANGER := 0.85

# 目标身高。主角实测 2.23 米（原型 2.14 米，加上抬脚离地的余量后是 2.23），
# 敌人要和他在同一量级才有对抗感：步行者与他齐平，鼓胀者略矮但更宽，
# 爬行者是趴着的半身，按体量而不是按身高算。
# 用"实测高度再整体缩放"而不是手写缩放系数——手调容易估错，
# 而且以后改任何一个部件都不用重新算。
const TARGET_HEIGHT := {
    Form.WALKER: 2.23,
    Form.BLOATER: 2.10,
    Form.CRAWLER: 1.15,
}

# 碰撞胶囊半径 = 最终身高 × 这个比例。
# 步行者是细长人形、鼓胀者是宽体、爬行者是摊开的长条，所以比例不同。
const COLLISION_RATIO := {
    Form.WALKER: 0.26,
    Form.BLOATER: 0.40,
    Form.CRAWLER: 0.45,
}

var form: Form = Form.WALKER
var show_danger_markers := true

var _body: Node3D
var _meshes: Array[MeshInstance3D] = []
var _pivots: Dictionary = {}
var _facet_mesh: ArrayMesh
var _base_scale := Vector3.ONE
var _body_pivot: Node3D
var _base_pose: Dictionary = {}
var _belly: MeshInstance3D
var _belly_base_scale := Vector3.ONE
var _anim_time := 0.0
var _phase := 0.0
var _speed := 0.0
var _attack := 0.0
var _flinch_energy := 0.0
var _dead := false


func configure(next_form: Form, with_markers := true) -> void:
    form = next_form
    show_danger_markers = with_markers
    _build()


func _build() -> void:
    _facet_mesh = FACET.icosphere()
    _body = Node3D.new()
    _body.name = "Body"
    add_child(_body)
    match form:
        Form.WALKER:
            _build_walker()
        Form.BLOATER:
            _build_bloater()
        Form.CRAWLER:
            _build_crawler()
    _ground_to_floor()
    _fit_height()
    _body_pivot = _pivots.get("Body", _body) as Node3D
    _capture_base_pose()
    _base_scale = _body.scale
    # 标记与暗斑按缩放后的真实尺寸生成，保证环永远套在身体外沿。
    var extent := _measure()
    var ring_radius := _ring_radius(extent)
    if show_danger_markers:
        _build_danger_markers(ring_radius)
    _build_contact_shadow(extent.radius)


# ── 形态一：步行者 ───────────────────────────────────────────────
# 站立、双臂前伸、头垂向一侧、下颌张开。胸口的工装被撕开，露出肋骨。
func _build_walker() -> void:
    _pivot("Body", Vector3.ZERO)
    _part("Hips", "ico", Vector3(0.17, 0.13, 0.14), Vector3(0.0, 0.86, 0.01), Vector3.ZERO, "coverall")
    _part("PelvisBare", "ico", Vector3(0.13, 0.09, 0.11), Vector3(0.0, 0.79, -0.02), Vector3.ZERO, "skin_deep")
    _part("Torso", "ico", Vector3(0.21, 0.25, 0.16), Vector3(0.0, 1.12, -0.05), Vector3(-14.0, 0.0, 0.0), "coverall")
    # 撕开的胸口：暗红空腔 + 四根横向肋骨露在外面
    _part("ChestCavity", "ico", Vector3(0.14, 0.16, 0.055), Vector3(0.0, 1.06, -0.155), Vector3(-14.0, 0.0, 0.0), "blood")
    _part("RibA", "box", Vector3(0.120, 0.011, 0.018), Vector3(0.0, 1.19, -0.205), Vector3(-14.0, 0.0, 0.0), "bone")
    _part("RibB", "box", Vector3(0.128, 0.011, 0.018), Vector3(0.0, 1.13, -0.215), Vector3(-14.0, 0.0, 0.0), "bone")
    _part("RibC", "box", Vector3(0.112, 0.011, 0.018), Vector3(0.0, 1.07, -0.215), Vector3(-14.0, 0.0, 0.0), "bone")
    _part("RibD", "box", Vector3(0.090, 0.011, 0.018), Vector3(0.0, 1.01, -0.205), Vector3(-14.0, 0.0, 0.0), "bone")
    _part("CollarBone", "ico", Vector3(0.16, 0.045, 0.075), Vector3(0.0, 1.34, -0.09), Vector3.ZERO, "skin")
    _part("RagHem", "ico", Vector3(0.19, 0.075, 0.15), Vector3(0.0, 0.95, 0.0), Vector3.ZERO, "coverall_dark")
    _part("Belt", "box", Vector3(0.17, 0.022, 0.13), Vector3(0.0, 0.92, -0.01), Vector3.ZERO, "strap")
    _part("ChestBadge", "box", Vector3(0.05, 0.026, 0.008), Vector3(-0.10, 1.27, -0.165), Vector3(-14.0, 0.0, 0.0), "gold", 0.25)
    _part("StainChest", "ico", Vector3(0.055, 0.06, 0.014), Vector3(0.07, 1.17, -0.19), Vector3.ZERO, "wound")
    _part("ShoulderL", "ico", Vector3(0.10, 0.085, 0.10), Vector3(-0.24, 1.40, -0.03), Vector3.ZERO, "coverall")
    _part("ShoulderR", "ico", Vector3(0.10, 0.085, 0.10), Vector3(0.24, 1.40, -0.03), Vector3.ZERO, "coverall")

    # 头：向一侧垂斜，眼窝是黑洞，下颌张着，嘴下挂着血
    _pivot("Head", Vector3(0.0, 1.47, -0.07))
    # 头向后仰：46° 俯角下只有仰头，眼窝和张开的嘴才会露在视锥里。
    _pivots["Head"].rotation_degrees = Vector3(-24.0, 10.0, 15.0)
    _part("Neck", "ico", Vector3(0.065, 0.06, 0.065), Vector3(0.0, 0.01, -0.01), Vector3.ZERO, "skin_deep", 0.0, "Head")
    _part("Skull", "ico", Vector3(0.165, 0.175, 0.165), Vector3(0.0, 0.16, -0.04), Vector3.ZERO, "skin", 0.0, "Head")
    # 五官必须贴在/略微凸出颅骨表面：颅骨半径 0.165、球心 z=-0.04，
    # 所以正面在 z≈-0.205。写在这个值里面就会被颅骨整个吞掉——
    # 上一版正是这样，远看只剩一颗光滑的白球。
    _part("SunkenFace", "ico", Vector3(0.105, 0.115, 0.045), Vector3(0.0, 0.13, -0.175), Vector3.ZERO, "skin_deep", 0.0, "Head")
    # 下颌要压到口腔下方，中间留一道黑洞，才读得出"张着嘴"；
    # 下颌盖住口腔会变成一条白条。
    _part("Jaw", "box", Vector3(0.072, 0.038, 0.050), Vector3(0.0, -0.032, -0.178), Vector3(4.0, 0.0, 0.0), "bone", 0.0, "Head")
    _part("MouthCavity", "box", Vector3(0.052, 0.030, 0.026), Vector3(0.0, 0.048, -0.187), Vector3.ZERO, "glass", 0.0, "Head")
    _part("TeethUp", "box", Vector3(0.046, 0.010, 0.016), Vector3(0.0, 0.068, -0.196), Vector3.ZERO, "teeth", 0.0, "Head")
    _part("TeethDown", "box", Vector3(0.044, 0.010, 0.016), Vector3(0.0, 0.000, -0.191), Vector3.ZERO, "teeth", 0.0, "Head")
    _part("SocketL", "ico", Vector3(0.045, 0.048, 0.020), Vector3(-0.058, 0.165, -0.196), Vector3.ZERO, "glass", 0.0, "Head")
    _part("SocketR", "ico", Vector3(0.045, 0.048, 0.020), Vector3(0.058, 0.165, -0.196), Vector3.ZERO, "glass", 0.0, "Head")
    _part("EyeL", "ico", Vector3(0.014, 0.012, 0.009), Vector3(-0.058, 0.163, -0.210), Vector3.ZERO, "spore", GLOW_EYE, "Head")
    _part("EyeR", "ico", Vector3(0.014, 0.012, 0.009), Vector3(0.058, 0.163, -0.210), Vector3.ZERO, "spore", GLOW_EYE, "Head")
    _part("BloodMouth", "box", Vector3(0.036, 0.045, 0.022), Vector3(0.0, -0.030, -0.168), Vector3.ZERO, "blood", 0.0, "Head")

    # 肩背上的那一小丛：这一关的寄生设定，但不再是主体
    _part("BloomRoot", "ico", Vector3(0.10, 0.09, 0.085), Vector3(0.0, 1.28, 0.12), Vector3.ZERO, "mycelium_dark")
    _part("BloomLobe", "ico", Vector3(0.06, 0.055, 0.055), Vector3(-0.05, 1.33, 0.10), Vector3.ZERO, "mycelium")
    _stalk(_body, Vector3(0.02, 1.31, 0.14), Vector3(-0.25, 0.92, 0.30), 0.22, 0.022, "mycelium", "spore")
    _stalk(_body, Vector3(-0.04, 1.29, 0.14), Vector3(0.10, 0.90, 0.42), 0.18, 0.019, "mycelium", "spore")

    # 双臂前伸：整具造型最重要的一条丧尸信号
    _build_reaching_arm("ArmL", Vector3(-0.26, 1.38, -0.04), Vector3(72.0, 0.0, -8.0), true)
    _build_reaching_arm("ArmR", Vector3(0.26, 1.38, -0.04), Vector3(78.0, 0.0, 9.0), false)

    # 腿：一条迈出、一条拖着，拖的那只鞋掉了。
    # 膝盖单独做枢轴，走路时小腿能向后收，不再整条腿当钟摆。
    _pivot("LegL", Vector3(-0.14, 0.88, 0.0))
    _pivots["LegL"].rotation_degrees = Vector3(-12.0, 0.0, 0.0)
    _part("Thigh", "ico", Vector3(0.085, 0.200, 0.090), Vector3(0.0, -0.20, 0.01), Vector3.ZERO, "coverall_dark", 0.0, "LegL")
    var knee_l := _joint("KneeL", Vector3(0.0, -0.38, 0.0), "LegL")
    _part("KneeCapL", "ico", Vector3(0.072, 0.070, 0.075), Vector3.ZERO, Vector3.ZERO, "skin_deep", 0.0, knee_l.name)
    _part("Shin", "ico", Vector3(0.070, 0.180, 0.075), Vector3(0.0, -0.08, -0.01), Vector3.ZERO, "skin", 0.0, knee_l.name)
    _part("Boot", "ico", Vector3(0.090, 0.060, 0.130), Vector3(0.0, -0.28, -0.05), Vector3.ZERO, "boot", 0.0, knee_l.name)
    _pivot("LegR", Vector3(0.14, 0.88, 0.0))
    _pivots["LegR"].rotation_degrees = Vector3(14.0, 0.0, 0.0)
    _part("Thigh", "ico", Vector3(0.085, 0.200, 0.090), Vector3(0.0, -0.20, 0.01), Vector3.ZERO, "coverall_dark", 0.0, "LegR")
    var knee_r := _joint("KneeR", Vector3(0.0, -0.38, 0.0), "LegR")
    _part("KneeCapR", "ico", Vector3(0.072, 0.070, 0.075), Vector3.ZERO, Vector3.ZERO, "skin_deep", 0.0, knee_r.name)
    _part("Shin", "ico", Vector3(0.070, 0.180, 0.075), Vector3(0.0, -0.08, -0.01), Vector3.ZERO, "skin", 0.0, knee_r.name)
    _part("BareFoot", "ico", Vector3(0.085, 0.055, 0.120), Vector3(0.0, -0.28, -0.06), Vector3.ZERO, "skin_deep", 0.0, knee_r.name)


## 前伸的手臂。枢轴绕 X 正转 70~80°，把原本自然下垂的手臂抬到"向前平伸"。
## 上臂挂在肩枢轴下，前臂和手再挂到肘枢轴下——这样走路时肘部能弯，
## 不会整条手臂像一根棍子一样跟着肩膀摆。
func _build_reaching_arm(pivot_name: String, pivot_position: Vector3, pivot_rotation: Vector3, intact: bool) -> void:
    _pivot(pivot_name, pivot_position)
    _pivots[pivot_name].rotation_degrees = pivot_rotation
    var twist := -1.0 if intact else 1.0
    _part("Upper", "ico", Vector3(0.075, 0.160, 0.080), Vector3(0.0, -0.15, 0.0), Vector3.ZERO, "coverall_dark", 0.0, pivot_name)
    var elbow := _joint(pivot_name + "Elbow", Vector3(0.0, -0.30, 0.0), pivot_name)
    _part("ElbowCap", "ico", Vector3(0.070, 0.070, 0.072), Vector3.ZERO, Vector3.ZERO, "skin_deep", 0.0, elbow.name)
    _part("Fore", "ico", Vector3(0.065, 0.140, 0.070), Vector3(0.008 * twist, -0.06, 0.0), Vector3.ZERO, "skin", 0.0, elbow.name)
    _part("Hand", "ico", Vector3(0.075, 0.085, 0.075), Vector3(0.015 * twist, -0.25, -0.005), Vector3.ZERO, "skin_deep", 0.0, elbow.name)
    _part("HandBlood", "ico", Vector3(0.045, 0.040, 0.030), Vector3(0.020 * twist, -0.25, -0.050), Vector3.ZERO, "wound", 0.0, elbow.name)
    # 一只手是完整的五指，另一只手断了两根
    var claw_count := 3 if intact else 2
    for index in claw_count:
        var side := float(index) - float(claw_count - 1) * 0.5
        _stalk(elbow, Vector3(0.015 * twist + side * 0.032, -0.32, -0.01), Vector3(side * 3.0, -1.0, -0.10), 0.10, 0.014, "skin_deep")
    if not intact:
        _part("ExposedBone", "box", Vector3(0.020, 0.090, 0.020), Vector3(0.0, -0.04, -0.052), Vector3.ZERO, "bone", 0.0, elbow.name)


# ── 形态二：鼓胀者 ───────────────────────────────────────────────
# 胀尸。肚子撑成一整个囊，衣服撑裂，皮肤上爬满暗色血管；
# 头向后仰、嘴张着，双臂垂在身侧。俯视是"宽"。
func _build_bloater() -> void:
    _pivot("Body", Vector3.ZERO)
    _belly = _part("Belly", "ico", Vector3(0.42, 0.36, 0.38), Vector3(0.0, 0.64, -0.02), Vector3.ZERO, "skin")
    _belly_base_scale = _belly.scale
    _part("BellyUnder", "ico", Vector3(0.34, 0.22, 0.32), Vector3(0.0, 0.45, 0.0), Vector3.ZERO, "skin_deep")
    _part("BellyLobeL", "ico", Vector3(0.18, 0.16, 0.16), Vector3(-0.30, 0.55, -0.06), Vector3.ZERO, "skin_deep")
    _part("BellyLobeR", "ico", Vector3(0.18, 0.16, 0.16), Vector3(0.30, 0.55, -0.06), Vector3.ZERO, "skin_deep")
    # 皮肤下的血管：三道暗色斜纹，避免肚子读成一颗白球
    _part("VeinA", "box", Vector3(0.014, 0.160, 0.010), Vector3(0.0, 0.72, -0.395), Vector3(0.0, 0.0, 18.0), "blood")
    _part("VeinB", "box", Vector3(0.014, 0.140, 0.010), Vector3(0.0, 0.62, -0.405), Vector3(0.0, 0.0, -22.0), "blood")
    _part("VeinC", "box", Vector3(0.012, 0.100, 0.010), Vector3(0.0, 0.52, -0.395), Vector3(0.0, 0.0, 8.0), "blood")
    _part("Rupture", "ico", Vector3(0.14, 0.12, 0.09), Vector3(0.14, 0.76, -0.30), Vector3.ZERO, "wound")
    _part("RuptureCore", "ico", Vector3(0.095, 0.10, 0.06), Vector3(0.17, 0.68, -0.36), Vector3.ZERO, "blood")
    _part("SacMain", "ico", Vector3(0.10, 0.095, 0.085), Vector3(0.0, 0.86, -0.32), Vector3.ZERO, "spore", GLOW_SAC, "Body", 0.70)
    _part("SacSide", "ico", Vector3(0.085, 0.080, 0.070), Vector3(-0.20, 0.80, -0.30), Vector3.ZERO, "spore", GLOW_SAC, "Body", 0.75)
    _part("Chest", "ico", Vector3(0.27, 0.22, 0.22), Vector3(0.0, 1.10, -0.07), Vector3(-6.0, 0.0, 0.0), "coverall")
    _part("ChestRib", "box", Vector3(0.10, 0.012, 0.015), Vector3(0.0, 1.10, -0.245), Vector3(-6.0, 0.0, 0.0), "bone")
    _part("RagHem", "ico", Vector3(0.34, 0.10, 0.30), Vector3(0.0, 0.98, -0.03), Vector3.ZERO, "coverall_dark")
    _part("ChestBadge", "box", Vector3(0.05, 0.026, 0.008), Vector3(-0.11, 1.14, -0.235), Vector3(-6.0, 0.0, 0.0), "gold", 0.25)

    # 头要够大、够高，并且向后仰——否则会被自己撑起来的肚子吃掉，
    # 俯视下只剩一颗"雪人脑袋"。
    _pivot("Head", Vector3(0.0, 1.30, -0.13))
    _pivots["Head"].rotation_degrees = Vector3(-26.0, 0.0, -10.0)
    _part("Neck", "ico", Vector3(0.075, 0.060, 0.075), Vector3(0.0, 0.0, -0.01), Vector3.ZERO, "skin_deep", 0.0, "Head")
    _part("Skull", "ico", Vector3(0.175, 0.180, 0.170), Vector3(0.0, 0.145, -0.02), Vector3.ZERO, "skin", 0.0, "Head")
    # 颅骨半径 0.175、球心 z=-0.02 → 正面在 z≈-0.195，五官必须写到这个值之外
    _part("SunkenFace", "ico", Vector3(0.115, 0.115, 0.045), Vector3(0.0, 0.115, -0.160), Vector3.ZERO, "skin_deep", 0.0, "Head")
    _part("Jaw", "box", Vector3(0.075, 0.042, 0.050), Vector3(0.0, -0.048, -0.168), Vector3(-10.0, 0.0, 0.0), "bone", 0.0, "Head")
    _part("MouthCavity", "box", Vector3(0.052, 0.030, 0.026), Vector3(0.0, 0.028, -0.176), Vector3.ZERO, "glass", 0.0, "Head")
    _part("TeethUp", "box", Vector3(0.048, 0.011, 0.016), Vector3(0.0, 0.052, -0.186), Vector3.ZERO, "teeth", 0.0, "Head")
    _part("TeethDown", "box", Vector3(0.046, 0.011, 0.016), Vector3(0.0, -0.018, -0.181), Vector3.ZERO, "teeth", 0.0, "Head")
    _part("SocketL", "ico", Vector3(0.046, 0.050, 0.021), Vector3(-0.062, 0.155, -0.181), Vector3.ZERO, "glass", 0.0, "Head")
    _part("SocketR", "ico", Vector3(0.046, 0.050, 0.021), Vector3(0.062, 0.155, -0.181), Vector3.ZERO, "glass", 0.0, "Head")
    _part("EyeL", "ico", Vector3(0.014, 0.012, 0.009), Vector3(-0.062, 0.153, -0.195), Vector3.ZERO, "spore", GLOW_EYE, "Head")
    _part("EyeR", "ico", Vector3(0.014, 0.012, 0.009), Vector3(0.062, 0.153, -0.195), Vector3.ZERO, "spore", GLOW_EYE, "Head")
    _part("BloodMouth", "box", Vector3(0.040, 0.052, 0.022), Vector3(0.0, -0.045, -0.158), Vector3.ZERO, "blood", 0.0, "Head")

    _part("BloomRoot", "ico", Vector3(0.14, 0.11, 0.11), Vector3(0.0, 1.14, 0.14), Vector3.ZERO, "mycelium_dark")
    _stalk(_body, Vector3(-0.05, 1.16, 0.16), Vector3(-0.35, 0.88, 0.32), 0.24, 0.024, "mycelium", "spore")
    _stalk(_body, Vector3(0.06, 1.13, 0.16), Vector3(0.18, 0.90, 0.38), 0.20, 0.021, "mycelium", "spore")
    _stalk(_body, Vector3(0.0, 1.10, 0.18), Vector3(0.0, 0.55, 0.84), 0.16, 0.018, "mycelium_dark")

    for side in [-1.0, 1.0]:
        var label := "L" if side < 0.0 else "R"
        # 手臂垂在身侧、略向前伸，读作"没力气抬起来"。
        # 肩点往外、往前挪，避免整条手臂被肚子完全挡住；前臂再挂一个肘关节。
        _pivot("Arm" + label, Vector3(side * 0.57, 1.00, -0.16))
        _pivots["Arm" + label].rotation_degrees = Vector3(30.0 if side < 0.0 else 26.0, 0.0, side * -13.0)
        _part("Upper", "ico", Vector3(0.110, 0.160, 0.110), Vector3(0.0, -0.15, 0.0), Vector3.ZERO, "coverall_dark", 0.0, "Arm" + label)
        var elbow := _joint("Arm" + label + "Elbow", Vector3(0.0, -0.30, 0.0), "Arm" + label)
        _part("ElbowCap", "ico", Vector3(0.095, 0.085, 0.095), Vector3.ZERO, Vector3.ZERO, "skin_deep", 0.0, elbow.name)
        _part("Fore", "ico", Vector3(0.100, 0.140, 0.100), Vector3(side * 0.01, -0.06, 0.0), Vector3.ZERO, "skin", 0.0, elbow.name)
        _part("Hand", "ico", Vector3(0.110, 0.100, 0.100), Vector3(side * 0.02, -0.22, 0.0), Vector3.ZERO, "skin_deep", 0.0, elbow.name)
        _part("HandBlood", "ico", Vector3(0.060, 0.050, 0.040), Vector3(side * 0.02, -0.28, -0.03), Vector3.ZERO, "wound", 0.0, elbow.name)

        _pivot("Leg" + label, Vector3(side * 0.19, 0.52, 0.0))
        _part("Thigh", "ico", Vector3(0.110, 0.150, 0.110), Vector3(side * 0.01, -0.10, 0.0), Vector3.ZERO, "coverall_dark", 0.0, "Leg" + label)
        _part("Boot", "ico", Vector3(0.130, 0.100, 0.160), Vector3(side * 0.02, -0.32, -0.04), Vector3.ZERO, "boot", 0.0, "Leg" + label)


# ── 形态三：爬行者 ───────────────────────────────────────────────
# 只剩上半身的丧尸，用两条手臂拖着身体往前爬，腰以下撕断。
# 俯视是"长"。这是丧尸题材里最好认的低姿态，也保住了和前两种的剪影差异。
func _build_crawler() -> void:
    _pivot("Body", Vector3.ZERO)
    _part("Chest", "ico", Vector3(0.24, 0.20, 0.30), Vector3(0.0, 0.38, -0.10), Vector3.ZERO, "coverall")
    _part("ChestCavity", "ico", Vector3(0.15, 0.09, 0.18), Vector3(0.0, 0.28, -0.10), Vector3.ZERO, "blood")
    _part("BackSeam", "box", Vector3(0.030, 0.012, 0.22), Vector3(0.0, 0.565, -0.10), Vector3.ZERO, "bone")
    _part("RibL", "box", Vector3(0.060, 0.011, 0.016), Vector3(-0.10, 0.560, -0.22), Vector3(0.0, 14.0, 0.0), "bone")
    _part("RibR", "box", Vector3(0.060, 0.011, 0.016), Vector3(0.10, 0.560, -0.22), Vector3(0.0, -14.0, 0.0), "bone")
    # 撕断的腰：暗红断面 + 拖在后面的组织
    _part("HipStump", "ico", Vector3(0.20, 0.16, 0.14), Vector3(0.0, 0.34, 0.26), Vector3.ZERO, "wound")
    _part("GutsA", "ico", Vector3(0.09, 0.07, 0.10), Vector3(-0.06, 0.30, 0.40), Vector3.ZERO, "blood")
    _part("GutsB", "ico", Vector3(0.07, 0.06, 0.09), Vector3(0.07, 0.28, 0.46), Vector3.ZERO, "wound")
    _part("ChestBadge", "box", Vector3(0.045, 0.024, 0.008), Vector3(-0.10, 0.50, -0.28), Vector3.ZERO, "gold", 0.25)

    _pivot("Head", Vector3(0.0, 0.46, -0.46))
    _pivots["Head"].rotation_degrees = Vector3(-28.0, 0.0, 11.0)
    _part("Neck", "ico", Vector3(0.075, 0.070, 0.075), Vector3(0.0, -0.02, 0.06), Vector3.ZERO, "skin_deep", 0.0, "Head")
    _part("Skull", "ico", Vector3(0.145, 0.150, 0.140), Vector3(0.0, 0.10, 0.0), Vector3.ZERO, "skin", 0.0, "Head")
    # 颅骨半径 0.145、球心 z=0 → 正面在 z≈-0.14
    _part("SunkenFace", "ico", Vector3(0.098, 0.100, 0.040), Vector3(0.0, 0.075, -0.118), Vector3.ZERO, "skin_deep", 0.0, "Head")
    _part("Jaw", "box", Vector3(0.068, 0.038, 0.048), Vector3(0.0, -0.048, -0.128), Vector3(-10.0, 0.0, 0.0), "bone", 0.0, "Head")
    _part("MouthCavity", "box", Vector3(0.046, 0.028, 0.022), Vector3(0.0, 0.008, -0.135), Vector3.ZERO, "glass", 0.0, "Head")
    _part("TeethUp", "box", Vector3(0.043, 0.010, 0.015), Vector3(0.0, 0.028, -0.143), Vector3.ZERO, "teeth", 0.0, "Head")
    _part("TeethDown", "box", Vector3(0.041, 0.010, 0.015), Vector3(0.0, -0.024, -0.139), Vector3.ZERO, "teeth", 0.0, "Head")
    _part("SocketL", "ico", Vector3(0.041, 0.044, 0.019), Vector3(-0.053, 0.110, -0.133), Vector3.ZERO, "glass", 0.0, "Head")
    _part("SocketR", "ico", Vector3(0.041, 0.044, 0.019), Vector3(0.053, 0.110, -0.133), Vector3.ZERO, "glass", 0.0, "Head")
    _part("EyeL", "ico", Vector3(0.013, 0.011, 0.008), Vector3(-0.053, 0.108, -0.146), Vector3.ZERO, "spore", GLOW_EYE, "Head")
    _part("EyeR", "ico", Vector3(0.013, 0.011, 0.008), Vector3(0.053, 0.108, -0.146), Vector3.ZERO, "spore", GLOW_EYE, "Head")
    _part("BloodMouth", "box", Vector3(0.034, 0.045, 0.020), Vector3(0.0, -0.062, -0.120), Vector3.ZERO, "blood", 0.0, "Head")

    _part("BloomRoot", "ico", Vector3(0.12, 0.075, 0.14), Vector3(0.0, 0.50, 0.02), Vector3.ZERO, "mycelium_dark")
    _stalk(_body, Vector3(-0.03, 0.55, -0.08), Vector3(-0.30, 0.90, 0.28), 0.20, 0.020, "mycelium", "spore")
    _stalk(_body, Vector3(0.04, 0.54, 0.06), Vector3(0.22, 0.90, 0.36), 0.17, 0.018, "mycelium", "spore")
    _stalk(_body, Vector3(0.0, 0.52, 0.16), Vector3(0.0, 0.72, 0.70), 0.14, 0.016, "mycelium_dark")

    # 两条手臂撑地向前，是这一形态最关键的阅读点
    _build_reaching_arm("ArmL", Vector3(-0.22, 0.34, -0.30), Vector3(80.0, 0.0, -10.0), true)
    _build_reaching_arm("ArmR", Vector3(0.22, 0.34, -0.30), Vector3(76.0, 0.0, 12.0), false)

    # 只剩下一条腿的残肢
    _pivot("LegStump", Vector3(-0.18, 0.34, 0.30))
    _pivots["LegStump"].rotation_degrees = Vector3(-64.0, 0.0, 0.0)
    _part("Thigh", "ico", Vector3(0.075, 0.140, 0.080), Vector3(0.0, -0.10, 0.0), Vector3.ZERO, "coverall_dark", 0.0, "LegStump")
    _part("StumpWound", "ico", Vector3(0.060, 0.050, 0.060), Vector3(0.0, -0.20, 0.0), Vector3.ZERO, "blood", 0.0, "LegStump")


## 落脚暗斑：复用霜烬星那一轮的 art_utils。
## 46° 俯视下缺少地面接触关系时，敌人会像贴纸一样浮在地面上。
func _build_contact_shadow(footprint: float) -> void:
    ART.contact_shadow(self, Vector3.ZERO, footprint * 0.95, 0.34)


func _build_danger_markers(ring_radius: float) -> void:
    # 跨星球沿用 SpaceEnemy3D 的敌对语言：红色危险环 + 红色点光。
    var ring := MeshInstance3D.new()
    var ring_mesh := TorusMesh.new()
    var outer := ring_radius
    ring_mesh.inner_radius = outer - 0.07
    ring_mesh.outer_radius = outer
    ring_mesh.rings = 28
    ring_mesh.ring_segments = 8
    ring.position.y = 0.07
    ring.mesh = ring_mesh
    ring.material_override = _material("danger", GLOW_DANGER, 1.0)
    add_child(ring)
    var light := OmniLight3D.new()
    light.name = "DangerGlow"
    light.light_color = Color(PALETTE["danger"])
    light.light_energy = 1.8
    light.omni_range = 3.2
    light.position.y = 0.8
    add_child(light)


# ── 构件辅助 ─────────────────────────────────────────────────────

func _pivot(pivot_name: String, pivot_position: Vector3) -> Node3D:
    if _pivots.has(pivot_name):
        return _pivots[pivot_name]
    var pivot := Node3D.new()
    pivot.name = pivot_name
    pivot.position = pivot_position
    _body.add_child(pivot)
    _pivots[pivot_name] = pivot
    return pivot


## 二级关节（膝、肘）。挂在上游枢轴下，动画只转这里，身体分件不会被拆散。
func _joint(joint_name: String, joint_position: Vector3, parent_name: String) -> Node3D:
    if _pivots.has(joint_name):
        return _pivots[joint_name]
    var parent := _pivots.get(parent_name, _body) as Node3D
    var joint := Node3D.new()
    joint.name = joint_name
    joint.position = joint_position
    parent.add_child(joint)
    _pivots[joint_name] = joint
    return joint


## 记录每个枢轴的初始姿态。动画在初始姿态上叠加，不覆盖造型师写好的站姿。
func _capture_base_pose() -> void:
    _base_pose.clear()
    for key in _pivots:
        var pivot := _pivots[key] as Node3D
        if pivot == null:
            continue
        _base_pose[key] = {
            "pos": pivot.position,
            "rot": pivot.rotation,
            "scale": pivot.scale,
        }


func _pose_rot(pivot_name: String, offset: Vector3) -> void:
    if not _base_pose.has(pivot_name):
        return
    var pivot := _pivots.get(pivot_name) as Node3D
    if pivot == null:
        return
    pivot.rotation = (_base_pose[pivot_name]["rot"] as Vector3) + offset


func _pose_pos(pivot_name: String, offset: Vector3) -> void:
    if not _base_pose.has(pivot_name):
        return
    var pivot := _pivots.get(pivot_name) as Node3D
    if pivot == null:
        return
    pivot.position = (_base_pose[pivot_name]["pos"] as Vector3) + offset


## half_size 是半尺寸：ico 直接当半径用，box 用边长 2 的基础网格再缩放，
## 两种形状的"尺寸"含义一致，写数据时不用换算。
func _part(part_name: String, shape: String, half_size: Vector3, at: Vector3, rot_degrees: Vector3, color_key: String, glow := 0.0, parent_name := "Body", alpha := 1.0) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = part_name
    if shape == "ico":
        instance.mesh = _facet_mesh
    elif shape == "box":
        var box := BoxMesh.new()
        box.size = Vector3(2.0, 2.0, 2.0)
        instance.mesh = box
    var material := _material(color_key, glow, alpha)
    if shape == "ico":
        material.vertex_color_use_as_albedo = true
    instance.material_override = material
    instance.position = at
    instance.rotation_degrees = rot_degrees
    instance.scale = half_size
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    var parent := _pivots.get(parent_name, _body) as Node3D
    parent.add_child(instance)
    _meshes.append(instance)
    return instance


## 菌柄：从 base 沿 direction 长出一根锥形柄，末端带一颗发光孢子荚。
func _stalk(parent: Node3D, base: Vector3, direction: Vector3, length: float, radius: float, color_key: String, pod_key := "") -> void:
    var dir := direction.normalized()
    var stalk := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius * 0.42
    mesh.bottom_radius = radius
    mesh.height = length
    mesh.radial_segments = 6
    stalk.mesh = mesh
    stalk.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), base + dir * length * 0.5)
    stalk.material_override = _material(color_key, 0.0, 1.0)
    stalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(stalk)
    _meshes.append(stalk)
    if pod_key.is_empty():
        return
    var pod := MeshInstance3D.new()
    pod.mesh = _facet_mesh
    var pod_material := _material(pod_key, GLOW_POD, 1.0)
    pod_material.vertex_color_use_as_albedo = true
    pod.material_override = pod_material
    pod.position = base + dir * length
    pod.scale = Vector3.ONE * maxf(radius * 1.7, 0.026)
    parent.add_child(pod)
    _meshes.append(pod)


func _material(color_key: String, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
    var color := Color(PALETTE[color_key])
    var linear := color.srgb_to_linear()
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(linear.r, linear.g, linear.b, alpha)
    material.roughness = 1.0
    if alpha < 1.0:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
    if glow > 0.0:
        material.emission_enabled = true
        material.emission = linear
        material.emission_energy_multiplier = glow
        material.roughness = 0.42
    return material


## 把整具模型抬到地面上。
## 必须沿父链累乘变换：肢体部件挂在 pivot 下，只看自身 transform 会漏掉 pivot 的
## 偏移与旋转，结果模型被整体抬高、悬在危险环上方。
func _ground_to_floor() -> void:
    var lowest := INF
    for instance in _meshes:
        for vertex in _vertices_of(instance):
            lowest = minf(lowest, (_transform_to_self(instance) * vertex).y)
    if is_finite(lowest):
        _body.position.y -= lowest


## 按目标身高整体缩放。先量真实顶点，再算比例，
## 这样换任何部件都不用重新手算缩放系数。
func _fit_height() -> void:
    var extent := _measure()
    if extent.height <= 0.001:
        return
    var factor: float = float(TARGET_HEIGHT[form]) / float(extent.height)
    _body.scale *= factor
    _body.position.y = 0.0
    _ground_to_floor()


## 在 self 的局部空间里量出高度与最宽半径（水平方向的最大外沿）。
func _measure() -> Dictionary:
    var lowest := INF
    var highest := -INF
    var radius := 0.0
    for instance in _meshes:
        var to_self := _transform_to_self(instance)
        for vertex in _vertices_of(instance):
            var point: Vector3 = to_self * vertex
            lowest = minf(lowest, point.y)
            highest = maxf(highest, point.y)
            radius = maxf(radius, Vector2(point.x, point.z).length())
    if not is_finite(lowest):
        lowest = 0.0
        highest = 1.0
    return {
        "height": highest - lowest,
        "top": highest,
        "radius": radius,
    }


## 每帧叠加步态、呼吸、前扑和受击回弹。
## planar_speed 由 RuinInfected3D 从 velocity / 实际位移算出；attack_strength 0~1。
func animate(delta: float, planar_speed: float, attack_strength := 0.0) -> void:
    if _body_pivot == null or _dead:
        return
    _anim_time += delta
    _speed = lerpf(_speed, clampf(planar_speed, 0.0, 7.0), 1.0 - exp(-8.0 * delta))
    _attack = lerpf(_attack, clampf(attack_strength, 0.0, 1.0), 1.0 - exp(-13.0 * delta))
    _flinch_energy = maxf(_flinch_energy - delta * 4.2, 0.0)

    var stride := clampf(_speed / 2.0, 0.0, 1.0)
    _phase += delta * (1.35 + _speed * 2.15)
    var attack_wave := sin(_attack * PI)
    var flinch := _flinch_energy
    var bob := sin(_phase * 2.0) * 0.022 * stride
    var waddle := 0.0
    if form == Form.BLOATER:
        # 鼓胀者即使停下来也会慢慢左右晃，肚子里的囊在呼吸。
        waddle = sin(_anim_time * 1.45) * 0.05

    _pose_pos("Body", Vector3(0.0, sin(_anim_time * 1.5) * 0.006 + bob, -0.07 * attack_wave + 0.045 * flinch))
    _pose_rot("Body", Vector3(-0.07 * stride + 0.14 * attack_wave - 0.10 * flinch, 0.0, sin(_phase) * 0.045 * stride + waddle))
    _pose_rot("Head", Vector3(0.05 * attack_wave - 0.12 * flinch, sin(_phase * 0.55) * 0.09 + 0.06 * flinch, sin(_phase * 0.8) * 0.05))

    var leg_swing := sin(_phase)
    _pose_rot("LegL", Vector3(leg_swing * 0.45 * stride + 0.10 * attack_wave, 0.0, 0.0))
    _pose_rot("LegR", Vector3(-leg_swing * 0.45 * stride + 0.10 * attack_wave, 0.0, 0.0))
    _pose_rot("KneeL", Vector3(maxf(0.0, -leg_swing) * 0.58 * stride + 0.10 + 0.30 * attack_wave, 0.0, 0.0))
    _pose_rot("KneeR", Vector3(maxf(0.0, leg_swing) * 0.58 * stride + 0.10 + 0.30 * attack_wave, 0.0, 0.0))
    _pose_rot("LegStump", Vector3(sin(_phase + 0.7) * 0.22 * stride, 0.0, 0.0))

    var arm_swing := sin(_phase + PI)
    # 爬行者靠两条手臂拖身体，摆幅要比站立形态大，否则还是像趴着滑。
    var arm_amp := 0.28 if form == Form.CRAWLER else 0.12
    _pose_rot("ArmL", Vector3(arm_swing * arm_amp * stride - 0.16 * attack_wave, 0.0, sin(_phase * 0.6) * 0.03 * stride))
    _pose_rot("ArmR", Vector3(-arm_swing * arm_amp * stride - 0.16 * attack_wave, 0.0, -sin(_phase * 0.6) * 0.03 * stride))
    _pose_rot("ArmLElbow", Vector3(0.08 + maxf(0.0, arm_swing) * 0.18 * stride + 0.28 * attack_wave, 0.0, 0.0))
    _pose_rot("ArmRElbow", Vector3(0.08 + maxf(0.0, -arm_swing) * 0.18 * stride + 0.28 * attack_wave, 0.0, 0.0))

    if _belly != null:
        var pulse := sin(_anim_time * 2.0)
        _belly.scale = _belly_base_scale * Vector3(1.0 + pulse * 0.012, 1.0 - pulse * 0.008, 1.0 + pulse * 0.012)


## 受击时做一次很短的挤压回弹。第一人称近距离下，不靠飘字也能确认打中了。
func flinch() -> void:
    if _body == null:
        return
    _flinch_energy = 1.0
    var tween := create_tween()
    tween.tween_property(_body, "scale", _base_scale * Vector3(1.07, 0.93, 1.07), 0.055)
    tween.tween_property(_body, "scale", _base_scale, 0.16)


## 死亡后停掉程序化动作，倒地和压扁交给 RuinInfected3D 的 Tween。
func die() -> void:
    _dead = true


## 交给游戏侧接入用的数值：碰撞胶囊、标签高度、危险环。
## 全部由实测尺寸推导，尺寸再改也不会和视觉脱节。
func stat_specs() -> Dictionary:
    var extent := _measure()
    var body_height: float = maxf(float(extent.height), 0.55)
    var radius: float = clampf(body_height * float(COLLISION_RATIO[form]), 0.35, 0.90)
    var height: float = body_height * 0.86
    return {
        "ring": _ring_radius(extent),
        "collision_radius": radius,
        "collision_height": height,
        "collision_y": height * 0.5,
        "label_y": float(extent.top) + 0.30,
    }


## 危险环半径。爬行者前后拉得很长，直接取最远点会让环大到没有意义，
## 所以上限压到 1.35（直径 2.7 米），比身体宽一圈即可。
func _ring_radius(extent: Dictionary) -> float:
    return clampf(float(extent.radius) * 1.15, 0.45, 1.35)


func lowest_point_y() -> float:
    var lowest := INF
    for instance in _meshes:
        for vertex in _vertices_of(instance):
            lowest = minf(lowest, (global_transform * (_transform_to_self(instance) * vertex)).y)
    return lowest


func _transform_to_self(node: Node3D) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current: Node3D = node
    while current != null and current != self:
        result = current.transform * result
        current = current.get_parent() as Node3D
    return result


func _vertices_of(instance: MeshInstance3D) -> PackedVector3Array:
    var mesh := instance.mesh
    if mesh == null:
        return PackedVector3Array()
    var faces := mesh.get_faces()
    if faces.size() > 0:
        return faces
    var result := PackedVector3Array()
    var box := mesh.get_aabb()
    for x in [box.position.x, box.end.x]:
        for y in [box.position.y, box.end.y]:
            for z in [box.position.z, box.end.z]:
                result.append(Vector3(x, y, z))
    return result
