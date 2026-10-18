extends Node3D
class_name ProtagonistVisual

const MODEL_PATH := "res://assets/characters/protagonist_model.json"
const SKIN_DIR := "res://assets/characters/skins/"
const DEFAULT_SKIN := "ranger"
const SHIELD_DOME_PATH := "res://assets/characters/tools/shield_dome.glb"
const WALK_RATE := 11.0
const GROUND_CLEARANCE := 0.035

var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_elbow: Node3D
var _right_elbow: Node3D
var _left_knee: Node3D
var _right_knee: Node3D
var _head: Node3D
var _body: Node3D
var _battery: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []
var _palette: Dictionary = {}
var _parts_cache: Array = []
var _geometry_points: Dictionary = {}
var _time := 0.0
var _hit_time := 0.0
var _attack_time := 0.0
var _revive_time := 0.0
var _was_downed := false
var _last_health := 5
var _rescuing := false
var _team_color := Color("#55dfff")
var _last_yaw := 0.0
var _turn_lag := 0.0
var _tool_id := ""
var _tool_node: Node3D
var _shield_dome: Node3D
var skin_id := DEFAULT_SKIN
var _mesh_base_color: Dictionary = {}

func _ready() -> void:
    _load_palette()
    if ResourceLoader.exists(_skin_path()) and _build_from_blender():
        return
    var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
    if file == null:
        push_error("主角模型数据未找到：" + MODEL_PATH)
        return
    var data: Dictionary = JSON.parse_string(file.get_as_text())
    _palette = data.get("palette", {})
    _parts_cache = data.get("parts", [])
    _body = Node3D.new()
    _body.name = "Body"
    add_child(_body)
    _left_arm = _pivot("LeftArmPivot", Vector3(-0.40, 1.20, 0.0))
    _right_arm = _pivot("RightArmPivot", Vector3(0.40, 1.20, 0.0))
    _left_leg = _pivot("LeftLegPivot", Vector3(-0.23, 0.61, 0.0))
    _right_leg = _pivot("RightLegPivot", Vector3(0.23, 0.61, 0.0))
    var parents := {
        "LeftArmPivot": _left_arm,
        "RightArmPivot": _right_arm,
        "LeftLegPivot": _left_leg,
        "RightLegPivot": _right_leg
    }
    var facet_mesh := _make_smooth_icosphere()
    for part in data.get("parts", []):
        var instance := MeshInstance3D.new()
        instance.name = str(part["name"])
        instance.mesh = facet_mesh if part["shape"] == "ico" else BoxMesh.new()
        if part["shape"] == "box":
            instance.mesh.size = Vector3.ONE
        _cache_geometry(instance.mesh)
        instance.position = _vec3(part["position"])
        instance.scale = _vec3(part["size"])
        var material := _material(Color(_palette[part["color"]]))
        material.vertex_color_use_as_albedo = part["shape"] == "ico"
        instance.material_override = material
        instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        var parent: Node3D = parents.get(part.get("parent", ""), _body)
        parent.add_child(instance)
        _meshes.append(instance)
    _build_battery()
    _build_identifier()
    _keep_above_ground()
    if _tool_id != "":
        set_tool_model(_tool_id)

func _build_battery() -> void:
    _battery = MeshInstance3D.new()
    _battery.name = "CarriedBattery"
    _battery.mesh = _make_smooth_icosphere()
    _battery.position = Vector3(0.0, 0.87, 0.60)
    _battery.scale = Vector3(0.17, 0.25, 0.17)
    _battery.material_override = _material(Color("#ffd45d"), true)
    _battery.visible = false
    _body.add_child(_battery)

func _load_palette() -> void:
    var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
    if file == null:
        return
    var data: Dictionary = JSON.parse_string(file.get_as_text())
    _palette = data.get("palette", {})
    _parts_cache = data.get("parts", [])

func _build_identifier() -> void:
    var identifier := MeshInstance3D.new()
    identifier.name = "PlayerIdentifier"
    var stripe := BoxMesh.new()
    stripe.size = Vector3(0.40, 0.07, 0.025)
    identifier.mesh = stripe
    identifier.position = Vector3(0.0, 1.20, 0.43)
    identifier.material_override = _material(_team_color, true)
    _body.add_child(identifier)

func _skin_path() -> String:
    var candidate: String = SKIN_DIR + "skin_%s.glb" % skin_id
    if ResourceLoader.exists(candidate):
        return candidate
    return SKIN_DIR + "skin_%s.glb" % DEFAULT_SKIN

func set_skin(next_skin: String) -> void:
    if next_skin.is_empty():
        return
    if next_skin == skin_id and _body != null:
        return
    skin_id = next_skin
    if not is_inside_tree():
        return
    if _body != null:
        _body.queue_free()
        _body = null
    _meshes.clear()
    _mesh_base_color.clear()
    _left_arm = null
    _right_arm = null
    _left_leg = null
    _right_leg = null
    _left_elbow = null
    _right_elbow = null
    _left_knee = null
    _right_knee = null
    _head = null
    _tool_node = null
    _shield_dome = null
    if ResourceLoader.exists(_skin_path()):
        _build_from_blender()
    if _tool_id != "":
        set_tool_model(_tool_id)

func _build_from_blender() -> bool:
    _palette["cyan_glow"] = _palette.get("cyan_glow", "#3fd8ff")
    _palette["amber_glow"] = _palette.get("amber_glow", "#ffb347")
    var packed: PackedScene = ResourceLoader.load(_skin_path()) as PackedScene
    if packed == null:
        return false
    var root_node: Node3D = packed.instantiate() as Node3D
    if root_node == null:
        return false
    var body: Node3D = root_node.find_child("Body", true, false) as Node3D
    if body == null:
        root_node.queue_free()
        return false
    # 重建一个名为 Body 的视觉根，保持与旧版一致的节点路径（Body/Helmet、Body/LeftArmPivot/...）。
    _body = Node3D.new()
    _body.name = "Body"
    add_child(_body)
    for child in body.get_children():
        body.remove_child(child)
        child.owner = null
        _body.add_child(child)
    root_node.queue_free()
    _left_arm = _body.find_child("LeftArmPivot", true, false) as Node3D
    _right_arm = _body.find_child("RightArmPivot", true, false) as Node3D
    _left_leg = _body.find_child("LeftLegPivot", true, false) as Node3D
    _right_leg = _body.find_child("RightLegPivot", true, false) as Node3D
    _left_elbow = _body.find_child("LeftElbowPivot", true, false) as Node3D
    _right_elbow = _body.find_child("RightElbowPivot", true, false) as Node3D
    _left_knee = _body.find_child("LeftKneePivot", true, false) as Node3D
    _right_knee = _body.find_child("RightKneePivot", true, false) as Node3D
    _head = _body.find_child("HeadPivot", true, false) as Node3D
    if _left_arm == null or _right_arm == null or _left_leg == null or _right_leg == null:
        return false
    for node in _body.find_children("*", "MeshInstance3D", true, false):
        var instance: MeshInstance3D = node as MeshInstance3D
        if instance.mesh == null:
            continue
        _cache_geometry(instance.mesh)
        # 颜色取自皮肤 GLB 自带的材质，保证每套皮肤配色不同；再叠加自发光便于命中/倒地染色。
        var base_color := Color("#6b94b4")
        var source_material := instance.mesh.surface_get_material(0) as StandardMaterial3D
        if source_material != null:
            base_color = source_material.albedo_color
        var material := _material(base_color, _is_glow_mesh(instance.name), 2.4)
        instance.material_override = material
        _mesh_base_color[instance] = base_color
        instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        _meshes.append(instance)
    _build_battery()
    _build_identifier()
    _keep_above_ground()
    if _tool_id != "":
        set_tool_model(_tool_id)
    return true

func _is_glow_mesh(mesh_name: String) -> bool:
    for keyword in ["Core", "Glow", "Thruster", "PulseStrip", "Emblem", "AntennaTip", "Stripe", "VisorGlint"]:
        if mesh_name.contains(keyword):
            return true
    return false

func _palette_color_for(mesh_name: String) -> String:
    if mesh_name.contains("VisorGlint"):
        return "visor_glint"
    if mesh_name.contains("Visor"):
        return "visor"
    if _is_glow_mesh(mesh_name):
        return "cyan_glow"
    if mesh_name.contains("ChestPanel"):
        return "chest"
    if mesh_name.contains("YellowShoulder"):
        return "yellow"
    if mesh_name.contains("Plate") or mesh_name.contains("Forearm") or mesh_name.contains("Collar") \
            or mesh_name.contains("HelmetCrest") or mesh_name.contains("Ear") or mesh_name.contains("ShoulderPad"):
        return "plate"
    if mesh_name.contains("Boot") or mesh_name.contains("Glove") or mesh_name.contains("Antenna") \
            or mesh_name.contains("Jaw") or mesh_name.contains("Belt") or mesh_name.contains("Hips") \
            or mesh_name.contains("Strap") or mesh_name.contains("Pouch") or mesh_name.contains("Neck"):
        return "suit_dark"
    return "suit"

func set_team_color(color: Color) -> void:
    _team_color = color

func set_tool_model(tool_id: String) -> void:
    _tool_id = tool_id
    if _right_arm == null:
        return
    if _tool_node != null and is_instance_valid(_tool_node):
        _tool_node.queue_free()
        _tool_node = null
    if tool_id == "":
        return
    var path := "res://assets/characters/tools/tool_%s.glb" % tool_id
    if not ResourceLoader.exists(path):
        return
    var packed := ResourceLoader.load(path) as PackedScene
    if packed == null:
        return
    var instance := packed.instantiate() as Node3D
    if instance == null:
        return
    instance.name = "CharacterTool"
    # 背挂式：工具斜挂在背包上，第三人称背后视角能看清轮廓。
    instance.rotation_degrees = Vector3(-90.0, 0.0, 12.0)
    instance.position = Vector3(0.46, 1.04, 0.34)
    instance.scale = Vector3.ONE * 1.7
    _body.add_child(instance)
    _tool_node = instance

func set_shield_visible(visible_state: bool) -> void:
    if not visible_state:
        if _shield_dome != null:
            _shield_dome.visible = false
        return
    if _shield_dome == null:
        if not ResourceLoader.exists(SHIELD_DOME_PATH):
            return
        var packed := ResourceLoader.load(SHIELD_DOME_PATH) as PackedScene
        if packed == null:
            return
        _shield_dome = packed.instantiate() as Node3D
        if _shield_dome == null:
            return
        _shield_dome.name = "ShieldDome"
        _shield_dome.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
        _body.add_child(_shield_dome)
    _shield_dome.visible = true

func set_resonance_visibility_priority(enabled: bool) -> void:
    var priority: int = 20 if enabled else 0
    for instance in _meshes:
        var material: StandardMaterial3D = instance.material_override as StandardMaterial3D
        if material != null:
            material.no_depth_test = enabled
            material.render_priority = priority
    for extra in [_battery, _body.get_node_or_null("PlayerIdentifier") if _body != null else null]:
        var extra_mesh: MeshInstance3D = extra as MeshInstance3D
        if extra_mesh == null:
            continue
        var extra_material: StandardMaterial3D = extra_mesh.material_override as StandardMaterial3D
        if extra_material != null:
            extra_material.no_depth_test = enabled
            extra_material.render_priority = priority

func _pivot(pivot_name: String, pivot_position: Vector3) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = pivot_name
    pivot.position = pivot_position
    _body.add_child(pivot)
    return pivot

func _vec3(values: Array) -> Vector3:
    return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _material(color: Color, glow := false, energy := 0.65) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.albedo_color.a = 1.0
    material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
    material.roughness = 1.0
    if glow:
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = energy
    return material

func _make_smooth_icosphere() -> ArrayMesh:
    var gold := (1.0 + sqrt(5.0)) / 2.0
    var points: Array[Vector3] = [
        Vector3(-1,gold,0), Vector3(1,gold,0), Vector3(-1,-gold,0), Vector3(1,-gold,0),
        Vector3(0,-1,gold), Vector3(0,1,gold), Vector3(0,-1,-gold), Vector3(0,1,-gold),
        Vector3(gold,0,-1), Vector3(gold,0,1), Vector3(-gold,0,-1), Vector3(-gold,0,1)
    ]
    var faces := [
        [0,11,5], [0,5,1], [0,1,7], [0,7,10], [0,10,11],
        [1,5,9], [5,11,4], [11,10,2], [10,7,6], [7,1,8],
        [3,9,4], [3,4,2], [3,2,6], [3,6,8], [3,8,9],
        [4,9,5], [2,4,11], [6,2,10], [8,6,7], [9,8,1]
    ]
    var verts := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    for face in faces:
        var a := points[face[0]].normalized()
        var b := points[face[1]].normalized()
        var c := points[face[2]].normalized()
        var ab := (a + b).normalized()
        var bc := (b + c).normalized()
        var ca := (c + a).normalized()
        for triangle in [[a,ab,ca], [b,bc,ab], [c,ca,bc], [ab,bc,ca]]:
            var normal: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
            if normal.dot(triangle[0]) < 0.0:
                triangle.reverse()
                normal = -normal
            # ArrayMesh 的正面采用顺时针顶点顺序，光照法线仍然朝外。
            triangle.reverse()
            var shade := clampf(0.80 + 0.18 * normal.dot(Vector3(-0.45, 0.78, -0.38).normalized()), 0.62, 0.98)
            for vertex in triangle:
                verts.append(vertex)
                normals.append(vertex.normalized())
                colors.append(Color(shade, shade, shade, 1.0))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func trigger_attack() -> void:
    _attack_time = 0.22

func set_rescuing(active: bool) -> void:
    _rescuing = active

func update_state(delta: float, direction: Vector2, is_downed: bool, scanning: bool, carrying: bool, health: int, lock_facing_to_parent: bool = false) -> void:
    if _body == null:
        return
    _time += delta
    _hit_time = maxf(_hit_time - delta, 0.0)
    _attack_time = maxf(_attack_time - delta, 0.0)
    _revive_time = maxf(_revive_time - delta, 0.0)
    if health < _last_health and not is_downed:
        _hit_time = 0.34
    if _was_downed and not is_downed:
        _revive_time = 0.7
    _last_health = health
    _was_downed = is_downed
    if lock_facing_to_parent:
        # 共振星的角色根节点由第三人称相机控制朝向，视觉子树不能再按移动向量覆盖它。
        rotation.y = 0.0
    elif direction.length() > 0.08 and not is_downed:
        rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.y), minf(delta * 13.0, 1.0))
    var moving := direction.length() > 0.08 and not scanning and not is_downed
    # 转向惯性：身体比朝向慢半拍，急转弯时有重量感。
    var yaw_delta := wrapf(rotation.y - _last_yaw, -PI, PI)
    _last_yaw = rotation.y
    _turn_lag = lerpf(_turn_lag, clampf(-yaw_delta * 6.0, -0.30, 0.30), minf(delta * 6.0, 1.0))
    var phase := _time * 8.4
    # 二次谐波让摆动有“抬腿快、落脚慢”的节奏差，不再是纯正弦。
    var wave := sin(phase) + 0.22 * sin(phase * 2.0)
    var stride := 0.45 if moving else 0.0
    var hip_left := wave * stride
    var hip_right := sin(phase + PI) * stride + 0.22 * sin((phase + PI) * 2.0) * stride
    _left_leg.rotation.x = lerpf(_left_leg.rotation.x, hip_left, minf(delta * 16.0, 1.0))
    _right_leg.rotation.x = lerpf(_right_leg.rotation.x, hip_right, minf(delta * 16.0, 1.0))
    # 膝盖：腿向后摆时弯曲，落地时伸直，避免整条腿像木棍一样甩。
    if _left_knee != null:
        var bend_left := maxf(0.0, -sin(phase + 0.6)) * (0.95 if moving else 0.0)
        _left_knee.rotation.x = lerpf(_left_knee.rotation.x, bend_left, minf(delta * 18.0, 1.0))
    if _right_knee != null:
        var bend_right := maxf(0.0, -sin(phase + PI + 0.6)) * (0.95 if moving else 0.0)
        _right_knee.rotation.x = lerpf(_right_knee.rotation.x, bend_right, minf(delta * 18.0, 1.0))
    # 手臂与腿反向摆动，肘部保持自然弯曲。
    var arm_left := -hip_left * 0.75
    var arm_right := -hip_right * 0.75
    if _rescuing:
        arm_left = -0.85
        arm_right = -0.85
    if _attack_time > 0.0:
        arm_right = -1.25 * sin((_attack_time / 0.22) * PI)
    _left_arm.rotation.x = lerpf(_left_arm.rotation.x, arm_left, minf(delta * 16.0, 1.0))
    _right_arm.rotation.x = lerpf(_right_arm.rotation.x, arm_right, minf(delta * 20.0, 1.0))
    if _left_elbow != null:
        _left_elbow.rotation.x = lerpf(_left_elbow.rotation.x, -0.35 - 0.30 * maxf(0.0, -sin(phase)), minf(delta * 14.0, 1.0))
    if _right_elbow != null:
        _right_elbow.rotation.x = lerpf(_right_elbow.rotation.x, -0.35 - 0.30 * maxf(0.0, -sin(phase + PI)), minf(delta * 14.0, 1.0))
    # 躯干：走路前倾并轻微侧摆；迈步时身体下沉，保证支撑脚始终贴地。
    var lean := 0.10 if moving else 0.0
    var sway := sin(phase) * 0.05 if moving else 0.0
    var bob := -0.10 * absf(sin(phase)) if moving else 0.012 * sin(_time * 1.8)
    _body.rotation.x = lerpf(_body.rotation.x, lean, minf(delta * 8.0, 1.0))
    _body.position.y = lerpf(_body.position.y, -0.38 if is_downed else bob, minf(delta * 10.0, 1.0))
    _body.rotation.z = lerpf(_body.rotation.z, 0.28 if is_downed else sway, minf(delta * 9.0, 1.0))
    # 攻击时上半身反向拧转，配合手臂挥击。
    var attack_twist := 0.32 * sin((_attack_time / 0.22) * PI) if _attack_time > 0.0 else 0.0
    _body.rotation.y = _turn_lag - attack_twist
    if _head != null:
        _head.rotation.x = lerpf(_head.rotation.x, -lean * 0.7, minf(delta * 8.0, 1.0))
        var idle_scan := 0.0 if moving else sin(_time * 0.55) * 0.28
        _head.rotation.y = lerpf(_head.rotation.y, idle_scan, minf(delta * 3.0, 1.0))
    _body.scale.y = lerpf(_body.scale.y, 0.65 if is_downed else 1.0, minf(delta * 9.0, 1.0))
    _battery.visible = carrying
    for instance in _meshes:
        var mat := instance.material_override as StandardMaterial3D
        var base: Color = _mesh_base_color.get(instance, Color(_palette.get(_part_color(instance.name), "#6b94b4")))
        mat.albedo_color = base.lerp(Color("#ff4e55"), 0.8 if _hit_time > 0.0 else (0.34 if is_downed else 0.0))
        if _rescuing and instance.name == "ChestPanel":
            mat.albedo_color = Color("#ffe198").lerp(base, 0.28 + 0.22 * sin(_time * 12.0))
    if _revive_time > 0.0:
        _body.scale.x = 1.0 + 0.12 * sin(_revive_time * 20.0)
        _body.scale.z = _body.scale.x
    else:
        _body.scale.x = lerpf(_body.scale.x, 1.0, minf(delta * 8.0, 1.0))
        _body.scale.z = _body.scale.x
    _keep_above_ground()

func _cache_geometry(mesh: Mesh) -> void:
    if _geometry_points.has(mesh):
        return
    var unique: Dictionary = {}
    for surface in mesh.get_surface_count():
        var arrays := mesh.surface_get_arrays(surface)
        for vertex in arrays[Mesh.ARRAY_VERTEX]:
            unique[vertex] = true
    _geometry_points[mesh] = PackedVector3Array(unique.keys())

func lowest_vertex_y() -> float:
    var lowest := INF
    var root_inverse := global_transform.affine_inverse()
    for instance in _meshes:
        var to_root := root_inverse * instance.global_transform
        var points: PackedVector3Array = _geometry_points[instance.mesh]
        for vertex in points:
            lowest = minf(lowest, (to_root * vertex).y)
    return lowest

func _keep_above_ground() -> void:
    # 同时处理摆腿、身体起伏、倒地压缩与救起动画；相机和碰撞体不被抬高。
    var lowest := lowest_vertex_y()
    if lowest < GROUND_CLEARANCE:
        _body.position.y += GROUND_CLEARANCE - lowest

func _part_color(part_name: String) -> String:
    for part in _parts_cache:
        if part["name"] == part_name:
            return part["color"]
    return "suit"

