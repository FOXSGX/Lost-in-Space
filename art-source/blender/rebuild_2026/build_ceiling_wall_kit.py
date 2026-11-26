"""《迷失太空》室内天花板结构桁架风管 & 分层科幻护墙板 & 隔断门框套件（Blender 4.5 / Y-up）
彻底终结室内“灰水泥平顶 + 素灰砖墙”的廉价感，让抬头看天花板、环顾四周墙壁都像真实 AAA 科幻极地基地！
1. hero_ceiling_bay_truss.glb —— 12m×6m 建筑级室内吊顶模块（工字钢主梁 + 镀锌暖通方风管 + 百叶出风口 + 工业橙线槽 + 嵌入式双灯槽）
2. hero_wall_bulkhead.glb     —— 8.6m×6.6m 分层装甲保温护墙板（奶油/浅灰吸音装甲分块 + 深钢立柱边框 + 顶部压檐灯槽 + 橙色防撞腰带 + 检修舱盖与墙面通讯对讲盒）
3. hero_door_arch_trim.glb    —— 5.8m×3.8m 室内隔断过道科幻斜角门框（包住生活楼/通讯楼内部隔断门洞，瞬间变身精致太空舱走廊！）
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
KIT_DIR = os.path.join(REPO, "art-source", "deliveries", "ART-SAMPLE-002_TEAM_KIT", "02_BLENDER_SOURCE", "scripts")
OUT_DIR = os.path.join(REPO, "game", "assets", "models", "rebuild")
sys.path.insert(0, KIT_DIR)

import aq2kit as K
import aqs_kit as A
import hero_mats as HM


def fresh_mats():
    K.reset_scene()
    K._MATS.clear()
    mats = HM.build_materials()
    mats["M_SteelDeep"] = mats["M_DarkSteel"]
    mats["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.88, 0.98), 0.14, 0.0, emit=(0.18, 0.86, 0.98), emit_strength=1.8)
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.98, 0.68, 0.28), 0.16, 0.0, emit=(0.98, 0.64, 0.24), emit_strength=1.9)
    return mats


def export_model(hero, filename, seed=180, ao_rays=6):
    gain = dict(HM.WEAR_GAIN)
    obj = hero.finish(
        smooth=True,
        split_angle=34.0,
        bake={"ao_rays": ao_rays, "ao_dist": 0.20, "seed": seed, "mat_gain": gain, "ground_z": 0.0, "verbose": False},
    )
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    K.apply_modifiers(obj)
    out_path = os.path.join(OUT_DIR, filename)
    A.export_glb(out_path, obj.name)
    A.report(filename, obj)


def bm_cyl(r1, r2, h, segs=14):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi * 0.5, 3, 'X'))
    return bm


def build_ceiling_bay_truss():
    """1. 12m × 6m 室内结构吊顶桁架模块（原点在吊顶顶面 y=0，向下延伸至 y=-1.05m，直接贴在各建筑天花板下！）"""
    m = fresh_mats()
    h = A.Hero("HeroCeilingBayTruss")

    # 两根跨度 12m 的粗壮钢构主横梁（工字钢上下翼缘 + 腹板）
    for bz in (-2.75, 2.75):
        h.add(A.bm_box((12.0, 0.56, 0.34), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(0.0, -0.32, bz))
        h.add(A.bm_box((12.0, 0.12, 0.52), bevel=0.02, segments=2), m["M_CastSteel"], loc=(0.0, -0.62, bz))
        # 斜角承重加强节点板
        for sx in (-5.2, 0.0, 5.2):
            h.add(A.bm_box((0.62, 0.72, 0.56), bevel=0.04, segments=2), m["M_CastSteel"], loc=(sx, -0.40, bz))

    # 3 根纵向联系次梁（形成饱满的井字型科幻天花板网格！）
    for bx in (-4.0, 0.0, 4.0):
        h.add(A.bm_box((0.28, 0.42, 5.6), bevel=0.03, segments=2), m["M_CastSteel"], loc=(bx, -0.24, 0.0))

    # 偏置布置的巨型镀锌保温暖通空调风管 + 紧固箍环 + 百叶出风口格栅
    h.add(A.bm_box((11.8, 0.52, 1.15), bevel=0.06, segments=2), m["M_PaintCream"], loc=(0.0, -0.30, -1.25))
    for rx in (-4.2, -1.4, 1.4, 4.2):
        h.add(A.bm_box((0.18, 0.58, 1.24), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(rx, -0.30, -1.25))
    for vx in (-2.8, 2.8):
        h.add(A.bm_box((1.15, 0.08, 0.72), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(vx, -0.58, -1.25))

    # 另一侧高空橙色强电桥架 + 平行细保温管
    h.add(A.bm_box((11.8, 0.16, 0.46), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(0.0, -0.28, 1.35))
    h.add(bm_cyl(0.11, 0.11, 11.8, 12), m["M_CastSteel"], loc=(0.0, -0.34, 1.92), rot=(0.0, 0.0, 90.0))

    # 中央嵌入式双条暖光天花板灯槽（带金属防眩格栅框，告别单调悬浮黄条！）
    for lx in (-2.6, 2.6):
        h.add(A.bm_box((3.2, 0.16, 0.78), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(lx, -0.14, 0.12))
        h.add(A.bm_box((2.85, 0.08, 0.48), bevel=0.02, segments=2), m["M_GlowAmber"], loc=(lx, -0.22, 0.12))
        for gx in (-0.9, 0.0, 0.9):
            h.add(A.bm_box((0.06, 0.10, 0.52), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(lx + gx, -0.25, 0.12))

    export_model(h, "hero_ceiling_bay_truss.glb", seed=181)


def build_wall_bulkhead():
    """2. 8.6m × 6.6m 分层装甲保温护墙板（贴在内墙表面 +Z 朝室内，彻底把素灰水泥墙变成精致太空舱内壁！）"""
    m = fresh_mats()
    h = A.Hero("HeroWallBulkhead")

    # 底部厚重深钢防撞踢脚线 + 底部倾斜导流脚座
    h.add(A.bm_box((8.6, 0.46, 0.28), bevel=0.05, segments=2), m["M_DarkSteel"], loc=(0.0, 0.23, 0.12))
    # 下半部深色吸音装甲护墙裙板（Y=0.46..1.55）+ 醒目工业橙水平防撞扶手腰带
    for px in (-2.8, 0.0, 2.8):
        h.add(A.bm_box((2.58, 0.98, 0.16), bevel=0.04, segments=2), m["M_CastSteel"], loc=(px, 0.98, 0.08))
    h.add(A.bm_box((8.6, 0.18, 0.24), bevel=0.03, segments=2), m["M_PaintOrange"], loc=(0.0, 1.56, 0.12))

    # 中上部两层倒角奶油白/冷灰保温复合墙面板块（立体拼接缝，彻底打破平墙！）
    for px in (-2.8, 0.0, 2.8):
        h.add(A.bm_box((2.52, 2.15, 0.15), bevel=0.05, segments=2), m["M_PaintCream"], loc=(px, 2.82, 0.07))
        h.add(A.bm_box((2.52, 1.65, 0.15), bevel=0.05, segments=2), m["M_PaintCream"], loc=(px, 4.86, 0.07))
        # 每块上层面板里嵌一道通风百叶小槽
        h.add(A.bm_box((1.35, 0.32, 0.18), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(px, 5.12, 0.09))

    # 顶部重型檐口压线 + 向上漫反射的隐藏暖/青天花板洗墙灯槽！
    h.add(A.bm_box((8.6, 0.42, 0.34), bevel=0.05, segments=2), m["M_DarkSteel"], loc=(0.0, 6.18, 0.16))
    h.add(A.bm_box((8.2, 0.08, 0.10), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(0.0, 5.95, 0.31))

    # 4 根粗壮钢构承重肋柱（上下斜撑托座 + 细长垂直气氛灯条）
    for cx in (-4.15, -1.40, 1.40, 4.15):
        h.add(A.bm_box((0.36, 6.45, 0.36), bevel=0.05, segments=2), m["M_DarkSteel"], loc=(cx, 3.22, 0.14))
        h.add(A.bm_box((0.46, 0.65, 0.44), bevel=0.04, segments=2), m["M_CastSteel"], loc=(cx, 0.36, 0.18))
        h.add(A.bm_box((0.46, 0.65, 0.46), bevel=0.04, segments=2), m["M_CastSteel"], loc=(cx, 6.08, 0.20))
        if abs(cx) < 2.0:
            h.add(A.bm_box((0.08, 1.45, 0.08), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(cx, 3.45, 0.33))

    # 生活/运维微细节：嵌入式墙面检修盒 + 内线对讲呼叫盒（右侧红绿状态灯）
    h.add(A.bm_box((0.72, 0.92, 0.18), bevel=0.03, segments=2), m["M_CastSteel"], loc=(-2.8, 2.35, 0.14))
    h.add(A.bm_box((0.32, 0.46, 0.14), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(2.8, 2.15, 0.16))
    h.add(A.bm_box((0.18, 0.16, 0.06), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(2.8, 2.24, 0.23))

    export_model(h, "hero_wall_bulkhead.glb", seed=182)


def build_door_arch_trim():
    """3. 室内隔断过道斜角科幻门框（净宽 4.8m × 净高 3.3m，完美套在生活楼等内部隔断通道上，绝不挡人！）"""
    m = fresh_mats()
    h = A.Hero("HeroDoorArchTrim")
    for sx in (-1.0, 1.0):
        h.add(A.bm_box((0.46, 3.55, 0.52), bevel=0.06, segments=2), m["M_DarkSteel"], loc=(sx * 2.68, 1.78, 0.0))
        h.add(A.bm_box((0.12, 2.65, 0.56), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(sx * 2.46, 1.55, 0.0))
        # 斜角太空舱门角撑
        h.add(A.bm_box((0.75, 0.26, 0.54), bevel=0.04, segments=2), m["M_CastSteel"], loc=(sx * 2.22, 3.22, 0.0), rot=(0.0, 0.0, sx * 38.0))
    # 门框顶部加厚门楣 + 双面青色引导状态条
    h.add(A.bm_box((5.85, 0.48, 0.58), bevel=0.06, segments=2), m["M_CastSteel"], loc=(0.0, 3.58, 0.0))
    h.add(A.bm_box((3.2, 0.10, 0.62), bevel=0.02, segments=2), m["M_GlowCyan"], loc=(0.0, 3.42, 0.0))
    export_model(h, "hero_door_arch_trim.glb", seed=183)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_ceiling_bay_truss()
    build_wall_bulkhead()
    build_door_arch_trim()
    print("BUILD_CEILING_WALL_KIT_OK (3 GLBs)")


if __name__ == "__main__":
    main()
