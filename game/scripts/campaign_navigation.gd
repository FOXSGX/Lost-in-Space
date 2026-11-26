extends RefCounted
class_name CampaignNavigation

## Authoritative voyage state. Fuel costs stay disabled until recovery is balanced.
const ENERGY_TARGET: int = 2
const SUPPLY_TARGET: int = 2
var enabled: bool = false
var location: String = "demo"
var grounded: bool = true
var core_installed: bool = false
var navigation_restored: bool = false
var home_reached: bool = false
var ordinary_fuel: int = 4
var energy: int = 0
var supplies: int = 0
var revision: int = 0
var visits: Dictionary = {"demo": 1}
var claims: Dictionary = {}
var frost_world: Dictionary = {}
var ruin_state: Dictionary = {}

func start_new() -> void:
    apply({"enabled": true})

func snapshot() -> Dictionary:
    return {"enabled": enabled, "location": location, "grounded": grounded, "core_installed": core_installed, "navigation_restored": navigation_restored, "home_reached": home_reached, "ordinary_fuel": ordinary_fuel, "energy": energy, "supplies": supplies, "revision": revision, "visits": visits.duplicate(true), "claims": claims.duplicate(true), "frost_world": frost_world.duplicate(true), "ruin_state": ruin_state.duplicate(true)}

func apply(state: Dictionary) -> void:
    enabled = bool(state.get("enabled", false))
    location = String(state.get("location", "demo"))
    grounded = bool(state.get("grounded", true))
    core_installed = bool(state.get("core_installed", false))
    navigation_restored = bool(state.get("navigation_restored", false))
    home_reached = bool(state.get("home_reached", false))
    ordinary_fuel = maxi(0, int(state.get("ordinary_fuel", 4)))
    energy = maxi(0, int(state.get("energy", 0)))
    supplies = maxi(0, int(state.get("supplies", 0)))
    revision = maxi(0, int(state.get("revision", 0)))
    visits = state.get("visits", {"demo": 1}).duplicate(true)
    claims = state.get("claims", {}).duplicate(true)
    frost_world = state.get("frost_world", {}).duplicate(true)
    ruin_state = state.get("ruin_state", {}).duplicate(true)

func can_return_home() -> bool:
    return navigation_restored and energy >= ENERGY_TARGET and supplies >= SUPPLY_TARGET

func block_reason(destination: String) -> String:
    if not enabled:
        return ""
    if home_reached:
        return "归航已完成"
    if destination not in ["demo", "electromagnetic", "ruin", "earth"]:
        return "未发现航线"
    if not navigation_restored:
        return "起飞核心损坏 · 出舱寻找替代能源"
    if destination == "earth" and not can_return_home():
        return "仍缺能源 %d、归航物资 %d" % [maxi(0, ENERGY_TARGET - energy), maxi(0, SUPPLY_TARGET - supplies)]
    return ""

func action_word(destination: String) -> String:
    if destination == "earth":
        return "准备返航地球"
    if destination == location:
        return "继续探索" if grounded else "登陆"
    return "前往"

func depart(destination: String) -> bool:
    if not block_reason(destination).is_empty():
        return false
    location = destination
    grounded = destination == "demo"
    visits[destination] = int(visits.get(destination, 0)) + 1
    revision += 1
    if destination == "earth":
        home_reached = true
    return true

func accept_frost(result: Dictionary) -> void:
    if result.get("planet_id", "") != "frost":
        return
    core_installed = core_installed or result.get("energy_state", "") == "installed"
    navigation_restored = navigation_restored or (core_installed and bool(result.get("navigation_restored", false)))
    if core_installed:
        claims["frost_core_01"] = "installed"
    var total: int = maxi(0, int(result.get("ordinary_fuel_salvaged", 0)))
    var previous: int = int(claims.get("frost_fuel_total", 0))
    ordinary_fuel += maxi(0, total - previous)
    claims["frost_fuel_total"] = maxi(total, previous)
    for cache_id: String in result.get("supply_caches", []):
        var key: String = "frost_supply:" + cache_id
        if cache_id in ["rib_sled", "nest_overlook", "incident_kit"] and not claims.has(key):
            claims[key] = "stored"
            supplies += 1

func settle_planet(planet: String, success: bool, found_supplies: Array = []) -> String:
    var added_energy: int = 0
    var added_supplies: int = 0
    if planet == "electromagnetic" and success and not claims.has("resonance_core_01"):
        claims["resonance_core_01"] = "stored"
        energy += 2
        added_energy = 2
    if planet == "ruin":
        for site: String in found_supplies:
            var key: String = "ruin:" + site
            if not claims.has(key):
                claims[key] = "stored"
                supplies += 1
                added_supplies += 1
    grounded = false
    return "本次归航入库：能源 +%d · 物资 +%d" % [added_energy, added_supplies]

func summary() -> String:
    var place: String = "地球" if location == "earth" else String(PlanetRegistry.info(location).get("title", location))
    return "%s%s   ·   普通燃料 %d\n归航能源 %d / %d   ·   归航物资 %d / %d" % [place, " · 地面" if grounded else " · 轨道", ordinary_fuel, energy, ENERGY_TARGET, supplies, SUPPLY_TARGET]

func planet_detail(destination: String) -> String:
    match destination:
        "demo":
            return "核心已修复 · 遗迹运输箱可补归航物资\n融冰、开柜与调查进度保留" if core_installed else "废弃科考站 · 冰下遗迹\n寻找替代能源，运输箱可补归航物资"
        "electromagnetic":
            return "核心已回收 · 可重访合作设施" if claims.has("resonance_core_01") else "工厂信号：高密度反应堆能源\n完成核心搬运后带回归航储备"
        "ruin":
            return "殖民地物资信号 · 注意噪音\n搜刮后回登陆点按 E 撤回"
        "earth":
            return "远程归航出口\n储备达标后全员就位返航"
    return "未知信号"
