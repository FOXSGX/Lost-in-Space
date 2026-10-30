extends SceneTree

## Standalone import/acceptance check for the experimental v4 hero entrance.
## It is intentionally outside the default resonance-cave suite because the
## visual quality gate did not pass; the default runtime still uses v3.

const HERO_PATH := "res://assets/resonance/models/resonance_cave_entrance_hero_v4.glb"
const HERO_ANCHORS := [
    "RES_Entrance", "RES_Respawn01", "RES_Task01_Power", "RES_Task01_Clamp",
    "RES_Transition01_MineGate", "RES_Chamber01_Camera"
]

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func run() -> void:
    check(ResourceLoader.exists(HERO_PATH), "v4 hero GLB 不存在")
    var packed := ResourceLoader.load(HERO_PATH) as PackedScene
    check(packed != null, "v4 hero GLB 无法加载")
    if packed == null:
        finish()
        return
    var hero := packed.instantiate() as Node3D
    check(hero != null, "v4 hero GLB 实例化失败")
    if hero == null:
        finish()
        return
    root.add_child(hero)
    await process_frame
    var rocks := 0
    var crystals := 0
    var mechs := 0
    var textured := 0
    for node in hero.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        if mesh == null:
            continue
        if mesh.name.begins_with("HeroRock_"):
            rocks += 1
        if mesh.name.begins_with("HeroCrystal_"):
            crystals += 1
        if mesh.name.begins_with("HeroRail_") or mesh.name.begins_with("HeroGate_") or mesh.name.begins_with("Task01_Power_") or mesh.name.begins_with("Task01_Clamp_"):
            mechs += 1
        var mat := mesh.get_active_material(0) as BaseMaterial3D
        if mat != null and mat.albedo_texture != null:
            textured += 1
    check(rocks >= 12, "v4 独立岩体少于 12：%d" % rocks)
    check(crystals >= 6, "v4 晶体模块少于 6：%d" % crystals)
    check(mechs >= 4, "v4 机械结构少于 4：%d" % mechs)
    check(hero.find_child("HeroArch_Rock_00", true, false) != null, "v4 缺少共振拱门")
    check(hero.find_child("HeroGate_Header", true, false) != null, "v4 缺少洞门")
    check(hero.find_child("HeroCaveShell", true, false) != null, "v4 缺少洞穴边界壳体")
    check(hero.find_child("Task01_Power_Orb", true, false) != null, "v4 缺少供能核心")
    check(hero.find_child("Task01_Clamp_Jaw_1", true, false) != null, "v4 缺少定场夹臂")
    for anchor_name in HERO_ANCHORS:
        var anchor := hero.find_child(anchor_name, true, false) as Node3D
        check(anchor != null, "v4 缺少入口锚点：%s" % anchor_name)
    check(textured >= 40, "v4 贴图 PBR 网格过少：%d" % textured)
    print("HERO_V4_ASSET: %d checks, %d failures (rocks=%d crystals=%d mechs=%d textured=%d)" % [checks, failures.size(), rocks, crystals, mechs, textured])
    finish()

func finish() -> void:
    quit(0 if failures.is_empty() else 1)
