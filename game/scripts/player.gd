extends CharacterBody2D
class_name NetworkPlayer

const SPEED := 260.0
const max_health := 5
const max_oxygen := 100.0
const ATTACK_RANGE := 150.0
const CARRY_SPEED_FACTOR := 0.72
const SYNC_INTERVAL := 1.0 / 30.0
const SMOOTH_RATE := 18.0
const CAMERA_ZOOM := Vector2(0.8, 0.8)

var health := max_health
var oxygen := max_oxygen
var warmth := 1.0
var carrying := 0
var carrying_crate_id := -1
var downed := false
var scan_lock_remaining := 0.0
var scan_cooldown_remaining := 0.0
var scan_origin := Vector2.ZERO
var scan_pulse_radius := 520.0
var peer_id: int = 1
var player_color := Color("#61dafb")
var display_name := "玩家"
var _last_sent_position := Vector2.INF
var _send_accumulator := 0.0
var _attack_cooldown := 0.0
var _target_position := Vector2.ZERO
var _has_target_position := false
var _damage_flash_timer := 0.0
var _damage_text := ""
var _damage_text_timer := 0.0

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
    _target_position = position
    z_index = int(position.y)
    if peer_id == multiplayer.get_unique_id():
        var camera := Camera2D.new()
        camera.name = "LocalCamera"
        camera.zoom = CAMERA_ZOOM
        camera.position_smoothing_enabled = true
        camera.position_smoothing_speed = 7.0
        camera.limit_left = 48
        camera.limit_top = 120
        camera.limit_right = 1428
        camera.limit_bottom = 900
        camera.limit_smoothed = true
        add_child(camera)

func _process(delta: float) -> void:
    z_index = int(position.y)
    _damage_flash_timer = maxf(_damage_flash_timer - delta, 0.0)
    _damage_text_timer = maxf(_damage_text_timer - delta, 0.0)
    # 客户端平滑远端玩家；主机保持权威位置，避免距离校验使用滞后坐标。
    var has_peer := multiplayer.multiplayer_peer != null
    if has_peer and scan_lock_remaining <= 0.0 and not is_multiplayer_authority() and not multiplayer.is_server() and _has_target_position:
        position = position.lerp(_target_position, 1.0 - exp(-SMOOTH_RATE * delta))
    if _damage_flash_timer > 0.0 or _damage_text_timer > 0.0:
        queue_redraw()

func show_damage(amount: int) -> void:
    _damage_flash_timer = 0.18
    _damage_text = "-%d" % amount
    _damage_text_timer = 0.75
    queue_redraw()

func teleport(next_position: Vector2) -> void:
    position = next_position
    _target_position = next_position
    _has_target_position = true
    velocity = Vector2.ZERO
    _last_sent_position = Vector2.INF
    _send_accumulator = SYNC_INTERVAL

func begin_scan(remaining: float, cooldown: float, origin: Vector2) -> void:
    scan_lock_remaining = maxf(remaining, 0.0)
    scan_cooldown_remaining = maxf(cooldown, 0.0)
    scan_origin = origin
    if scan_lock_remaining > 0.0:
        teleport(origin)

func tick_scan_lock(delta: float) -> void:
    if scan_lock_remaining > 0.0:
        velocity = Vector2.ZERO
        position = scan_origin
    scan_lock_remaining = maxf(scan_lock_remaining - delta, 0.0)
    scan_cooldown_remaining = maxf(scan_cooldown_remaining - delta, 0.0)

func _physics_process(delta: float) -> void:
    tick_scan_lock(delta)
    if multiplayer.multiplayer_peer == null:
        return
    if not is_multiplayer_authority():
        return
    _attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
    if downed or not get_parent().is_gameplay_active():
        velocity = Vector2.ZERO
        queue_redraw()
        return
    if Input.is_action_just_pressed("scan"):
        get_parent().scan_local_area()
        velocity = Vector2.ZERO
        queue_redraw()
        return
    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    var speed := SPEED * (CARRY_SPEED_FACTOR if carrying > 0 else 1.0)
    if scan_lock_remaining > 0.0:
        velocity = Vector2.ZERO
        position = scan_origin
    else:
        velocity = input_vector * speed
        move_and_slide()
    var movement_bounds := Rect2(72, 146, 1320, 728)
    if get_parent().has_method("get_player_bounds"):
        movement_bounds = get_parent().get_player_bounds()
    position.x = clampf(position.x, movement_bounds.position.x, movement_bounds.end.x)
    position.y = clampf(position.y, movement_bounds.position.y, movement_bounds.end.y)
    _send_accumulator += delta
    if _send_accumulator >= SYNC_INTERVAL:
        _send_accumulator = 0.0
        _last_sent_position = position
        sync_transform.rpc(position)
    for action in ["repair", "pickup", "deposit", "revive"]:
        if Input.is_action_just_pressed(action):
            var stage_controller := get_parent()
            var target: Dictionary = stage_controller.get_action_target(position, action)
            if not target.is_empty():
                var kind := int(target.get("kind", 0))
                var target_id := int(target.get("id", 0))
                if multiplayer.is_server():
                    stage_controller.handle_interaction(peer_id, kind, target_id)
                else:
                    stage_controller.request_interaction.rpc_id(1, kind, target_id)
    if Input.is_action_pressed("attack") and _attack_cooldown <= 0.0:
        _attack_cooldown = 0.35
        var stage_controller := get_parent()
        if multiplayer.is_server():
            stage_controller.attack_enemy_from_peer(peer_id)
        else:
            stage_controller.request_attack.rpc_id(1)
    queue_redraw()

@rpc("authority", "unreliable_ordered", "call_remote", 1)
func sync_transform(next_position: Vector2) -> void:
    if is_multiplayer_authority() or downed or scan_lock_remaining > 0.0:
        return
    if multiplayer.is_server():
        position = next_position
    elif position.distance_to(next_position) > 160.0:
        position = next_position
        _target_position = next_position
        _has_target_position = true
    else:
        _target_position = next_position
        _has_target_position = true

func _draw() -> void:
    var controller := get_parent()
    var can_show_attack_range: bool = multiplayer.multiplayer_peer != null and is_multiplayer_authority() and controller.has_method("is_gameplay_active") and controller.is_gameplay_active()
    if can_show_attack_range:
        draw_arc(Vector2.ZERO, ATTACK_RANGE, 0.0, TAU, 96, Color(0.35, 0.85, 1.0, 0.28), 2.0)
    # 椭圆阴影 + 高光轮廓，给角色一个轻量 2.5D 的落地感。
    draw_set_transform(Vector2(0, 16), 0.0, Vector2(1.25, 0.42))
    draw_circle(Vector2.ZERO, 19.0, Color(0.0, 0.02, 0.04, 0.52))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if _damage_flash_timer > 0.0:
        draw_circle(Vector2.ZERO, 25.0, Color(1.0, 0.22, 0.30, 0.34))
    var body_color := player_color
    if downed:
        body_color = Color("#7c8798")
    draw_circle(Vector2.ZERO, 20.0, Color(0.02, 0.05, 0.1, 0.9))
    draw_circle(Vector2.ZERO, 17.0, body_color)
    draw_arc(Vector2.ZERO, 17.0, PI * 0.08, PI * 0.92, 24, Color(1, 1, 1, 0.42), 2.0)
    draw_colored_polygon(PackedVector2Array([Vector2(-8, -13), Vector2(0, -25), Vector2(8, -13)]), Color(0.78, 0.91, 1.0, 0.72))
    if downed:
        draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color("#ff6b8a"), 2.0)
    else:
        draw_circle(Vector2(-5.0, -5.0), 5.0, Color(1, 1, 1, 0.65))
        draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(1, 1, 1, 0.65), 2.0)
    draw_string(ThemeDB.fallback_font, Vector2(-26.0, -28.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 52.0, 14, Color("#e8f2ff"))
    draw_rect(Rect2(-20, 25, 40, 4), Color("#1b2430"))
    draw_rect(Rect2(-20, 25, 40.0 * float(health) / max_health, 4), Color("#8be28b"))
    draw_rect(Rect2(-20, 31, 40, 4), Color("#1b2430"))
    var oxygen_ratio := oxygen / max_oxygen
    var oxygen_color := Color("#61dafb") if oxygen_ratio > 0.3 else Color("#ffcf5c")
    draw_rect(Rect2(-20, 31, 40.0 * oxygen_ratio, 4), oxygen_color)
    if warmth < 0.999 and not downed:
        draw_arc(Vector2.ZERO, 25.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - warmth), 28, Color("#9fd8ff"), 3.0)
    if carrying > 0:
        draw_string(ThemeDB.fallback_font, Vector2(-32.0, 52.0), "电池 ×%d" % carrying, HORIZONTAL_ALIGNMENT_CENTER, 64.0, 12, Color("#8fe5cb"))
    if downed:
        draw_string(ThemeDB.fallback_font, Vector2(-46.0, 68.0), "倒地 · 等待队友救援", HORIZONTAL_ALIGNMENT_CENTER, 92.0, 12, Color("#ff6b8a"))
    if _damage_text_timer > 0.0:
        var damage_alpha := minf(_damage_text_timer / 0.75, 1.0)
        var damage_y := -45.0 - (0.75 - _damage_text_timer) * 16.0
        draw_string(ThemeDB.fallback_font, Vector2(-32.0, damage_y), _damage_text, HORIZONTAL_ALIGNMENT_CENTER, 64.0, 16, Color(1.0, 0.35, 0.42, damage_alpha))
