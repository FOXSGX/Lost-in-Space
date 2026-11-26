"""《迷失太空》6 款高清室内写实科幻 LED 墙屏与科考简报大屏贴图生成器（HarmonyOS Sans SC）
彻底替换旧版简陋纯色方块白板，让每栋楼墙面上挂着真实、细腻、信息感满满的科幻显示大屏！
"""

import math
import os
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONT_BOLD = os.path.join(REPO, "game", "assets", "fonts", "HarmonyOS_Sans_SC_Bold.ttf")
FONT_REG = os.path.join(REPO, "game", "assets", "fonts", "HarmonyOS_Sans_SC_Regular.ttf")
OUT_DIR = os.path.join(REPO, "game", "assets", "textures", "interior_screens")

BG = (10, 19, 30)
PANEL = (15, 29, 44)
GRID = (20, 42, 62)
ICE = (232, 247, 255)
MUTED = (128, 174, 198)
CYAN = (60, 232, 255)
GREEN = (64, 240, 158)
AMBER = (255, 174, 66)
CORAL = (255, 102, 74)


def f_bold(sz): return ImageFont.truetype(FONT_BOLD, sz)
def f_reg(sz): return ImageFont.truetype(FONT_REG, sz)


def base_screen(title, tag, accent, w=1024, h=512):
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)
    for y in range(0, h, 24):
        d.line([(0, y), (w, y)], fill=GRID, width=1)
    for x in range(0, w, 32):
        d.line([(x, 0), (x, h)], fill=(14, 28, 42), width=1)
    d.rounded_rectangle([18, 18, w - 18, h - 18], radius=18, fill=PANEL, outline=accent, width=4)
    # 顶栏标题带
    d.rounded_rectangle([36, 36, w - 36, 114], radius=12, fill=(14, 34, 52), outline=accent, width=2)
    d.rounded_rectangle([48, 48, 224, 102], radius=8, fill=accent)
    d.text((70, 56), tag, font=f_bold(32), fill=BG)
    d.text((252, 52), title, font=f_bold(42), fill=ICE)
    # 右上三颗状态灯
    for i, c in enumerate((GREEN, accent, AMBER)):
        d.ellipse([w - 138 + i * 30, 66, w - 120 + i * 30, 84], fill=c)
    return img, d


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # 1. 生活区食堂与气象公告屏
    img, d = base_screen("生活区气象与值班简报", "HAB-03", AMBER)
    d.rounded_rectangle([42, 138, 490, 470], radius=12, fill=(11, 22, 34), outline=(42, 74, 96), width=2)
    d.text((64, 156), "今日极地室外实况", font=f_bold(30), fill=AMBER)
    d.text((64, 206), "-48°C   风速 14m/s", font=f_bold(44), fill=ICE)
    d.text((64, 274), "▸ 室内供暖系统：稳定 21.5°C", font=f_reg(26), fill=GREEN)
    d.text((64, 318), "▸ 食堂今日热饮：极地热可可 / 浓缩咖啡", font=f_reg(24), fill=MUTED)
    d.text((64, 362), "▸ 出舱提醒：务必携带热风机与满氧瓶", font=f_reg(24), fill=MUTED)
    d.text((64, 406), "▸ 应急联络：通讯总部 CH-04", font=f_reg(24), fill=CYAN)
    # 右侧温度曲线图
    d.rounded_rectangle([514, 138, 982, 470], radius=12, fill=(11, 22, 34), outline=(42, 74, 96), width=2)
    d.text((536, 156), "24H 极寒风暴波动曲线", font=f_bold(28), fill=CYAN)
    pts = [(540 + i * 38, 330 + int(math.sin(i * 0.65) * 68)) for i in range(12)]
    d.line(pts, fill=AMBER, width=5)
    for px, py in pts:
        d.ellipse([px - 6, py - 6, px + 6, py + 6], fill=ICE)
    img.save(os.path.join(OUT_DIR, "wall_living_poster.png"))

    # 2. 医疗舱生命体征监测屏
    img, d = base_screen("医疗维生与体征监测阵列", "MED-01", GREEN)
    d.rounded_rectangle([42, 138, 660, 470], radius=12, fill=(9, 24, 24), outline=GREEN, width=2)
    d.text((64, 154), "ECG // 心电与抗寒代谢曲线", font=f_bold(26), fill=GREEN)
    ecg = []
    for x in range(60, 640, 8):
        t = (x - 60) % 96
        y = 310
        if 32 <= t <= 38: y = 210
        elif 40 <= t <= 46: y = 375
        elif 48 <= t <= 56: y = 278
        ecg.append((x, y))
    d.line(ecg, fill=GREEN, width=5)
    d.rounded_rectangle([684, 138, 982, 470], radius=12, fill=(11, 22, 34), outline=(42, 86, 76), width=2)
    for idx, (lbl, val, col) in enumerate([("血氧 SPO2", "99%", CYAN), ("核心体温", "36.8°C", AMBER), ("维生舱压", "101kPa", GREEN), ("恢复状态", "就绪", ICE)]):
        yy = 160 + idx * 74
        d.text((706, yy), lbl, font=f_reg(22), fill=MUTED)
        d.text((846, yy - 4), val, font=f_bold(30), fill=col)
    img.save(os.path.join(OUT_DIR, "wall_med_vitals.png"))

    # 3. 冰川钻探地质剖面屏
    img, d = base_screen("冰川深层钻探剖面 · CORE-09", "GEO-09", CYAN)
    # 左侧分层冰芯地质剖面
    layers = [(150, 210, (32, 92, 128), "0–120m  表层极地冰盖"),
              (210, 290, (22, 68, 108), "120–340m  高压蓝冰晶层"),
              (290, 380, (42, 54, 72), "340–520m  古兽遗骸空腔异常回波"),
              (380, 460, (68, 42, 34), "520m+  地热基岩热脉")]
    for y1, y2, col, txt in layers:
        d.rectangle([48, y1, 610, y2], fill=col, outline=CYAN, width=2)
        d.text((68, y1 + 16), txt, font=f_bold(24), fill=ICE)
    # 右侧样本波形
    d.rounded_rectangle([636, 146, 980, 464], radius=12, fill=(10, 22, 34), outline=CYAN, width=2)
    d.text((656, 162), "异常样本能量谱", font=f_bold(26), fill=CYAN)
    for i in range(9):
        bh = 50 + int(abs(math.sin(i * 0.9 + 0.4)) * 185)
        bx = 662 + i * 33
        d.rectangle([bx, 430 - bh, bx + 22, 430], fill=CYAN if i != 5 else AMBER)
    img.save(os.path.join(OUT_DIR, "wall_drill_geology.png"))

    # 4. 生态温室水培环境监控屏
    img, d = base_screen("生态穹顶水培环境控制", "BIO-07", GREEN)
    bars = [("光照强度", 0.88, AMBER), ("氧气产出", 0.94, GREEN), ("营养液循环", 0.82, CYAN), ("穹顶恒温", 0.90, GREEN)]
    for i, (lbl, ratio, col) in enumerate(bars):
        yy = 156 + i * 76
        d.text((54, yy), lbl, font=f_bold(28), fill=ICE)
        d.rounded_rectangle([240, yy + 4, 940, yy + 38], radius=8, fill=(14, 30, 36), outline=(44, 86, 74), width=2)
        d.rounded_rectangle([244, yy + 8, 244 + int(692 * ratio), yy + 34], radius=6, fill=col)
    img.save(os.path.join(OUT_DIR, "wall_greenhouse_botany.png"))

    # 5. 地热反应堆遥测屏
    img, d = base_screen("地热涡轮核心负荷监控", "PWR-12", AMBER)
    for idx, (cx, lbl, pct, col) in enumerate([(200, "一号涡轮", 0.86, AMBER), (512, "二号涡轮", 0.92, CORAL), (824, "主电网输出", 0.78, CYAN)]):
        d.ellipse([cx - 110, 170, cx + 110, 390], outline=(38, 62, 78), width=18)
        d.arc([cx - 110, 170, cx + 110, 390], -90, -90 + int(360 * pct), fill=col, width=18)
        d.text((cx - 52, 260), "%d%%" % int(pct * 100), font=f_bold(46), fill=ICE)
        d.text((cx - 56, 412), lbl, font=f_bold(26), fill=col)
    img.save(os.path.join(OUT_DIR, "wall_reactor_telemetry.png"))

    # 6. 极地基地总览战术地图屏
    img, d = base_screen("霜烬星极地基地建筑总图", "SEC-04", CYAN)
    d.rounded_rectangle([42, 138, 982, 470], radius=12, fill=(9, 20, 32), outline=CYAN, width=2)
    # 绘制 16 栋建筑缩略平面图 + 公路十字线
    d.line([(512, 150), (512, 460)], fill=(32, 76, 98), width=6)
    d.line([(60, 305), (960, 305)], fill=(32, 76, 98), width=6)
    blocks = [(512, 225, 110, 44, CYAN, "主科研楼"), (360, 275, 58, 52, AMBER, "标本馆"),
              (664, 275, 58, 52, GREEN, "生活医疗"), (360, 360, 74, 44, MUTED, "仓库"),
              (664, 360, 74, 44, AMBER, "车库"), (220, 220, 62, 62, GREEN, "温室"),
              (800, 220, 68, 48, CYAN, "通讯总部"), (200, 355, 82, 50, AMBER, "货运站"),
              (820, 355, 82, 50, CORAL, "机甲厂"), (512, 424, 70, 38, CORAL, "坠毁归航号")]
    for bx, by, bw, bh, col, name in blocks:
        d.rounded_rectangle([bx - bw // 2, by - bh // 2, bx + bw // 2, by + bh // 2], radius=6, fill=(18, 38, 54), outline=col, width=3)
        d.text((bx - bw // 2 + 6, by - 11), name, font=f_bold(16), fill=ICE)
    img.save(os.path.join(OUT_DIR, "wall_colony_map.png"))

    print(f"GENERATED 6 HIGH-RES SCI-FI INTERIOR WALL SCREENS -> {OUT_DIR}")


if __name__ == "__main__":
    main()
