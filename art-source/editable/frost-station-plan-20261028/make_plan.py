"""Editable, equal-scale site plan. Design artifact only; no game data is edited."""
from pathlib import Path
from html import escape
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
W, H = 2340, 2020
BG='#e9eff0'; PAPER='#f6f8f5'; GRID='#e0e8e7'; INK='#173e49'; MUTED='#66818a'
PRIMARY='#245c69'; WING='#bfd7d4'; AUX='#d9e2df'; GOLD='#c88936'
ROUTE='#287d91'; OPT='#8c729e'; PIPE='#bd9258'; BORDER='#a7bfbd'; SNOW='#dce8eb'
im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',f'<rect width="{W}" height="{H}" fill="{BG}"/>']
fonts={}
def font(size,bold=False):
    key=(size,bold)
    if key not in fonts:fonts[key]=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc' if bold else 'C:/Windows/Fonts/msyh.ttc',size)
    return fonts[key]
def rect(x,y,w,h,fill,stroke=None,sw=1,r=0):
    if r:d.rounded_rectangle((x,y,x+w,y+h),r,fill,stroke,sw)
    else:d.rectangle((x,y,x+w,y+h),fill,stroke,sw)
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{sw}"/>')
def line(points,col,width=2,dash=False):
    points=[tuple(map(float,p)) for p in points]
    if dash:
        for a,b in zip(points,points[1:]):
            length=math.dist(a,b)
            for t in range(0,int(length),20):
                u=t/max(1,length);v=min(t+11,length)/max(1,length)
                d.line((a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u,a[0]+(b[0]-a[0])*v,a[1]+(b[1]-a[1])*v),fill=col,width=width)
    else:d.line(points,fill=col,width=width,joint='curve')
    svg.append('<polyline points="'+' '.join(f'{x},{y}' for x,y in points)+f'" fill="none" stroke="{col}" stroke-width="{width}" stroke-linejoin="round"'+(' stroke-dasharray="11 9"' if dash else '')+'/>')
def poly(points,fill,stroke=None,sw=2):
    d.polygon(points,fill)
    if stroke:d.line(points+[points[0]],stroke,sw,joint='curve')
    svg.append('<polygon points="'+' '.join(f'{x},{y}' for x,y in points)+f'" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{sw}"/>')
def circle(x,y,r,fill,stroke=None,sw=2):
    d.ellipse((x-r,y-r,x+r,y+r),fill,stroke,sw)
    svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{sw}"/>')
def text(x,y,s,size=26,col=INK,bold=False,anchor='left'):
    f=font(size,bold);tw=d.textlength(s,font=f)
    xx=x-tw/2 if anchor=='middle' else x-tw if anchor=='right' else x
    d.text((xx,y),s,font=f,fill=col)
    svg.append(f'<text x="{x}" y="{y+size*.98}" font-family="Microsoft YaHei, Noto Sans CJK SC, sans-serif" font-size="{size}" font-weight="{700 if bold else 400}" text-anchor="'+('middle' if anchor=='middle' else 'end' if anchor=='right' else 'start')+f'" fill="{col}">{escape(s)}</text>')
def arrow(a,b,col=ROUTE,width=4,head=16):
    line([a,b],col,width)
    ang=math.atan2(b[1]-a[1],b[0]-a[0])
    for dd in [-.55,.55]:line([b,(b[0]-head*math.cos(ang+dd),b[1]-head*math.sin(ang+dd))],col,width)
def badge(x,y,s,fill=PRIMARY,r=24):
    circle(x,y,r,fill);text(x,y-17,s,25,'#ffffff',True,'middle')

text(64,46,'霜烬星 · 科考站',61,INK,True)
text(66,133,'建筑布局规划  /  一主 · 两辅 · 三配套',30,MUTED)
rect(1820,62,452,63,PRIMARY,r=10)
text(2046,73,'规划草案 01 · 未接入游戏',26,'#ffffff',True,'middle')
line([(65,205),(2275,205)],BORDER,2)
rect(50,245,1655,1590,PAPER,BORDER,2,18)
rect(1740,245,550,1590,PAPER,BORDER,2,18)
text(81,268,'总平面 / 顶视',25,INK,True)
text(1668,270,'北 ↑ · 遗迹方向',24,MUTED,False,'right')

S=8.25; OX=125; OY=340
def p(x,y):return (OX+x*S,OY+y*S)
def wl(points,col,width=2,dash=False):line([p(x,y) for x,y in points],col,width,dash)
def wr(x,y,w,h,fill,stroke=None,sw=2,r=0):
    xx,yy=p(x,y);rect(xx,yy,w*S,h*S,fill,stroke,sw,r)
def wt(x,y,s,size=25,col=INK,bold=False,anchor='middle'):text(*p(x,y),s,size,col,bold,anchor)
def wc(x,y,r,fill,stroke=None,sw=2):circle(*p(x,y),r*S,fill,stroke,sw)
def door(x,y,axis='h',width=6,col=ROUTE,wall=PAPER):
    ends=[(x-width/2,y),(x+width/2,y)] if axis=='h' else [(x,y-width/2),(x,y+width/2)]
    wl(ends,wall,10);wl(ends,col,4)
    # End jambs clearly identify a real doorway.
    for a,b in ends:
        wl([(a,b-.7),(a,b+.7)] if axis=='h' else [(a-.7,b),(a+.7,b)],col,3)
def building(x,y,w,h,fill,sw=4):
    wr(x+.7,y+.9,w,h,'#cad5d2',None)
    wr(x,y,w,h,fill,PRIMARY if fill==PRIMARY else '#638884',sw)
def route(points,width=8):
    wl(points,'#f6f8f5',width+5);wl(points,ROUTE,width)
def optional(points):wl(points,OPT,4,True)
def room(x,y,w,h,label,light=True):
    wr(x,y,w,h,None,'#7ba2a8' if light else '#91adaa',2)
    wt(x+w/2,y+h/2-1.4,label,22,'#e5f0ed' if light else '#315a60')

# Planning grid: local coordinates, metres, not existing runtime coordinates.
for x in range(0,181,20):
    wl([(x,0),(x,176)],GRID,1);wt(x,-2.6,str(x),17,MUTED)
for y in range(0,177,20):
    wl([(0,y),(180,y)],GRID,1);text(OX-25,OY+y*S-10,str(y),17,MUTED,False,'right')

# Snow and rock edges frame a compact settlement without enclosing a maze.
poly([p(x,y) for x,y in [(0,19),(7,13),(18,18),(23,29),(15,43),(9,50),(0,47)]],SNOW)
poly([p(x,y) for x,y in [(166,10),(180,2),(180,59),(173,67),(168,49)]],SNOW)
poly([p(x,y) for x,y in [(0,112),(12,116),(15,140),(10,151),(0,158)]],SNOW)
poly([p(x,y) for x,y in [(169,116),(180,108),(180,176),(165,168),(169,149)]],SNOW)
for x,y,w,h in [(7,32,5,3),(173,41,4,5),(7,128,4,3),(173,151,4,4)]:wr(x,y,w,h,'#9cb3bb',None)

# Outdoor pedestrian / cargo surfaces.
wr(53,65,70,53,'#e0e9e3','#bfd0c8',2)
wr(72,114,36,40,'#e4e8e2',None)
wr(29,113,123,9,'#e1e6df',None)
wr(71,147,40,29,'#dae2dc','#aebfb8',2)
# A clear 12 m departure corridor passes east of the main building.
wr(121,6,11,82,'#e0e7e1',None)
wr(110,80,22,10,'#e0e7e1',None)
wr(132,56,32,8,'#e0e7e1',None)

# Covered connections are short optional links, with a distinct floor pattern.
for pts in [[(57,60),(57,71),(49,71)],[(115,60),(115,73),(128,73)]]:
    wl(pts,'#b4c8c4',56);wl(pts,'#f3f7f2',46)
    for a,b in zip(pts,pts[1:]):
        for i in range(1,max(2,int(math.dist(a,b)/2))):
            t=i/max(2,int(math.dist(a,b)/2));x=a[0]+(b[0]-a[0])*t;y=a[1]+(b[1]-a[1])*t
            if a[0]==b[0]:wl([(x-2.8,y),(x+2.8,y)],'#bbccc5',2)
            else:wl([(x,y-2.8),(x,y+2.8)],'#bbccc5',2)

# Service pipes run outside the optional loops; they are infrastructure, not routes.
pipepath=[(146,26),(146,19),(123.5,19),(123.5,62),(166,62),(166,118),(153,118),(153,125)]
wl(pipepath,PIPE,7)
wl([(123.5,62),(123.5,114),(47,114),(47,124)],PIPE,5)
for x,y in [(123.5,65),(123.5,83),(123.5,103),(166,80),(166,103),(80,114)]:wr(x-.6,y-.6,1.2,1.2,'#8f785b',None)

# 01 main building, largest footprint, frontal entrance to courtyard.
building(50,26,70,34,PRIMARY,5)
room(50,26,21,14,'档案 / 指挥')
wr(71,26,22,14,None,'#7ba2a8',2)
wt(82,36,'能源保管室',21,'#e5f0ed')
room(93,26,27,14,'通讯与研究')
room(50,45,23,15,'基础实验室')
room(98,45,22,15,'办公 / 会议')
wl([(50,40),(120,40)],'#7ba2a8',2);wl([(50,45),(73,45)],'#7ba2a8',2)
wt(85,48,'接待大厅',25,'#ffffff',True)
wt(85,54,'主要入口',20,'#b9d6d6')
wr(75.5,30,9,5,'#b98b45','#f3d59c',2)
wt(80,30.5,'保险柜',18,'#ffffff',True)
for x in [58,65,78,85,101,109]:wl([(x,26),(x+4,26)],'#bad6d6',6)
door(85,60,'h',10,'#f3c678',PRIMARY)
door(57,60,'h',5,'#b8d6cf',PRIMARY)
door(115,60,'h',5,'#b8d6cf',PRIMARY)
wr(75,60,20,3,'#cddbd4','#8ba8a2',2)
for y in [60.8,61.8]:wl([(76,y),(94,y)],'#8da9a2',1)
# Tower is an appendage of the main building rather than a seventh building.
wr(54,17,9,9,'#a2bfbd',PRIMARY,3)
wc(58.5,21.5,3.2,None,PRIMARY,3);wc(58.5,21.5,1.2,PRIMARY)
wl([(58.5,18.3),(58.5,24.7)],PRIMARY,2);wl([(55.3,21.5),(61.7,21.5)],PRIMARY,2)
wt(49,18.6,'附属通讯塔',21,MUTED,False,'right')
badge(*p(50,26),'01',GOLD)
wt(89,15,'主科研楼',37,PRIMARY,True)
wt(89,21,'视觉中心 · 局部二层',20,MUTED)

# 02 specimen hall, wide observing bays and a recognisable large specimen.
building(15,67,34,42,WING)
wr(17,69,15,24,'#b0c9c8','#83a5a4',2)
wr(33,69,14,24,'#aec4cf','#83a5a4',2)
wl([(17,95),(47,95)],'#83a5a4',2)
wt(24.5,72,'骨骼标本',22,INK,True)
wt(40,72,'隔离观察',22,INK,True)
wl([(20,84),(29,84)],'#eee7cb',10)
for x in [21,23,25,27]:wl([(x,80),(x,88)],'#eee7cb',5)
for x,y in [(37,82),(43,87)]:wc(x,y,2.1,'#b78bb0','#856a8a',2)
wt(32,98,'样本交接 / 冷藏',21,INK)
door(49,88,'v',8)
door(49,71,'v',5)
optional([(60,88),(49,88),(40,88)])
badge(*p(15,67),'02')
wt(32,59.4,'标本保存与隔离馆',30,PRIMARY,True)
wt(32,64,'第二重点 · 挑高单层',19,MUTED)

# 03 living / medical wing, articulated smaller rooms.
building(128,70,34,38,WING)
for x in [128,145]:
    for y in [70,80]:
        if y==70:
            wr(x,y,17,10,None,'#91adaa',2)
            wt(x+8.5,76.6,'宿舍',20,'#315a60')
        else:room(x,y,17,10,'医务室' if x==128 else '更衣室',False)
wr(128,94,34,14,'#c6d9cf','#91adaa',2)
wt(145,98,'食堂 / 公共活动',22,INK)
for x in [130,133,136,147,150,153]:wr(x,71.3,2,4,'#98b6b2',None)
for y in [74,85,99]:wl([(162,y),(162,y+5)],'#678e93',5)
door(128,88,'v',8);door(128,73,'v',5)
optional([(111,88),(128,88),(139,88)])
badge(*p(162,70),'03')
wt(145,109.4,'生活医疗楼',30,PRIMARY,True)
wt(145,114,'生活痕迹 / 撤离线索',19,MUTED)

# 04 power and life support, background infrastructure.
building(132,26,32,26,AUX,3)
wl([(151,26),(151,52)],'#a8bcb4',2)
wt(141.5,31,'动力机组',21,MUTED,True)
wt(141.5,43,'维护间',20,MUTED)
for y in [32,42]:wc(157,y,3.7,'#b6c9c4','#839d99',2)
door(146,52,'h',6)
optional([(126,59),(146,59),(146,52)])
badge(*p(132,26),'04','#718e8c')
wt(148,18.2,'动力与生命保障站',27,INK,True)
wt(157,47,'制氧 / 水',16,MUTED)

# 05 garage; broad vehicle bays face the logistics lane.
building(112,125,48,25,AUX,3)
wl([(144,125),(144,150)],'#a5b9b2',2)
wt(151.5,130,'维修台',21,MUTED)
wt(151.5,140,'零件',20,MUTED)
for x in [116,130]:
    wr(x,131,9,12,'#aebfba','#78918b',2,r=7)
    wr(x+1.2,132,6.6,3,'#69888b',None)
    for dx in [-.6,8.6]:wr(x+dx,133,1.3,7,'#69827e',None)
    door(x+4.5,125,'h',10)
badge(*p(112,125),'05','#718e8c')
wt(136,152,'机修车库',29,INK,True)
wt(136,157,'运输橇 / 雪地车辆',19,MUTED)

# 06 warehouse; loading dock and sorted finite stocks.
building(23,124,43,25,AUX,3)
wl([(53,124),(53,149)],'#a5b9b2',2)
for y in [129,136,143]:
    for x in [27,37]:wr(x,y,7,3,'#a0b4a8','#7f9989',1)
wt(59.5,131,'耗材',21,MUTED)
wt(59.5,140,'工具',21,MUTED)
door(45,124,'h',12)
wr(27,120,32,4,'#d0d9ca','#9aae9e',2)
for x,y in [(28,118),(34,118),(59,121),(63,119)]:wr(x,y,3,2,'#b6bca7','#939d86',1)
badge(*p(23,124),'06','#718e8c')
wt(44.5,151,'物资仓库',29,INK,True)
wt(44.5,156,'电池 / 氧气 / 医疗耗材',19,MUTED)

# Courtyard: usable assembly space, snow banks, low equipment, clear view to lobby.
for x,y in [(57,101),(113,101)]:wr(x,y,6,3,'#c5d6d5',None)
for x,y in [(55,77),(117,77),(58,109),(116,109)]:
    wc(x,y,.7,'#4b777e');wc(x,y,1.3,None,'#a1c0bf',1)
wt(87,76,'中央作业院',35,PRIMARY,True)
wt(87,82,'集结 · 分流 · 回程定位',22,MUTED)
# Main route avoids the courtyard label and splits to the eastern departure corridor.
route([(86,160),(86,108),(86,91),(86,87)])
route([(86,72),(86,64)])
arrow(p(86,68),p(86,64),ROUTE,5)
arrow(p(86,128),p(86,116),ROUTE,5)
route([(86,64),(86,68),(104,68),(104,85),(126,85),(126,6)],6)
for a,b in [((104,77),(104,83)),((126,77),(126,66)),((126,18),(126,7))]:arrow(p(*a),p(*b),ROUTE,4)
# Two tiny destination circles indicate traversable door-side approach.
wc(86,64,1.3,GOLD)
optional([(86,114),(45,114),(45,120)])
optional([(97,116),(120.5,116),(120.5,125)])
wt(87,96,'开放集结空地',22,MUTED)
wt(87,101,'外侧可自由绕行',19,MUTED)
wt(93.5,135,'入站主轴',20,ROUTE,True,'left')
wt(113,93,'出站',19,ROUTE)
wt(113,97,'绕行',19,ROUTE)

# Ship and apron, separated from the six station buildings.
wr(72,153,36,23,'#d6e0db','#8ba69d',2)
for x in [74,103]:
    wl([(x,155),(x,158)],'#fafbf5',4);wl([(x,171),(x,174)],'#fafbf5',4)
poly([p(x,y) for x,y in [(86,156),(91,162),(91,171),(88,174),(84,174),(81,171),(81,162)]],'#76959a',PRIMARY,2)
wr(83.5,163,5,5,'#e4edef',None)
wt(117,167,'飞船 / 停机坪',28,PRIMARY,True,'left')
wl([(108,167),(114,167)],'#8ea9a4',2)
wt(87,178,'入口与返航方向',24,ROUTE,True)
arrow(p(86,175),p(86,179),ROUTE,4)

# Departure target lies outside this site plan; no invented distance to the caves.
arrow(p(126,6),p(126,0),ROUTE,5)
rect(*p(95,-7),62*S,43,PAPER)
wt(126,-6.5,'通往巨型骨口与遗迹',27,ROUTE,True)

# Sidebar: program, priorities and route explanation.
text(1770,277,'建筑重点',32,INK,True)
text(1770,328,'入口正对主楼，两翼围合作业院。',23,MUTED)
def card(y,n,title,role,detail,col):
    badge(1797,y+23,n,col,22)
    text(1834,y-2,title,28,INK,True)
    text(1772,y+45,role,23,col,True)
    text(1772,y+80,detail,22,MUTED)
    line([(1772,y+122),(2256,y+122)],'#d4dfd9',1)
card(392,'01','主科研楼','主线核心 · 最大体量','接待、档案、保险柜、通讯指挥',PRIMARY)
card(548,'02','标本保存与隔离馆','第二重点 · 生态探索','骨骼标本、冷藏、活体观察',PRIMARY)
card(704,'03','生活医疗楼','辅助探索 · 人员故事','宿舍、食堂、医务与撤离痕迹',PRIMARY)
text(1772,866,'04—06  后勤配套',27,'#617f7e',True)
text(1772,913,'动力站靠侧后方；仓库与车库',23,MUTED)
text(1772,950,'靠近停机坪，组成装卸入口。',23,MUTED)
text(1772,987,'配套楼内部可精简，不增加',23,MUTED)
text(1772,1024,'逐栋完成才能通关的门槛。',23,MUTED)
line([(1772,1081),(2256,1081)],BORDER,2)
text(1772,1104,'主线路线',29,INK,True)
for i,s in enumerate(['停机坪 → 作业院 → 主楼调查','从主楼东侧绕行 → 巨型骨口','遗迹取钥匙 → 返回主楼开柜','回到飞船 → 安装能源并返航']):text(1772,1159+i*42,s,23,ROUTE)
line([(1772,1355),(2256,1355)],BORDER,2)
text(1772,1378,'图例',29,INK,True)
line([(1780,1446),(1841,1446)],ROUTE,6);text(1860,1428,'主线往返路线',23,INK)
line([(1780,1494),(1841,1494)],OPT,4,True);text(1860,1476,'可选探索连接',23,INK)
line([(1780,1542),(1841,1542)],PIPE,6);text(1860,1524,'架空管线（下方通行）',23,INK)
line([(1780,1590),(1841,1590)],'#b4c8c4',18);line([(1780,1590),(1841,1590)],PAPER,10);text(1860,1572,'有顶短连廊',23,INK)
rect(1780,1627,61,16,PRIMARY);text(1860,1612,'建筑实体 / 室内分区',23,INK)
text(1772,1688,'尺度参考',24,INK,True)
line([(1774,1743),(1939,1743)],INK,4)
for x in [1774,1856.5,1939]:line([(x,1735),(x,1751)],INK,3)
text(1774,1757,'0',19,MUTED);text(1939,1757,'20m',19,MUTED,False,'right')
text(1990,1728,'主图等比例',21,MUTED)
text(1990,1761,'建筑高度另行设计',19,MUTED)

line([(65,1875),(2275,1875)],BORDER,2)
text(65,1900,'布局说明',25,INK,True)
text(205,1901,'已确认：六类建筑、主次层级与围院方向。图中尺寸、房间分隔和具体路线为本轮规划草案。',24,MUTED)
text(65,1947,'站区规划范围约 180 × 176m；遗迹在图外。室内门洞与垂直交通简化，需灰盒步行验证。',23,MUTED)
text(2275,1949,'2026.10.28 / PLAN 01',20,MUTED,False,'right')
svg.append('</svg>')
(OUT/'霜烬星-科考站-围院规划01.svg').write_text('\n'.join(svg),encoding='utf-8')
im.save(OUT/'霜烬星-科考站-围院规划01.png')
print('Created PNG and SVG:',W,H)
