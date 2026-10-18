extends RefCounted
class_name PlanetRegistry

# 关卡元信息统一入口。后续星球接入时填写场景、介绍和 available。
const DESTINATIONS := {
    "ship": {"title": "归航号 · 飞船", "subtitle": "返回轨道 / 整备下一次登陆", "scene": "", "available": true, "accent": Color("#67dfcd")},
    "demo": {"title": "霜烬星", "subtitle": "修复气象信标 · 收集热能电池 · 暴风雪中撤离", "scene": "", "available": true, "accent": Color("#79c7ed")},
    "electromagnetic": {"title": "共振星", "subtitle": "移动式轨道工厂 · 双端锁止 · 反应堆核心搬运", "scene": "", "available": true, "accent": Color("#aa9de5")},
    "ruin": {"title": "腐墟星", "subtitle": "废墟城区 · 噪声引来感染者 · 搜刮物资后撤离", "scene": "", "available": true, "accent": Color("#9fb356")},
}

static func info(id: String) -> Dictionary:
    return DESTINATIONS.get(id, {})

static func can_land(id: String) -> bool:
    var entry := info(id)
    return not entry.is_empty() and bool(entry.get("available", false))
