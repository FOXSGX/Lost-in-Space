"""霜烬星 2.0 · 解剖级巨兽生物骨架（巨兽头骨 + 沙漏型脊椎骨节 + 扁平弧形肋骨笼）
彻底告别“弯管子”：
1. hero_fossil_arch.glb：
   - 顶脊：沙漏型椎体（两端关节盘膨大、中段收腰）+ 向后掠起的扁平背棘突 + 左右横突关节窝；
   - 肋骨：真实解剖扁平刃状截面（前后宽、内外扁、外缘带骨棱），自关节结节大弧度外张并自然收尖插入雪地；
   - 每组包含主/副两对带自然破损与微不对称的肋骨，一眼读出远古海洋/极地巨兽遗骸。
2. hero_leviathan_skull.glb：
   - 流线型古巨兽长吻颅骨 + 深凹眼眶 + 颧弓骨棱 + 高耸鼻脊 + 弧形下颌与弯钩利齿，坐镇巨骨峡谷入口。
"""

import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
KIT_DIR = os.path.join(REPO, "art-source", "deliveries", "ART-SAMPLE-002_TEAM_KIT", "02_BLENDER_SOURCE", "scripts")
sys.path.insert(0, KIT_DIR)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aqs_kit as A
from build_hero_pack import fresh_mats, finalize_and_export


def bm_bladed_rib(pts, widths, thicks, seg=12, seed=1):
    """沿 3D 骨弧扫掠解剖学扁平水滴/肋骨截面（外缘圆厚、内缘带骨槽、自然骨质凹凸）"""
    vs = [Vector(p) for p in pts]
    n = len(vs)
    tangs = []
    for i in range(n):
        t = (vs[1] - vs[0]) if i == 0 else ((vs[-1] - vs[-2]) if i == n - 1 else (vs[i + 1] - vs[i - 1]))
        tangs.append(t.normalized())

    bm = bmesh.new()
    rings = []
    for i in range(n):
        t = tangs[i]
        # 肋骨平面法向大致沿 Z（前后宽），厚度沿曲线径向
        fore = Vector((0.0, 0.0, 1.0))
        fore = (fore - t * fore.dot(t))
        if fore.length < 1e-4:
            fore = Vector((1.0, 0.0, 0.0))
        fore.normalize()
        rad = t.cross(fore).normalized()

        w = widths[i]
        th = thicks[i]
        ring = []
        for k in range(seg):
            a = A.TAU * k / seg
            # 解剖学水滴肋骨截面：前缘饱满、后缘略收窄、内侧微凹（肋沟）
            ca, sa = math.cos(a), math.sin(a)
            groove = 0.82 if sa < -0.25 else 1.0
            ridge = 1.14 if abs(ca) < 0.35 and sa > 0.35 else 1.0
            local_p = fore * (ca * w) + rad * (sa * th * groove * ridge)
            ring.append(bm.verts.new(vs[i] + local_p))
        rings.append(ring)

    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(seg):
            k2 = (k + 1) % seg
            try:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                f.smooth = True
            except ValueError:
                pass
    try:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    except ValueError:
        pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    A.soften(bm, amp=0.055, freq=1.1, seed=seed)
    return bm


def add_vertebra(hero, mat_bone, mat_dark, z_off, y_top, scale=1.0, seed=1):
    """精雕单节解剖学巨兽脊椎骨：沙漏椎体 + 掠后背棘突 + 左右横突关节"""
    s = scale
    # 1. 沙漏型椎体（沿 Z 轴车削：两端关节盘粗大、中间收细）
    prof = [
        (0.0, -1.65 * s), (1.38 * s, -1.65 * s), (1.46 * s, -1.35 * s),
        (1.02 * s, -0.65 * s), (0.88 * s, 0.0), (1.02 * s, 0.65 * s),
        (1.46 * s, 1.35 * s), (1.38 * s, 1.65 * s), (0.0, 1.65 * s),
    ]
    centrum = A.bm_lathe(prof, seg=16)
    A.soften(centrum, amp=0.04 * s, freq=1.6, seed=seed)
    hero.add(centrum, mat_bone, loc=(0.0, y_top, z_off), axis="zp")

    # 2. 椎间暗色软骨/关节缝盘
    disc = A.bm_cyl(1.18 * s, 0.42 * s, seg=14)
    hero.add(disc, mat_dark, loc=(0.0, y_top, z_off + 1.65 * s), axis="zp")

    # 3. 高耸掠后的扁平背棘突（Neural Spine）—— 生物脊椎最具辨识度的剪影！
    spine_pts = [
        (0.0, y_top + 0.85 * s, z_off + 0.25 * s),
        (0.0, y_top + 2.35 * s, z_off - 0.55 * s),
        (0.0, y_top + 3.95 * s, z_off - 1.55 * s),
        (0.0, y_top + 4.85 * s, z_off - 2.35 * s),
    ]
    n_spine = bm_bladed_rib(
        spine_pts,
        [1.15 * s, 0.92 * s, 0.68 * s, 0.28 * s],
        [0.42 * s, 0.34 * s, 0.24 * s, 0.12 * s],
        seg=10,
        seed=seed + 7,
    )
    hero.add(n_spine, mat_bone)

    # 4. 左右粗壮横突（Transverse Processes，承接肋骨头）
    for sx in (-1.0, 1.0):
        tp_pts = [
            (sx * 0.85 * s, y_top + 0.15 * s, z_off),
            (sx * 2.25 * s, y_top + 0.45 * s, z_off - 0.18 * s),
            (sx * 3.15 * s, y_top + 0.20 * s, z_off - 0.30 * s),
        ]
        tp = bm_bladed_rib(
            tp_pts,
            [0.78 * s, 0.62 * s, 0.72 * s],
            [0.52 * s, 0.42 * s, 0.48 * s],
            seg=10,
            seed=seed + (11 if sx > 0 else 17),
        )
        hero.add(tp, mat_bone)


def add_rib_pair(hero, mat_bone, z_off, y_top, span_x, drop_y, broken_right=False, seed=1):
    """一对自然大弧度扁平肋骨（带关节膨大结节、向后略掠、底部自然收尖插地或中段折断）"""
    for side in (-1.0, 1.0):
        is_broken = broken_right and side > 0
        steps = 9 if is_broken else 13
        pts = []
        ws = []
        ths = []
        for i in range(steps):
            t = i / 12.0  # 始终按完整 12 段参数化，折断肋骨提前截断
            # 从脊柱横突外张→高拱→弧形下垂插入雪原，带轻微向后掠角
            ang = t * math.pi * 0.92
            x = side * (2.6 + math.sin(ang * 0.78) * span_x + (t ** 2) * 1.4)
            y = y_top + 0.2 + math.sin(ang * 0.55) * 1.4 - (t ** 1.65) * drop_y
            z = z_off - math.sin(t * math.pi * 0.85) * 1.85 + side * 0.15
            pts.append((x, y, z))
            # 肋头膨大 → 肋体宽扁厚实 → 末端逐渐收尖
            if i == 0:
                w, th = 0.88, 0.58
            elif i == 1:
                w, th = 0.66, 0.40
            else:
                fade = max(0.22, 1.0 - (t ** 1.35) * 0.72)
                w, th = 0.96 * fade, 0.36 * fade
            ws.append(w)
            ths.append(th)
        rib_bm = bm_bladed_rib(pts, ws, ths, seg=12, seed=seed + (31 if side > 0 else 43))
        hero.add(rib_bm, mat_bone)


def build_fossil_arch():
    """重制 hero_fossil_arch.glb：两节连贯巨兽脊椎 + 两对宽扁解剖肋骨（一对完整大拱 + 一对自然微断副肋）"""
    m = fresh_mats()
    h = A.Hero("HeroFossilArch")
    bone = m["M_FossilBone"]
    dark_bone = m["M_BedrockDark"]

    y_spine = 14.8
    # 前主椎节 + 完整巨型扁平肋骨对
    add_vertebra(h, bone, dark_bone, z_off=0.0, y_top=y_spine, scale=1.18, seed=501)
    add_rib_pair(h, bone, z_off=0.0, y_top=y_spine, span_x=12.4, drop_y=16.8, broken_right=False, seed=510)

    # 后副椎节（自然微起伏）+ 带单侧远古断茬的副肋骨对，彻底打破机械对称感
    add_vertebra(h, bone, dark_bone, z_off=-4.8, y_top=y_spine - 0.55, scale=1.08, seed=521)
    add_rib_pair(h, bone, z_off=-4.8, y_top=y_spine - 0.55, span_x=11.5, drop_y=16.2, broken_right=True, seed=530)

    # 两侧肋脚压入解理暗岩碎块（接地自然）
    for sx in (-14.2, 14.2):
        rb = A.rock_from_planes((4.2, 2.6, 4.8), seed=540 if sx < 0 else 541, cuts=9, subdiv=2, bevel=0.014, rough=0.05)
        h.add(rb, m["M_Bedrock"], loc=(sx, 0.7, -1.8))

    finalize_and_export(h, "hero_fossil_arch.glb", seed=555, ao_rays=6)


def build_leviathan_skull():
    """新建 hero_leviathan_skull.glb：坐镇冰川峡谷入口的远古巨兽头骨与弯钩利齿拱门"""
    m = fresh_mats()
    h = A.Hero("HeroLeviathanSkull")
    bone = m["M_FossilBone"]
    dark = m["M_BedrockDark"]

    # 1. 上颅骨冠盖（流线楔形放样：宽枕骨 → 凹陷眼眶上脊 → 向前收窄的长吻骨喙）
    skull_secs = [
        (0.0, A.rrect_r(12.8, 4.6, 1.4, 5)),
        (3.5, A.rrect_r(13.6, 5.2, 1.6, 5)),
        (8.5, A.rrect_r(9.8, 4.2, 1.2, 5)),
        (14.5, A.rrect_r(5.6, 2.8, 0.8, 5)),
        (19.5, A.rrect_r(2.4, 1.4, 0.4, 5)),
    ]
    cranium = A.bm_loft(skull_secs, smooth_sides=True)
    A.soften(cranium, amp=0.14, freq=0.55, seed=601)
    # 旋转使长吻朝 +Z（迎向科考站方向）并略微仰起形成巨口拱顶
    h.add(cranium, bone, loc=(0.0, 17.5, -4.0), rot=(82.0, 0.0, 0.0))

    # 2. 中央高耸骨质鼻脊冠（Crest）
    crest_pts = [
        (0.0, 19.6, -2.5), (0.0, 22.8, 1.2), (0.0, 22.2, 6.8), (0.0, 19.4, 12.2)
    ]
    h.add(bm_bladed_rib(crest_pts, [1.8, 1.4, 0.95, 0.35], [0.65, 0.48, 0.34, 0.16], seg=10, seed=602), bone)

    # 3. 左右深邃骨质眼眶颧弓（Orbital Ridges，一眼看出是生物头骨！）
    for sx in (-1.0, 1.0):
        brow_pts = [
            (sx * 4.8, 18.8, -1.0), (sx * 8.2, 18.2, 2.2),
            (sx * 9.2, 15.6, 4.8), (sx * 6.5, 14.8, 7.2)
        ]
        h.add(bm_bladed_rib(brow_pts, [1.25, 1.15, 0.95, 0.72], [0.75, 0.68, 0.55, 0.42], seg=10, seed=610 if sx > 0 else 611), bone)
        # 深邃眼眶暗影凹腔
        h.add(A.bm_cyl(1.65, 1.2, seg=12), dark, loc=(sx * 6.4, 16.5, 3.2), rot=(0.0, 0.0, sx * 72.0))

        # 4. 两侧巨型弧形颌骨拱柱（从雪地大弧度攀升衔接颅骨，留出宽 22m 极地车通航口）
        jaw_pts = [
            (sx * 16.2, -1.0, 2.5),
            (sx * 15.2, 5.5, 4.2),
            (sx * 12.6, 11.8, 2.8),
            (sx * 8.4, 16.4, -0.5),
        ]
        h.add(bm_bladed_rib(jaw_pts, [2.1, 1.85, 1.55, 1.25], [1.15, 0.98, 0.82, 0.70], seg=12, seed=620 if sx > 0 else 621), bone)

        # 5. 上颌边缘 4 颗弧形弯钩利齿（长短错落，真正远古海兽威慑力！）
        for idx, (tx, ty, tz, tlen) in enumerate([
            (sx * 6.6, 15.6, 6.2, 3.8),
            (sx * 5.2, 15.8, 9.2, 3.2),
            (sx * 3.8, 16.2, 11.8, 2.6),
            (sx * 2.2, 16.6, 13.8, 2.1),
        ]):
            fang_pts = [
                (tx, ty, tz),
                (tx - sx * 0.25, ty - tlen * 0.55, tz - 0.35),
                (tx - sx * 0.45, ty - tlen, tz - 0.85),
            ]
            h.add(bm_bladed_rib(fang_pts, [0.58, 0.36, 0.06], [0.46, 0.28, 0.05], seg=10, seed=640 + idx), bone)

    finalize_and_export(h, "hero_leviathan_skull.glb", seed=666, ao_rays=6)


if __name__ == "__main__":
    build_fossil_arch()
    build_leviathan_skull()
    print("LEVIATHAN_BIO_SKELETON_BUILT_OK")
