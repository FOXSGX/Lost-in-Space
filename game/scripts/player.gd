extends CharacterBody2D
class_name NetworkPlayer

const SPEED := 260.0
var peer_id: int = 1
var player_color := Color("#61dafb")
var display_name := "玩家"
var _last_sent_position := Vector2.INF
var _send_accumulator := 0.0

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
    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    velocity = input_vector * SPEED
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
        if stage_controller.has_method("get_nearest_interaction_id"):
            var nearest_id: int = stage_controller.get_nearest_interaction_id(position)
            if nearest_id >= 0:
                if multiplayer.is_server():
                    stage_controller.activate_interaction_from_peer(peer_id, nearest_id)
                else:
                    stage_controller.request_activate_interaction.rpc_id(1, nearest_id)
    queue_redraw()

@rpc("any_peer", "unreliable", "call_remote")
func sync_transform(next_position: Vector2) -> void:
    if not is_multiplayer_authority():
        position = next_position
        queue_redraw()

func _draw() -> void:
    draw_circle(Vector2.ZERO, 20.0, Color(0.02, 0.05, 0.1, 0.9))
    draw_circle(Vector2.ZERO, 17.0, player_color)
    draw_circle(Vector2(-5.0, -5.0), 5.0, Color(1, 1, 1, 0.65))
    draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(1, 1, 1, 0.65), 2.0)
    draw_string(ThemeDB.fallback_font, Vector2(-26.0, -28.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 52.0, 14, Color("#e8f2ff"))
