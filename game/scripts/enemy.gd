extends CharacterBody2D
class_name DungeonEnemy

var enemy_id := 0
var health := 3
var max_health := 3
var move_speed := 72.0
var attack_damage := 1
var target: Node2D
var attack_timer := 0.0
var sync_timer := 0.0
var _target_position := Vector2.ZERO
var _has_target_position := false
var _damage_flash_timer := 0.0
var _damage_text := ""
var _damage_text_timer := 0.0
const ATTACK_RANGE := 34.0

func setup(id: int, player_count := 1) -> void:
    enemy_id = id
    max_health = 3 + maxi((player_count - 1) / 2, 0)
    health = max_health
    move_speed = 72.0 + maxi(player_count - 1, 0) * 4.0
    attack_damage = 2 if player_count >= 4 else 1
    name = "Enemy_%d" % id

func _ready() -> void:
    _target_position = position

func _process(delta: float) -> void:
    _damage_flash_timer = maxf(_damage_flash_timer - delta, 0.0)
    _damage_text_timer = maxf(_damage_text_timer - delta, 0.0)
    if not multiplayer.is_server() and _has_target_position:
        position = position.lerp(_target_position, 1.0 - exp(-18.0 * delta))
    if _damage_flash_timer > 0.0 or _damage_text_timer > 0.0:
        queue_redraw()

func show_damage(amount: int) -> void:
    _damage_flash_timer = 0.18
    _damage_text = "-%d" % amount
    _damage_text_timer = 0.75
    queue_redraw()

func apply_network_position(next_position: Vector2) -> void:
    if position.distance_to(next_position) > 160.0:
        position = next_position
    else:
        _target_position = next_position
        _has_target_position = true

func server_tick(delta: float, players: Dictionary) -> Dictionary:
    var current_target := target as NetworkPlayer
    if current_target == null or not is_instance_valid(current_target) \
            or current_target.downed or not players.has(current_target.peer_id):
        target = null
        var nearest := INF
        for candidate in players.values():
            var player := candidate as NetworkPlayer
            if player == null or not is_instance_valid(player) or player.downed:
                continue
            var distance := global_position.distance_to(player.global_position)
            if distance < nearest:
                nearest = distance
                target = player
    if target == null:
        velocity = Vector2.ZERO
        return {"sync": sync_timer >= 0.05}
    var distance := global_position.distance_to(target.global_position)
    if distance > ATTACK_RANGE:
        velocity = global_position.direction_to(target.global_position) * move_speed
        move_and_slide()
        sync_timer += delta
    else:
        velocity = Vector2.ZERO
        attack_timer -= delta
        if attack_timer <= 0.0:
            attack_timer = 1.0
            return {"target_id": target.peer_id, "damage": attack_damage}
    queue_redraw()
    return {"sync": sync_timer >= 0.05}

func take_damage(amount: int) -> bool:
    health -= amount
    show_damage(amount)
    queue_redraw()
    return health <= 0

func _draw() -> void:
    if _damage_flash_timer > 0.0:
        draw_circle(Vector2.ZERO, 24.0, Color(1.0, 0.22, 0.30, 0.34))
    draw_circle(Vector2.ZERO, 18.0, Color("#351b2b"))
    draw_circle(Vector2.ZERO, 14.0, Color("#e05b67"))
    draw_circle(Vector2(-5, -3), 3.0, Color("#fff1b8"))
    draw_circle(Vector2(5, -3), 3.0, Color("#fff1b8"))
    draw_rect(Rect2(-18, -28, 36, 4), Color("#1b1018"))
    draw_rect(Rect2(-18, -28, 36.0 * float(health) / max_health, 4), Color("#8be28b"))
    if _damage_text_timer > 0.0:
        var damage_alpha := minf(_damage_text_timer / 0.75, 1.0)
        var damage_y := -42.0 - (0.75 - _damage_text_timer) * 16.0
        draw_string(ThemeDB.fallback_font, Vector2(-28.0, damage_y), _damage_text, HORIZONTAL_ALIGNMENT_CENTER, 56.0, 15, Color(1.0, 0.42, 0.48, damage_alpha))
