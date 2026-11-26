"""Editable, equal-scale site plan. Design artifact only; no game data is edited."""
from pathlib import Path
from html import escape
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
W, H = 2400, 2280
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

ICE='#91c2d7'
text(64,45,'霜烬星 · 六栋建筑功能方案',59,INK,True)
text(66,133,'依据七轮采访整理 / 已确认用途 + 建议房间落位 / 主楼一、二层分开表示',28,MUTED)
rect(1910,62,420,60,PRIMARY,r=10)
text(2120,72,'功能草案 03 · 未接入游戏',25,'#ffffff',True,'middle')
line([(65,207),(2335,207)],BORDER,2)
def panel(x,y,w,h,n,title,subtitle):
    rect(x,y,w,h,PAPER,BORDER,2,16)
    badge(x+40,y+46,n,PRIMARY,23)
    text(x+79,y+22,title,33,INK,True)
    text(x+30,y+83,subtitle,23,MUTED)
def room(x,y,w,h,label,sub=None,fill=WING):
    rect(x,y,w,h,fill,'#7b9f9b',2)
    text(x+w/2,y+h/2-(31 if sub else 17),label,25,INK,True,'middle')
    if sub:text(x+w/2,y+h/2+8,sub,20,MUTED,False,'middle')
def steps(x,y,w,h):
    rect(x,y,w,h,'#cbdcd4','#789b92',2)
    for i in range(1,10):line([(x+5,y+h*i/10),(x+w-5,y+h*i/10)],'#8caaa0',2)
    arrow((x+w*.73,y+h*.85),(x+w*.73,y+h*.15),ROUTE,4)

panel(50,245,1460,1095,'01','主科研楼','连续大厅与综合实验室 · 明显侧梯 · 二楼首席办公室保管能源')
text(105,380,'一层',30,PRIMARY,True)
text(835,380,'局部二层',30,PRIMARY,True)
rect(100,444,650,705,'#e4eeea',PRIMARY,4)
rect(830,444,630,705,'#dce9e3',PRIMARY,4)

# First-floor spaces: central hall opens directly into the large eastern lab.
room(112,456,170,206,'档案室','图表 / 照片')
room(112,684,170,156,'设备间','器材 / 备件')
steps(112,862,150,245)
text(187,975,'侧梯',24,INK,True,'middle')
text(187,1014,'普通步行上楼',17,INK,False,'middle')
rect(307,560,425,523,'#c9ded8',None)
text(594,716,'综合实验室',31,PRIMARY,True,'middle')
text(594,761,'随处尝试，不设试用区',21,MUTED,False,'middle')
for x,y,w,h in [(489,499,193,48),(539,950,153,47),(599,862,88,52)]:rect(x,y,w,h,'#a6c3b9','#71968e',2)
rect(520,505,70,30,'#c7a86f',GOLD,2,6)
text(521,550,'吸推器 · 可拿走',21,GOLD,True)
for x,y in [(677,620),(695,661),(461,991),(496,1030)]:rect(x,y,27,25,'#b5bea3','#98a48c',1)
circle(653,890,12,'#d4bc9e','#9d927e',2)
text(383,840,'中央大厅',31,PRIMARY,True,'middle')
text(383,890,'宽开口连续工作区',21,MUTED,False,'middle')
# Broad opening is depicted without a boundary line or door between these areas.
line([(295,680),(440,680)],'#7b9f9b',2)
line([(296,680),(296,787)],'#7b9f9b',2)
arrow((388,1081),(388,980),ROUTE,5)
arrow((348,955),(278,955),ROUTE,4)
line([(336,1149),(437,1149)],PAPER,10)
line([(336,1149),(437,1149)],GOLD,4)
text(389,1171,'主入口 / 面向作业院',23,PRIMARY,True,'middle')
text(104,1250,'拿起吸推器 → 对小物件和队友自由尝试 → 可携带进入遗迹',23,MUTED)

# Partial upper floor: a void makes the lower hall visible from the ring gallery.
rect(985,704,308,319,PAPER,'#8ba9a0',3)
line([(980,699),(1298,699),(1298,1028),(980,1028),(980,699)],'#71958c',2,True)
text(1138,823,'大厅挑空',31,PRIMARY,True,'middle')
text(1138,872,'能看到楼下队友',22,MUTED,False,'middle')
rect(849,457,360,181,WING,'#7b9f9b',2)
text(1029,550,'首席办公室',25,INK,True,'middle')
text(1029,595,'保险柜 + 钥匙去向线索',20,MUTED,False,'middle')
rect(870,477,105,61,'#c59853',GOLD,2)
text(922,490,'保险柜',22,'#ffffff',True,'middle')
room(1232,457,208,181,'观察廊','北望骨口')
line([(1242,444),(1430,444)],'#c0a16b',8)
arrow((1335,425),(1335,390),ROUTE,4)
text(1335,353,'巨型骨口方向',22,ROUTE,True,'middle')
steps(849,862,109,245)
text(904,1008,'楼梯口',20,INK,True,'middle')
text(1380,841,'环廊',26,PRIMARY,True,'middle')
arrow((918,825),(918,681),ROUTE,4)
arrow((932,668),(1042,668),ROUTE,4)
text(1135,1084,'局部办公位 / 环廊',22,MUTED,False,'middle')
text(840,1250,'首次找线索；取钥匙后沿熟悉侧梯回访开柜。',23,MUTED)

panel(1540,245,810,535,'02','标本保存与隔离馆','观看未拼装完的巨大骨架；少量生物介绍。')
rect(1580,387,730,270,'#e5ece7',PRIMARY,3)
room(1595,405,133,91,'入口缓冲',None,'#d5e3da')
room(2180,405,115,172,'保存区',None,'#d5e3da')
line([(1780,516),(2123,516)],'#b3a78c',20)
for x in [1805,1845,1885,1925,1965,2005,2045,2085]:
    line([(x,465),(x-12,515),(x,566)],'#c2b59c',13)
circle(2135,516,29,'#c8baa0','#ac9f87',2)
for x,y in [(1770,602),(1870,598),(2050,601)]:rect(x,y,57,15,'#c1b498',None,1,6)
for x in [1760,2150]:
    rect(x,415,19,172,'#8da3a2',None);line([(x+9,421),(x+80,421)],'#8da3a2',8)
text(1940,419,'骨架主厅 · 可绕行观看',24,PRIMARY,True,'middle')
rect(1595,519,133,99,'#c5d9d1','#829d93',2)
text(1661,533,'生物介绍',21,INK,True,'middle')
text(1661,571,'实体图文牌',18,MUTED,False,'middle')
line([(1870,657),(1975,657)],PAPER,9)
text(1580,691,'吊装夹具与工作台作现场陈设，不设拼装或标本操作任务。',22,MUTED)

panel(1540,810,810,530,'03','生活医疗楼','宿舍搜集生活物资；现场能吃，部分可收藏；取消游戏机。')
rect(1580,956,730,257,'#e5ece7',PRIMARY,3)
room(1593,968,310,113,'宿舍 A','床位 / 储物柜')
room(1593,1092,310,108,'宿舍 B','零食 / 收藏物')
room(1920,968,181,113,'医务附间','护理用品')
room(2114,968,181,113,'更衣附间','用具架')
room(1920,1092,375,108,'食堂 / 茶水间','食品与可搬动小物')
for x,y in [(1620,996),(1822,996),(1620,1119)]:rect(x,y,31,56,'#94b3a4','#73978a',1)
rect(1815,1128,43,32,'#d2aa65',GOLD,2,4)
line([(2310,1081),(2310,1138)],PAPER,9)
text(1580,1250,'发现物资的乐趣为主；不以认识队员或收集人物档案为目标。',22,MUTED)

panel(50,1380,740,680,'04','动力与生命保障站','完整多房间探索；操作后站区外部也能看出变化。')
rect(90,1535,660,349,'#e5ece7',PRIMARY,3)
room(102,1547,195,117,'控制室','分区状态 / 复位')
room(313,1547,423,165,'机组大厅','设备 / 可视管线')
room(102,1682,195,188,'供暖 / 制氧','维护台')
room(313,1730,184,140,'备件库','可搜集物资')
room(513,1730,223,140,'检修间','维护回路')
line([(90,1567),(90,1626)],PAPER,9)
for y in [1580,1621,1662]:rect(646,y,65,22,'#9fb8af','#799c8d',1)
text(92,1922,'恢复：部分照明与供暖 + 更方便的慢充补氧。',23,PRIMARY,True)
text(92,1973,'保留基础补给兜底；动力恢复为可选探索。',22,MUTED)

panel(830,1380,740,680,'05','机修车库','可驾驶小运输车：运货、载队友，并尽量开入遗迹。')
rect(870,1535,660,349,'#e5ece7',PRIMARY,3)
room(882,1560,147,170,'维修间','工作台')
room(1240,1547,276,144,'工具 / 零件库','可搜集')
room(1240,1709,276,161,'设备 / 装货区','小件和货物')
rect(1070,1600,131,226,'#9ab5ad',PRIMARY,3,12)
rect(1084,1615,103,60,'#6e9194',None)
rect(1084,1694,103,108,'#c4d5c8','#7d9d91',2)
for x in [1060,1194]:
    for y in [1630,1747]:rect(x,y,17,46,'#5f7d78',None)
line([(1055,1535),(1210,1535)],PAPER,10)
arrow((1135,1580),(1135,1507),ROUTE,5)
text(871,1922,'按真实地形决定通过与停车，不按洞厅编号禁驾。',23,PRIMARY,True)
text(871,1973,'阻挡处下车继续；车位、转弯和装载需原型实测。',22,MUTED)

panel(1610,1380,740,680,'06','物资仓库','多房间搜集；先逛开放区域，再融冰进入局部库房。')
rect(1650,1535,660,349,'#e5ece7',PRIMARY,3)
room(1662,1547,635,88,'装卸厅','对接车辆装货位置')
room(1662,1653,194,217,'开放工具库','器材 / 耗材')
room(1874,1653,194,217,'开放生活库','普通物资')
room(2090,1653,207,98,'冰封库房 A',None,'#c4dce3')
room(2090,1769,207,101,'冰封库房 B',None,'#c4dce3')
line([(2101,1653),(2168,1653)],ICE,12)
line([(2090,1786),(2090,1836)],ICE,12)
for x in [1679,1763,1891,1975]:
    for y in [1810,1840]:rect(x,y,57,16,'#a9b99e','#8e9f88',1)
line([(1920,1535),(2025,1535)],PAPER,9)
arrow((2160,1623),(2160,1646),GOLD,4)
text(1651,1922,'热风机融开实际入口；融冰保留，物资不重复领取。',23,PRIMARY,True)
text(1651,1973,'具体物资、奖励与库房数量仍为候选。',22,MUTED)

line([(65,2105),(2335,2105)],BORDER,2)
text(65,2130,'读图说明：建筑用途和关键行为来自用户确认；图中房间位置、数量和连接为建议落位，并非已确认尺寸或已实现关卡。',24,MUTED)
text(65,2177,'此图表达功能关系，各建筑未按统一比例绘制；普通门洞、楼梯细部和车辆通过尺度需另行验证。',23,MUTED)
text(2335,2223,'2026.10.28 / INTERVIEW DESIGN 03',20,MUTED,False,'right')
svg.append('</svg>')
(OUT/'霜烬星-六栋建筑-功能草案03.svg').write_text('\n'.join(svg),encoding='utf-8')
im.save(OUT/'霜烬星-六栋建筑-功能草案03.png')
print('Created building program:',W,H)

