extends Node2D

var elapsed := 0.0

func _process(delta: float) -> void:
    elapsed += delta
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(48, 138, 879, 534), Color("#0d1c2b"))
    # 飞船舱体和观察窗，仅作公共大厅背景，不引入额外碰撞规则。
    draw_rect(Rect2(76, 180, 818, 450), Color("#152b3b"))
    draw_rect(Rect2(76, 180, 818, 450), Color("#335669"), false, 2)
    draw_rect(Rect2(96, 202, 780, 105), Color("#081522"))
    for i in 42:
        var point := Vector2(106 + fmod(i * 173.0, 750.0), 209 + fmod(i * 71.0, 86.0))
        draw_circle(point, 1.2, Color(0.6, 0.85, 0.93, 0.45))
    draw_circle(Vector2(732, 264), 37.0, Color("#1e5864"))
    draw_arc(Vector2(732, 264), 46, -1.5, 1.8, 35, Color("#67dfcd"), 1)
    draw_line(Vector2(98, 307), Vector2(875, 307), Color("#67dfcd"), 2)
    for x in range(110, 875, 64):
        draw_line(Vector2(x, 330), Vector2(x, 600), Color(0.23, 0.43, 0.55, 0.28), 1)
    for y in range(336, 600, 48):
        draw_line(Vector2(98, y), Vector2(875, y), Color(0.23, 0.43, 0.55, 0.28), 1)
    draw_rect(Rect2(355, 360, 235, 168), Color("#0d2231"))
    draw_rect(Rect2(355, 360, 235, 168), Color("#456774"), false, 2)
    draw_rect(Rect2(369, 374, 207, 94), Color("#163e4b"))
    draw_line(Vector2(394, 424), Vector2(540, 424), Color("#67dfcd"), 2)
    for x in [397, 470, 538]:
        draw_circle(Vector2(x, 424), 7, Color("#67dfcd"))
    draw_circle(Vector2(470, 424), 21 + sin(elapsed) * 2, Color(0.4, 0.9, 0.8, 0.1))
    draw_string(ThemeDB.fallback_font, Vector2(393, 506), "航线控制台", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#d6eaf0"))
    for x in [119, 217, 706, 804]:
        draw_rect(Rect2(x, 535, 62, 64), Color("#244354"))
        draw_rect(Rect2(x + 8, 543, 46, 36), Color("#142938"))
        draw_line(Vector2(x + 16, 553), Vector2(x + 47, 553), Color("#67dfcd"), 2)
    draw_string(ThemeDB.fallback_font, Vector2(106, 166), "归航号 / 船员整备舱", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#a7c9d7"))
    draw_string(ThemeDB.fallback_font, Vector2(278, 649), "打开航线图，选择下一颗星球。船员将在抵达时一同登陆。", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#a7c9d7"))
