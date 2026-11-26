extends RefCounted
class_name PlanetRegistry

# 关卡元信息统一入口。后续星球接入时填写场景、介绍和 available。
const DESTINATIONS := {
    "ship": {"title": "归航号 · 飞船", "subtitle": "返回轨道 / 整备下一次登陆", "scene": "", "available": true, "accent": Color("#67dfcd")},
    "demo": {"title": "霜烬星", "subtitle": "坠落科考站 · 11 栋极地小镇 · 探索巨兽峡谷与起飞核心", "scene": "res://previews/frost_first_playable/adventure.tscn", "available": true, "accent": Color("#79c7ed")},
    "electromagnetic": {"title": "共振星", "subtitle": "五幕合作战役 · 静默矿站 → 断轨矿车 → 记忆晶体 → 地心设施", "scene": "", "available": true, "accent": Color("#aa9de5")},
    "ruin": {"title": "腐墟星", "subtitle": "废墟城区 · 噪声引来感染者 · 搜刮物资后撤离", "scene": "", "available": true, "accent": Color("#9fb356")},
}

static func info(id: String) -> Dictionary:
    return DESTINATIONS.get(id, {})

static func can_land(id: String) -> bool:
    var entry := info(id)
    return not entry.is_empty() and bool(entry.get("available", false))
