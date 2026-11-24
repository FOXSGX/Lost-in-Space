"""ART-SAMPLE-001 · 英雄区共用材质表

命名约定：GLB 里的材质 `resource_name` 就是 Godot 侧材质库的键。
色板沿用项目既定方向（奶油 / 工业橙 / 琥珀黄 / 蓝灰金属 / 青绿），
本轮只把"同一块漆"拆成有工序的层次（底漆 → 面漆 → 露底 → 锈），
具体表现全部在 Godot 侧 shader 里完成，Blender 里只给基准色与粗糙度。
"""

import aq2kit as K

# 面漆（可剥落）
PAINT_CREAM = (0.610, 0.572, 0.482)
PAINT_ORANGE = (0.700, 0.268, 0.062)
PAINT_YELLOW = (0.800, 0.560, 0.090)
PAINT_TEAL = (0.145, 0.330, 0.330)      # 青绿：项目色板里的强调色
PAINT_GREY = (0.300, 0.318, 0.330)

# 裸金属
STEEL_BARE = (0.400, 0.430, 0.455)
STEEL_MACHINED = (0.560, 0.575, 0.585)
STEEL_DARK = (0.098, 0.108, 0.118)
STEEL_CAST = (0.300, 0.312, 0.322)
BRONZE = (0.520, 0.372, 0.150)
COPPER = (0.470, 0.245, 0.135)

# 非金属
CONCRETE = (0.330, 0.330, 0.318)
GROUT = (0.395, 0.388, 0.362)
RUBBER = (0.048, 0.050, 0.054)
GLASS = (0.700, 0.780, 0.820)

# 岩 / 晶
BEDROCK_A = (0.300, 0.248, 0.202)
BEDROCK_B = (0.150, 0.126, 0.106)
TALUS = (0.268, 0.230, 0.192)
CRYSTAL_SHELL = (0.090, 0.420, 0.520)
CRYSTAL_CORE = (0.480, 0.900, 1.000)
CRYSTAL_VEIN = (0.480, 0.320, 0.900)


def build_materials():
    m = {}
    m["M_PaintCream"] = K.mat("M_PaintCream", PAINT_CREAM, 0.46, 0.10)
    m["M_PaintOrange"] = K.mat("M_PaintOrange", PAINT_ORANGE, 0.50, 0.10)
    m["M_PaintYellow"] = K.mat("M_PaintYellow", PAINT_YELLOW, 0.48, 0.10)
    m["M_PaintTeal"] = K.mat("M_PaintTeal", PAINT_TEAL, 0.44, 0.12)
    m["M_PaintGrey"] = K.mat("M_PaintGrey", PAINT_GREY, 0.52, 0.15)
    m["M_BareSteel"] = K.mat("M_BareSteel", STEEL_BARE, 0.32, 0.85)
    m["M_MachinedSteel"] = K.mat("M_MachinedSteel", STEEL_MACHINED, 0.20, 0.95)
    m["M_DarkSteel"] = K.mat("M_DarkSteel", STEEL_DARK, 0.42, 0.70)
    m["M_CastSteel"] = K.mat("M_CastSteel", STEEL_CAST, 0.62, 0.65)
    m["M_Bronze"] = K.mat("M_Bronze", BRONZE, 0.34, 0.80)
    m["M_Copper"] = K.mat("M_Copper", COPPER, 0.30, 0.85)
    m["M_Concrete"] = K.mat("M_Concrete", CONCRETE, 0.85, 0.0)
    m["M_Grout"] = K.mat("M_Grout", GROUT, 0.80, 0.0)
    m["M_Rubber"] = K.mat("M_Rubber", RUBBER, 0.92, 0.0)
    m["M_Glass"] = K.mat("M_Glass", GLASS, 0.14, 0.0)
    m["M_Bedrock"] = K.mat("M_Bedrock", BEDROCK_A, 0.88, 0.0)
    m["M_BedrockDark"] = K.mat("M_BedrockDark", BEDROCK_B, 0.92, 0.0)
    m["M_Talus"] = K.mat("M_Talus", TALUS, 0.90, 0.0)
    m["M_CrystalShell"] = K.mat("M_CrystalShell", CRYSTAL_SHELL, 0.10, 0.0)
    m["M_CrystalCore"] = K.mat("M_CrystalCore", CRYSTAL_CORE, 0.06, 0.0,
                               emit=CRYSTAL_CORE, emit_strength=2.0)
    m["M_CrystalVein"] = K.mat("M_CrystalVein", CRYSTAL_VEIN, 0.08, 0.0,
                               emit=CRYSTAL_VEIN, emit_strength=1.2)
    m["M_RootRock"] = K.mat("M_RootRock", BEDROCK_A, 0.90, 0.0)
    m["M_RootSteel"] = K.mat("M_RootSteel", (0.470, 0.455, 0.425), 0.34, 0.88)
    return m


# 遮罩烘焙增益：哪些材料"最容易被磨"（漆面 > 铸铁 > 机加工 > 橡胶/岩）
WEAR_GAIN = {
    "M_PaintCream": 1.15, "M_PaintOrange": 1.10, "M_PaintYellow": 1.10,
    "M_PaintTeal": 1.05, "M_PaintGrey": 1.05,
    "M_CastSteel": 0.85, "M_BareSteel": 0.55, "M_MachinedSteel": 0.35,
    "M_Bronze": 0.45, "M_DarkSteel": 0.60,
    "M_Concrete": 0.55, "M_Grout": 0.85, "M_Rubber": 0.25, "M_Glass": 0.10,
    "M_Bedrock": 0.55, "M_BedrockDark": 0.55, "M_Talus": 1.30,
    "M_CrystalShell": 0.55, "M_CrystalCore": 0.2, "M_CrystalVein": 0.2,
    "M_RootRock": 0.75, "M_RootSteel": 0.6,
}

