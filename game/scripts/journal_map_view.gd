extends Control
class_name JournalMapView

var map_size := Vector2(384.0, 256.0)
var cliffs: Array = []
var pathways: Array = []
var landmarks: Array = []
var player_position := Vector2.ZERO
var safehouse := Vector2.ZERO
var extraction := Vector2.ZERO
var discovered_regions: Array[String] = []
var beacon_positions: Array = []
var crate_positions: Array = []
var activated_beacons: Array[int] = []
var taken_crates: Array[int] = []
var heat_sources: Array = []
var field_sites: Array = []
var map_markers: Array = []
var show_player := false

func configure(next_cliffs: Array, next_pathways: Array, next_landmarks: Array, next_safehouse: Vector2, next_extraction: Vector2) -> void:
    cliffs = next_cliffs
    pathways = next_pathways
    landmarks = next_landmarks
    safehouse = next_safehouse
    extraction = next_extraction
    queue_redraw()

func update_state(next_player: Vector2, next_regions: Array[String], player_visible: bool) -> void:
    player_position = next_player
    discovered_regions = next_regions
    show_player = player_visible
    queue_redraw()

func update_objectives(next_beacons: Array, next_crates: Array, next_activated: Array[int], next_taken: Array[int]) -> void:
    beacon_positions = next_beacons
    crate_positions = next_crates
    activated_beacons = next_activated
    taken_crates = next_taken
    queue_redraw()

func update_heat_sources(next_sources: Array) -> void:
    heat_sources = next_sources
    queue_redraw()

func update_field_sites(next_sites: Array) -> void:
    field_sites = next_sites
    queue_redraw()

func update_markers(next_markers: Array) -> void:
    map_markers = next_markers
    queue_redraw()

func _draw() -> void:
    var rect := Rect2(Vector2(18.0, 18.0), size - Vector2(36.0, 36.0))
    draw_style_box(_panel_style(Color("#081b2a"), Color("#2d7080"), 12), rect)
    var scale := minf((rect.size.x - 32.0) / map_size.x, (rect.size.y - 32.0) / map_size.y)
    var origin := rect.position + rect.size * 0.5
    # 冰面和通路先画出来，让地图读起来像路线图而不是坐标表。
    draw_rect(Rect2(origin - map_size * scale * 0.5, map_size * scale), Color("#102f43"), true)
    for pathway in pathways:
        var a := _project(Vector2(pathway.get("from", Vector2.ZERO)), origin, scale)
        var b := _project(Vector2(pathway.get("to", Vector2.ZERO)), origin, scale)
        var width := maxf(float(pathway.get("width", 8.0)) * scale, 2.0)
        draw_line(a, b, Color("#5c9caf"), width, true)
    for cliff in cliffs:
        var center := Vector2(cliff[0])
        var cliff_size := Vector2(cliff[1]) * scale
        draw_rect(Rect2(_project(center, origin, scale) - cliff_size * 0.5, cliff_size), Color("#08131e"), true)
        draw_rect(Rect2(_project(center, origin, scale) - cliff_size * 0.5, cliff_size), Color("#6eb4c3"), false, 1.0)
    draw_circle(_project(safehouse, origin, scale), 5.0, Color("#ffbd61"))
    draw_string(ThemeDB.fallback_font, _project(safehouse, origin, scale) + Vector2(8.0, 4.0), "安全屋", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffe1a3"))
    draw_circle(_project(extraction, origin, scale), 5.0, Color("#68deff"))
    draw_string(ThemeDB.fallback_font, _project(extraction, origin, scale) + Vector2(8.0, 4.0), "撤离", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a9f3ff"))
    for landmark in landmarks:
        var point := Vector2(landmark.get("position", Vector2.ZERO))
        var color := Color("#8a98a4")
        var region := String(landmark.get("region", ""))
        if discovered_regions.has(region):
            color = Color("#f2b86b")
        draw_circle(_project(point, origin, scale), 4.0, color)
        if discovered_regions.has(region):
            draw_string(ThemeDB.fallback_font, _project(point, origin, scale) + Vector2(7.0, 4.0), String(landmark.get("name", "地标")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
    for index in beacon_positions.size():
        draw_circle(_project(Vector2(beacon_positions[index]), origin, scale), 3.0, Color("#ffd36b"))
    for index in crate_positions.size():
        draw_circle(_project(Vector2(crate_positions[index]), origin, scale), 2.5, Color("#5ce8be"))
    for site in field_sites:
        var point := Vector2(site.get("position", Vector2.ZERO))
        var projected := _project(point, origin, scale)
        var color := Color("#b2e3cc") if bool(site.get("used", false)) else Color("#8ce7e1")
        draw_rect(Rect2(projected - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), color, false, 1.5)
        if point.distance_to(player_position) <= 32.0:
            draw_string(ThemeDB.fallback_font, projected + Vector2(7.0, -7.0), String(site.get("label", "现场设备")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
    for source in heat_sources:
        var heat_point := Vector2(source.get("position", Vector2.ZERO))
        var projected := _project(heat_point, origin, scale)
        draw_circle(projected, 6.0, Color("#ff9e58"))
        draw_arc(projected, 9.0, 0.0, TAU, 18, Color("#ffd27e"), 1.5)
        draw_string(ThemeDB.fallback_font, projected + Vector2(9.0, 4.0), String(source.get("label", "热源")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#ffd27e"))
    for marker in map_markers:
        var marker_point := Vector2(marker.get("position", Vector2.ZERO))
        var marker_color := Color("#ff8ea8") if String(marker.get("kind", "")) == "clue" else Color("#ffcc66")
        var projected := _project(marker_point, origin, scale)
        draw_circle(projected, 5.5, marker_color)
        draw_line(projected - Vector2(8.0, 8.0), projected + Vector2(8.0, 8.0), marker_color, 2.0, true)
        draw_line(projected + Vector2(8.0, -8.0), projected - Vector2(8.0, -8.0), marker_color, 2.0, true)
        draw_string(ThemeDB.fallback_font, projected + Vector2(10.0, -5.0), String(marker.get("label", "标记")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, marker_color)
    draw_string(ThemeDB.fallback_font, rect.position + Vector2(18.0, rect.size.y - 10.0), "黄：信标   绿：电池   金：地标   橙圈：热源   青方框：现场设备   叉：我的标记   白：你", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8fb4c4"))
    if show_player:
        draw_circle(_project(player_position, origin, scale), 4.5, Color("#e9fbff"))
        draw_arc(_project(player_position, origin, scale), 8.0, 0.0, TAU, 24, Color("#62e8dc"), 1.5)

func _project(point: Vector2, origin: Vector2, scale: float) -> Vector2:
    return origin + point * scale

func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    return style
