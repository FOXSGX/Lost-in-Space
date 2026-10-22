extends Node
class_name CrewItems3D

const CAPACITY: int = 2
const JET_REFILL_DELAY: float = 0.3
const JET_REFILL_RATE: float = 1.0
const JET_OXYGEN_COST: float = 2.0
const NAMES: Dictionary = {"medical": "医疗包", "oxygen": "氧气瓶", "battery": "热能电池", "sample": "异常冰样", "penguin": "回声企鹅", "bubble": "反重力泡", "board": "雪地滑板", "hologram": "全息替身", "smoke": "彩色信号烟"}
const SUPPLIES: Array[String] = ["medical", "oxygen"]
const CARGO: Array[String] = ["battery", "sample"]
const HEAVY: Dictionary = {3: "core", 4: "freight", 5: "coolant"}
const ICONS: Dictionary = {
    "medical": preload("res://assets/items/icons/medical.svg"),
    "oxygen": preload("res://assets/items/icons/oxygen.svg"),
    "battery": preload("res://assets/items/icons/battery.svg"),
    "sample": preload("res://assets/items/icons/sample.svg"),
    "penguin": preload("res://assets/items/icons/penguin.svg"),
    "bubble": preload("res://assets/items/icons/bubble.svg"),
    "board": preload("res://assets/items/icons/board.svg"),
    "hologram": preload("res://assets/items/icons/hologram.svg"),
    "smoke": preload("res://assets/items/icons/smoke.svg"),
    "core": preload("res://assets/items/icons/core.svg"),
    "freight": preload("res://assets/items/icons/freight.svg"),
    "coolant": preload("res://assets/items/icons/coolant.svg"),
}
const TRAINING_POSITIONS: Dictionary = {"oxygen": Vector3(-7.0, 0.96, 3.8)}

var controller: Main3D
var bags: Dictionary = {}
var drops: Array = []
var training_saved: Dictionary = {}
var next_uid: int = 1
var choice_open: bool = false
var _layer: CanvasLayer
var _bar: Control
var _cells: Array[Panel] = []
var _icons: Array[TextureRect] = []
var _choice: Panel
var _choice_actions: Array[String] = []
var _visual_parent: Node3D
var _props: Node3D
var _revision: int = 0
var _drawn_revision: int = -1
var _held: Dictionary = {}
var _pending_choices: Dictionary = {}
var _last_selected: int = -1
var suppress_use_until: int = 0
var _prop_bodies: Dictionary = {}
var _physics_sync_elapsed: float = 0.0
var _jet_bar: ProgressBar
var _equipment_column: VBoxContainer
var _equipment_panel: Panel
var _equipment_icon: TextureRect
var _equipment_percent: Label
var _slot_levels: Array[Label] = []

func _ready() -> void:
    controller = get_parent() as Main3D
    _build_ui()

func _build_ui() -> void:
    _layer = CanvasLayer.new()
    _layer.layer = 32
    add_child(_layer)
    _bar = Control.new()
    _bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    controller._place_hud(_bar, Control.PRESET_CENTER_BOTTOM, Vector2(-74, -160), Vector2(148, 68))
    _layer.add_child(_bar)
    for index: int in CAPACITY:
        var panel: Panel = controller._panel(_bar, Vector2(index * 80, 0), Vector2(68, 68), Color("#183445"), Color("#56727c"), 10)
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _cells.append(panel)
        var icon: TextureRect = TextureRect.new()
        icon.position = Vector2(12, 12)
        icon.size = Vector2(44, 44)
        icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_child(icon)
        _icons.append(icon)
        var level: Label = Label.new()
        level.position = Vector2(4, 45)
        level.size = Vector2(54, 20)
        level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        level.add_theme_font_size_override("font_size", 12)
        level.add_theme_color_override("font_color", Color("#c9f6f3"))
        level.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_child(level)
        _slot_levels.append(level)
    _choice = controller._panel(_layer, Vector2(390, 230), Vector2(500, 240), Color("#173446"), Color("#8ccdd0"), 16)
    _choice.visible = false
    _build_equipment_ui()

func _build_equipment_ui() -> void:
    _equipment_column = VBoxContainer.new()
    _equipment_column.add_theme_constant_override("separation", 12)
    _equipment_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    controller._place_hud(_equipment_column, Control.PRESET_CENTER_LEFT, Vector2(24, -34), Vector2(68, 68))
    _layer.add_child(_equipment_column)
    _equipment_panel = controller._panel(_equipment_column, Vector2.ZERO, Vector2(68, 68), Color("#9d5728"), Color("#f2ad60"), 10)
    _equipment_panel.custom_minimum_size = Vector2(68, 68)
    _equipment_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _equipment_panel.tooltip_text = "宇航服装备"
    _equipment_icon = TextureRect.new()
    _equipment_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _equipment_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _equipment_icon.texture = ICONS.oxygen
    _equipment_icon.position = Vector2(14, 8)
    _equipment_icon.size = Vector2(40, 40)
    _equipment_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _equipment_panel.add_child(_equipment_icon)
    _equipment_percent = Label.new()
    _equipment_percent.position = Vector2(4, 45)
    _equipment_percent.size = Vector2(54, 20)
    _equipment_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _equipment_percent.add_theme_font_size_override("font_size", 12)
    _equipment_percent.add_theme_color_override("font_color", Color("#fff0d4"))
    _equipment_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _equipment_panel.add_child(_equipment_percent)
    _jet_bar = ProgressBar.new()
    _jet_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
    _jet_bar.show_percentage = false
    _jet_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _jet_bar.tooltip_text = "喷气储备"
    _jet_bar.add_theme_font_size_override("font_size", 1)
    var background: StyleBoxFlat = StyleBoxFlat.new()
    background.bg_color = Color("#59341e")
    background.set_corner_radius_all(2)
    var fill: StyleBoxFlat = StyleBoxFlat.new()
    fill.bg_color = Color("#ffdea0")
    fill.set_corner_radius_all(2)
    _jet_bar.add_theme_stylebox_override("background", background)
    _jet_bar.add_theme_stylebox_override("fill", fill)
    _jet_bar.custom_minimum_size = Vector2(4, 42)
    _jet_bar.position = Vector2(60, 8)
    _jet_bar.size = Vector2(4, 42)
    _equipment_panel.add_child(_jet_bar)

func _process(_delta: float) -> void:
    if controller == null:
        return
    var live: bool = controller.ship_active or controller.game_started
    if controller.is_host and controller.game_started and controller.current_planet_id == "electromagnetic":
        var changed: bool = false
        for id: int in controller.players:
            changed = sync_heavy(id) or changed
        if changed:
            publish()
    _bar.visible = live and not controller._settings_visible and not controller.market_visible and not controller.is_journal_visible() and not controller._ship_session.has_panel()
    _equipment_column.visible = _bar.visible
    if not live:
        _clear_held()
        return
    var peer_id: int = multiplayer.get_unique_id()
    var local: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    var equipped: bool = has_jet(peer_id)
    _equipment_icon.visible = equipped
    _equipment_percent.visible = equipped
    _jet_bar.visible = equipped
    if local != null and equipped:
        _equipment_percent.text = "%d%%" % ceili(tank_oxygen(peer_id))
        _jet_bar.value = local.jet_charge * 100.0
    var bag: Dictionary = ensure_bag(peer_id)
    var slots: Array = bag.slots
    for index: int in CAPACITY:
        var kind: String = String((slots[index] as Dictionary).get("kind", ""))
        _icons[index].texture = ICONS.get(kind) as Texture2D
        _slot_levels[index].visible = kind == "oxygen"
        _slot_levels[index].text = "%d%%" % ceili(float((slots[index] as Dictionary).get("oxygen", 100.0))) if kind == "oxygen" else ""
        if _last_selected != int(bag.selected):
            var style: StyleBoxFlat = (_cells[index].get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
            style.border_color = Color("#a4f3e0") if int(bag.selected) == index else Color("#56727c")
            style.set_border_width_all(3 if int(bag.selected) == index else 1)
            _cells[index].add_theme_stylebox_override("panel", style)
    _last_selected = int(bag.selected)
    _refresh_world()
    _refresh_held()

func ensure_bag(peer_id: int) -> Dictionary:
    if not bags.has(peer_id):
        var slots: Array = [{}, {}]
        var legacy: Dictionary = controller._ship_session.packs.get(peer_id, {})
        var cursor: int = 0
        for kind: String in SUPPLIES:
            for count: int in int(legacy.get(kind, 0)):
                if cursor < CAPACITY:
                    slots[cursor] = {"kind": kind}
                    cursor += 1
        bags[peer_id] = {"slots": slots, "selected": 0}
    return bags[peer_id]

func occupied(peer_id: int) -> int:
    var total: int = 0
    for entry: Dictionary in ensure_bag(peer_id).slots:
        if not entry.is_empty():
            total += 1
    return total

func has_jet(peer_id: int) -> bool:
    return bool(ensure_bag(peer_id).get("oxygen_mounted", false))

func tank_oxygen(peer_id: int) -> float:
    return clampf(float(ensure_bag(peer_id).get("tank_oxygen", 100.0)), 0.0, 100.0) if has_jet(peer_id) else 0.0

func jet_reserve(peer_id: int) -> float:
    return clampf(float(ensure_bag(peer_id).get("jet_reserve", 0.0)), 0.0, 1.0)

func _new_tank_serial(bag: Dictionary) -> void:
    bag.tank_serial = next_uid
    next_uid += 1
    bag.jet_revision = int(bag.get("jet_revision", 0)) + 1

func mount_oxygen(peer_id: int, slot_index: int = -1) -> void:
    var bag: Dictionary = ensure_bag(peer_id)
    var index: int = int(bag.selected) if slot_index < 0 else clampi(slot_index, 0, CAPACITY - 1)
    var item: Dictionary = bag.slots[index]
    if item.get("kind", "") != "oxygen":
        return
    var replacement: Dictionary = {"kind": "oxygen", "ref": -1, "oxygen": tank_oxygen(peer_id)} if has_jet(peer_id) else {}
    bag.slots[index] = replacement
    bag.oxygen_mounted = true
    bag.tank_oxygen = clampf(float(item.get("oxygen", 100.0)), 0.0, 100.0)
    bag.jet_reserve = jet_reserve(peer_id)
    bag.jet_idle = 0.0
    _new_tank_serial(bag)
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player != null:
        player.jet_charge = jet_reserve(peer_id)
    if area() == "training":
        controller._ship_session.training[peer_id] = maxi(int(controller._ship_session.training.get(peer_id, 0)), 2)
    controller._ship_session._notify(peer_id, "已装配 · 落地等待充气 / 长按空格喷气")
    publish()

func refill_oxygen(peer_id: int) -> void:
    var bag: Dictionary = ensure_bag(peer_id)
    if has_jet(peer_id):
        bag.tank_oxygen = 100.0
        _new_tank_serial(bag)
    for item: Dictionary in bag.slots:
        if item.get("kind", "") == "oxygen":
            item.oxygen = 100.0

func _grounded_for_refill(player: SpacePlayer3D) -> bool:
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.08, player.global_position - Vector3.UP * 0.16, 2 | 8)
    return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _tick_jet_resources(delta: float) -> Array:
    var states: Array = []
    for peer_id: int in controller.players:
        var player: SpacePlayer3D = controller.players[peer_id] as SpacePlayer3D
        var bag: Dictionary = ensure_bag(peer_id)
        if not has_jet(peer_id) or player == null:
            continue
        var reserve: float = jet_reserve(peer_id)
        var oxygen: float = tank_oxygen(peer_id)
        var blocked: bool = player.downed or player.lava_dead or player.falling_to_lava
        if player.is_multiplayer_authority():
            blocked = blocked or controller._settings_visible or controller.market_visible or choice_open or controller.is_journal_visible()
        if player.jet_active and not blocked:
            reserve = maxf(reserve - delta / SpacePlayer3D.JET_DURATION, 0.0)
            if reserve < 0.0001:
                reserve = 0.0
        if player.jet_button_held or player.jet_active or blocked or not _grounded_for_refill(player):
            bag.jet_idle = 0.0
        else:
            bag.jet_idle = float(bag.get("jet_idle", 0.0)) + delta
            if float(bag.jet_idle) >= JET_REFILL_DELAY:
                var fill: float = minf(JET_REFILL_RATE * delta, minf(1.0 - reserve, oxygen / JET_OXYGEN_COST))
                reserve += fill
                oxygen = maxf(oxygen - fill * JET_OXYGEN_COST, 0.0)
        bag.jet_reserve = reserve
        bag.tank_oxygen = oxygen
        bag.jet_revision = int(bag.get("jet_revision", 0)) + 1
        player.jet_charge = reserve
        if reserve <= 0.0:
            player.jet_active = false
        states.append([peer_id, int(bag.get("tank_serial", 0)), int(bag.jet_revision), oxygen, reserve, float(bag.get("jet_idle", 0.0))])
    return states

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_jet_resources(states: Array) -> void:
    for state: Array in states:
        var peer_id: int = int(state[0])
        if not bags.has(peer_id):
            continue
        var bag: Dictionary = bags[peer_id]
        if int(state[1]) != int(bag.get("tank_serial", 0)) or int(state[2]) < int(bag.get("jet_revision", 0)):
            continue
        bag.jet_revision = int(state[2])
        bag.tank_oxygen = float(state[3])
        bag.jet_reserve = float(state[4])
        bag.jet_idle = float(state[5])
        var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
        if player != null:
            player.jet_charge = float(state[4])

func selected(peer_id: int) -> Dictionary:
    var bag: Dictionary = ensure_bag(peer_id)
    return bag.slots[int(bag.selected)]

func count_kind(peer_id: int, kind: String) -> int:
    var count: int = 0
    for entry: Dictionary in ensure_bag(peer_id).slots:
        if String(entry.get("kind", "")) == kind:
            count += 1
    return count

func add_item(peer_id: int, kind: String, reference: int = -1, data: Dictionary = {}) -> bool:
    if not NAMES.has(kind) and not HEAVY.values().has(kind):
        return false
    var bag: Dictionary = ensure_bag(peer_id)
    for index: int in CAPACITY:
        if (bag.slots[index] as Dictionary).is_empty():
            bag.slots[index] = {"kind": kind, "ref": reference}
            if kind == "oxygen":
                bag.slots[index]["oxygen"] = clampf(float(data.get("oxygen", 100.0)), 0.0, 100.0)
            _sync_legacy(peer_id)
            return true
    return false

func remove_item(peer_id: int, kind: String, reference: int = -1) -> bool:
    var bag: Dictionary = ensure_bag(peer_id)
    for index: int in CAPACITY:
        var entry: Dictionary = bag.slots[index]
        if String(entry.get("kind", "")) == kind and (reference < 0 or int(entry.get("ref", -1)) == reference):
            bag.slots[index] = {}
            _sync_legacy(peer_id)
            return true
    return false

func cargo_entries(peer_id: int) -> Array:
    var result: Array = []
    for entry: Dictionary in ensure_bag(peer_id).slots:
        if CARGO.has(String(entry.get("kind", ""))):
            result.append(entry.duplicate(true))
    return result

func item_name(kind: String) -> String:
    return String({"core": "能源核心", "freight": "磁力货箱", "coolant": "冷却单元"}.get(kind, NAMES.get(kind, "空格")))

func sync_heavy(peer_id: int) -> bool:
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return false
    var bag: Dictionary = ensure_bag(peer_id)
    var wanted: String = String(HEAVY.get(player.carrying, ""))
    var changed: bool = false
    for index: int in CAPACITY:
        var current: String = String((bag.slots[index] as Dictionary).get("kind", ""))
        if HEAVY.values().has(current) and current != wanted:
            bag.slots[index] = {}
            changed = true
    if not wanted.is_empty() and count_kind(peer_id, wanted) == 0:
        if add_item(peer_id, wanted, player.carrying_id):
            changed = true
        else:
            controller._resonance_stage.handle_action(peer_id, "drop")
            controller._ship_session._notify(peer_id, "需要一个空物品格才能搬运任务设备。")
    return changed

func clear_planet_cargo() -> void:
    for id: int in bags:
        var bag: Dictionary = ensure_bag(id)
        for index: int in CAPACITY:
            var kind: String = String((bag.slots[index] as Dictionary).get("kind", ""))
            if CARGO.has(kind) or HEAVY.values().has(kind):
                bag.slots[index] = {}
        _sync_legacy(id)

func move_multiplier(peer_id: int) -> float:
    return 0.58 if count_kind(peer_id, "sample") > 0 else (0.72 if count_kind(peer_id, "battery") > 0 else 1.0)

func _sync_legacy(peer_id: int) -> void:
    controller._ship_session.packs[peer_id] = {"medical": count_kind(peer_id, "medical"), "oxygen": count_kind(peer_id, "oxygen")}
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player != null and (controller.ship_active or controller.current_planet_id == "demo"):
        var chosen: Dictionary = selected(peer_id)
        if not CARGO.has(String(chosen.get("kind", ""))):
            var cargo: Array = cargo_entries(peer_id)
            chosen = cargo[0] if not cargo.is_empty() else {}
        player.carrying = 1 if chosen.get("kind", "") == "battery" else (2 if chosen.get("kind", "") == "sample" else 0)
        player.carrying_id = int(chosen.get("ref", 0)) if player.carrying > 0 else 0

func snapshot() -> Dictionary:
    return {"bags": bags.duplicate(true), "drops": drops.duplicate(true), "training_saved": training_saved.duplicate(true), "next_uid": next_uid}

func apply_state(state: Dictionary) -> void:
    var previous: Dictionary = bags
    bags = state.get("bags", bags).duplicate(true)
    for peer_id: int in bags:
        var incoming: Dictionary = bags[peer_id]
        var old: Dictionary = previous.get(peer_id, {})
        if int(incoming.get("tank_serial", 0)) == int(old.get("tank_serial", 0)) and int(incoming.get("jet_revision", 0)) < int(old.get("jet_revision", 0)):
            for key: String in ["tank_oxygen", "jet_reserve", "jet_revision", "jet_idle"]:
                if old.has(key):
                    incoming[key] = old[key]
        var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
        if player != null:
            player.jet_charge = float(incoming.get("jet_reserve", 0.0))
    drops = state.get("drops", drops).duplicate(true)
    training_saved = state.get("training_saved", training_saved).duplicate(true)
    next_uid = int(state.get("next_uid", next_uid))
    if not controller.is_host:
        for peer_id: int in bags:
            _sync_legacy(peer_id)
    _revision += 1

func publish() -> void:
    for peer_id: int in bags:
        _sync_legacy(peer_id)
    controller._ship_session.broadcast()

func real_counts(peer_id: int) -> Dictionary:
    var bag: Dictionary = training_saved.get(peer_id, {}).get("bag", ensure_bag(peer_id))
    var counts: Dictionary = {"medical": 0, "oxygen": 0}
    for entry: Dictionary in bag.slots:
        var kind: String = String(entry.get("kind", ""))
        if SUPPLIES.has(kind):
            counts[kind] = int(counts[kind]) + 1
    if bool(bag.get("oxygen_mounted", false)):
        counts.oxygen = int(counts.oxygen) + 1
    return counts

func real_oxygen_levels(peer_id: int) -> Array:
    var bag: Dictionary = training_saved.get(peer_id, {}).get("bag", ensure_bag(peer_id))
    var levels: Array = []
    for item: Dictionary in bag.slots:
        if item.get("kind", "") == "oxygen":
            levels.append(clampf(float(item.get("oxygen", 100.0)), 0.0, 100.0))
    if bool(bag.get("oxygen_mounted", false)):
        levels.append(clampf(float(bag.get("tank_oxygen", 100.0)), 0.0, 100.0))
    return levels

func clear_session() -> void:
    bags.clear()
    drops.clear()
    training_saved.clear()
    _revision += 1
    close_choice()

func start_training(peer_id: int) -> void:
    if not controller.is_host or training_saved.has(peer_id):
        return
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    training_saved[peer_id] = {"bag": ensure_bag(peer_id).duplicate(true), "vitals": [player.health, player.oxygen, player.warmth] if player != null else [5, 100.0, 1.0], "claimed": []}
    bags[peer_id] = {"slots": [{}, {}], "selected": 0}
    controller._ship_session.training[peer_id] = 0
    if player != null:
        player.health = 5
    _sync_legacy(peer_id)
    _revision += 1

func finish_training(peer_id: int) -> void:
    if not controller.is_host or not training_saved.has(peer_id):
        return
    var saved: Dictionary = training_saved[peer_id]
    bags[peer_id] = saved.bag.duplicate(true)
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player != null:
        player.health = int(saved.vitals[0])
        player.oxygen = float(saved.vitals[1])
        player.warmth = float(saved.vitals[2])
    training_saved.erase(peer_id)
    drops = drops.filter(func(entry: Dictionary) -> bool: return not (entry.get("area", "") == "training" and int(entry.get("owner", -1)) == peer_id))
    _sync_legacy(peer_id)
    _revision += 1

func remove_peer(peer_id: int) -> void:
    finish_training(peer_id)
    bags.erase(peer_id)
    _revision += 1

func area() -> String:
    if controller.ship_active:
        return "hub" if controller._ship_session.in_hub else "training"
    return "planet:" + controller.current_planet_id

func world_catalog(peer_id: int) -> Array:
    var result: Array = []
    var current: String = area()
    for entry: Dictionary in drops:
        if entry.area == current:
            result.append(entry)
    if current == "hub":
        for kind: String in SUPPLIES:
            if int(controller._ship_session.stock.get(kind, 0)) > 0:
                result.append({"uid": "stock_" + kind, "kind": kind, "position": Vector3(-17.5, 0.98, 4.1 if kind == "medical" else 4.9), "source": "stock", "oxygen": controller._ship_session.stock_oxygen_level() if kind == "oxygen" else 100.0})
    elif current == "training":
        var claimed: Array = training_saved.get(peer_id, {}).get("claimed", [])
        for kind: String in TRAINING_POSITIONS:
            if claimed.has(kind):
                continue
            result.append({"uid": "training_" + str(peer_id) + "_" + kind, "kind": kind, "position": TRAINING_POSITIONS[kind], "source": "training"})
    return result

func nearby_item(peer_id: int) -> Dictionary:
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return {}
    var nearest: Dictionary = {}
    var distance: float = 2.25
    for entry: Dictionary in world_catalog(peer_id):
        var point: Vector3 = entry.position
        var candidate: float = (player.global_position + Vector3.UP * 0.7).distance_to(point)
        if candidate >= distance:
            continue
        if controller.ship_active:
            var direction: Vector3 = point - player.global_position
            direction.y = 0
            var facing: Vector3 = -player.global_transform.basis.z
            if direction.length() > 0.65 and facing.dot(direction.normalized()) < 0.2:
                continue
        var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.4, point + Vector3.UP * 0.2, 2)
        if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
            continue
        nearest = entry
        distance = candidate
    return nearest

func pickup(peer_id: int, entry: Dictionary) -> bool:
    # Resolve against live authority state so an old interaction cannot clone a removed prop.
    var available: Dictionary = {}
    for candidate: Dictionary in world_catalog(peer_id):
        if candidate.uid == entry.get("uid", ""):
            available = candidate
            break
    if available.is_empty():
        return false
    entry = available
    var kind: String = String(entry.get("kind", ""))
    if not add_item(peer_id, kind, -1, entry):
        controller._ship_session._notify(peer_id, "物品栏已满 · G 放下")
        return false
    if entry.get("source", "") == "stock":
        controller._ship_session.stock[kind] = int(controller._ship_session.stock[kind]) - 1
        if kind == "oxygen":
            controller._ship_session.take_stock_oxygen_level()
    elif entry.get("source", "") == "training":
        var claimed: Array = training_saved[peer_id].get("claimed", [])
        claimed.append(kind)
        training_saved[peer_id]["claimed"] = claimed
    elif entry.get("source", "") != "training":
        drops = drops.filter(func(value: Dictionary) -> bool: return value.uid != entry.uid)
    if area() == "training":
        var step: int = int(controller._ship_session.training.get(peer_id, 0))
        if kind == "oxygen" and step == 0:
            controller._ship_session.training[peer_id] = 1
    var message: String = "已拾取 " + String(NAMES[kind])
    if area() == "training":
        message = "左键 · 安装氧气瓶到宇航服" if kind == "oxygen" else message
    controller._ship_session._notify(peer_id, message)
    publish()
    return true

func handle_action(peer_id: int, action: String) -> void:
    if not controller.is_host or not controller.connected_ids.has(peer_id):
        return
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed or controller.mission_completed or controller.mission_failed:
        return
    var bag: Dictionary = ensure_bag(peer_id)
    if action.begins_with("choice_"):
        var pending: Dictionary = _pending_choices.get(peer_id, {})
        var choice: String = action.trim_prefix("choice_")
        if choice in pending.get("actions", []) and controller._flat_distance(player.position, Vector3(pending.get("position", Vector3.INF))) < 3.2 and Time.get_ticks_msec() < int(pending.get("deadline", 0)):
            _pending_choices.erase(peer_id)
            controller.handle_action(peer_id, choice)
        return
    if action in ["slot_1", "slot_2", "slot_next", "slot_previous"]:
        bag.selected = (int(bag.selected) + 1) % CAPACITY if action in ["slot_next", "slot_previous"] else (0 if action == "slot_1" else 1)
        publish()
        return
    if action == "item_drop":
        _drop_selected(peer_id)
    elif action == "item_use":
        _use_selected(peer_id)
    elif action == "interact":
        _interact(peer_id)
    elif action == "item_scan":
        if controller.game_started:
            controller.start_scan_for_peer(peer_id)

func _use_selected(peer_id: int) -> void:
    var item: Dictionary = selected(peer_id)
    var kind: String = String(item.get("kind", ""))
    if kind == "oxygen":
        mount_oxygen(peer_id)
    elif SUPPLIES.has(kind):
        controller._ship_session._use_supply(peer_id, kind)
    elif NAMES.has(kind) and not CARGO.has(kind):
        if controller._goofy_items != null:
            controller._goofy_items.activate(peer_id, kind)
    elif kind.is_empty():
        if controller.game_started:
            controller.attack_from_peer(peer_id)
    else:
        var message: String = "任务货物：到对应设备旁按 E 安装或投送。"
        controller._ship_session._notify(peer_id, message)

func _drop_selected(peer_id: int) -> void:
    var item: Dictionary = selected(peer_id).duplicate(true)
    if item.is_empty():
        if not has_jet(peer_id):
            return
        item = {"kind": "oxygen", "oxygen": tank_oxygen(peer_id), "mounted_drop": true}
        ensure_bag(peer_id)["oxygen_mounted"] = false
        _new_tank_serial(ensure_bag(peer_id))
        (controller.players[peer_id] as SpacePlayer3D).stop_jet()
    var kind: String = String(item.kind)
    var player: SpacePlayer3D = controller.players[peer_id] as SpacePlayer3D
    if HEAVY.values().has(kind):
        controller.handle_action(peer_id, "drop")
        sync_heavy(peer_id)
        publish()
        return
    if CARGO.has(kind) and area().begins_with("planet:"):
        player.carrying = 1 if kind == "battery" else 2
        player.carrying_id = int(item.get("ref", -1))
        controller._drop_carried_item(peer_id)
        return
    var point: Vector3 = drop_position(player)
    drops.append({"uid": "drop_%d" % next_uid, "kind": kind, "position": point + Vector3.UP * 0.48, "rotation": Vector3(0.75, player.rotation.y, 0.35), "area": area(), "owner": peer_id, "oxygen": float(item.get("oxygen", 100.0))})
    next_uid += 1
    if not bool(item.get("mounted_drop", false)):
        remove_item(peer_id, kind)
    publish()

func drop_position(player: SpacePlayer3D) -> Vector3:
    var point: Vector3 = player.global_position - player.global_transform.basis.z * 0.85
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.4, point + Vector3.UP * 0.4, 2)
    var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        point = player.global_position
    var floor_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.8, point + Vector3.DOWN * 12.0, 2)
    var floor_hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(floor_query)
    if not floor_hit.is_empty():
        point.y = (floor_hit.position as Vector3).y + 0.025
    return point

func _interact(peer_id: int) -> void:
    var player: SpacePlayer3D = controller.players[peer_id] as SpacePlayer3D
    if area() == "training":
        if controller._flat_distance(player.position, ShipTutorial3D.ENTRY_POINT) < 1.8:
            controller._ship_session.switch_area.rpc(true)
            return
        if has_jet(peer_id) and (player.position - Vector3(-7, 0, 5.0)).length() < 2.0 and nearby_item(peer_id).is_empty():
            refill_oxygen(peer_id)
            controller._ship_session._notify(peer_id, "瓶内氧气已补满 · 喷气储备需等待充气")
            publish()
            return
    elif controller.game_started:
        var resolved: String = context_planet_action(peer_id)
        if resolved in ["deposit", "revive"]:
            if resolved == "deposit" and controller._field_interactions != null:
                var site: Dictionary = controller._field_interactions.nearest(player)
                var needed: String = "battery" if site.get("kind", "") == "heater" else ("sample" if site.get("kind", "") == "sample" else "")
                for entry: Dictionary in cargo_entries(peer_id):
                    if entry.kind == needed:
                        player.carrying = 1 if needed == "battery" else 2
                        player.carrying_id = int(entry.get("ref", -1))
                        break
            controller.handle_action(peer_id, resolved)
            return
        var physical_item: Dictionary = nearby_item(peer_id)
        if not physical_item.is_empty():
            pickup(peer_id, physical_item)
            return
        if resolved == "pickup":
            controller.handle_action(peer_id, resolved)
            return
        if controller.current_planet_id == "demo":
            if controller.knowledge_flags.has("relay") and not controller.anomaly_resolved and controller.activated_beacons.size() >= controller.beacon_positions.size() and controller._near_landmark(player, "relay"):
                _open_choice_for_peer(peer_id, "处理地下异常", ["repair", "deposit"], ["稳定信标", "关闭信标"])
                return
            if controller._signal_source(player) != Vector3.INF:
                _open_choice_for_peer(peer_id, "信号阵列", ["signal_high", "signal_low"], ["高频探测（引发风暴）", "低频诱导（引开生物）"])
                return
    var item: Dictionary = nearby_item(peer_id)
    if not item.is_empty():
        pickup(peer_id, item)
        return
    if controller.ship_active:
        controller._ship_session.handle_request(peer_id, "interact")
    else:
        controller.handle_action(peer_id, context_planet_action(peer_id))

func context_planet_action(peer_id: int) -> String:
    var player: SpacePlayer3D = controller.players[peer_id] as SpacePlayer3D
    for mate: SpacePlayer3D in controller.players.values():
        if mate.peer_id != peer_id and mate.downed and controller._flat_distance(player.position, mate.position) <= controller.REVIVE_RANGE:
            return "revive"
    if controller.current_planet_id == "electromagnetic":
        var held_target: Dictionary = controller._resonance_stage.get_stage_action_target(peer_id, "pickup")
        if player.carrying >= 3 and not held_target.is_empty() and float(held_target.get("distance", 0.0)) <= 4.0:
            return "pickup"
        var repair_target: Dictionary = controller._resonance_stage.get_stage_action_target(peer_id, "repair")
        if not repair_target.is_empty():
            return "repair"
        var pickup_target: Dictionary = controller._resonance_stage.get_stage_action_target(peer_id, "pickup")
        return "pickup" if not pickup_target.is_empty() and float(pickup_target.get("distance", 0.0)) <= 4.0 else "repair"
    if controller.current_planet_id != "demo":
        return "repair"
    if controller._field_interactions != null:
        var site: Dictionary = controller._field_interactions.nearest(player)
        if not site.is_empty():
            var state: Dictionary = controller._field_interactions.states.get(String(site.id), {})
            var kind: String = String(site.kind)
            if kind in ["radio", "helmet"] and bool(state.get("heard", false)) and not bool(state.get("answered", false)):
                return "deposit"
            if kind == "heater" and bool(state.get("repaired", false)) and not bool(state.get("boosted", false)) and count_kind(peer_id, "battery") > 0:
                return "deposit"
            if kind == "sample" and not bool(state.get("sealed", false)) and count_kind(peer_id, "sample") > 0:
                return "deposit"
            return "repair"
    if not controller._side_quest_prompt(player).is_empty():
        return "repair"
    if controller._roam_activities != null and not controller._roam_activities.prompt(player).is_empty():
        return "repair"
    if player.carrying > 0 and controller._flat_distance(player.position, Vector3(controller.EXTRACTION.x, 0, controller.EXTRACTION.y)) <= 2.4:
        return "deposit"
    if controller.scan_device_active and controller._flat_distance(player.position, controller.scan_device_position) < controller.RESOURCE_INTERACTION_RADIUS:
        return "pickup"
    for node: Node3D in controller.crates.values():
        if node.visible and controller._flat_distance(player.position, node.position) < controller._pickup_reach(peer_id):
            return "pickup"
    for node: Node3D in controller.samples.values():
        if node.visible and controller._flat_distance(player.position, node.position) < controller.RESOURCE_INTERACTION_RADIUS:
            return "pickup"
    return "repair"

func item_hint(peer_id: int) -> String:
    var item: Dictionary = nearby_item(peer_id)
    if item.is_empty():
        var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
        if area() == "training" and has_jet(peer_id) and player != null and (player.position - Vector3(-7, 0, 5.0)).length() < 2.0 and tank_oxygen(peer_id) < 99.99:
            return "E 补满瓶内氧气"
        if selected(peer_id).get("kind", "") == "oxygen":
            return "左键 安装氧气瓶" if not has_jet(peer_id) else "左键 更换宇航服氧气瓶"
        return ""
    return "E 拾取 " + String(NAMES[item.kind]) if occupied(peer_id) < CAPACITY else "已满 · G 放下"

func aims_at_training_target(player: SpacePlayer3D) -> bool:
    var eye: Vector3 = player.global_position + Vector3.UP * SpacePlayer3D.SHIP_EYE_HEIGHT
    var target: Vector3 = ShipTutorial3D.TARGET_POINT + Vector3.UP * 1.22
    var delta: Vector3 = target - eye
    if delta.length() > SpacePlayer3D.ATTACK_RANGE or player.aim_direction().dot(delta.normalized()) < 0.99:
        return false
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, target, 2)
    var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
    return not hit.is_empty() and String((hit.collider as Node).name) == "TargetCollision"

func can_reach(player: SpacePlayer3D, point: Vector3, radius: float, check_wall: bool = true) -> bool:
    var delta: Vector3 = point - player.global_position
    delta.y = 0
    if delta.length() > radius:
        return false
    if controller.ship_active and delta.length() > 0.5 and (-player.global_transform.basis.z).dot(delta.normalized()) < 0.4:
        return false
    if not check_wall:
        return true
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.4, point + Vector3.UP * 1.1, 2)
    return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _open_choice_for_peer(peer_id: int, title: String, actions: Array, labels: Array) -> void:
    var player: SpacePlayer3D = controller.players[peer_id] as SpacePlayer3D
    _pending_choices[peer_id] = {"actions": actions, "position": player.position, "deadline": Time.get_ticks_msec() + 30000}
    if peer_id == 1:
        show_choices(title, actions, labels)
    else:
        show_choices.rpc_id(peer_id, title, actions, labels)

@rpc("authority", "call_remote", "reliable")
func show_choices(title: String, actions: Array, labels: Array) -> void:
    for child: Node in _choice.get_children():
        _choice.remove_child(child)
        child.queue_free()
    controller._ui_label(_choice, title, Vector2(24, 18), Vector2(450, 32), 24, Color("#e6eddd"))
    for index: int in actions.size():
        var action: String = String(actions[index])
        controller._ui_button(_choice, String(labels[index]), Vector2(24, 68 + index * 56), Vector2(450, 44), func():
            controller.handle_action(multiplayer.get_unique_id(), "choice_" + action)
            close_choice())
    controller._ui_label(_choice, "Esc 关闭", Vector2(24, 196), Vector2(450, 24), 16, Color("#a2c0c2"))
    _choice.visible = true
    choice_open = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _refresh_world() -> void:
    var parent: Node3D = controller._ship_session.room if controller.ship_active else controller._world_root
    if parent == null:
        return
    if is_instance_valid(_props) and parent == _visual_parent and _drawn_revision == _revision:
        return
    if parent != _visual_parent or not is_instance_valid(_props):
        if is_instance_valid(_props):
            _props.queue_free()
        _prop_bodies.clear()
        _visual_parent = parent
        _props = Node3D.new()
        _props.name = "PhysicalItems"
        parent.add_child(_props)
    var live_ids: Array[String] = []
    for entry: Dictionary in world_catalog(multiplayer.get_unique_id()):
        var uid: String = String(entry.uid)
        live_ids.append(uid)
        if is_instance_valid(_prop_bodies.get(uid)):
            continue
        var dynamic: bool = not entry.has("source")
        var body: RigidBody3D = RigidBody3D.new()
        body.name = uid
        body.freeze = not dynamic or not controller.is_host
        body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
        body.collision_layer = 8
        body.collision_mask = 2 | 8 | 1
        body.mass = 1.5
        body.continuous_cd = true
        body.linear_damp = 0.65
        body.angular_damp = 0.9
        var material: PhysicsMaterial = PhysicsMaterial.new()
        material.friction = 0.65
        material.bounce = 0.12
        body.physics_material_override = material
        body.position = Vector3(entry.position) + (Vector3.ZERO if dynamic else Vector3.UP * 0.34)
        body.rotation = Vector3(entry.get("rotation", Vector3(0, float(entry.get("yaw", 0)), 0)))
        var collider: CollisionShape3D = CollisionShape3D.new()
        if entry.kind == "oxygen":
            var capsule: CapsuleShape3D = CapsuleShape3D.new()
            capsule.radius = 0.16
            capsule.height = 0.68
            collider.shape = capsule
        else:
            var box: BoxShape3D = BoxShape3D.new()
            box.size = Vector3(0.43, 0.42, 0.33)
            collider.shape = box
        body.add_child(collider)
        var model: ItemProp3D = ItemProp3D.create(String(entry.kind))
        model.position.y = -0.34 if entry.kind == "oxygen" else -0.2
        model.set_meta("item_uid", entry.uid)
        body.add_child(model)
        _props.add_child(body)
        if dynamic and controller.is_host:
            body.angular_velocity = Vector3(1.1, 0.3, 1.4)
        _prop_bodies[uid] = body
    for uid: String in _prop_bodies.keys():
        if not live_ids.has(uid):
            var body: RigidBody3D = _prop_bodies[uid] as RigidBody3D
            if is_instance_valid(body):
                _props.remove_child(body)
                body.queue_free()
            _prop_bodies.erase(uid)
    _drawn_revision = _revision

func _physics_process(delta: float) -> void:
    if controller == null or not (controller.ship_active or controller.game_started):
        return
    var jet_states: Array = _tick_jet_resources(delta) if controller.is_host else []
    var poses: Array = []
    for entry: Dictionary in drops:
        if entry.get("area", "") != area():
            continue
        var body: RigidBody3D = _prop_bodies.get(String(entry.uid)) as RigidBody3D
        if not is_instance_valid(body):
            continue
        if controller.is_host:
            if body.position.y < -12.0:
                body.position = Vector3(entry.get("safe_position", Vector3(0, 1, 0)))
                body.linear_velocity = Vector3.ZERO
            entry.position = body.position
            entry.rotation = body.rotation
            poses.append([entry.uid, body.position, body.rotation])
        else:
            body.position = body.position.lerp(Vector3(entry.position), 1.0 - exp(-22.0 * delta))
            body.quaternion = body.quaternion.slerp(Quaternion.from_euler(Vector3(entry.get("rotation", Vector3.ZERO))), 1.0 - exp(-22.0 * delta))
    _physics_sync_elapsed += delta
    if controller.is_host and _physics_sync_elapsed >= 0.1:
        _physics_sync_elapsed = 0.0
        if not multiplayer.get_peers().is_empty():
            if not poses.is_empty():
                sync_prop_poses.rpc(area(), poses)
            if not jet_states.is_empty():
                sync_jet_resources.rpc(jet_states)

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_prop_poses(current_area: String, poses: Array) -> void:
    if current_area != area():
        return
    for pose: Array in poses:
        for entry: Dictionary in drops:
            if entry.uid == pose[0]:
                entry.position = pose[1]
                entry.rotation = pose[2]
                break

func _refresh_held() -> void:
    for peer_id: int in controller.players:
        var player: SpacePlayer3D = controller.players[peer_id] as SpacePlayer3D
        var kind: String = String(selected(peer_id).get("kind", ""))
        if HEAVY.values().has(kind):
            kind = ""
        var first_person: bool = peer_id == multiplayer.get_unique_id() and controller.ship_active and player._camera != null
        var parent: Node3D = player._camera if first_person else player
        var signature: String = kind + str(parent.get_instance_id())
        var record: Dictionary = _held.get(peer_id, {})
        if record.get("signature", "") == signature and is_instance_valid(record.get("node")):
            continue
        if is_instance_valid(record.get("node")):
            (record.node as Node).queue_free()
        if kind.is_empty():
            _held.erase(peer_id)
            continue
        var model: ItemProp3D = ItemProp3D.create(kind)
        model.position = Vector3(0.32, -0.42, -0.72) if first_person else Vector3(0.38, 0.85, -0.28)
        model.rotation.y = 0.0 if first_person else PI
        model.scale = Vector3.ONE * (0.65 if first_person else 0.8)
        parent.add_child(model)
        _held[peer_id] = {"signature": signature, "node": model}

func _clear_held() -> void:
    for record: Dictionary in _held.values():
        if is_instance_valid(record.get("node")):
            (record.node as Node).queue_free()
    _held.clear()

func close_choice() -> void:
    suppress_use_until = Time.get_ticks_msec() + 180
    choice_open = false
    if _choice != null:
        _choice.visible = false
    if controller != null:
        if controller.ship_active:
            controller._refresh_ship_pointer()
        elif controller.game_started and controller.current_planet_id == "electromagnetic":
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
