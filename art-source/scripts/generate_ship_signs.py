"""使用 HarmonyOS Sans SC 生成太空舱 & 训练舱暗底发光科技感 LED 显示屏贴图"""

import os
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONT_BOLD = os.path.join(REPO, "game", "assets", "fonts", "HarmonyOS_Sans_SC_Bold.ttf")
FONT_REG = os.path.join(REPO, "game", "assets", "fonts", "HarmonyOS_Sans_SC_Regular.ttf")
OUT_DIR = os.path.join(REPO, "game", "assets", "textures", "ship_signs")

BG_DARK = (9, 19, 31)
BG_PANEL = (14, 29, 46)
GRID_LINE = (18, 40, 60)
ICE_WHITE = (234, 248, 255)
MUTED_CYAN = (128, 178, 202)
NEON_CYAN = (56, 232, 255)
NEON_TEAL = (48, 224, 196)
NEON_GREEN = (72, 240, 158)
NEON_ORANGE = (255, 166, 62)
NEON_CORAL = (255, 102, 74)


def load_font(path, size):
    return ImageFont.truetype(path, size)


def draw_led_bg(draw, w, h, accent):
    # 深黑蓝 LED 玻璃基板 + 细微科技点阵网格
    draw.rectangle([0, 0, w, h], fill=BG_DARK)
    for y in range(0, h, 16):
        draw.line([(0, y), (w, y)], fill=GRID_LINE, width=1)
    for x in range(0, w, 24):
        draw.line([(x, 0), (x, h)], fill=(13, 28, 43), width=1)
    # 内发光科技边线框
    draw.rounded_rectangle([14, 14, w - 14, h - 14], radius=18, fill=BG_PANEL, outline=accent, width=4)
    # 四角 L 形高亮定位角标
    L = 34
    for cx, cy, dx, dy in [(22, 22, 1, 1), (w - 22, 22, -1, 1), (22, h - 22, 1, -1), (w - 22, h - 22, -1, -1)]:
        draw.line([(cx, cy), (cx + dx * L, cy)], fill=ICE_WHITE, width=5)
        draw.line([(cx, cy), (cx, cy + dy * L)], fill=ICE_WHITE, width=5)


def make_hub_led(filename, badge_text, title_text, subtitle_text, accent, arrow=None, w=1024, h=320):
    img = Image.new("RGB", (w, h), BG_DARK)
    draw = ImageDraw.Draw(img)
    draw_led_bg(draw, w, h, accent)

    # 左侧发光 LED 状态徽章
    badge_w = 205 if len(badge_text) <= 2 else 248
    draw.rounded_rectangle([38, 40, 38 + badge_w, h - 40], radius=16, fill=accent)
    f_badge = load_font(FONT_BOLD, 90 if len(badge_text) <= 2 else 62)
    bb = draw.textbbox((0, 0), badge_text, font=f_badge)
    bw, bh = bb[2] - bb[0], bb[3] - bb[1]
    bx = 38 + (badge_w - bw) // 2 - bb[0]
    by = 40 + ((h - 80) - bh) // 2 - bb[1]
    draw.text((bx, by), badge_text, font=f_badge, fill=BG_DARK)

    # 高亮 LED 鸿蒙粗体主标题 + 青灰副标题
    tx = 38 + badge_w + 42
    f_title = load_font(FONT_BOLD, 82)
    f_sub = load_font(FONT_REG, 36)
    draw.text((tx, 54), title_text, font=f_title, fill=ICE_WHITE)
    draw.text((tx + 4, 178), subtitle_text, font=f_sub, fill=MUTED_CYAN)

    # 底部 LED 分段脉冲进度条
    seg_y = 248
    seg_x = tx
    for i in range(14):
        col = accent if i < 10 else (28, 54, 78)
        draw.rounded_rectangle([seg_x + i * 32, seg_y, seg_x + i * 32 + 22, seg_y + 14], radius=4, fill=col)

    # 可选发光 LED 方向大箭头
    if arrow in ("right", "down"):
        cx, cy = w - 106, 152
        draw.rounded_rectangle([cx - 56, cy - 56, cx + 56, cy + 56], radius=18, fill=(18, 42, 62), outline=accent, width=4)
        if arrow == "right":
            pts = [(cx - 22, cy - 26), (cx + 28, cy), (cx - 22, cy + 26)]
        else:
            pts = [(cx - 26, cy - 18), (cx + 26, cy - 18), (cx, cy + 28)]
        draw.polygon(pts, fill=accent)

    img.save(os.path.join(OUT_DIR, filename))


def make_training_led(filename, step_tag, title_text, line1, line2, accent, w=1024, h=580):
    img = Image.new("RGB", (w, h), BG_DARK)
    draw = ImageDraw.Draw(img)
    draw_led_bg(draw, w, h, accent)

    # 顶部发光 LED 状态条
    draw.rounded_rectangle([46, 42, w - 46, 140], radius=14, fill=(18, 44, 66), outline=accent, width=3)
    draw.rounded_rectangle([62, 58, 92, 124], radius=6, fill=accent)
    f_tag = load_font(FONT_BOLD, 52)
    draw.text((116, 62), step_tag, font=f_tag, fill=accent)

    # 中部高亮大标题
    f_title = load_font(FONT_BOLD, 78)
    draw.text((66, 184), title_text, font=f_title, fill=ICE_WHITE)

    # 底部操作说明发光框
    draw.rounded_rectangle([54, 310, w - 54, 514], radius=18, fill=(10, 22, 36), outline=(36, 78, 108), width=3)
    f_body = load_font(FONT_BOLD, 44)
    f_tip = load_font(FONT_REG, 38)
    draw.text((88, 348), "▸  " + line1, font=f_body, fill=ICE_WHITE)
    draw.text((88, 428), "▸  " + line2, font=f_tip, fill=MUTED_CYAN)

    img.save(os.path.join(OUT_DIR, filename))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # 太空舱 LED 显示屏（8 块）
    make_hub_led("sign_bridge.png", "01", "舰桥 · 驾驶舱", "全员就位 3 秒自动点火起飞", NEON_CYAN)
    make_hub_led("sign_store.png", "02", "物资存回", "手持物资按 E 快捷入库", NEON_CYAN)
    make_hub_led("sign_refill.png", "03", "生命补给 · 充氧", "按 E 一键回满生命与氧气瓶", NEON_GREEN)
    make_hub_led("sign_repair.png", "04", "舰体维修总闸", "按 E 消耗零件抢修船体", NEON_ORANGE)
    make_hub_led("sign_workshop.png", "05", "工坊与军械台", "制作补给 · 装备 · 玩具 · 换装", NEON_ORANGE)
    make_hub_led("sign_airlock.png", "出舱", "星球登陆气闸", "降落星球后拉闸出舱探索", NEON_CORAL, arrow="down")
    make_hub_led("sign_crashed_airlock.png", "登舱", "返回飞船主舱", "靠近按 E 进入归航号主舱", NEON_CYAN, arrow="down")
    make_hub_led("sign_training.png", "训练", "独立喷气训练舱", "右舷专用通道 · 按 E 进入练习", NEON_TEAL, arrow="right")
    make_hub_led("sign_ship_name.png", "归航", "归航号探索舰", "HOMECOMING EXPEDITION · DECK 01", NEON_CYAN)

    # 训练舱 LED 教学大屏（6 块）
    make_training_led("train_01_equip.png", "STEP 01 · 领装备", "桌边拿取氧气瓶", "走近装备台按 E 拿取氧气瓶", "按鼠标左键安装到宇航服背囊", NEON_CYAN)
    make_training_led("train_02_jump.png", "STEP 02 · 短跳", "短按空格跳低台", "轻按一下空格跳上前方低台", "普通跳跃不消耗喷气推进氧气", NEON_TEAL)
    make_training_led("train_03_boost.png", "STEP 03 · 喷气", "长按空格喷气登高", "按住空格持续点火向上攀升", "穿过空中发光导引环飞向高台", NEON_ORANGE)
    make_training_led("train_04_recharge.png", "STEP 04 · 回充", "落地松手自动充能", "稳稳落在高台松开空格键", "背囊会自动消耗氧气快速回充", NEON_GREEN)
    make_training_led("train_05_cross.png", "STEP 05 · 冲刺", "飞跃终点金色高台", "借喷气穿过高空光环抵达终点", "下方还放有弹跳垫与碰碰球可玩", NEON_ORANGE)
    make_training_led("train_06_exit.png", "RETURN · 返航", "返回归航号主舱", "走近右侧舱门按 E 回到主舱", "将从主舱右舷训练门走回大厅", NEON_CORAL)
    print("ALL 14 SCI-FI LED SCREEN TEXTURES GENERATED ->", OUT_DIR)


if __name__ == "__main__":
    main()
