extends RefCounted
class_name FrostMapLayout

# 霜烬星地图灰盒数据：区域、冰崖墙、通路、目标角落
# 参考：docs/design/planets/planet-00-map-concept.svg
#
# 尺寸说明：384 × 256，玩家速度 5.8 单位/秒，横穿约 66 秒。
# 冰崖墙把地图切成互不可见的区块，玩家必须走进通路才能看到对面。

const MAP_SIZE := Vector2(384.0, 256.0)
const SAFEHOUSE := Vector2(-164.0, 106.0)
const EXTRACTION := Vector2(172.0, 74.0)

# 区域定义：区域是"可辨认的地貌"，用顶点色画在地形上。
const REGIONS := {
    "坠落点": {
        "center": Vector2(-164.0, 106.0),
        "radius": 20.0,
        "kind": "start"
    },
    "静默台地": {
        "center": Vector2(-130.0, -78.0),
        "width": 72.0,
        "height": 64.0,
        "kind": "plateau"
    },
    "回声峡谷": {
        "center": Vector2(-130.0, 28.0),
        "width": 72.0,
        "height": 120.0,
        "kind": "canyon"
    },
    "中央冰湖": {
        "center": Vector2(0.0, 0.0),
        "radius": 46.0,
        "kind": "lake"
    },
    "热脉裂谷": {
        "center": Vector2(134.0, -84.0),
        "width": 80.0,
        "height": 76.0,
        "kind": "rift"
    },
    "残骸湾": {
        "center": Vector2(126.0, 74.0),
        "width": 76.0,
        "height": 74.0,
        "kind": "wreckage"
    },
    "撤离点": {
        "center": Vector2(172.0, 74.0),
        "radius": 16.0,
        "kind": "extraction"
    }
}

# 冰崖墙：[中心点, 尺寸]。墙体之间刻意留出缺口作为通路。
const ICE_CLIFFS := [
    # ── 西侧隔断（x ≈ -82）：分开西侧两区和中央冰湖 ──
    [Vector2(-82.0, -86.0), Vector2(14.0, 84.0)],
    [Vector2(-82.0, 12.0), Vector2(14.0, 48.0)],
    [Vector2(-82.0, 100.0), Vector2(14.0, 56.0)],

    # ── 台地／峡谷隔断（y ≈ -40）──
    [Vector2(-170.0, -40.0), Vector2(64.0, 12.0)],
    [Vector2(-102.0, -40.0), Vector2(32.0, 12.0)],

    # ── 北侧隔断（y ≈ -82）：封住冰湖北面，只留一条北通道 ──
    [Vector2(-24.0, -82.0), Vector2(116.0, 12.0)],
    [Vector2(77.0, -82.0), Vector2(34.0, 12.0)],

    # ── 东侧隔断（x ≈ 78）：分开冰湖和东侧两区 ──
    [Vector2(78.0, -104.0), Vector2(14.0, 48.0)],
    [Vector2(78.0, -4.0), Vector2(14.0, 80.0)],
    [Vector2(78.0, 100.0), Vector2(14.0, 56.0)],

    # ── 裂谷／残骸湾隔断（y ≈ -8）──
    [Vector2(120.0, -8.0), Vector2(84.0, 12.0)],
    [Vector2(191.0, -8.0), Vector2(18.0, 12.0)],
]

# 通路：与墙体缺口一一对应，用来在地形上画出可通行的走廊。
const PATHWAYS := [
    {
        "name": "西侧主路",
        "from": Vector2(-105.0, 54.0),
        "to": Vector2(-52.0, 50.0),
        "width": 30.0
    },
    {
        "name": "台地通道",
        "from": Vector2(-105.0, -28.0),
        "to": Vector2(-52.0, -24.0),
        "width": 28.0
    },
    {
        "name": "北侧通道",
        "from": Vector2(47.0, -60.0),
        "to": Vector2(47.0, -102.0),
        "width": 24.0
    },
    {
        "name": "薄冰桥",
        "from": Vector2(9.0, -44.0),
        "to": Vector2(62.0, -74.0),
        "width": 14.0,
        "fragile": true
    },
    {
        "name": "冰脊坡",
        "from": Vector2(171.0, -42.0),
        "to": Vector2(171.0, 26.0),
        "width": 16.0
    },
    {
        "name": "单向滑坡",
        "from": Vector2(148.0, 82.0),
        "to": Vector2(168.0, 76.0),
        "width": 18.0,
        "one_way": true
    },
]

# 目标角落：信标、电池只在这些地点之间随机，保证目标落在有意义的位置。
const BEACON_CORNERS := [
    Vector2(-138.0, -96.0),  # 静默台地深处
    Vector2(20.0, -52.0),    # 中央冰湖北岸
    Vector2(144.0, -104.0),  # 热脉裂谷深处
]

const CRATE_CORNERS := [
    Vector2(-144.0, 66.0),   # 回声峡谷南端
    Vector2(-64.0, -24.0),   # 台地通道旁
    Vector2(52.0, 24.0),     # 中央冰湖东侧
    Vector2(132.0, 96.0),    # 残骸湾南端
]

const SAMPLE_CORNERS := [
    Vector2(-116.0, -108.0),
    Vector2(36.0, 72.0),
]

# 兴趣点（地标、敌人巢穴、隐藏补给）
const POINTS_OF_INTEREST := {
    "旧气象站": {
        "position": Vector2(-130.0, -88.0),
        "region": "西北·静默台地",
        "kind": "landmark"
    },
    "冰层裂谷": {
        "position": Vector2(132.0, -94.0),
        "region": "东北·热脉裂谷",
        "kind": "landmark"
    },
    "坠毁运输舱": {
        "position": Vector2(130.0, 74.0),
        "region": "东南·残骸湾",
        "kind": "landmark"
    },
    "废弃通信阵列": {
        "position": Vector2(-124.0, 52.0),
        "region": "西南·回声峡谷",
        "kind": "landmark"
    },
    "敌人巢穴_北": {
        "position": Vector2(120.0, -116.0),
        "region": "东北·热脉裂谷",
        "kind": "enemy_lair"
    },
    "敌人巢穴_南": {
        "position": Vector2(150.0, 46.0),
        "region": "东南·残骸湾",
        "kind": "enemy_lair"
    },
    "隐藏补给_冰墙": {
        "position": Vector2(-46.0, 84.0),
        "region": "西南·回声峡谷",
        "kind": "hidden_supply"
    },
}

# 地热口：中段取暖点。玩家从安全屋出发后靠这些点续命，
# 它们同时也是"看得见的地标"，把长距离移动切成若干段。
const THERMAL_VENTS := [
    {"name": "回声温泉", "position": Vector2(-96.0, 44.0)},
    {"name": "台地裂隙", "position": Vector2(-120.0, -56.0)},
    {"name": "湖心泉眼", "position": Vector2(-14.0, 6.0)},
    {"name": "北岸地热", "position": Vector2(44.0, -60.0)},
    {"name": "裂谷热井", "position": Vector2(128.0, -70.0)},
    {"name": "残骸熔口", "position": Vector2(112.0, 62.0)},
]

# 静态障碍物：[位置, 尺寸, 类型, 高度缩放]
const OBSTACLES := [
    # 西侧
    [Vector2(-148.0, -18.0), Vector2(4.6, 3.4), 0, 1.4],
    [Vector2(-116.0, 6.0), Vector2(3.4, 2.8), 1, 1.2],
    [Vector2(-156.0, -60.0), Vector2(5.6, 2.4), 2, 1.3],
    [Vector2(-110.0, -100.0), Vector2(4.0, 3.0), 3, 1.2],
    [Vector2(-164.0, 76.0), Vector2(5.0, 2.6), 0, 1.3],
    [Vector2(-120.0, 80.0), Vector2(3.6, 3.2), 1, 1.1],
    # 中央
    [Vector2(-54.0, -44.0), Vector2(6.4, 2.8), 2, 1.4],
    [Vector2(-36.0, 40.0), Vector2(4.8, 2.4), 0, 1.2],
    [Vector2(0.0, -70.0), Vector2(6.8, 2.6), 3, 1.3],
    [Vector2(8.0, 52.0), Vector2(5.4, 3.0), 1, 1.2],
    [Vector2(-22.0, -8.0), Vector2(4.0, 3.4), 2, 1.0],
    [Vector2(26.0, -12.0), Vector2(4.6, 2.8), 0, 1.3],
    [Vector2(46.0, 10.0), Vector2(6.0, 2.4), 1, 1.2],
    [Vector2(36.0, -56.0), Vector2(4.4, 3.0), 3, 1.1],
    [Vector2(-10.0, 86.0), Vector2(5.2, 2.6), 2, 1.3],
    # 东侧
    [Vector2(90.0, -36.0), Vector2(5.8, 2.8), 0, 1.4],
    [Vector2(116.0, -48.0), Vector2(4.8, 3.2), 1, 1.2],
    [Vector2(154.0, -110.0), Vector2(6.2, 2.6), 2, 1.3],
    [Vector2(104.0, -118.0), Vector2(4.2, 2.8), 3, 1.1],
    [Vector2(168.0, -66.0), Vector2(5.6, 3.0), 0, 1.2],
    [Vector2(92.0, 52.0), Vector2(6.0, 2.6), 1, 1.3],
    [Vector2(120.0, 44.0), Vector2(4.6, 3.2), 2, 1.2],
    [Vector2(154.0, 98.0), Vector2(5.2, 2.8), 3, 1.3],
    [Vector2(104.0, 104.0), Vector2(4.4, 2.6), 0, 1.1],
    [Vector2(162.0, 64.0), Vector2(5.8, 3.0), 1, 1.2],
    # 南侧
    [Vector2(-100.0, 114.0), Vector2(5.0, 2.8), 2, 1.3],
    [Vector2(-48.0, 118.0), Vector2(6.0, 2.6), 0, 1.2],
    [Vector2(4.0, 114.0), Vector2(4.6, 3.2), 1, 1.3],
    [Vector2(58.0, 124.0), Vector2(5.4, 2.8), 3, 1.2],
    [Vector2(96.0, 118.0), Vector2(4.2, 2.6), 2, 1.1],

    # ── 中央冰湖内部：大区块必须有地貌，否则走起来是空地 ──
    [Vector2(-76.0, 26.0), Vector2(7.0, 3.2), 0, 1.5],
    [Vector2(-58.0, -58.0), Vector2(5.4, 3.6), 1, 1.4],
    [Vector2(-40.0, 62.0), Vector2(8.2, 2.8), 2, 1.6],
    [Vector2(-16.0, -46.0), Vector2(6.0, 3.4), 3, 1.3],
    [Vector2(16.0, 30.0), Vector2(7.4, 3.0), 0, 1.5],
    [Vector2(38.0, -32.0), Vector2(5.2, 3.8), 1, 1.4],
    [Vector2(52.0, 54.0), Vector2(6.6, 2.8), 2, 1.5],
    [Vector2(-62.0, 12.0), Vector2(4.8, 3.4), 3, 1.2],
    [Vector2(22.0, 70.0), Vector2(7.8, 2.6), 0, 1.6],
    [Vector2(-30.0, -74.0), Vector2(5.6, 3.2), 1, 1.4],
    [Vector2(58.0, -8.0), Vector2(6.4, 3.6), 2, 1.3],
    [Vector2(-8.0, 26.0), Vector2(4.4, 3.0), 3, 1.5],

    # ── 静默台地内部 ──
    [Vector2(-96.0, -66.0), Vector2(7.0, 3.0), 0, 1.4],
    [Vector2(-140.0, -110.0), Vector2(5.8, 3.6), 1, 1.3],
    [Vector2(-166.0, -70.0), Vector2(6.6, 2.8), 2, 1.5],
    [Vector2(-98.0, -112.0), Vector2(4.6, 3.4), 3, 1.2],

    # ── 回声峡谷内部 ──
    [Vector2(-100.0, 20.0), Vector2(6.2, 3.4), 0, 1.5],
    [Vector2(-152.0, 44.0), Vector2(5.4, 2.8), 1, 1.3],
    [Vector2(-118.0, 94.0), Vector2(7.2, 3.2), 2, 1.4],
    [Vector2(-168.0, 18.0), Vector2(4.8, 3.6), 3, 1.2],

    # ── 热脉裂谷内部 ──
    [Vector2(102.0, -80.0), Vector2(6.8, 3.2), 0, 1.4],
    [Vector2(160.0, -56.0), Vector2(5.6, 2.8), 1, 1.5],
    [Vector2(126.0, -126.0), Vector2(7.4, 3.4), 2, 1.3],
    [Vector2(168.0, -108.0), Vector2(4.6, 3.0), 3, 1.2],

    # ── 残骸湾内部 ──
    [Vector2(94.0, 30.0), Vector2(6.4, 3.0), 0, 1.5],
    [Vector2(146.0, 30.0), Vector2(5.2, 3.6), 1, 1.3],
    [Vector2(104.0, 92.0), Vector2(7.0, 2.8), 2, 1.4],
    [Vector2(152.0, 116.0), Vector2(5.0, 3.2), 3, 1.2],
]

static func get_random_positions(pool: Array, count: int, rng: RandomNumberGenerator, min_spacing: float) -> Array:
    var available := pool.duplicate()
    for i in range(available.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var temp = available[i]
        available[i] = available[j]
        available[j] = temp

    var selected: Array = []
    for candidate in available:
        var clear := true
        for other in selected:
            if (Vector2(candidate) - Vector2(other)).length() < min_spacing:
                clear = false
                break
        if clear:
            selected.append(candidate)
        if selected.size() >= count:
            break

    while selected.size() < count:
        selected.append(available[selected.size()])

    return selected
