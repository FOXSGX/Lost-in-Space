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
var _visual_node: Node3D
var _dying := false
var _last_anim_position := Vector3.ZERO
var _has_anim_position := false
var _remote_attack := 0.0


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
    elif form == VISUAL.Form.CRAWLER:
        max_health = maxi(max_health - 2, 2)
        move_speed *= 1.32
    health = max_health


## 覆盖父类的默认造型（红色胶囊 + 触角）。
## 腐墟星第一人称不再给感染体加悬浮名牌：
## 近身后玩家能直接看清造型，名字和"空格攻击"提示交给 HUD。
func _build_visual() -> void:
    var visual := VISUAL.new() as Node3D
    visual.name = "InfectedVisual"
    add_child(visual)
    _visual_node = visual
    visual.configure(form, true)
    _spec = visual.stat_specs()
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


## 父类负责远端位置插值；这里只把"实际移动速度"和"攻击前摇"喂给分件动画。
## 客户端 velocity 通常为 0，所以用位置差补速度，远端感染体不会滑步。
func _process(delta: float) -> void:
    super._process(delta)
    if _visual_node == null or _dying:
        return
    if not _has_anim_position:
        _last_anim_position = global_position
        _has_anim_position = true
    var planar := Vector2(velocity.x, velocity.z).length()
    if not multiplayer.is_server():
        var moved := global_position.distance_to(_last_anim_position)
        planar = maxf(planar, moved / maxf(delta, 0.001))
    _last_anim_position = global_position
    var attack := 0.0
    if attack_timer > 0.55:
        attack = clampf((attack_timer - 0.55) / 0.45, 0.0, 1.0)
    if _remote_attack > 0.0:
        attack = maxf(attack, _remote_attack)
        _remote_attack = maxf(_remote_attack - delta * 2.4, 0.0)
    _visual_node.call("animate", delta, planar, attack)


## 主机在攻击窗口内额外发一次前扑信号；客户端没有 attack_timer，
## 只靠它也能看到感染体抬臂前扑，而不是站着滑过来。
func server_tick(delta: float, players: Dictionary, lure_position := Vector3.ZERO, lure_active := false, storm_active := false, goofy_lures: Array = [], frost_combat := false) -> Dictionary:
    var before := attack_timer
    var result: Dictionary = super.server_tick(delta, players, lure_position, lure_active, storm_active, goofy_lures, frost_combat)
    if attack_timer > before + 0.05:
        sync_ruin_attack.rpc()
    return result


@rpc("authority", "call_remote", "reliable")
func sync_ruin_attack() -> void:
    _remote_attack = 1.0


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


func flinch() -> void:
    if _visual_node != null and _visual_node.has_method("flinch"):
        _visual_node.call("flinch")


## 死亡不立刻 queue_free：先倒向一侧并压扁，让第一人称近战能看到"打倒了"，
## 再由 RuinPlanet 的注册表把它从可攻击列表里移除。
func play_death() -> void:
    if _dying:
        return
    _dying = true
    set_physics_process(false)
    collision_layer = 0
    collision_mask = 0
    if _visual_node != null and _visual_node.has_method("die"):
        _visual_node.call("die")
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(self, "rotation:z", 1.30, 0.30)
    tween.tween_property(self, "scale", Vector3(1.0, 0.22, 1.0), 0.30)
    tween.tween_property(self, "position:y", position.y - 0.15, 0.30)
