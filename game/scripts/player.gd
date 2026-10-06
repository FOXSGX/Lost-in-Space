extends CharacterBody2D
class_name NetworkPlayer

const SPEED := 260.0
const max_health := 5
const max_oxygen := 100.0
const CARRY_SPEED_FACTOR := 0.72

var health := max_health
var oxygen := max_oxygen
var warmth := 1.0
var carrying := 0
var downed := false
var peer_id: int = 1
var player_color := Color("#61dafb")
var display_name := "玩家"
var _last_sent_position := Vector2.INF
var _send_accumulator := 0.0
var _attack_cooldown := 0.0

func setup(id: int, color: Color) -> void:
    peer_id = id
    player_color = color
    display_name = "玩家 %d" % id
    name = "Player_%d" % id
    queue_redraw()

func _enter_tree() -> void:
    if name.begins_with("Player_"):
        var parsed := name.trim_prefix("Player_").to_int()
        if parsed > 0:
            peer_id = parsed
    set_multiplayer_authority(peer_id)

func _ready() -> void:
    queue_redraw()

func _physics_process(delta: float) -> void:
    if not is_multiplayer_authority():
        return
    _attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
    if downed:
        velocity = Vector2.ZERO
        queue_redraw()
        return
    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    var speed := SPEED * (CARRY_SPEED_FACTOR if carrying > 0 else 1.0)
    velocity = input_vector * speed
    move_and_slide()
    position.x = clampf(position.x, 55.0, 930.0)
    position.y = clampf(position.y, 145.0, 665.0)
    _send_accumulator += delta
    if _send_accumulator >= 0.05 and (position.distance_to(_last_sent_position) > 0.5):
        _send_accumulator = 0.0
        _last_sent_position = position
        sync_transform.rpc(position)
    if Input.is_action_just_pressed("interact"):
        var stage_controller := get_parent()
        if stage_controller.has_method("get_nearest_interaction"):
            var target: Dictionary = stage_controller.get_nearest_interaction(position)
            if not target.is_empty():
                var kind := int(target.get("kind", 0))
                var target_id := int(target.get("id", 0))
                if multiplayer.is_server():
                    stage_controller.handle_interaction(peer_id, kind, target_id)
                else:
                    stage_controller.request_interaction.rpc_id(1, kind, target_id)
    # 一次按键触发一次攻击，由冷却控制连续攻击，避免战斗操作不明确。
    if Input.is_action_just_pressed("attack") and _attack_cooldown <= 0.0:
        _attack_cooldown = 0.35
        var stage_controller := get_parent()
        if multiplayer.is_server():
            stage_controller.attack_enemy_from_peer(peer_id)
        else:
            stage_controller.request_attack.rpc_id(1)
    queue_redraw()

@rpc("any_peer", "unreliable", "call_remote")
func sync_transform(next_position: Vector2) -> void:
    if not is_multiplayer_authority():
        position = next_position
        queue_redraw()

func _draw() -> void:
    var body_color := player_color
    if downed:
        body_color = Color("#7c8798")
    draw_circle(Vector2.ZERO, 20.0, Color(0.02, 0.05, 0.1, 0.9))
    draw_circle(Vector2.ZERO, 17.0, body_color)
    if downed:
        draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color("#ff6b8a"), 2.0)
    else:
        draw_circle(Vector2(-5.0, -5.0), 5.0, Color(1, 1, 1, 0.65))
        draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(1, 1, 1, 0.65), 2.0)
    draw_string(ThemeDB.fallback_font, Vector2(-26.0, -28.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 52.0, 14, Color("#e8f2ff"))

    # 生命条与氧气条。
    draw_rect(Rect2(-20, 25, 40, 4), Color("#1b2430"))
    draw_rect(Rect2(-20, 25, 40.0 * float(health) / max_health, 4), Color("#8be28b"))
    draw_rect(Rect2(-20, 31, 40, 4), Color("#1b2430"))
    var oxygen_ratio := oxygen / max_oxygen
    var oxygen_color := Color("#61dafb") if oxygen_ratio > 0.3 else Color("#ffcf5c")
    draw_rect(Rect2(-20, 31, 40.0 * oxygen_ratio, 4), oxygen_color)

    # 失温环：体温越低，缺口越大。
    if warmth < 0.999 and not downed:
        draw_arc(Vector2.ZERO, 25.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - warmth), 28, Color("#9fd8ff"), 3.0)

    if carrying > 0:
        draw_string(ThemeDB.fallback_font, Vector2(-32.0, 52.0), "资源 ×%d" % carrying, HORIZONTAL_ALIGNMENT_CENTER, 64.0, 12, Color("#8fe5cb"))
    if downed:
        draw_string(ThemeDB.fallback_font, Vector2(-46.0, 68.0), "倒地 · 等待队友救援", HORIZONTAL_ALIGNMENT_CENTER, 92.0, 12, Color("#ff6b8a"))
