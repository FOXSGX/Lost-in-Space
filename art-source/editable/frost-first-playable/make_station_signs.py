"""Reproducible original equipment pictograms for Frost station v0.3.

Run from any working directory with Pillow installed.  These are opaque surface
textures, never camera-facing text.  Every text box is checked against its panel.
"""
from pathlib import Path
import hashlib
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "game/previews/frost_first_playable/signs/station03"
NOTE = ROOT / "work/gameplay-iterations/20261025-frost-station-03/assets-note.md"
FONT = Path("C:/Windows/Fonts/msyh.ttc")
SIZE = (1280, 640)
BG, PANEL, INK = "#193646", "#214555", "#d8e5e5"
CYAN, ORANGE, DIM = "#a8e1e5", "#f4d1a1", "#7798a4"
CHECKS = []


def font(size):
    return ImageFont.truetype(str(FONT), size)


def text(draw, value, box, size=32, color=INK, center=True):
    """Fit intentionally short labels and reject clipping, including Chinese."""
    x0, y0, x1, y1 = box
    while size >= 18:
        face = font(size)
        bounds = draw.textbbox((0, 0), value, font=face)
        width, height = bounds[2] - bounds[0], bounds[3] - bounds[1]
        if width <= x1 - x0 and height <= y1 - y0:
            break
        size -= 1
    assert width <= x1 - x0 and height <= y1 - y0, (value, box)
    px = (x0 + x1 - width) / 2 if center else x0
    py = (y0 + y1 - height) / 2 - bounds[1]
    draw.text((px, py), value, font=face, fill=color)
    CHECKS.append((value, size, box))


def base(title, subtitle):
    im = Image.new("RGB", SIZE, BG)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((12, 12, 1267, 627), 28, outline="#dbb674", width=8)
    d.line((42, 126, 1238, 126), fill=DIM, width=3)
    text(d, title, (46, 28, 1234, 91), 51, CYAN)
    text(d, subtitle, (46, 91, 1234, 119), 23, INK)
    return im, d


def card(d, bounds, fill=PANEL):
    d.rounded_rectangle(bounds, 19, fill=fill, outline=DIM, width=3)


def arrow(d, a, b, color=ORANGE, width=9, head=17):
    d.line((a, b), fill=color, width=width)
    angle = math.atan2(b[1] - a[1], b[0] - a[0])
    p = (b[0] - head * math.cos(angle - .55), b[1] - head * math.sin(angle - .55))
    q = (b[0] - head * math.cos(angle + .55), b[1] - head * math.sin(angle + .55))
    d.polygon((b, p, q), fill=color)


def icon(d, name, cx, cy, s=1, color=CYAN):
    """Hand-authored simple silhouettes; shared 120 by 120 drawing coordinates."""
    def pt(x, y):
        return (cx + x * s, cy + y * s)
    def rect(x0, y0, x1, y1, fill=None, outline=color, w=6, r=0):
        fn = d.rounded_rectangle if r else d.rectangle
        args = {"fill": fill, "outline": outline, "width": max(1, round(w * s))}
        if r:
            args["radius"] = round(r * s)
        fn((pt(x0, y0), pt(x1, y1)), **args)
    def line(points, fill=color, w=6):
        d.line([pt(x, y) for x, y in points], fill=fill, width=max(1, round(w * s)), joint="curve")
    def ellipse(bounds, fill=None, outline=color, w=6):
        d.ellipse((pt(*bounds[:2]), pt(*bounds[2:])), fill=fill, outline=outline, width=max(1, round(w * s)))
    if name == "crate":
        rect(-45, -35, 45, 42, r=7)
        line([(-45, -12), (45, -12)])
        rect(-12, -44, 12, -28, fill=color)
        line([(-14, 10), (0, 23), (17, 0)], fill=ORANGE)
    elif name == "safe":
        rect(-46, -49, 46, 49, r=7)
        rect(-35, -38, 35, 38, w=3)
        ellipse((-13, -15, 13, 11), w=5)
        line([(0, 11), (0, 29)], fill=ORANGE)
        line([(-46, -27), (-33, -27)])
        line([(-46, 27), (-33, 27)])
    elif name == "key":
        ellipse((-42, -31, -2, 9), w=9)
        line([(-5, 1), (43, 43)], fill=ORANGE, w=10)
        line([(22, 25), (34, 11)], fill=ORANGE, w=9)
        line([(36, 37), (47, 24)], fill=ORANGE, w=9)
    elif name == "bed":
        rect(-47, -9, 47, 32, fill=color)
        rect(-40, -25, -10, -8, fill=INK, w=2, r=4)
        line([(-47, -38), (-47, 48)], w=9)
        line([(47, 20), (47, 48)], w=9)
    elif name == "flask":
        line([(-16, -48), (16, -48)])
        line([(-12, -47), (-12, -15), (-40, 35), (-36, 46), (36, 46), (40, 35), (12, -15), (12, -47)])
        d.polygon([pt(-27, 18), pt(27, 18), pt(36, 40), pt(-36, 40)], fill=ORANGE)
    elif name == "freezer":
        rect(-38, -52, 38, 52, r=7)
        line([(-38, -11), (38, -11)], w=3)
        line([(24, -38), (24, -25)], fill=ORANGE)
        line([(24, 9), (24, 27)], fill=ORANGE)
        for angle in (0, math.pi/3, 2*math.pi/3):
            line([(-math.cos(angle)*15-5, -math.sin(angle)*15+20), (math.cos(angle)*15-5, math.sin(angle)*15+20)], w=3)
    elif name == "slice":
        rect(-47, 22, 47, 39, fill=DIM, outline=DIM, w=2)
        rect(-27, -6, 18, 21, fill=ORANGE, outline=ORANGE, w=2)
        d.polygon([pt(14, -48), pt(40, -35), pt(-4, 9), pt(-15, -1)], fill=color)
        line([(-43, 47), (43, 47)], w=4)
    elif name == "microscope":
        line([(-15, -40), (14, -25), (28, -48)], w=13)
        d.arc((pt(-17, -25), pt(43, 43)), -75, 105, fill=color, width=max(1, round(9*s)))
        line([(-35, 19), (11, 19)], fill=ORANGE, w=7)
        line([(-11, 19), (-15, 45), (-43, 45), (38, 45)], w=9)
    elif name == "sealed":
        rect(-41, -32, 41, 47, r=4)
        rect(-46, -43, 46, -28, fill=color)
        rect(-10, -28, 10, 23, fill=ORANGE, outline=ORANGE, w=2)
        line([(-23, 31), (-3, 41), (26, 17)], fill=INK, w=5)
    elif name in ("hatch", "ice_hatch"):
        rect(-39, -53, 39, 53, r=8)
        rect(-28, -40, 28, 40, w=3)
        ellipse((8, -6, 24, 10), fill=ORANGE, outline=ORANGE)
        if name == "ice_hatch":
            d.polygon([pt(-46, 51), pt(-48, -9), pt(-24, -33), pt(-6, 4), pt(6, -17), pt(43, 14), pt(43, 51)], fill="#779eaf", outline=CYAN)
            line([(-23, -17), (-10, 8), (-16, 30)], fill=INK, w=3)
            line([(8, 5), (20, 21), (14, 40)], fill=INK, w=3)
        else:
            line([(-17, -23), (-17, 22), (-2, 29)], fill=ORANGE, w=7)
    elif name == "heater":
        rect(-53, -17, 5, 17, r=7)
        rect(4, -25, 17, 25, fill=ORANGE, outline=ORANGE, r=3)
        d.polygon([pt(-34, 17), pt(-11, 17), pt(-7, 45), pt(-27, 45)], fill=color)
        for y in (-22, 0, 22):
            line([(28, y), (36, y-5), (46, y+5), (57, y)], fill=ORANGE, w=4)
    elif name == "switch":
        rect(-43, -32, 43, 48, r=7)
        ellipse((-17, 6, 17, 40), fill=DIM, outline=CYAN, w=4)
        line([(0, 21), (22, -31)], fill=ORANGE, w=13)
        ellipse((9, -44, 35, -18), fill=ORANGE, outline=ORANGE, w=2)
        rect(-26, -17, -12, -3, fill=DIM, outline=DIM, w=1)
    elif name == "light":
        ellipse((-30, -44, 30, 16), fill=ORANGE, outline=ORANGE)
        rect(-16, 16, 16, 34, fill=CYAN, r=4)
        line([(-13, 43), (13, 43)], w=5)
        for x, y in ((-48,-43),(0,-63),(48,-43),(-51,8),(51,8)):
            line([(x*.83,y*.83), (x,y)], fill=ORANGE, w=4)
    elif name == "bolt":
        d.polygon([pt(4,-51),pt(-35,8),pt(-3,8),pt(-12,52),pt(37,-14),pt(6,-14)], fill=ORANGE)
    elif name == "sos":
        rect(-36, 7, 36, 45, r=5)
        line([(3, 7), (3, -33)], w=7)
        line([(3, -33), (18, -43)], fill=ORANGE, w=6)
        for radius in (25, 42):
            d.arc((pt(3-radius,-33-radius),pt(3+radius,-33+radius)),195,300,fill=ORANGE,width=max(1,round(4*s)))
        text(d,"SOS",(cx-30*s,cy+13*s,cx+30*s,cy+37*s),round(21*s),ORANGE)
    elif name == "storm":
        ellipse((-46,-38,7,9),fill=color)
        ellipse((-18,-55,31,6),fill=color)
        ellipse((8,-35,49,9),fill=color)
        rect(-40,-10,40,11,fill=color,outline=color,w=1)
        for x, y in ((-35,33),(0,45),(35,33)):
            line([(x-8,y),(x+8,y)],fill=ORANGE,w=4)
            line([(x,y-8),(x,y+8)],fill=ORANGE,w=4)
        line([(-43,61),(43,-50)],fill=ORANGE,w=7)
    elif name == "ship":
        d.polygon([pt(-18,20),pt(-40,39),pt(-37,5),pt(-17,-12),pt(0,-47),pt(17,-12),pt(37,5),pt(40,39),pt(18,20)],fill=color)
        ellipse((-8,-14,8,2),fill=BG,outline=BG,w=2)
        line([(-9,29),(-9,49)],fill=ORANGE,w=5)
        line([(9,29),(9,49)],fill=ORANGE,w=5)
    elif name == "energy":
        rect(-33,-47,33,47,r=10)
        rect(-20,-59,20,-46,fill=color)
        d.polygon([pt(5,-32),pt(-18,5),pt(2,5),pt(-5,32),pt(20,-9),pt(2,-9)],fill=ORANGE)
    elif name == "core":
        rect(-48,-46,48,46,r=10)
        rect(-34,-32,0,32,w=3)
        rect(11,-26,32,26,fill=ORANGE,outline=ORANGE,w=2,r=4)
        for y in (-32,-12,8,28):
            line([(-60,y),(-48,y)],w=4)
        arrow(d,pt(52,0),pt(8,0),width=max(1,round(5*s)),head=10*s)


def stage(d, x, number, label, hint, symbol, width=260):
    card(d,(x,154,x+width,526))
    text(d,number,(x+16,170,x+62,215),33,ORANGE)
    icon(d,symbol,x+width/2,302,1.25)
    text(d,label,(x+12,405,x+width-12,457),35,CYAN)
    text(d,hint,(x+12,463,x+width-12,510),24,INK)


def save(im, name):
    OUT.mkdir(parents=True,exist_ok=True)
    im.save(OUT/f"{name}.png", optimize=True)


def station_plan():
    im,d=base("霜烬科考站 · 分区导览","沿中央运输线前行，主科考楼面向遗迹")
    # Relative positions preserve the outdoor layout: logistics lower left,
    # personnel middle right, main laboratory upper left, ruins straight ahead.
    d.rounded_rectangle((610,205,654,518),12,fill="#487484")
    arrow(d,(632,498),(632,179),width=11)
    text(d,"遗迹入口",(500,143,766,184),32,ORANGE)
    icon(d,"ship",632,528,.36)
    text(d,"停机坪",(528,552,738,579),22)
    card(d,(49,163,534,338))
    icon(d,"flask",109,233,.52)
    icon(d,"safe",181,233,.52)
    text(d,"主科考楼",(230,179,512,219),35,CYAN)
    text(d,"样本处理 / 能源保管",(221,228,514,265),27)
    text(d,"能源锁柜 · 需钥匙",(224,278,511,316),27,ORANGE)
    arrow(d,(610,265),(550,265),width=7)
    card(d,(753,306,1226,464))
    icon(d,"bed",821,374,.63)
    text(d,"人员休整",(882,325,1208,371),35,CYAN)
    text(d,"床铺 / 餐桌 / 撤离记录",(865,391,1208,433),25)
    arrow(d,(658,389),(741,389),width=7)
    card(d,(49,378,534,500))
    icon(d,"crate",116,438,.58)
    text(d,"仓储与装卸",(195,393,509,437),34,CYAN)
    text(d,"工具 / 电池 / 运输橇",(183,446,513,483),25)
    arrow(d,(610,442),(551,442),width=7)
    icon(d,"key",82,598,.25)
    text(d,"首席科学家携钥匙进入遗迹，尚未归队",(110,581,1215,615),27,ORANGE,False)
    save(im,"station_plan")


def sample_process():
    im,d=base("样本处理 · 标准流程","观察窗与封存柜供科考人员共同使用")
    specs=[("冷藏","保持样本低温","freezer"),("切片","取少量薄片","slice"),("观察","记录结构变化","microscope"),("封存","封盖并归档","sealed")]
    for i,(label,hint,symbol) in enumerate(specs):
        x=46+i*307
        stage(d,x,f"0{i+1}",label,hint,symbol,266)
        if i<3:
            arrow(d,(x+274,339),(x+298,339),width=6,head=12)
    text(d,"保留原始样本 · 使用后归位",(65,548,1215,600),32,ORANGE)
    save(im,"sample_process")


def thaw_hatch():
    im,d=base("检修附间 · 冰封入口","热风机可随身携带，瞄准看得到的冰雪持续吹风")
    for i,(label,hint,symbol) in enumerate([("冰封检修门","先处理表面冰层","ice_hatch"),("持续吹风","热风融开入口","heater"),("靠近开门","按 E 操作门把手","hatch")]):
        x=56+i*410
        stage(d,x,f"0{i+1}",label,hint,symbol,348)
        if i<2:
            arrow(d,(x+361,339),(x+397,339),width=7,head=14)
    text(d,"电池用尽：补电 / 换电池，再继续操作",(58,549,1220,602),31,ORANGE)
    save(im,"thaw_hatch")


def relay():
    im,d=base("实验供电 · 旁路手柄","旁路供电连接实验设备与灯具，保险柜仍使用钥匙")
    card(d,(56,157,432,527))
    icon(d,"switch",244,290,1.4)
    text(d,"靠近扳动手柄",(75,404,412,451),35,CYAN)
    d.rounded_rectangle((180,458,308,509),10,fill=ORANGE)
    text(d,"E 操作",(185,459,303,506),29,BG)
    arrow(d,(460,328),(557,328),width=11,head=22)
    card(d,(588,157,1224,527))
    icon(d,"light",735,280,1.2)
    icon(d,"microscope",1066,280,1.2)
    d.line((779,344,1017,344),fill=ORANGE,width=8)
    icon(d,"bolt",904,344,.56)
    text(d,"指示灯亮",(618,406,854,457),35,CYAN)
    text(d,"实验设备供电",(915,406,1202,457),33,CYAN)
    text(d,"E 扳动 → 灯亮 → 实验电路恢复",(64,550,1216,601),32,ORANGE)
    save(im,"relay")


def evac_timeline():
    im,d=base("撤离记录 · 事件顺序","接收记录仅能确认先后，不能确认袭击者身份")
    for i,(label,hint,symbol) in enumerate([("深入小队遇袭","发出求救后失联","sos"),("暴雪迫使停航","航线随后被封锁","storm"),("留守人员撤离","搜救未能完成","ship")]):
        x=56+i*410
        stage(d,x,f"0{i+1}",label,hint,symbol,348)
        if i<2:
            arrow(d,(x+361,339),(x+397,339),width=7,head=14)
    text(d,"先遇袭，后暴雪 · 袭击者身份未知",(58,549,1220,602),33,ORANGE)
    save(im,"evac_timeline")


def energy_case():
    im,d=base("高密度能源 · 航行核心用","普通燃料尚有储备，受损的是起飞高能核心")
    for i,(label,hint,symbol) in enumerate([("钥匙开柜","首席科学家保管钥匙","safe"),("取出能源","本柜保管一份能源","energy"),("回船更换核心","沿来时路线返回","core")]):
        x=56+i*410
        stage(d,x,f"0{i+1}",label,hint,symbol,348)
        if i<2:
            arrow(d,(x+361,339),(x+397,339),width=7,head=14)
    icon(d,"key",101,567,.35)
    text(d,"取能后带回飞船 · 原路返回停机坪",(151,549,1209,602),32,ORANGE)
    save(im,"energy_case")


def audit():
    lines=["# 0.3 科考站实体图牌资源", "", "本文件仅记录本次原创图牌的来源和静态资源检查；关卡接入及运行验证由主任务记录。", "", "- 原稿：`art-source/editable/frost-first-playable/make_station_signs.py`。", "- 生成方式：Python + Pillow 几何绘图，无外部图片、照片、生成式位图或下载素材。", "- 字体：本机系统微软雅黑 `C:/Windows/Fonts/msyh.ttc`，仅输出光栅图像；未复制字体文件。", "- 风格：沿用现有深蓝、青色、浅橙色设备图牌；全部为不透明表面纹理。", "- 尺寸：每张 1280 × 640，RGB，2:1。", "- 使用方式：贴合墙面、设备或门板。不得用作悬浮/随镜头转向的 3D 文字。", "", "| 文件 | 内容 | SHA-256 |", "| --- | --- | --- |"]
    descriptions={"station_plan":"主楼含样本处理/能源保管，人员休整、仓储、运输线、遗迹方向和钥匙去向", "sample_process":"冷藏→切片→观察→封存", "thaw_hatch":"冰封检修门→持续热风→E 开门", "relay":"E 扳动旁路手柄→灯亮→实验设备供电；保险柜独立使用钥匙", "evac_timeline":"小队先遇袭求救→暴雪后封航→留守撤离；袭击者身份未知", "energy_case":"钥匙开柜→取高密度能源→原路回船更换核心"}
    for name in descriptions:
        path=OUT/f"{name}.png"
        with Image.open(path) as image:
            assert image.size==SIZE and image.mode=="RGB"
            assert len(image.getcolors(maxcolors=1000000))>40
        lines.append(f"| `{name}.png` | {descriptions[name]} | `{hashlib.sha256(path.read_bytes()).hexdigest()}` |")
    lines += ["", f"静态检查：6 张 PNG 均重新读取成功；尺寸、RGB 模式和非空颜色检查通过。共 {len(CHECKS)} 个文本框均经 Pillow textbbox 检查，无越出指定布局框。", "", "剧情约束：图牌不指定凶手、动机或袭击方法；旁路供电不作为保险柜前置条件。全基地示意表达现有相对分区，不是测绘比例地图。", ""]
    NOTE.parent.mkdir(parents=True,exist_ok=True)
    NOTE.write_text("\n".join(lines),encoding="utf-8")
    print(f"Created 6 surface signs; {len(CHECKS)} text boxes within bounds.")
    for path in sorted(OUT.glob("*.png")):
        print(f"{path.name}: {path.stat().st_size} bytes, {SIZE[0]}x{SIZE[1]} RGB")


if __name__=="__main__":
    assert FONT.exists(), "Install/select Microsoft YaHei before reproducing labels."
    station_plan()
    sample_process()
    thaw_hatch()
    relay()
    evac_timeline()
    energy_case()
    audit()
