"""Original equipment/wall pictograms, baked as PNG for Godot; no floating text."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'game/previews/frost_first_playable/signs'
OUT.mkdir(parents=True, exist_ok=True)
FONT = 'C:/Windows/Fonts/msyh.ttc'
SIGNS = {
    'core': ('归航号 · 核心舱', '高能核心故障', '普通燃料有余 / 需要更换高密度能源'),
    'safe': ('03 · 科考站', '能源保管柜', '钥匙由深入遗迹的首席科学家携带'),
    'charge': ('维护电源', '按住 E 慢充', '热风机与氧气瓶 / 不生成备用物资'),
    'record': ('科考记录', 'E 查阅', '请保持设备完整 / 离开前归还样件'),
    'key': ('首席科学家', '遗留物品', 'E 检查装备并收好钥匙'),
    'evidence': ('故障记录器', 'E 读取时间记录', '安全回路 / 原始事件日志'),
    'warehouse': ('01 · 仓储与物流', '电池 / 氧气 / 燃料', '接驳停机坪 → 科考站 → 遗迹'),
    'research': ('02 · 样本与生活区', '科考人员已撤离', '深入小队失联 / 搜救记录留存'),
}
for key, lines in SIGNS.items():
    image = Image.new('RGB', (1024, 512), '#193646')
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((12,12,1012,500), 32, outline='#d7b274', width=10)
    draw.rectangle((40,42,62,112), fill='#94d6da')
    for y, text, size, color in [(42,lines[0],52,'#a8e1e5'),(165,lines[1],72,'#f4d1a1'),(330,lines[2],34,'#d8e5e5')]:
        draw.text((86,y),text,font=ImageFont.truetype(FONT,size),fill=color)
    image.save(OUT / f'{key}.png')
