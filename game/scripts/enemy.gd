extends CharacterBody2D
class_name DungeonEnemy

var enemy_id := 0
var health := 3
var target: Node2D
var attack_timer := 0.0
var sync_timer := 0.0
const SPEED := 72.0
const ATTACK_RANGE := 34.0

func setup(id: int) -> void:
    enemy_id = id
    name = "Enemy_%d" % id

func server_tick(delta: float, players: Dictionary) -> Dictionary:
    if target == null or not is_instance_valid(target):
        var nearest := INF
        for candidate in players.values():
            var distance := global_position.distance_to(candidate.global_position)
            if distance < nearest:
                nearest = distance
                target = candidate
    if target == null:
        return {}
    var distance := global_position.distance_to(target.global_position)
    if distance > ATTACK_RANGE:
        velocity = global_position.direction_to(target.global_position) * SPEED
        move_and_slide()
        sync_timer += delta
    else:
        velocity = Vector2.ZERO
        attack_timer -= delta
        if attack_timer <= 0.0:
            attack_timer = 1.0
            return {"target_id": target.peer_id, "damage": 1}
    queue_redraw()
    return {"sync": sync_timer >= 0.05}

func take_damage(amount: int) -> bool:
    health -= amount
    queue_redraw()
    return health <= 0

func _draw() -> void:
    draw_circle(Vector2.ZERO, 18.0, Color("#351b2b"))
    draw_circle(Vector2.ZERO, 14.0, Color("#e05b67"))
    draw_circle(Vector2(-5, -3), 3.0, Color("#fff1b8"))
    draw_circle(Vector2(5, -3), 3.0, Color("#fff1b8"))
    draw_rect(Rect2(-18, -28, 36, 4), Color("#1b1018"))
    draw_rect(Rect2(-18, -28, 36.0 * float(health) / 3.0, 4), Color("#8be28b"))
