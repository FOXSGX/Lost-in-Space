extends SceneTree

const ASSET_PATH := "res://assets/resonance/models/resonance_cave_vertical_slice_v3_deepseek.glb"
const REQUIRED_ANCHORS := [
    "RES_Entrance", "RES_Respawn01", "RES_Task01_Power", "RES_Task01_Clamp",
    "RES_Transition01_MineGate", "RES_Chamber01_Camera", "RES_Tunnel01_Entry",
    "RES_Tunnel01_Exit", "RES_Tunnel01_Camera", "RES_Chamber02_Entry",
    "RES_Task02_Freight", "RES_Task02_StableSocket", "RES_Respawn02",
    "RES_Chamber02_Camera", "RES_Exit"
]

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("run_test")

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func run_test() -> void:
    print("DEEPSEEK_ASSET: start")
    check(ResourceLoader.exists(ASSET_PATH), "DeepSeek GLB 不存在")
    var packed := ResourceLoader.load(ASSET_PATH) as PackedScene
    check(packed != null, "DeepSeek GLB 无法作为 PackedScene 加载")
    if packed == null:
        _finish()
        return
    var root_node := packed.instantiate() as Node3D
    check(root_node != null, "DeepSeek GLB 实例化失败")
    if root_node == null:
        _finish()
        return
    root.add_child(root_node)
    await process_frame
    for anchor_name in REQUIRED_ANCHORS:
        var anchor := root_node.find_child(anchor_name, true, false) as Node3D
        check(anchor != null, "缺少锚点：%s" % anchor_name)
        if anchor != null:
            check(absf(anchor.global_position.y) <= 0.25 or anchor_name.ends_with("Camera"), "锚点高度异常：%s y=%s" % [anchor_name, anchor.global_position.y])
    var floor := root_node.find_child("CaveFloor_Walkable", true, false) as MeshInstance3D
    check(floor != null, "缺少 CaveFloor_Walkable")
    if floor != null:
        var aabb := floor.get_aabb()
        var world_aabb: AABB = floor.global_transform * aabb
        check(world_aabb.size.y < 1.2, "地面世界 AABB 厚度异常：%s" % world_aabb.size)
        check(world_aabb.size.x > 100.0 and world_aabb.size.z > 25.0, "地面世界范围不足：%s" % world_aabb.size)
        check(floor.global_position.y < 0.1, "地面中心高度异常：%s" % floor.global_position.y)
    var document := GLTFDocument.new()
    var gltf_state := GLTFState.new()
    var append_error := document.append_from_file(ASSET_PATH, gltf_state)
    check(append_error == OK, "GLTFDocument 读取失败：%s" % append_error)
    var json: Variant = gltf_state.get_json()
    check(json is Dictionary, "GLTF JSON 状态缺失")
    var json_nodes: Array = (json as Dictionary).get("nodes", []) if json is Dictionary else []
    var json_anchor_map: Dictionary = {}
    for node_value in json_nodes:
        var node: Dictionary = node_value as Dictionary
        var node_name := String(node.get("name", ""))
        if node_name.begins_with("RES_"):
            json_anchor_map[node_name] = node
    check(json_anchor_map.size() == REQUIRED_ANCHORS.size(), "GLB extras 中锚点数量异常：%d" % json_anchor_map.size())
    for anchor_name in REQUIRED_ANCHORS:
        var json_node: Dictionary = json_anchor_map.get(anchor_name, {})
        var extras: Dictionary = json_node.get("extras", {}) as Dictionary
        check(String(extras.get("route_id", "")) == "resonance_cave_vertical_slice_v3", "GLB extras route_id 丢失：%s" % anchor_name)
        check(String(extras.get("anchor_type", "")) != "", "GLB extras anchor_type 丢失：%s" % anchor_name)
    print("DEEPSEEK_ASSET: %d checks, %d failures" % [checks, failures.size()])
    _finish()

func _finish() -> void:
    quit(0 if failures.is_empty() else 1)
