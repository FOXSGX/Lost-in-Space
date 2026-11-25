extends Control

signal destination_selected(destination: String)
const POINTS: Dictionary = {"demo": Vector2(0.17, 0.62), "electromagnetic": Vector2(0.48, 0.28), "ruin": Vector2(0.76, 0.66), "earth": Vector2(0.88, 0.13)}
var voyage: CampaignNavigation
var selected: String = ""
var buttons: Dictionary = {}

func _ready() -> void:
    custom_minimum_size = Vector2(448, 252)
    for id: String in POINTS:
        var button: Button = Button.new()
        button.name = "Map_" + id
        button.text = "地球" if id == "earth" else String(PlanetRegistry.info(id).get("title", id))
        button.custom_minimum_size = Vector2(108, 46)
        button.pressed.connect(func() -> void: destination_selected.emit(id))
        add_child(button)
        buttons[id] = button
    resized.connect(_layout)
    _layout()

func _layout() -> void:
    for id: String in buttons:
        var button: Button = buttons[id]
        button.position = POINTS[id] * (size - Vector2(108, 60)) + Vector2(0, 16)
        button.size = Vector2(108, 46)
    queue_redraw()

func refresh(state: CampaignNavigation, destination: String) -> void:
    voyage = state
    selected = destination
    for id: String in buttons:
        var prefix: String = ""
        if id == voyage.location:
            prefix = "◆ "
        elif voyage.visits.has(id):
            prefix = "✓ "
        (buttons[id] as Button).text = prefix + ("地球" if id == "earth" else String(PlanetRegistry.info(id).get("title", id)))
        (buttons[id] as Button).modulate = Color("a4e9ce") if id == selected else Color.WHITE
    queue_redraw()

func _draw() -> void:
    for index: int in 32:
        draw_circle(Vector2(fmod(index * 97.0, maxf(size.x, 1)), fmod(index * 61.0, maxf(size.y, 1))), 1.2, Color(0.5, 0.75, 0.8, 0.22))
    if buttons.size() != 4:
        return
    var origin: Vector2 = (buttons.demo as Button).position + Vector2(54, 23)
    var middle: Vector2 = (buttons.electromagnetic as Button).position + Vector2(54, 23)
    var far: Vector2 = (buttons.ruin as Button).position + Vector2(54, 23)
    draw_line(origin, middle, Color("497d89"), 2, true)
    draw_line(origin, far, Color("497d89"), 2, true)
    draw_line(middle, far, Color("497d89"), 2, true)
    draw_dashed_line(middle, (buttons.earth as Button).position + Vector2(54, 23), Color("ac9265"), 2, 7, true)
    if voyage != null and buttons.has(voyage.location):
        var marker: Vector2 = (buttons[voyage.location] as Button).position + Vector2(54, 23)
        draw_arc(marker, 61, 0, TAU, 48, Color("96e4ca"), 2, true)
