extends SceneTree

const STEP := 2.0
const CLEARANCE := 1.2
const MAP_MARGIN := 8.0

var failures := 0

func _initialize() -> void:
    run.call_deferred()

func _grid(point: Vector2) -> Vector2i:
    return Vector2i(roundi(point.x / STEP), roundi(point.y / STEP))

func _world(cell: Vector2i) -> Vector2:
    return Vector2(cell.x * STEP, cell.y * STEP)

func _blocked(point: Vector2) -> bool:
    var half_map := FrostMapLayout.MAP_SIZE * 0.5 - Vector2(MAP_MARGIN, MAP_MARGIN)
    if absf(point.x) > half_map.x or absf(point.y) > half_map.y:
        return true
    for cliff in FrostMapLayout.ICE_CLIFFS:
        var center := Vector2(cliff[0])
        var size := Vector2(cliff[1]) + Vector2(1.8, 1.8) + Vector2(CLEARANCE, CLEARANCE)
        if absf(point.x - center.x) <= size.x * 0.5 and absf(point.y - center.y) <= size.y * 0.5:
            return true
    return false

func _reachable(start: Vector2, target: Vector2) -> bool:
    var origin := _grid(start)
    var goal := _grid(target)
    if _blocked(_world(origin)) or _blocked(_world(goal)):
        return false
    var queue: Array[Vector2i] = [origin]
    var visited := {origin: true}
    var directions: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
    while not queue.is_empty():
        var current: Vector2i = queue.pop_front()
        if current == goal:
            return true
        for direction in directions:
            var next: Vector2i = current + direction
            if visited.has(next) or _blocked(_world(next)):
                continue
            # 对角移动不能穿过两个相邻墙角。
            if direction.x != 0 and direction.y != 0 and (_blocked(_world(current + Vector2i(direction.x, 0))) or _blocked(_world(current + Vector2i(0, direction.y)))):
                continue
            visited[next] = true
            queue.append(next)
    return false

func _check(start: Vector2, target: Vector2, label: String) -> void:
    if not _reachable(start, target):
        failures += 1
        push_error("不可达：%s -> %s" % [label, str(target)])

func run() -> void:
    var start := FrostMapLayout.SAFEHOUSE
    _check(start, FrostMapLayout.EXTRACTION, "安全屋到撤离点")
    for index in FrostMapLayout.BEACON_CORNERS.size():
        _check(start, Vector2(FrostMapLayout.BEACON_CORNERS[index]), "安全屋到信标角落 %d" % (index + 1))
    for index in FrostMapLayout.CRATE_CORNERS.size():
        _check(start, Vector2(FrostMapLayout.CRATE_CORNERS[index]), "安全屋到电池角落 %d" % (index + 1))
    for name in FrostMapLayout.POINTS_OF_INTEREST:
        var point: Dictionary = FrostMapLayout.POINTS_OF_INTEREST[name]
        _check(start, Vector2(point.get("position", Vector2.ZERO)), "安全屋到%s" % name)
    print("霜烬星可达性：%d 项失败" % failures)
    quit(0 if failures == 0 else 1)
