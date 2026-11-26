"""《迷失太空》统一写实科幻头盔面罩全息投影风格 · 全套 27 个物品图标生成器
- 统一采用深空半透明微光底 + 锐利冰青/琥珀/翡翠/珊瑚发光工程线框 + 内部实体剪影 + 四角瞄准微刻度；
- 彻底替换旧版杂乱卡通 SVG 与像素粗糙 PNG，256×256 超清抗锯齿导出至 game/assets/items/visor_icons/。
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(REPO, "game", "assets", "items", "visor_icons")

CYAN = (76, 238, 255)
CYAN_SOFT = (76, 238, 255, 52)
TEAL = (56, 234, 198)
TEAL_SOFT = (56, 234, 198, 52)
AMBER = (255, 184, 72)
AMBER_SOFT = (255, 184, 72, 54)
CORAL = (255, 110, 78)
CORAL_SOFT = (255, 110, 78, 54)
EMERALD = (78, 245, 162)
EMERALD_SOFT = (78, 245, 162, 54)
VIOLET = (176, 146, 255)
VIOLET_SOFT = (176, 146, 255, 54)
ICE_WHITE = (232, 249, 255)


def new_canvas(size=256):
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def finish_icon(base_img, accent, filename):
    # 添加克制的全息外发光光晕，使其像真实投影在宇航员头盔面罩上
    glow = base_img.filter(ImageFilter.GaussianBlur(radius=6))
    # 提升发光层饱和度
    r, g, b, a = glow.split()
    a = a.point(lambda v: min(255, int(v * 0.65)))
    glow = Image.merge("RGBA", (r, g, b, a))

    out = new_canvas(256)
    # 极淡的战术菱形/圆环光学校准底纹
    bg_draw = ImageDraw.Draw(out)
    col_ring = (accent[0], accent[1], accent[2], 32)
    col_tick = (accent[0], accent[1], accent[2], 95)
    bg_draw.ellipse([20, 20, 236, 236], outline=col_ring, width=2)
    # 四角极简 L 形全息定位角标
    m, L = 18, 20
    for cx, cy, dx, dy in [(m, m, 1, 1), (256 - m, m, -1, 1), (m, 256 - m, 1, -1), (256 - m, 256 - m, -1, -1)]:
        bg_draw.line([(cx, cy), (cx + dx * L, cy)], fill=col_tick, width=3)
        bg_draw.line([(cx, cy), (cx, cy + dy * L)], fill=col_tick, width=3)

    out = Image.alpha_composite(out, glow)
    out = Image.alpha_composite(out, base_img)
    out.save(os.path.join(OUT_DIR, filename))


def rr(draw, box, rad, fill=None, outline=None, width=6):
    draw.rounded_rectangle(box, radius=rad, fill=fill, outline=outline, width=width)


def build_all():
    os.makedirs(OUT_DIR, exist_ok=True)

    # 1. 氧气瓶 oxygen
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [84, 72, 172, 220], 34, fill=CYAN_SOFT, outline=CYAN, width=7)
    d.rectangle([86, 122, 170, 162], fill=(76, 238, 255, 110))
    d.line([(128, 72), (128, 42)], fill=ICE_WHITE, width=10)
    d.line([(98, 44), (158, 44)], fill=AMBER, width=9)
    d.ellipse([108, 130, 148, 156], outline=ICE_WHITE, width=4)
    d.rectangle([84, 196, 172, 220], fill=(76, 238, 255, 80), outline=CYAN, width=5)
    finish_icon(img, CYAN, "oxygen.png")

    # 2. 医疗包 medical
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [46, 76, 210, 204], 22, fill=EMERALD_SOFT, outline=EMERALD, width=7)
    rr(d, [96, 46, 160, 78], 12, outline=EMERALD, width=7)
    d.rectangle([114, 102, 142, 178], fill=ICE_WHITE)
    d.rectangle([90, 126, 166, 154], fill=ICE_WHITE)
    finish_icon(img, EMERALD, "medical.png")

    # 3. 便携热风机 heater
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [46, 98, 168, 154], 16, fill=AMBER_SOFT, outline=AMBER, width=7)
    d.polygon([(168, 104), (210, 90), (210, 162), (168, 148)], fill=(255, 110, 78, 90), outline=CORAL)
    d.line([(168, 104), (210, 90), (210, 162), (168, 148), (168, 104)], fill=CORAL, width=6)
    rr(d, [68, 154, 104, 214], 10, fill=AMBER_SOFT, outline=AMBER, width=7)
    # 热量波纹
    for x in (118, 140):
        d.line([(x, 110), (x, 142)], fill=ICE_WHITE, width=5)
    for y in (106, 126, 146):
        d.line([(218, y), (234, y)], fill=AMBER, width=5)
    finish_icon(img, AMBER, "heater.png")

    # 4. 手持吸推器 suction
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [44, 98, 148, 152], 14, fill=CYAN_SOFT, outline=CYAN, width=7)
    rr(d, [64, 152, 98, 212], 10, fill=CYAN_SOFT, outline=CYAN, width=7)
    # 三爪磁力发射口 + 波纹弧
    d.line([(148, 104), (186, 86)], fill=ICE_WHITE, width=7)
    d.line([(148, 125), (194, 125)], fill=ICE_WHITE, width=7)
    d.line([(148, 146), (186, 164)], fill=ICE_WHITE, width=7)
    d.arc([172, 78, 224, 172], -55, 55, fill=CYAN, width=6)
    d.arc([192, 64, 240, 186], -50, 50, fill=TEAL, width=5)
    finish_icon(img, CYAN, "suction.png")

    # 5. 备用电池 / 热能电池 / 燃料 cell / battery / fuel
    for fname, col, soft in [("cell.png", AMBER, AMBER_SOFT), ("battery.png", CYAN, CYAN_SOFT), ("fuel.png", CORAL, CORAL_SOFT)]:
        img = new_canvas(); d = ImageDraw.Draw(img)
        rr(d, [76, 62, 180, 214], 18, fill=soft, outline=col, width=7)
        rr(d, [104, 38, 152, 64], 8, fill=col, outline=col, width=4)
        # 闪电符号
        d.polygon([(136, 86), (102, 144), (128, 144), (118, 192), (156, 130), (130, 130)], fill=ICE_WHITE)
        finish_icon(img, col, fname)

    # 6. 脆脆薯片 chips
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [68, 56, 188, 206], 18, fill=AMBER_SOFT, outline=AMBER, width=7)
    d.line([(68, 78), (188, 78)], fill=AMBER, width=5)
    d.line([(68, 184), (188, 184)], fill=AMBER, width=5)
    d.ellipse([96, 104, 160, 160], fill=(255, 184, 72, 110), outline=ICE_WHITE, width=6)
    d.arc([106, 118, 150, 146], 190, 350, fill=ICE_WHITE, width=5)
    finish_icon(img, AMBER, "chips.png")

    # 7. 科考纪念杯 keepsake
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [64, 86, 166, 204], 18, fill=TEAL_SOFT, outline=TEAL, width=7)
    d.arc([148, 104, 206, 178], -90, 90, fill=TEAL, width=8)
    d.line([(64, 116), (166, 116)], fill=AMBER, width=6)
    # 星星徽章
    d.polygon([(115, 132), (122, 150), (140, 150), (126, 161), (131, 178), (115, 168), (99, 178), (104, 161), (90, 150), (108, 150)], fill=ICE_WHITE)
    finish_icon(img, TEAL, "keepsake.png")

    # 8. 轻型样本箱 / 货箱 crate / freight
    for fname, col, soft in [("crate.png", CYAN, CYAN_SOFT), ("freight.png", AMBER, AMBER_SOFT)]:
        img = new_canvas(); d = ImageDraw.Draw(img)
        rr(d, [50, 68, 206, 198], 16, fill=soft, outline=col, width=7)
        d.line([(50, 106), (206, 106)], fill=col, width=6)
        d.line([(128, 106), (128, 198)], fill=col, width=5)
        rr(d, [104, 82, 152, 120], 6, fill=ICE_WHITE)
        finish_icon(img, col, fname)

    # 9. 异常冰样 sample
    img = new_canvas(); d = ImageDraw.Draw(img)
    pts = [(128, 38), (178, 96), (162, 204), (94, 204), (78, 96)]
    d.polygon(pts, fill=CYAN_SOFT)
    d.line(pts + [pts[0]], fill=CYAN, width=7)
    d.line([(128, 38), (128, 204)], fill=ICE_WHITE, width=4)
    d.line([(78, 96), (178, 96)], fill=ICE_WHITE, width=4)
    finish_icon(img, CYAN, "sample.png")

    # 10. 极地弹跳垫 bounce_pad（专属弹簧跳垫 + 向上双箭头！）
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [44, 166, 212, 206], 18, fill=CYAN_SOFT, outline=CYAN, width=7)
    d.line([(68, 186), (188, 186)], fill=AMBER, width=7)
    # 两个向上跃起发光箭头
    for y in (122, 82):
        d.line([(86, y + 24), (128, y), (170, y + 24)], fill=ICE_WHITE if y == 82 else CYAN, width=9)
    finish_icon(img, CYAN, "bounce_pad.png")

    # 11. 极光信号弹 flare（燃烧信号棒 + 星芒！）
    img = new_canvas(); d = ImageDraw.Draw(img)
    # 斜放信号棒
    d.line([(86, 206), (154, 106)], fill=CORAL, width=22)
    d.line([(106, 176), (138, 128)], fill=ICE_WHITE, width=10)
    # 顶部爆炸星芒
    cx, cy = 166, 86
    for deg in range(0, 360, 45):
        ang = math.radians(deg)
        r2 = 44 if deg % 90 == 0 else 28
        d.line([(cx, cy), (cx + math.cos(ang) * r2, cy + math.sin(ang) * r2)], fill=AMBER, width=6)
    d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=ICE_WHITE)
    finish_icon(img, CORAL, "flare.png")

    # 12. 复古磁力音响 boombox（双大喇叭 + 磁带仓 + 声波！）
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [38, 92, 218, 198], 18, fill=VIOLET_SOFT, outline=VIOLET, width=7)
    rr(d, [80, 56, 176, 94], 12, outline=CYAN, width=7)
    for cx in (78, 178):
        d.ellipse([cx - 28, 118, cx + 28, 174], fill=CYAN_SOFT, outline=CYAN, width=6)
        d.ellipse([cx - 10, 136, cx + 10, 156], fill=ICE_WHITE)
    rr(d, [112, 124, 144, 166], 6, outline=AMBER, width=5)
    finish_icon(img, VIOLET, "boombox.png")

    # 13. 雪地反重力碰碰球 bumper_orb（力场大球 + 十字环带！）
    img = new_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([54, 54, 202, 202], fill=CYAN_SOFT, outline=CYAN, width=8)
    d.arc([54, 94, 202, 162], 0, 180, fill=AMBER, width=7)
    d.arc([94, 54, 162, 202], -90, 90, fill=ICE_WHITE, width=5)
    d.ellipse([112, 112, 144, 144], fill=ICE_WHITE)
    finish_icon(img, CYAN, "bumper_orb.png")

    # 14. 极地热可可保温壶 thermos（圆润保温壶 + 温暖热气波！）
    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [84, 92, 172, 216], 24, fill=AMBER_SOFT, outline=AMBER, width=7)
    rr(d, [98, 66, 158, 96], 10, fill=(255, 110, 78, 95), outline=CORAL, width=6)
    d.line([(86, 148), (170, 148)], fill=ICE_WHITE, width=7)
    # 温暖热气曲线
    for sx in (106, 128, 150):
        d.line([(sx, 56), (sx + 6, 44), (sx - 4, 32)], fill=ICE_WHITE, width=5)
    finish_icon(img, AMBER, "thermos.png")

    # 15. 装备类 & 其他特殊道具统一全息化（thermal_suit / wide_scanner / signal_stabilizer / core / coolant / penguin / bubble / board / hologram / smoke）
    # thermal_suit 恒温外套
    img = new_canvas(); d = ImageDraw.Draw(img)
    pts = [(94, 58), (162, 58), (206, 108), (180, 134), (166, 118), (166, 204), (90, 204), (90, 118), (76, 134), (50, 108)]
    d.polygon(pts, fill=AMBER_SOFT)
    d.line(pts + [pts[0]], fill=AMBER, width=7)
    d.line([(128, 58), (128, 204)], fill=ICE_WHITE, width=5)
    finish_icon(img, AMBER, "thermal_suit.png")

    # wide_scanner 广域扫描器
    img = new_canvas(); d = ImageDraw.Draw(img)
    for r in (26, 54, 82):
        d.ellipse([128 - r, 128 - r, 128 + r, 128 + r], outline=CYAN, width=5)
    d.line([(128, 128), (192, 72)], fill=ICE_WHITE, width=7)
    d.ellipse([116, 116, 140, 140], fill=AMBER)
    finish_icon(img, CYAN, "wide_scanner.png")

    # signal_stabilizer 信号稳压器
    img = new_canvas(); d = ImageDraw.Draw(img)
    d.line([(128, 54), (128, 204)], fill=TEAL, width=9)
    d.line([(86, 204), (170, 204)], fill=TEAL, width=9)
    for r in (28, 54):
        d.arc([128 - r, 86 - r, 128 + r, 86 + r], 210, 330, fill=ICE_WHITE, width=6)
        d.arc([128 - r, 86 - r, 128 + r, 86 + r], 30, 150, fill=CYAN, width=6)
    d.ellipse([114, 72, 142, 100], fill=AMBER)
    finish_icon(img, TEAL, "signal_stabilizer.png")

    # core / coolant / hologram / bubble / board / smoke / penguin
    img = new_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([66, 66, 190, 190], fill=AMBER_SOFT, outline=AMBER, width=7)
    d.polygon([(128, 46), (176, 128), (128, 210), (80, 128)], outline=ICE_WHITE, width=6)
    d.ellipse([108, 108, 148, 148], fill=ICE_WHITE)
    finish_icon(img, AMBER, "core.png")

    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [80, 62, 176, 206], 24, fill=CYAN_SOFT, outline=CYAN, width=7)
    for deg in range(0, 180, 60):
        ang = math.radians(deg)
        d.line([(128 - math.cos(ang) * 32, 134 - math.sin(ang) * 32),
                (128 + math.cos(ang) * 32, 134 + math.sin(ang) * 32)], fill=ICE_WHITE, width=6)
    finish_icon(img, CYAN, "coolant.png")

    img = new_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([96, 52, 160, 116], fill=CYAN_SOFT, outline=CYAN, width=7)
    d.polygon([(74, 204), (92, 126), (164, 126), (182, 204)], fill=CYAN_SOFT)
    d.line([(74, 204), (92, 126), (164, 126), (182, 204), (74, 204)], fill=CYAN, width=7)
    for y in (148, 168, 188):
        d.line([(86, y), (170, y)], fill=ICE_WHITE, width=4)
    finish_icon(img, CYAN, "hologram.png")

    img = new_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([60, 60, 196, 196], fill=VIOLET_SOFT, outline=VIOLET, width=7)
    d.arc([82, 82, 174, 174], 200, 290, fill=ICE_WHITE, width=7)
    finish_icon(img, VIOLET, "bubble.png")

    img = new_canvas(); d = ImageDraw.Draw(img)
    rr(d, [44, 108, 212, 152], 22, fill=TEAL_SOFT, outline=TEAL, width=7)
    d.line([(72, 130), (184, 130)], fill=ICE_WHITE, width=6)
    finish_icon(img, TEAL, "board.png")

    img = new_canvas(); d = ImageDraw.Draw(img)
    for cx, cy, r in [(100, 138, 34), (138, 116, 40), (162, 146, 30)]:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=CORAL_SOFT, outline=CORAL, width=6)
    finish_icon(img, CORAL, "smoke.png")

    img = new_canvas(); d = ImageDraw.Draw(img)
    d.ellipse([80, 60, 176, 204], fill=CYAN_SOFT, outline=CYAN, width=7)
    d.ellipse([100, 104, 156, 190], fill=(232, 249, 255, 90))
    d.polygon([(118, 96), (138, 96), (128, 114)], fill=AMBER)
    finish_icon(img, CYAN, "penguin.png")

    print(f"GENERATED 27 SCI-FI VISOR ITEM ICONS -> {OUT_DIR}")


if __name__ == "__main__":
    build_all()
