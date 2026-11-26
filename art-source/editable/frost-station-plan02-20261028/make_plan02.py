"""Editable, equal-scale site plan. Design artifact only; no game data is edited."""
from pathlib import Path
from html import escape
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
W, H = 2340, 2100
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

VIEW='#bd6e39'
text(64,46,'霜烬星 · 科考站',61,INK,True)
text(66,133,'围院规划 02  /  收紧作业院 · 强化地标视线',30,MUTED)
rect(1820,62,452,63,PRIMARY,r=10)
text(2046,73,'第 1、4 项修订 · 规划图',26,'#ffffff',True,'middle')
line([(65,205),(2275,205)],BORDER,2)
rect(50,245,1655,1670,PAPER,BORDER,2,18)
rect(1740,245,550,1670,PAPER,BORDER,2,18)
text(81,268,'总平面 / 顶视',25,INK,True)
text(1668,270,'北 ↑ · 遗迹方向',24,MUTED,False,'right')

S=8.9; OX=143; OY=345
def p(x,y):return (OX+x*S,OY+y*S)
def wl(points,col,width=2,dash=False):line([p(x,y) for x,y in points],col,width,dash)
def wr(x,y,w,h,fill,stroke=None,sw=2,r=0):
    xx,yy=p(x,y);rect(xx,yy,w*S,h*S,fill,stroke,sw,r)
def wt(x,y,s,size=25,col=INK,bold=False,anchor='middle'):text(*p(x,y),s,size,col,bold,anchor)
def wc(x,y,r,fill,stroke=None,sw=2):circle(*p(x,y),r*S,fill,stroke,sw)
def door(x,y,axis='h',width=6,col=ROUTE,wall=PAPER):
    ends=[(x-width/2,y),(x+width/2,y)] if axis=='h' else [(x,y-width/2),(x,y+width/2)]
    wl(ends,wall,10);wl(ends,col,4)
    for a,b in ends:wl([(a,b-.7),(a,b+.7)] if axis=='h' else [(a-.7,b),(a+.7,b)],col,3)
def building(x,y,w,h,fill,sw=4):
    wr(x+.7,y+.9,w,h,'#cad5d2',None)
    wr(x,y,w,h,fill,PRIMARY if fill==PRIMARY else '#638884',sw)
def route(points,width=7):
    wl(points,PAPER,width+5);wl(points,ROUTE,width)
def optional(points):wl(points,OPT,3,True)
def room(x,y,w,h,label,light=True):
    wr(x,y,w,h,None,'#7ba2a8' if light else '#91adaa',2)
    wt(x+w/2,y+h/2-1.4,label,22,'#e5f0ed' if light else '#315a60')

for x in range(0,156,20):
    wl([(x,0),(x,168)],GRID,1);wt(x,-2.6,str(x),17,MUTED)
for y in range(0,169,20):
    wl([(0,y),(155,y)],GRID,1);text(OX-25,OY+y*S-10,str(y),17,MUTED,False,'right')
for shape in [[(0,18),(7,13),(15,23),(11,46),(0,50)],[(150,12),(155,6),(155,61),(150,57)],[(0,111),(7,108),(9,137),(0,149)],[(150,114),(155,107),(155,168),(149,159)]]:
    poly([p(x,y) for x,y in shape],SNOW)
for x,y,w,h in [(4,30,4,3),(151,44,3,5),(4,124,3,4),(151,151,3,4)]:wr(x,y,w,h,'#9cb3bb',None)

# Core court: a true 40 x 35 m rectangle. Other outdoor surfaces connect to it.
wr(50,65,40,35,'#dce7dc','#9ab69f',3)
wr(56,99,38,43,'#e3e8df',None)
wr(18,104,112,8,'#e1e6df',None)
wr(104,6,15,57,'#e0e7e1',None)
wr(89,61,25,9,'#e0e7e1',None)
wr(118,56,31,7,'#e0e7e1',None)

# Short pre-existing type of covered connection; no new route system.
for pts in [[(40,60),(40,65)],[(100,60),(100,65)]]:
    wl(pts,'#b4c8c4',55);wl(pts,PAPER,45)
    for y in [61.5,63.5]:wl([(pts[0][0]-2.5,y),(pts[0][0]+2.5,y)],'#bbccc5',2)

# Building placements close inward with the court; the six roles remain.
building(35,26,70,34,PRIMARY,5)
room(35,26,21,14,'档案 / 指挥')
wr(56,26,22,14,None,'#7ba2a8',2)
wt(67,36,'能源保管室',21,'#e5f0ed')
wr(61,29,10,5,'#b98b45','#f3d59c',2);wt(66,29.7,'保险柜',18,'#ffffff',True)
room(78,26,27,14,'研究 / 通讯')
room(35,45,23,15,'基础实验室')
room(83,45,22,15,'办公 / 会议')
wl([(35,40),(105,40)],'#7ba2a8',2)
wt(70,48,'接待大厅',26,'#ffffff',True)
wt(70,54,'主要入口',20,'#b9d6d6')
door(70,60,'h',10,'#f3c678',PRIMARY)
door(40,60,'h',5,'#b8d6cf',PRIMARY);door(100,60,'h',5,'#b8d6cf',PRIMARY)
wr(60,60,20,3,'#cddbd4','#8ba8a2',2)
for y in [60.8,61.8]:wl([(61,y),(79,y)],'#8da9a2',1)
for x in [40,48,57,67,82,95]:wl([(x,26),(x+4,26)],'#bad6d6',6)
badge(*p(35,26),'01',GOLD)
wt(53,17,'主科研楼',36,PRIMARY,True)
wt(53,22,'主楼体量保持最大',20,MUTED)

# Roof tower sits close to the arrival axis: a silhouette visible above the facade.
wr(66,17,9,9,'#a2bfbd',PRIMARY,3)
wc(70.5,21.5,3.2,None,PRIMARY,3);wc(70.5,21.5,1.1,PRIMARY)
wl([(70.5,18.3),(70.5,24.7)],PRIMARY,2);wl([(67.3,21.5),(73.7,21.5)],PRIMARY,2)
wt(77,19,'通讯塔',23,PRIMARY,True,'left')
wt(77,23,'塔顶约 +22m',18,MUTED,False,'left')

building(9,65,34,38,WING)
wr(11,68,15,21,'#b0c9c8','#83a5a4',2)
wr(27,68,14,21,'#aec4cf','#83a5a4',2)
wt(18.5,70,'骨骼标本',22,INK,True);wt(34,70,'隔离观察',22,INK,True)
wl([(13,82),(23,82)],'#eee7cb',10)
for x in [14,17,20,22]:wl([(x,78),(x,86)],'#eee7cb',5)
for x,y in [(31,79),(37,84)]:wc(x,y,2.1,'#b78bb0','#856a8a',2)
wl([(11,92),(41,92)],'#83a5a4',2)
wt(26,96,'样本交接 / 冷藏',21,INK)
door(43,86,'v',8);door(40,65,'h',5)
badge(*p(9,65),'02')
wt(23,57.4,'标本保存与隔离馆',29,PRIMARY,True)
wt(23,62,'辅助探索',18,MUTED)

building(99,65,34,38,WING)
for x in [99,116]:
    wr(x,65,17,10,None,'#91adaa',2);wt(x+8.5,71.6,'宿舍',20,'#315a60')
    room(x,75,17,10,'医务室' if x==99 else '更衣室',False)
for x in [101,104,107,118,121,124]:wr(x,66.3,2,4,'#98b6b2',None)
wr(99,89,34,14,'#c6d9cf','#91adaa',2);wt(116,94,'食堂 / 公共活动',22,INK)
door(99,86,'v',8);door(100,65,'h',5)
badge(*p(133,65),'03')
wt(116,104.4,'生活医疗楼',28,PRIMARY,True)

building(121,26,28,26,AUX,3)
wl([(137,26),(137,52)],'#a8bcb4',2)
wt(129,31,'动力机组',20,MUTED,True);wt(129,43,'维护间',20,MUTED)
for y in [32,42]:wc(143,y,3.3,'#b6c9c4','#839d99',2)
door(133,52,'h',6)
badge(*p(121,26),'04','#718e8c')
wt(135,17.5,'动力与生命保障站',25,INK,True)
wt(143,47,'制氧 / 水',16,MUTED)

building(95,113,48,25,AUX,3)
wl([(127,113),(127,138)],'#a5b9b2',2)
wt(135,119,'维修台',21,MUTED);wt(135,129,'零件',20,MUTED)
for x in [99,113]:
    wr(x,119,9,12,'#aebfba','#78918b',2,r=7);wr(x+1.2,120,6.6,3,'#69888b',None)
    for dx in [-.6,8.6]:wr(x+dx,121,1.3,7,'#69827e',None)
    door(x+4.5,113,'h',10)
badge(*p(95,113),'05','#718e8c')
wt(119,140,'机修车库',29,INK,True)

building(12,113,43,25,AUX,3)
wl([(42,113),(42,138)],'#a5b9b2',2)
for y in [118,125,132]:
    for x in [16,26]:wr(x,y,7,3,'#a0b4a8','#7f9989',1)
wt(48.5,120,'耗材',21,MUTED);wt(48.5,129,'工具',21,MUTED)
door(34,113,'h',12);wr(16,109,32,4,'#d0d9ca','#9aae9e',2)
for x,y in [(18,107),(24,107),(49,110)]:wr(x,y,3,2,'#b6bca7','#939d86',1)
badge(*p(12,113),'06','#718e8c')
wt(33.5,140,'物资仓库',29,INK,True)

# The pipe is overhead. It does not block the pedestrian sight or walking route.
pipepath=[(136,26),(136,23),(117,23),(117,57),(145,57),(145,108),(136,108),(136,113)]
wl(pipepath,PIPE,5);wl([(145,108),(34,108),(34,109)],PIPE,4)

# Low yard furniture stays near edges; the arrival axis is open.
wr(51.5,91,6,2.8,'#b8c7b8','#8da391',1)
wr(82.5,91,6,2.8,'#c1cebf','#8da391',1)
for x,y in [(53,94),(85,94)]:
    wr(x,y,2.6,1.7,'#b6bca7','#939d86',1)
for x,y in [(52,68),(88,68),(52,97),(88,97)]:wc(x,y,.6,'#4b777e')
wt(70,76,'中央作业院',34,PRIMARY,True)
wt(70,81,'40 × 35m',28,PRIMARY,True)
wt(70,86,'低矮装卸架 · 保持入口视野',19,MUTED)

route([(70,145),(70,98),(70,93)])
route([(70,71),(70,64)])
arrow(p(70,121),p(70,110),ROUTE,4)
route([(70,64),(70,67),(88,67),(110,61),(111,7)],6)
arrow(p(111,17),p(111,7),ROUTE,4)
optional([(56,86),(43,86)])
optional([(90,86),(99,86)])
optional([(70,105),(34,105),(34,109)])
optional([(81,106),(103.5,106),(103.5,113)])
optional([(111,59),(133,59),(133,52)])
wt(116,53,'遗迹路',18,ROUTE)

# Arrival landmark sightline A: overhead projection, explicitly not a ground path.
wl([(64,144),(70.5,21.5)],VIEW,4,True)
arrow(p(70.7,31),p(70.5,23),VIEW,3)
badge(*p(80,123),'A',VIEW,19)
wt(83,126.5,'仰望通讯塔',20,VIEW,True,'left')

# Upper gallery B is on the north facade; the cyan geometry below remains ground floor.
wr(80,26,22,5,'#326d79','#8ab4ba',2)
wl([(80,26),(102,26)],'#f0cc8c',7)
wt(91,26.5,'上层观察廊',20,'#ffffff',True)
wl([(92,27),(111,-2)],VIEW,4,True)
arrow(p(105,7),p(111,-2),VIEW,3)
badge(*p(97,10),'B',VIEW,19)
wt(86,7.5,'面向骨口',20,VIEW,True,'right')
wc(92,27,1.2,'#f0cc8c')

# Pad moved toward the tighter cluster; cabin remains separate from station buildings.
wr(56,141,36,23,'#d6e0db','#8ba69d',2)
for x in [58,87]:
    wl([(x,143),(x,146)],'#fafbf5',4);wl([(x,159),(x,162)],'#fafbf5',4)
poly([p(x,y) for x,y in [(74,144),(79,150),(79,159),(76,162),(72,162),(69,159),(69,150)]],'#76959a',PRIMARY,2)
wr(71.5,151,5,5,'#e4edef',None)
# The eye point remains visible at the clear side of the landing platform.
wl([(64,144),(64.22,140)],VIEW,4,True)
wc(64,144,1.3,PAPER,VIEW,3)
wt(101,151,'飞船 / 停机坪',28,PRIMARY,True,'left')
wt(101,156,'A：下船先识别主楼',20,VIEW,False,'left')
wl([(92,151),(98,151)],'#8ea9a4',2)
arrow(p(74,163),p(74,166),ROUTE,4)
wt(74,168,'入口 / 返航',24,ROUTE,True)

# Dimension brackets show what was specifically tightened, outside the furniture.
wl([(50,101.5),(90,101.5)],'#7d9b80',2)
for x in [50,90]:wl([(x,100),(x,103)],'#7d9b80',2)
wt(70,102.3,'40m',18,'#638369')
wl([(47.8,65),(47.8,100)],'#7d9b80',2)
for y in [65,100]:wl([(46.7,y),(49,y)],'#7d9b80',2)
text(*p(45.8,89),'35m',17,'#638369',False,'right')

# Off-map destination is schematic; no new cave location or distance is locked.
rect(*p(93,-8),46*S,42,PAPER)
wt(114,-7.5,'巨型骨口方向',27,ROUTE,True)
wt(114,-3.5,'图外地标 · 距离待定',17,MUTED)

# Sidebar centres the two approved changes rather than proposing more buildings.
text(1772,276,'本轮修改',32,INK,True)
badge(1798,357,'1',PRIMARY,22)
text(1835,337,'院落收紧',29,INK,True)
text(1774,397,'作业院 70×53m → 40×35m',24,PRIMARY,True)
text(1774,443,'两翼与后勤靠拢，缩短楼间空走。',23,MUTED)
text(1774,482,'装卸架留在边缘，中央保持通行。',23,MUTED)
line([(1774,536),(2258,536)],BORDER,2)
badge(1798,593,'4',PRIMARY,22)
text(1835,573,'主楼与骨口的视线',29,INK,True)
text(1774,635,'A  停机坪 → 通讯塔顶',25,VIEW,True)
text(1774,677,'塔位贴近入站轴，轮廓高于主楼。',23,MUTED)
text(1774,731,'B  主楼观察廊 → 巨型骨口',25,VIEW,True)
text(1774,773,'北侧上层看见下一段探索方向。',23,MUTED)
text(1774,815,'观察廊与主路可分别前往。',23,MUTED)
line([(1774,872),(2258,872)],BORDER,2)

# Elevation schematic: A visibility concept over the front parapet.
text(1774,897,'A  视线剖面示意',27,INK,True)
base=1176
line([(1785,base),(2255,base)],'#8fa6a4',2)
rect(2010,1097,130,79,'#ccdad5','#7b9994',2)
rect(2094,998,27,178,'#9ebcb7',PRIMARY,2)
circle(1820,1154,7,INK);line([(1820,1162),(1820,1176)],INK,3)
line([(1826,1154),(2107,998)],VIEW,3,True)
text(1786,1195,'下船视点',20,MUTED)
text(2007,1195,'主楼约9m',20,MUTED)
text(2160,1014,'塔顶',20,PRIMARY)
text(2160,1046,'约22m',20,PRIMARY)
text(1774,1251,'高度为候选；需实机验证遮挡。',22,MUTED)
line([(1774,1303),(2258,1303)],BORDER,2)

text(1774,1327,'建筑编号',27,INK,True)
labels=['01 主科研楼','02 标本保存与隔离馆','03 生活医疗楼','04 动力与生命保障站','05 机修车库','06 物资仓库']
for i,label in enumerate(labels):text(1778+(i%2)*240,1379+(i//2)*41,label,21,PRIMARY if i<3 else MUTED,i==0)
line([(1774,1525),(2258,1525)],BORDER,2)
text(1774,1547,'图例',27,INK,True)
for yy,col,label,dashed in [(1610,ROUTE,'主线往返路线',False),(1656,OPT,'可选探索连接',True),(1702,VIEW,'视线投影（不是步行线）',True),(1748,PIPE,'架空管线',False)]:
    line([(1782,yy),(1840,yy)],col,4,dashed);text(1860,yy-18,label,22,INK)
line([(1782,1815),(1960,1815)],INK,3)
for x in [1782,1871,1960]:line([(x,1808),(x,1822)],INK,2)
text(1782,1834,'0',18,MUTED);text(1960,1834,'20m',18,MUTED,False,'right')
text(2020,1803,'主图等比例',21,MUTED)
text(2020,1838,'剖面为示意',19,MUTED)

line([(65,1957),(2275,1957)],BORDER,2)
text(65,1980,'已按用户确认的第1、4项修订；六类建筑与既有主线保留。本图为规划草案，尚未接入游戏。',24,MUTED)
text(65,2024,'范围约155×168m；尺寸、塔高与视线需灰盒实测。普通室内门洞、楼梯及上层细部简化。',23,MUTED)
text(2275,2026,'2026.10.28 / PLAN 02',20,MUTED,False,'right')
svg.append('</svg>')
(OUT/'霜烬星-科考站-围院规划02.svg').write_text('\n'.join(svg),encoding='utf-8')
im.save(OUT/'霜烬星-科考站-围院规划02.png')
print('Created revision 02:',W,H)

