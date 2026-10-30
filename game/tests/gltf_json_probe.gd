extends SceneTree

func _initialize() -> void:
    var doc := GLTFDocument.new()
    var state := GLTFState.new()
    var err := doc.append_from_file("res://assets/resonance/models/resonance_cave_vertical_slice_v3_deepseek.glb", state)
    print("ERR ", err)
    var json: Variant = state.get_json()
    print("JSON_TYPE ", typeof(json))
    if json is Dictionary:
        var nodes: Array = (json as Dictionary).get("nodes", [])
        print("NODES ", nodes.size())
        for node_value in nodes:
            var node: Dictionary = node_value as Dictionary
            var name := String(node.get("name", ""))
            if name.begins_with("RES_"):
                print("ANCHOR_JSON ", name, " ", node.get("extras", {}))
    quit(0)
