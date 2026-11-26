"""Original, reproducible surface labels and quiet environment audio for v0.2."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'game/previews/frost_first_playable'
FONT = 'C:/Windows/Fonts/msyh.ttc'
SIGNS = {
    'cache': ('科考运输箱', 'E 打开 / 冰封时先融雪', '耐用电池 · 应急物资 / 取用后不刷新'),
    'rib_route': ('01 · 肋骨前厅', '运输橇搁浅在左侧冰坡', '主骨脊通往深处 / 斜坡可双向通行'),
    'nest_route': ('02 · 活体栖息厅', '观察台 / 受热弹射', '站背部向下吹 / 后侧骨坡可步行返回'),
    'incident_route': ('03 · 深层科考现场', '失联小队最后停留点', '损坏设备留在侧台 / 请勿改动原始痕迹'),
    'evacuation': ('留守人员撤离板', '小队遇袭 → 暴雪封航', '搜救未完成 / 工具与应急补给留给后来者'),
    'valve_normal': ('样件 A · 完好', '三枚锁销均在位', '封盖与安全线完整 / 仅供对照'),
    'valve_damaged': ('设备 B · 现场', '锁销移出 / 线束旁接', '损伤发生在求救前 / 操作者未知'),
}
for key, lines in SIGNS.items():
    im = Image.new('RGB', (1024, 512), '#193646')
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((12, 12, 1012, 500), 28, outline='#dbb674', width=9)
    for y, text, size, color in [(45, lines[0], 54, '#a8e1e5'), (173, lines[1], 54, '#f4d1a1'), (338, lines[2], 32, '#d8e5e5')]:
        d.text((50, y), text, font=ImageFont.truetype(FONT, size), fill=color)
    if key == 'nest_route':
        d.ellipse((720, 255, 850, 310), fill='#d595b9')
        d.line([(785, 253), (785, 110), (760, 148)], fill='#f4d1a1', width=12)
        d.rectangle((875, 195, 966, 215), fill='#c6b69a')
    im.save(OUT / 'signs' / f'{key}.png')

# Periodic sum of sine partials, with a quiet filtered-noise wind band.
# Endpoint blending ensures a loop seam without a click; original synthesis.
rate = 22050
duration = 12
rng = random.Random(251025)
for kind in ('wind', 'cavity'):
    samples = []
    filtered = 0.0
    for i in range(rate * duration):
        t = i / rate
        filtered = filtered * 0.965 + rng.uniform(-1, 1) * 0.035
        swell = 0.65 + 0.2 * math.sin(2 * math.pi * t / duration)
        tone = math.sin(2 * math.pi * (72 if kind == 'cavity' else 116) * t)
        value = (filtered * (0.4 if kind == 'wind' else 0.09) + tone * 0.007) * swell
        samples.append(value)
    seam = 1024
    for i in range(seam):
        blend = i / (seam - 1)
        samples[-seam + i] = samples[-seam + i] * (1 - blend) + samples[0] * blend
    peak = max(abs(value) for value in samples)
    gain = (0.55 if kind == 'wind' else 0.4) / peak
    samples = [value * gain for value in samples]
    with wave.open(str(OUT / 'audio' / f'{kind}.wav'), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(b''.join(struct.pack('<h', max(-32767, min(32767, round(x * 32767)))) for x in samples))
print('Created seven equipment/surface labels and two quiet original ambient loops.')
