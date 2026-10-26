"""Project-authored instructional diagrams. Rebuild with local Pillow + Microsoft YaHei.
No third-party illustration or font file is distributed; text is rasterized into the artwork.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).resolve().parent
TARGET = ROOT / 'game/assets/training-wall-posters'
TARGET.mkdir(parents=True, exist_ok=True)
(SOURCE / 'previews').mkdir(exist_ok=True)
W, H = 1200, 720
BG, INK, ORANGE, CYAN, MUTED = '#f1efdf', '#233c4d', '#edaa52', '#65c9d5', '#8dadae'
FONT = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'

def text(d, xy, value, size=40, color=INK, bold=False, anchor=None):
    d.text(xy, value, font=ImageFont.truetype(BOLD if bold else FONT, size), fill=color, anchor=anchor)

def line(d, points, color=INK, width=14):
    d.line(points, fill=color, width=width, joint='curve')

def arrow(d, start, end, color=ORANGE, width=16):
    import math
    line(d, [start, end], color, width)
    a = math.atan2(end[1] - start[1], end[0] - start[0])
    points = [end]
    points += [(end[0] - 36 * math.cos(a + delta), end[1] - 36 * math.sin(a + delta)) for delta in [-0.5, 0.5]]
    d.polygon(points, fill=color)

def key(d, box, value):
    d.rounded_rectangle(box, radius=16, fill=BG, outline=INK, width=5)
    d.line([(box[0]+8, box[3]-9), (box[2]-8, box[3]-9)], fill=MUTED, width=3)
    text(d, ((box[0]+box[2])/2, (box[1]+box[3])/2-4), value, 32, bold=True, anchor='mm')

def bottle(d, x, y, scale=1.0):
    def b(rect):
        return tuple((x if i % 2 == 0 else y) + v * scale for i, v in enumerate(rect))
    d.rounded_rectangle(b((-43, -80, 43, 83)), radius=int(30*scale), fill=CYAN, outline=INK, width=max(2,int(4*scale)))
    d.rectangle(b((-13,-111,13,-78)), fill=INK)
    d.rounded_rectangle(b((-29,-122,29,-106)), radius=3, fill=ORANGE)
    d.rounded_rectangle(b((-30,-30,30,27)), radius=4, fill=BG)

def astronaut(d, x, y, scale=1.0, jet=False, arm_up=False):
    def pt(dx, dy):
        return (x+dx*scale, y+dy*scale)
    d.ellipse([pt(-40,-152),pt(40,-72)], fill=BG, outline=INK, width=max(3,int(6*scale)))
    d.rounded_rectangle([pt(-28,-137),pt(29,-96)], radius=int(12*scale), fill=INK)
    d.ellipse([pt(10,-131),pt(20,-121)], fill=CYAN)
    d.rounded_rectangle([pt(-32,-69),pt(34,16)], radius=int(14*scale), fill=ORANGE, outline=INK, width=max(3,int(5*scale)))
    line(d, [pt(-16,12),pt(-26,66)], INK, int(19*scale))
    line(d, [pt(18,12),pt(30,66)], INK, int(19*scale))
    line(d, [pt(-29,-48),pt(-56,-7 if not arm_up else -100)], INK, int(15*scale))
    line(d, [pt(32,-48),pt(57,-10)], INK, int(15*scale))
    bottle(d, x+45*scale, y-27*scale, scale*0.38)
    if jet:
        d.polygon([pt(35,9),pt(56,9),pt(45,100)], fill=CYAN)
        d.polygon([pt(41,9),pt(51,9),pt(45,70)], fill=BG)

def platform(d, rect):
    d.rounded_rectangle(rect, radius=7, fill=MUTED)
    d.rectangle((rect[0], rect[1], rect[2], rect[1]+14), fill=CYAN)
    for x in [rect[0]+18, rect[2]-24]:
        d.rectangle((x,rect[3],x+10,530), fill=INK)

def canvas(number, title, caption):
    im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
    d.rounded_rectangle((12,12,W-13,H-13),radius=28,outline=INK,width=6)
    d.rounded_rectangle((38,38,141,143),radius=20,fill=ORANGE)
    text(d,(90,89),number,47,bold=True,anchor='mm')
    text(d,(174,46),title,53,bold=True)
    text(d,(177,113),'归航号  /  船员训练',22,color='#657e80')
    line(d,[(42,574),(1158,574)],MUTED,3)
    text(d,(600,634),caption,34,anchor='mm')
    for x,y in [(31,31),(1168,31),(31,688),(1168,688)]:
        d.ellipse((x-5,y-5,x+5,y+5),fill=MUTED)
    return im,d

def save(im, name):
    im.save(SOURCE/'previews'/f'{name}.png')
    im.save(TARGET/f'{name}.png')

im,d=canvas('01','装上氧气瓶','拿到就能装，用完还能补')
bottle(d,265,335,1.2); arrow(d,(408,335),(602,335))
astronaut(d,815,370,1.28)
key(d,(170,471,370,541),'E  拿取')
d.rounded_rectangle((725,466,793,546),radius=27,outline=INK,width=5)
d.pieslice((727,468,791,532),180,270,fill=ORANGE)
line(d,[(759,468),(759,505)],INK,4)
text(d,(815,490),'左键安装',32,bold=True)
save(im,'01-equip')

im,d=canvas('02','轻点起跳','短按空格 · 跳上低台')
platform(d,(670,445,1020,480)); astronaut(d,860,373,0.9)
astronaut(d,287,436,0.65)
arrow(d,(415,427),(556,300),CYAN)
arrow(d,(556,300),(680,385),CYAN)
key(d,(105,205,399,273),'SPACE')
text(d,(252,314),'轻点',30,anchor='mm')
save(im,'02-jump')

im,d=canvas('03','喷气登高','长按空格 · 满条可喷气 0.5 秒')
platform(d,(775,313,1080,348))
astronaut(d,616,359,1.0,jet=True,arm_up=True)
arrow(d,(773,452),(773,218),ORANGE)
key(d,(100,264,410,336),'SPACE')
line(d,[(128,373),(382,373)],ORANGE,15)
text(d,(254,422),'按住',32,anchor='mm')
save(im,'03-boost')

im,d=canvas('04','落地充气','松开后等 0.3 秒 · 1 秒充满 · 耗氧 2%')
astronaut(d,245,405,0.88)
line(d,[(126,467),(390,467)],INK,10)
bottle(d,520,346,0.8)
text(d,(520,485),'-2%',40,anchor='mm',bold=True)
arrow(d,(614,341),(743,341))
d.rounded_rectangle((812,231,941,461),radius=15,outline=INK,width=6)
d.rounded_rectangle((828,330,925,444),radius=8,fill=CYAN)
arrow(d,(1007,447),(1007,257),ORANGE)
save(im,'04-recharge')

im,d=canvas('05','越过间隔','移动 + 喷气 · 落上终点平台')
platform(d,(130,458,397,490)); platform(d,(800,351,1090,385))
astronaut(d,577,321,0.85,jet=True)
arrow(d,(383,373),(486,260),CYAN)
arrow(d,(672,262),(794,300),CYAN)
key(d,(105,184,368,250),'W A S D')
key(d,(815,184,1090,250),'SPACE')
line(d,[(1025,205),(1025,340)],INK,8)
d.polygon([(1029,207),(1113,227),(1029,260)],fill=ORANGE)
save(im,'05-cross')

im,d=canvas('E','返回主舱','靠近舱门 · 按 E 返回')
d.rounded_rectangle((760,204,964,517),radius=20,outline=INK,width=10)
d.rectangle((782,226,938,516),fill=MUTED)
d.ellipse((903,368,917,382),fill=ORANGE)
arrow(d,(252,351),(656,351),ORANGE,25)
key(d,(372,423,530,512),'E')
save(im,'06-exit')
print('Generated 6 original wall diagrams:',TARGET)
