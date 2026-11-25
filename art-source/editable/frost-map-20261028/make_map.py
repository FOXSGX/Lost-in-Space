from pathlib import Path
from html import escape
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
W, H = 2200, 2400
BG = '#0b1825'; PANEL = '#102333'; EDGE = '#294556'
TEXT = '#eaf4f5'; MUTED = '#9eb7c4'; CYAN = '#65d9dd'
GOLD = '#f0bd71'; PURPLE = '#c5a0df'; ICE = '#9ccbdc'
im = Image.new('RGB', (W,H), BG)
d = ImageDraw.Draw(im)
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',f'<rect width="{W}" height="{H}" fill="{BG}"/>']
fonts = {}
def font(size,bold=False):
    k=(size,bold)
    if k not in fonts: fonts[k]=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc' if bold else 'C:/Windows/Fonts/msyh.ttc',size)
    return fonts[k]
def rect(x,y,w,h,fill,stroke=None,sw=1,r=0):
    if r: d.rounded_rectangle((x,y,x+w,y+h),r,fill,stroke,sw)
    else: d.rectangle((x,y,x+w,y+h),fill,stroke,sw)
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{sw}"/>')
def line(points,color,width=2,dash=False):
    points=[(float(x),float(y)) for x,y in points]
    if dash:
        for a,b in zip(points,points[1:]):
            length=math.dist(a,b)
            for t in range(0,int(length),17):
                u=t/max(length,1);v=min(t+9,length)/max(length,1)
                d.line((a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u,a[0]+(b[0]-a[0])*v,a[1]+(b[1]-a[1])*v),fill=color,width=width)
    else: d.line(points,fill=color,width=width,joint='curve')
    pts=' '.join(f'{x},{y}' for x,y in points)
    svg.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round"'+(' stroke-dasharray="9 8"' if dash else '')+'/>')
def circle(x,y,r,fill,stroke=None,sw=2):
    d.ellipse((x-r,y-r,x+r,y+r),fill,stroke,sw)
    svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{sw}"/>')
def text(x,y,s,size=28,color=TEXT,bold=False,anchor='left'):
    f=font(size,bold); length=d.textlength(s,font=f)
    xx=x-length/2 if anchor=='middle' else x-length if anchor=='right' else x
    d.text((xx,y),s,font=f,fill=color)
    svg.append(f'<text x="{x}" y="{y+size*.98}" font-family="Microsoft YaHei, Noto Sans CJK SC, sans-serif" font-size="{size}" font-weight="{700 if bold else 400}" text-anchor="'+('middle' if anchor=='middle' else 'end' if anchor=='right' else 'start')+f'" fill="{color}">{escape(s)}</text>')
def arrow(a,b,color=CYAN,width=4):
    line([a,b],color,width)
    ang=math.atan2(b[1]-a[1],b[0]-a[0])
    for delta in [-.55,.55]: line([b,(b[0]-14*math.cos(ang+delta),b[1]-14*math.sin(ang+delta))],color,width)
def badge(x,y,n,color=CYAN):
    circle(x,y,21,BG,color,3); text(x,y-17,str(n),25,color,True,'middle')

text(64,43,'霜烬星',64,TEXT,True)
text(340,66,'平面地图',38,ICE)
text(65,126,'0.3 科考站扩展版  /  依据当前独立试玩关卡绘制',27,MUTED)
rect(1740,58,395,56,'#183c43',None,r=12)
text(1937,67,'当前实现 · 观察事实',26,CYAN,True,'middle')
line([(65,184),(2135,184)],EDGE,2)
rect(60,215,1045,1925,PANEL,EDGE,2,22)
rect(1140,215,1000,1145,PANEL,EDGE,2,22)
rect(1140,1390,1000,750,PANEL,EDGE,2,22)

# Equal-scale world X/Z projection. North is map convention: world -Z.
S=1.88
def p(x,z): return (590+x*S,260+(z+908)*S)
def wr(x,z,w,depth,fill,stroke=EDGE,sw=2):
    a=p(x-w/2,z-depth/2);rect(*a,w*S,depth*S,fill,stroke,sw)
def wline(points,color,width=3,dash=False):line([p(x,z) for x,z in points],color,width,dash)
text(91,240,'01  总平面',28,TEXT,True)
text(91,282,'上方为遗迹深处',23,MUTED)
arrow((1025,346),(1025,276),ICE,3)
text(1025,238,'N',24,ICE,True,'middle')
text(1025,360,'−Z',20,MUTED,False,'middle')

# Actual floor extents and continuous rooms.
wr(0,-220,150,520,'#1c3948','#587a8a',2)
for i,(z,col) in enumerate([(-530,'#254554'),(-680,'#3d3652'),(-830,'#4b3c32')]):
    wr(0,z,142,152,col,'#71838b',3)
    for side in [-1,1]:wr(side*69,z,8,152,'#1b2832','#3c505c',1)
    for dz in [-50,-25,0,25,50]:
        for side in [-1,1]:wr(side*36,z+dz,3,4,'#9b9688',None)
    # In-room bone ramps, physically reversible.
    path=[(0,z+68),(-23,z+38),(18,z+6),(-15,z-32),(0,z-52)]
    wline(path,'#b4a58e',15)
    for x,zz in path:wr(x,zz,10,10,'#b4a58e',None)
    wr(0,z-52,24,20,'#b4a58e',None)
    if i<2:
        wr(0,z-63,138,2,'#a59a87',None)
        path += [(0,z-61.8),(0,z-78)]
    wline(path,CYAN,4)
    for x in [-20,22]:wr(x,z+45,5,3,ICE,None)
    # Maintenance station location.
    q=p(-25,z+56); circle(*q,8,CYAN);text(q[0]-14,q[1]-21,'+',23,BG,True)
    q=p(0,z+22);circle(*q,8,PURPLE)
wr(0,-905,140,5,'#17252f','#536676',1)

# Outdoor landmarks, buildings and transport axis.
for z in range(-45,-465,-24):wr(0,z,9,20,'#476776',None)
for z in range(-440,20,35):
    for x in [-74,74]:wr(x,z,6,24,'#344c5b',None)
for x,z,w,dep,color in [(-38,-95,30,34,'#846c47'),(38,-210,32,38,'#386876'),(-36,-340,32,35,'#3c756e')]:
    wr(x,z,w,dep,color,'#b1c9ca',2)
wr(-10.75,-335,18.5,22,'#345453','#7ba7a1',2)
wr(0,4,30,28,'#576e7d','#b6c4c6',2)
wr(0,11,14,16,'#c3c9c2','#f1ce90',3)
wr(-19,0,2,40,'#253744',None);wr(19,0,2,40,'#253744',None)
wr(0,-18,8.1,1.5,ICE,ICE,2)
for x in [-24,24]:wr(x,-463,8,12,'#c9b89a','#e3d4b3',2)
wline([(-24,-463),(24,-463)],'#c9b89a',9,True)

# Main approach includes the visit to the research station, then back to axis.
wline([(0,8),(0,-18),(0,-70),(0,-305),(-36,-318),(-36,-340)],CYAN,4)
wline([(-36,-318),(0,-305),(0,-462)],CYAN,4)
for zz in [-140,-270,-410]:arrow(p(0,zz+14),p(0,zz-14),CYAN,4)
for zz in [-530,-680,-830]:arrow(p(0,zz+68),p(-10,zz+55),CYAN,4)

# Optional off-axis loops: preserve their actual side of the room.
for route in [[(0,-490),(-44,-516)],[(25,-702),(43,-683),(43,-706),(28,-718)],[(0,-800),(50,-821),(50,-846),(44,-854)]]:
    wline(route,PURPLE,3,True)
for x,z in [(-44,-516),(28,-718),(44,-854)]:
    wr(x,z,15 if x<0 else 20,14 if x<0 else 16,'#62526d',PURPLE,2)
for x,z in [(-29,-84),(-5,5)]:circle(*p(x,z),8,CYAN)
# Objective locations.
circle(*p(-2.4,-882),12,GOLD)
circle(*p(-36,-349),9,GOLD)

def callout(x,z,side,title,sub,y=None,color=TEXT):
    xx,yy=p(x,z);yy=yy if y is None else y
    if side=='left':
        line([p(x,z),(398,yy),(115,yy)],'#6a8797',2)
        text(114,yy-65,title,29,color,True)
        text(114,yy-27,sub,23,MUTED)
    else:
        line([p(x,z),(775,yy),(1057,yy)],'#6a8797',2)
        text(785,yy-65,title,29,color,True)
        text(785,yy-27,sub,23,MUTED)

callout(-2.4,-882,'left','06  深处钥匙','首席遗体旁 · 高台约 +12m',y=390,color=GOLD)
callout(44,-854,'right','设备侧台','可选记录 / 补给',y=410,color=PURPLE)
callout(-55,-822,'left','深厅','小型敌对生物',y=520)
callout(28,-718,'right','弹射观察台','生物弹射 / 东侧缓坡',y=660,color=PURPLE)
callout(-55,-680,'left','栖息厅','多只柔软生物',y=745)
callout(-44,-516,'left','冰封运输橇','可选物资箱',y=935,color=PURPLE)
callout(55,-542,'right','05  入口厅','骨脊斜坡 / 生物体验',y=1000)
callout(24,-463,'right','04  巨型骨口','基地与遗迹的连接口',y=1135)
callout(-36,-340,'left','03  主科考楼','保险柜 / 实验 / 观察夹层',y=1360)
callout(38,-210,'right','生活与后勤楼','床铺 / 撤离记录 / 补给',y=1590)
callout(-38,-95,'left','02  仓储楼','电池 / 医疗 / 维护台',y=1800)
callout(0,-18,'right','融冰出口','热风机融开封冰',y=1875,color=ICE)
callout(0,11,'left','01  飞船与停机坪','取装备 → 返航安装能源',y=2035,color=GOLD)
text(785,2037,'地表约 150m 宽',23,MUTED)
text(785,2070,'全图纵深约 940m',23,MUTED)

# Station detail in exact X/Z proportion; separated mezzanine drawing below.
text(1174,243,'02  主科考楼 · 放大平面',32,TEXT,True)
text(1174,295,'南侧进出；东侧附间是可选实验环路',25,MUTED)
K=15
def sp(x,z):return (1230+(x+55)*K,410+(z+360)*K)
def sr(x,z,w,dep,fill,stroke=EDGE,sw=2):
    xx,yy=sp(x-w/2,z-dep/2);rect(xx,yy,w*K,dep*K,fill,stroke,sw)
sr(-36,-340,32,35,'#214640','#7baaa4',4)
sr(-10.75,-335,18.5,22,'#254250','#71939d',4)
# Open main entrance and ice-closed hatch.
line([sp(-44.5,-322.5),sp(-33.5,-322.5)],BG,10)
line([sp(-20,-337.1),sp(-20,-332.9)],ICE,10)
sr(-48,-332,4.5,2.4,'#9abcb5',None)
sr(-36,-349.6,4.6,2,GOLD,None)
sr(-30,-326.8,4,1.6,'#658b91',None)
sr(-26,-332,3.8,1.5,'#67818c',None)
sr(-10,-341,2.3,1.2,GOLD,None)
for z in [-338,-345,-353]:sr(-49,z,2,1.4,'#6b8f95',None)
# Upper deck is explicitly ghosted, not an invented ground-floor room.
sr(-29.5,-349,9,14,'#304e51','#7e9c9b',2)
line([sp(-34,-342),sp(-34,-356),sp(-25,-356),sp(-25,-342),sp(-34,-342)],PURPLE,3,True)
line([sp(-22.6,-339.5),sp(-22.6,-352.2)],PURPLE,8)
arrow(sp(-22.6,-342),sp(-22.6,-349),PURPLE,3)
text(*sp(-29.5,-352.8),'夹层',22,PURPLE,True,'middle')
text(*sp(-29.5,-350.4),'+3.2m',19,PURPLE,False,'middle')
text(*sp(-36,-346.5),'保险柜',23,GOLD,True,'middle')
text(*sp(-46.8,-329.5),'样本台',23,TEXT,True,'middle')
text(*sp(-10.7,-338.8),'旁路电源',22,GOLD,True,'middle')
text(*sp(-10.7,-331),'检修附间',23,TEXT,True,'middle')
text(*sp(-30,-324.5),'接待台',20,MUTED,False,'middle')
text(*sp(-44,-342),'主通道',21,CYAN,True,'middle')
arrow(sp(-41,-320),sp(-41,-338),CYAN,4)
arrow(sp(-41,-338),sp(-38,-346),CYAN,4)
arrow(sp(-31,-335),sp(-17,-335),PURPLE,3)
circle(*sp(-3,-340),6,CYAN)
text(2028,408,'N ↑',23,ICE)
text(1665,1000,'↑ 南侧入口',25,CYAN,True,'middle')
text(1180,1044,'青色：开柜主通道    紫色：可选实验与夹层',25,MUTED)
line([(1180,1100),(2100,1100)],EDGE,2)
text(1180,1120,'实验环路',28,PURPLE,True)
text(1180,1167,'融开检修门 → E 开门 → 复位电源 → 解冻并观察样本',25,TEXT)
text(1180,1215,'观察夹层经楼内斜坡往返；观察窗密闭。',25,MUTED)
text(1180,1263,'实验、供电和日志均不作为开保险柜的门槛。',25,GOLD)

text(1174,1420,'03  路线与图例',32,TEXT,True)
steps=[('出发','飞船取装备，融开停机坪出口。'),('调查','前往主科考楼，发现能源与钥匙线索。'),('深入','穿过骨口，依次进入口厅、栖息厅、深厅。'),('取钥匙','沿可逆骨脊斜坡到深处高台。'),('返航','原路返回科考楼开柜，再回飞船。')]
for i,(title,desc) in enumerate(steps):
    yy=1485+i*83
    badge(1200,yy+19,i+1,GOLD if i==4 else CYAN)
    text(1240,yy-1,title,28,TEXT,True)
    text(1380,yy+1,desc,25,MUTED)
text(1180,1915,'回船后操作核心台两次：安装能源 → 恢复航行。',25,GOLD)
line([(1180,1974),(2100,1974)],EDGE,2)
line([(1188,2013),(1250,2013)],CYAN,5);text(1265,1992,'主线 / 骨脊可往返',24,TEXT)
line([(1640,2013),(1702,2013)],PURPLE,4,True);text(1717,1992,'可选探索支路',24,TEXT)
circle(1208,2076,9,CYAN);text(1235,2055,'慢充 / 补氧',24,MUTED)
rect(1600,2068,25,16,ICE);text(1640,2055,'可融封冰',24,MUTED)
circle(1890,2076,9,GOLD);text(1913,2055,'关键目标',24,MUTED)

line([(65,2186),(2135,2186)],EDGE,2)
text(65,2210,'图面说明',27,TEXT,True)
text(65,2253,'总图按 X/Z 等比例投影；北向约定为 −Z。骨脊高度以文字标注，屋顶与高处骨架省略。',25,MUTED)
text(65,2296,'细小物资、表层雪块与陈设已简化；本图记录 0.3 独立试玩实现，不代表整颗星球的最终设计。',25,MUTED)
text(65,2344,'LOST IN SPACE  /  PLANET 00',19,'#658697')
text(2135,2344,'2026.10.28 · 平面资料图',20,'#658697',False,'right')

svg.append('</svg>')
(OUT/'霜烬星-0.3-平面地图.svg').write_text('\n'.join(svg),encoding='utf-8')
im.save(OUT/'霜烬星-0.3-平面地图.png')
print(OUT/'霜烬星-0.3-平面地图.png')
