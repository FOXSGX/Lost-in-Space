extends SceneTree

func _initialize() -> void:
    print("GLTFDocument methods:")
    for item in ClassDB.class_get_method_list("GLTFDocument"):
        print(item.get("name", ""))
    print("GLTFState methods:")
    for item in ClassDB.class_get_method_list("GLTFState"):
        print(item.get("name", ""))
    print("GLTFNode methods:")
    for item in ClassDB.class_get_method_list("GLTFNode"):
        print(item.get("name", ""))
    quit(0)
