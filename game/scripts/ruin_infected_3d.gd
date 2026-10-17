extends SpaceEnemy3D

# 腐墟星的感染体节点。
#
# 只换"长什么样、多大、数值多少"，移动、寻声、伤害结算、位置同步全部沿用
# SpaceEnemy3D。之所以用继承而不是直接改 SpaceEnemy3D：
# 那个脚本是霜烬星和腐墟星共用的，改它等于连带改霜烬星的敌人。
# 这里只被 ruin_planet.gd 使用，霜烬星仍然走原来的 enemy_3d.tscn，互不影响。

const VISUAL := preload("res://scripts/ruin_infected_visual.gd")

# 取值见 RuinInfectedVisual.Form。
var form := 0
var _spec: Dictionary = {}


## 必须在 setup() 之前调用：setup() 里会按形态生成网格。
func setup_form(next_form: int) -> void:
    form = next_form


func setup(id: int, player_count: int = 1) -> void:
    super.setup(id, player_count)
    # 三种形态的差异压得很小：这一关的压力来自"声音"，不是靠数值硬堆。
    # 鼓胀者慢而厚，爬行者快而脆，步行者是基准。
    if form == VISUAL.Form.BLOATER:
        max_health += 3
        move_speed *= 0.72
        attack_damage += 1
    elif form == VISUAL.Form.CRAWLER:
        max_health = maxi(max_health - 2, 2)
        move_speed *= 1.32
    health = max_health


## 覆盖父类的默认造型（红色胶囊 + 触角）。
func _build_visual() -> void:
    var visual := VISUAL.new() as Node3D
    visual.name = "InfectedVisual"
    add_child(visual)
    visual.configure(form, true)
    _spec = visual.stat_specs()
    # 头顶标签保留，但整体上抬。
    # _spec.label_y 是「模型顶端 + 0.30」，而这个标签是两行 billboard，
    # 总高接近 1 米，中心放在顶端上方 0.3 米时下半截会压住头部和肩膀。
    # 上抬 0.85 米后标签下沿才真正离开模型。
    _name_label = Label3D.new()
    _name_label.text = "【%s】\n%s" % [display_name, hint_text]
    _name_label.position = Vector3(0.0, float(_spec.label_y) + 0.85, 0.0)
    _name_label.font_size = 46
    _name_label.pixel_size = 0.011
    _name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _name_label.modulate = Color("#ffe8a6")
    _name_label.outline_size = 10
    _name_label.outline_modulate = Color("#4a0a0f")
    _name_label.shaded = false
    add_child(_name_label)
    _rebuild_collision()


## 父类 _ready() 会补一个固定大小的胶囊；这里改为按形态给尺寸，
## 所以覆盖成只设置碰撞层。
func _ready() -> void:
    collision_layer = 1
    collision_mask = 2
    # 正常流程里 setup() 一定先跑；万一有人直接实例化又不调 setup，
    # 至少给一个能站住的默认胶囊，不至于变成没有碰撞的幽灵。
    if _spec.is_empty():
        _spec = {"collision_radius": 0.45, "collision_height": 1.0, "collision_y": 0.5}
        _rebuild_collision()


func _rebuild_collision() -> void:
    for child in get_children():
        if child is CollisionShape3D:
            child.queue_free()
    var radius := float(_spec.get("collision_radius", 0.45))
    var height := maxf(float(_spec.get("collision_height", 1.0)), radius * 2.0)
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = radius
    capsule.height = height
    shape.shape = capsule
    shape.position.y = float(_spec.get("collision_y", height * 0.5))
    add_child(shape)
