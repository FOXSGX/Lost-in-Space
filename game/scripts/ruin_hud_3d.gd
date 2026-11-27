extends CanvasLayer
class_name RuinHUD3D

## 腐墟星第一人称准星。
##
## 只在腐墟星、且没有打开设置/日志/物品选择时显示。
## 命中时四根准星线会短暂向外扩并变成珊瑚色，给近战一个即时的确认。
## 这里不画血量等常驻 HUD，那些仍由 Main3D 的面板负责，避免两套读数。

var controller: Main3D
var _crosshair: Control
var _hit_remaining := 0.0
var _hit_was_kill := false


func setup(owner: Main3D) -> void:
	controller = owner
	layer = 5
	_crosshair = Control.new()
	_crosshair.name = "Crosshair"
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair.draw.connect(_draw_crosshair)
	visible = false


func tick(delta: float) -> void:
	if controller == null or _crosshair == null:
		return
	var local: SpacePlayer3D = controller.players.get(multiplayer.get_unique_id()) as SpacePlayer3D
	var active: bool = controller.game_started \
		and controller.current_planet_id == "ruin" \
		and not controller._settings_visible \
		and not controller.is_journal_visible() \
		and (controller._items == null or not controller._items.choice_open) \
		and not controller.mission_completed \
		and not controller.mission_failed
	visible = active
	if not active:
		return
	if local != null and local.downed:
		visible = false
		return
	_hit_remaining = maxf(_hit_remaining - delta, 0.0)
	_crosshair.queue_redraw()


## 命中/击杀反馈。由 Attack 的 RPC 在本地玩家身上触发。
func flash_hit(kill := false) -> void:
	_hit_remaining = 0.20 if not kill else 0.28
	_hit_was_kill = kill
	if _crosshair != null:
		_crosshair.queue_redraw()


func _draw_crosshair() -> void:
	var center: Vector2 = _crosshair.size * 0.5
	var main_color := Color("#fff6e2")
	var pulse: float = _hit_remaining / 0.20 if _hit_remaining > 0.0 else 0.0
	if _hit_remaining > 0.0:
		main_color = Color("#ff9a74") if not _hit_was_kill else Color("#ffd166")
	var gap: float = 6.0 + pulse * 5.0
	var length: float = 9.0 + pulse * 5.0
	var outline := Color(0.05, 0.12, 0.14, 0.78)
	# 中心点：先画深色底再画亮色芯，奶油墙面前也能读出来。
	_crosshair.draw_circle(center, 3.3, outline)
	_crosshair.draw_circle(center, 1.9, main_color)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var start: Vector2 = center + direction * gap
		var finish: Vector2 = center + direction * (gap + length)
		_crosshair.draw_line(start, finish, outline, 3.8)
		_crosshair.draw_line(start, finish, main_color, 1.7)
	# 命中时加一个斜向的短叉，和四根准星线区分开
	if _hit_remaining > 0.0:
		for direction: Vector2 in [Vector2(1.0, 1.0).normalized(), Vector2(1.0, -1.0).normalized(), Vector2(-1.0, 1.0).normalized(), Vector2(-1.0, -1.0).normalized()]:
			_crosshair.draw_line(center + direction * (gap + 2.0), center + direction * (gap + 8.0), outline, 3.2)
			_crosshair.draw_line(center + direction * (gap + 2.0), center + direction * (gap + 8.0), main_color, 1.5)
