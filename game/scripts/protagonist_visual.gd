extends Node3D
class_name ProtagonistVisual

const MODEL_PATH := "res://assets/characters/protagonist_model.json"
const WALK_RATE := 11.0
const GROUND_CLEARANCE := 0.035

var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
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

func _ready() -> void:
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
    _battery = MeshInstance3D.new()
    _battery.name = "CarriedBattery"
    _battery.mesh = facet_mesh
    _battery.position = Vector3(0.0, 0.87, 0.60)
    _battery.scale = Vector3(0.17, 0.25, 0.17)
    _battery.material_override = _material(Color("#ffd45d"), true)
    _battery.visible = false
    _body.add_child(_battery)
    var identifier := MeshInstance3D.new()
    identifier.name = "PlayerIdentifier"
    var stripe := BoxMesh.new()
    stripe.size = Vector3(0.40, 0.07, 0.025)
    identifier.mesh = stripe
    identifier.position = Vector3(0.0, 1.19, 0.535)
    identifier.material_override = _material(_team_color, true)
    _body.add_child(identifier)
    _keep_above_ground()

func set_team_color(color: Color) -> void:
    _team_color = color

func _pivot(pivot_name: String, pivot_position: Vector3) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = pivot_name
    pivot.position = pivot_position
    _body.add_child(pivot)
    return pivot

func _vec3(values: Array) -> Vector3:
    return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _material(color: Color, glow := false) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.albedo_color.a = 1.0
    material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
    material.roughness = 1.0
    if glow:
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = 0.65
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

func update_state(delta: float, direction: Vector2, is_downed: bool, scanning: bool, carrying: bool, health: int) -> void:
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
    if direction.length() > 0.08 and not is_downed:
        rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.y), minf(delta * 13.0, 1.0))
    var moving := direction.length() > 0.08 and not scanning and not is_downed
    var gait := sin(_time * WALK_RATE) * (0.55 if moving else 0.0)
    _left_leg.rotation.x = lerpf(_left_leg.rotation.x, gait, minf(delta * 16.0, 1.0))
    _right_leg.rotation.x = lerpf(_right_leg.rotation.x, -gait, minf(delta * 16.0, 1.0))
    _left_arm.rotation.x = lerpf(_left_arm.rotation.x, -0.85 if _rescuing else -gait * 0.65, minf(delta * 16.0, 1.0))
    var attack_swing := -1.25 * sin((_attack_time / 0.22) * PI) if _attack_time > 0.0 else gait * 0.65
    _right_arm.rotation.x = lerpf(_right_arm.rotation.x, -0.85 if _rescuing else attack_swing, minf(delta * 20.0, 1.0))
    _body.position.y = lerpf(_body.position.y, -0.38 if is_downed else (0.035 * sin(_time * WALK_RATE * 2.0) if moving else 0.0), minf(delta * 9.0, 1.0))
    _body.rotation.z = lerpf(_body.rotation.z, 0.28 if is_downed else 0.0, minf(delta * 9.0, 1.0))
    _body.scale.y = lerpf(_body.scale.y, 0.65 if is_downed else 1.0, minf(delta * 9.0, 1.0))
    _battery.visible = carrying
    for instance in _meshes:
        var mat := instance.material_override as StandardMaterial3D
        var base := Color(_palette[_part_color(instance.name)])
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

