"""《迷失太空》呆萌极地科考小机器人“小霜” + 巨兽遗迹终点冰封心脏密钥祭坛（Blender 4.5）"""

import math
import os
import sys

import bmesh
from mathutils import Vector

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
    mats["M_Teal"] = K.mat("M_Teal", (0.16, 0.56, 0.58), 0.38, 0.12)
    mats["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.88, 0.98), 0.14, 0.0,
                               emit=(0.18, 0.88, 1.0), emit_strength=2.2)
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.98, 0.64, 0.18), 0.16, 0.0,
                                emit=(1.0, 0.58, 0.16), emit_strength=2.2)
    mats["M_FossilBone"] = K.mat("M_FossilBone", (0.62, 0.58, 0.50), 0.72, 0.0)
    return mats


def bm_sphere(r=0.5, u=18, v=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r)
    return bm


def bm_cyl(r1, r2, h, segs=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    return bm


def finalize(hero, filename, seed=501, ao_rays=8):
    gain = dict(HM.WEAR_GAIN)
    gain["M_FossilBone"] = 0.75
    gain["M_Teal"] = 0.75
    obj = hero.finish(
        smooth=True,
        split_angle=34.0,
        bake={"ao_rays": ao_rays, "ao_dist": 0.16, "seed": seed, "mat_gain": gain, "ground_z": 0.0, "verbose": False},
    )
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    K.apply_modifiers(obj)
    A.export_glb(os.path.join(OUT_DIR, filename), obj.name)
    A.report(filename, obj)


def build_helper_bot():
    """呆萌极地科考小机器人“小霜” (高约 1.28m, 正面朝 -Z)"""
    m = fresh_mats()
    h = A.Hero("HeroHelperBot")
    # 左右厚实雪地履带底盘（圆角深钢履带 + 工业橙轮毂）
    for sx in (-0.36, 0.36):
        h.add(A.bm_box((0.20, 0.24, 0.78), bevel=0.055, segments=3), m["M_Rubber"], loc=(sx, 0.12, 0.0))
        for wz in (-0.25, 0.0, 0.25):
            h.add(bm_cyl(0.08, 0.08, 0.23, 14), m["M_PaintOrange"], loc=(sx, 0.12, wz), rot=(0, 0, 90))
    # 胖乎乎奶油白/青绿圆润身体（车削+放样）
    h.add(A.bm_loft([
        (0.20, A.rrect_r(0.68, 0.62, 0.18, 6)),
        (0.38, A.rrect_r(0.76, 0.70, 0.20, 6)),
        (0.74, A.rrect_r(0.74, 0.68, 0.20, 6)),
        (0.84, A.rrect_r(0.60, 0.56, 0.16, 6)),
    ]), m["M_PaintCream"])
    # 胸口暖心热核取暖窗（给靠近的玩家发暖光！）+ 青绿腰带
    h.add(A.bm_box((0.78, 0.12, 0.72), bevel=0.04, segments=2), m["M_Teal"], loc=(0.0, 0.54, 0.0))
    h.add(A.bm_box((0.30, 0.20, 0.08), bevel=0.02, segments=2), m["M_SteelDeep"], loc=(0.0, 0.44, -0.34))
    h.add(A.bm_box((0.22, 0.12, 0.09), bevel=0.015, segments=2), m["M_GlowAmber"], loc=(0.0, 0.44, -0.355))
    # 两只萌萌的短机械小手（挂在身体两侧）
    for sx in (-0.44, 0.44):
        h.add(A.bm_box((0.12, 0.12, 0.36), bevel=0.03, segments=2), m["M_CastSteel"], loc=(sx, 0.56, -0.14), rot=(-18, 0, 0))
        h.add(A.bm_box((0.10, 0.12, 0.12), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(sx, 0.50, -0.32))
    # 脖子与大号 WALL-E 风格双筒大眼睛头部（朝 -Z）
    h.add(bm_cyl(0.11, 0.14, 0.24, 16), m["M_Bronze"], loc=(0.0, 0.90, -0.02))
    h.add(A.bm_box((0.52, 0.24, 0.32), bevel=0.06, segments=3), m["M_SteelDeep"], loc=(0.0, 1.04, -0.04))
    for ex in (-0.15, 0.15):
        h.add(bm_cyl(0.115, 0.115, 0.24, 20), m["M_PaintCream"], loc=(ex, 1.05, -0.15), rot=(90, 0, 0))
        h.add(bm_cyl(0.082, 0.082, 0.26, 18), m["M_GlowCyan"], loc=(ex, 1.05, -0.16), rot=(90, 0, 0))
    # 头顶呆毛天线 + 橙色发光小球
    h.add(bm_cyl(0.016, 0.010, 0.26, 10), m["M_BareSteel"], loc=(0.12, 1.24, 0.02), rot=(0, 0, -16))
    h.add(bm_sphere(0.048, 12, 10), m["M_PaintOrange"], loc=(0.16, 1.37, 0.02))
    finalize(h, "hero_helper_bot.glb", seed=501)


def build_heart_altar():
    """巨兽遗迹终点 · 冰封巨兽心脏密钥祭坛 (直径 11m, 高 9.5m)"""
    m = fresh_mats()
    h = A.Hero("HeroHeartAltar")
    # 阶梯式深岩圆形神殿底座（三层台阶，中间平滑可站）
    h.add(A.bm_lathe([
        (0.0, 0.0), (5.4, 0.0), (5.1, 0.45), (4.2, 0.45), (4.0, 0.95), (2.8, 0.95), (2.6, 1.35), (0.0, 1.35)
    ], 16), m["M_Bedrock"])
    # 底座发光能量脉络青铜圆环
    h.add(A.bm_torus(3.4, 0.14, 28, 8), m["M_Bronze"], loc=(0.0, 0.98, 0.0))
    h.add(A.bm_torus(2.2, 0.12, 24, 8), m["M_GlowCyan"], loc=(0.0, 1.38, 0.0))
    # 6 根环形弯曲合抱的远古巨兽古骨肋爪（向中心托起巨兽心脏晶核）
    for k in range(6):
        ang = k * 60.0 + 30.0
        rad = math.radians(ang)
        for seg in range(4):
            t0 = seg / 4.0
            t1 = (seg + 1) / 4.0
            r0 = 4.6 - t0 * 1.4 + math.sin(t0 * math.pi) * 0.8
            r1 = 4.6 - t1 * 1.4 + math.sin(t1 * math.pi) * 0.8
            y0 = 0.6 + t0 * 7.2
            y1 = 0.6 + t1 * 7.2
            p0 = Vector((math.cos(rad) * r0, y0, math.sin(rad) * r0))
            p1 = Vector((math.cos(rad) * r1, y1, math.sin(rad) * r1))
            mid = (p0 + p1) * 0.5
            v = p1 - p0
            horiz = math.hypot(v.x, v.z)
            pitch = -math.degrees(math.atan2(v.y, max(horiz, 1e-4)))
            yaw = math.degrees(math.atan2(v.x, v.z))
            w = 0.58 * (1.0 - t0 * 0.45)
            h.add(A.bm_box((w, w * 0.72, v.length + 0.18), bevel=w * 0.2, segments=2),
                  m["M_FossilBone"], loc=mid, rot=(pitch, yaw, 0))
    # 正中悬空雕琢的冰封巨兽心脏大晶簇（多面棱柱 + 发光核心脉络）
    h.add(bm_cyl(0.15, 1.15, 3.8, 6), m["M_CrystalCore"], loc=(0.0, 4.6, 0.0))
    h.add(bm_cyl(1.15, 0.10, 2.2, 6), m["M_CrystalCore"], loc=(0.0, 7.5, 0.0))
    for k in range(4):
        ang = k * 90.0 + 20.0
        rad = math.radians(ang)
        h.add(bm_cyl(0.08, 0.48, 2.8, 6), m["M_GlowCyan"],
              loc=(math.cos(rad) * 0.95, 4.4, math.sin(rad) * 0.95), rot=(22, ang, -18))
    # 围绕心脏的双层青铜与琥珀全息约束环
    h.add(A.bm_torus(2.15, 0.08, 28, 8), m["M_GlowAmber"], loc=(0.0, 5.2, 0.0), rot=(24, 15, 10))
    h.add(A.bm_torus(1.75, 0.07, 24, 8), m["M_GlowCyan"], loc=(0.0, 5.2, 0.0), rot=(-28, -20, 14))
    finalize(h, "hero_heart_altar.glb", seed=502, ao_rays=6)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    build_helper_bot()
    build_heart_altar()
    print("BOT_AND_ALTAR_GLBS_OK")
