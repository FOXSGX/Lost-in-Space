extends RefCounted

# 俯视 2.5D 的通用美术工具。
#
# 这个脚本只生成视觉节点，不参与碰撞、玩法数值和联机同步。
# 之所以单独成文件：霜烬星的地表、地貌和道具分散在 main_3d.gd
# 与 frost_obstacle_3d.gd 里，而"俯视下怎么读出一个体积"是所有物件共用的规则。

const SHADOW_TEXTURE_SIZE := 64
# 暗斑本身的颜色和透明度。压得很暗是因为它叠在已经很亮的雪面上，
# 太浅的话在白色地面上完全看不见。
const SHADOW_TINT := Color(0.02, 0.07, 0.12, 0.38)
# 抬起一点点避免与地面 z-fighting。地形噪声振幅约 ±0.21，
# 所以贴地暗斑不能只抬 0.01。
const SHADOW_LIFT := 0.05

static var _shadow_material: StandardMaterial3D
static var _shadow_texture: GradientTexture2D


## 贴地的柔和暗斑。
## 相机是 46° 俯角的正交视角，物件底部与雪面的接触关系在画面上本来就弱，
## 少了这一层，椅子、电池、冰岩都会像贴纸一样浮在地表。
static func contact_shadow(parent: Node3D, world_position: Vector3, radius: float, strength := 0.38) -> MeshInstance3D:
    var shadow := MeshInstance3D.new()
    shadow.name = "ContactShadow"
    var quad := QuadMesh.new()
    quad.size = Vector2(radius * 2.0, radius * 2.0)
    shadow.mesh = quad
    # QuadMesh 默认朝 +Z，绕 X 轴 -90° 后法线朝上，正好平铺在地面上。
    shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
    shadow.position = world_position + Vector3(0.0, SHADOW_LIFT, 0.0)
    shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    shadow.material_override = shadow_material(strength)
    parent.add_child(shadow)
    return shadow


## 暗斑材质按透明度缓存：整张霜烬星有上百个物件，
## 每个都新建一份材质会让批次碎掉。
static func shadow_material(strength: float) -> StandardMaterial3D:
    if _shadow_material == null:
        _shadow_material = StandardMaterial3D.new()
        _shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        _shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        _shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
        _shadow_material.disable_receive_shadows = true
        _shadow_material.albedo_texture = radial_fade_texture()
    var material := _shadow_material.duplicate() as StandardMaterial3D
    material.albedo_color = Color(SHADOW_TINT.r, SHADOW_TINT.g, SHADOW_TINT.b, SHADOW_TINT.a * clampf(strength / 0.38, 0.0, 2.0))
    return material


## 中心实、边缘透明的圆形渐变。硬边圆片会被读成"地上画了个圈"，
## 只有边缘虚化才像阴影。
static func radial_fade_texture() -> GradientTexture2D:
    if _shadow_texture == null:
        var gradient := Gradient.new()
        gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
        gradient.colors = PackedColorArray([
            Color(1.0, 1.0, 1.0, 1.0),
            Color(1.0, 1.0, 1.0, 0.52),
            Color(1.0, 1.0, 1.0, 0.0),
        ])
        _shadow_texture = GradientTexture2D.new()
        _shadow_texture.gradient = gradient
        _shadow_texture.fill = GradientTexture2D.FILL_RADIAL
        _shadow_texture.fill_from = Vector2(0.5, 0.5)
        _shadow_texture.fill_to = Vector2(1.0, 0.5)
        _shadow_texture.width = SHADOW_TEXTURE_SIZE
        _shadow_texture.height = SHADOW_TEXTURE_SIZE
    return _shadow_texture
