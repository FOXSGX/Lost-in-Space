"""生成奶龙星背景音乐循环（纯 stdlib，无第三方素材）。

    python make_bgm.py <输出目录>

- 22050 Hz / 单声道 / 16-bit PCM WAV，40 秒无缝循环（96 BPM × 16 小节）。
- 全部由正弦/噪声合成：暖垫（A 小调 → F 大七 → C add9 → G add9）+ 低音拨弦 + 软底鼓 + 细碎脉冲。
- 循环无缝的做法：所有声音都“环形写入”同一个缓冲区（越界的尾巴从 0 处继续），
  因此首尾天然连续，不需要额外交叉淡化。
- 这是占位级配乐：结构简单、可复现、版权干净；要换成正式曲子只需替换 wav 并保留同名。
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
BPM = 96.0
BEAT = 60.0 / BPM
BAR = 4.0 * BEAT
BARS = 16
LOOP = BAR * BARS            # 40 s
N = int(RATE * LOOP)

# 每个和弦 10 s；四段覆盖 40 s。
CHORDS = [
    (0.0, [110.00, 130.81, 164.81, 246.94]),   # A2 C3 E3 B3  → Am(add9)
    (10.0, [87.31, 110.00, 130.81, 164.81]),   # F2 A2 C3 E3  → Fmaj7
    (20.0, [130.81, 164.81, 196.00, 293.66]),  # C3 E3 G3 D4  → Cadd9
    (30.0, [98.00, 123.47, 146.83, 220.00]),   # G2 B2 D3 A3  → Gadd9
]

random.seed(20261125)
buf = [0.0] * N


def wrap_add(start_sample, values):
    n = len(buf)
    for i, value in enumerate(values):
        buf[(start_sample + i) % n] += value


def smooth_step(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def pad_window(tau, hold=10.0, fade=2.0):
    if tau < 0.0 or tau > hold + fade:
        return 0.0
    if tau < fade:
        return smooth_step(tau / fade)
    if tau > hold:
        return smooth_step((hold + fade - tau) / fade)
    return 1.0


def render_pad():
    for start, notes in CHORDS:
        total = 14.0
        count = int(RATE * total)
        for freq in notes:
            phase1 = 0.0
            phase2 = 0.0
            phase3 = 0.0
            d1 = 2.0 * math.pi * freq / RATE
            d2 = 2.0 * math.pi * freq * 2.0 / RATE * 1.002
            d3 = 2.0 * math.pi * freq * 3.0 / RATE * 0.998
            values = [0.0] * count
            for i in range(count):
                tau = i / RATE
                window = pad_window(tau)
                if window <= 0.0:
                    continue
                tone = (math.sin(phase1) + 0.42 * math.sin(phase2) + 0.18 * math.sin(phase3))
                values[i] = tone * window * 0.085
                phase1 += d1
                phase2 += d2
                phase3 += d3
            wrap_add(int((start - 2.0) * RATE), values)


def render_bass():
    for bar in range(BARS):
        chord_index = int((bar * BAR) // 10.0) % len(CHORDS)
        root = CHORDS[chord_index][1][0] * 0.5
        for offset_beats in (0.0, 2.0):
            start = int((bar * BAR + offset_beats * BEAT) * RATE)
            count = int(RATE * 0.55)
            values = [0.0] * count
            phase = 0.0
            d = 2.0 * math.pi * root / RATE
            for i in range(count):
                t = i / RATE
                env = math.exp(-t * 7.0) * (1.0 - math.exp(-t * 240.0))
                values[i] = (math.sin(phase) + 0.22 * math.sin(phase * 2.0)) * env * 0.30
                phase += d
            wrap_add(start, values)


def render_kick():
    for bar in range(BARS):
        for offset_beats in (0.0, 2.0):
            start = int((bar * BAR + offset_beats * BEAT) * RATE)
            count = int(RATE * 0.20)
            values = [0.0] * count
            phase = 0.0
            for i in range(count):
                t = i / RATE
                freq = 92.0 - 46.0 * min(1.0, t / 0.10)
                phase += 2.0 * math.pi * freq / RATE
                env = math.exp(-t * 26.0)
                values[i] = math.sin(phase) * env * 0.34
            wrap_add(start, values)


def render_ticks():
    step = BEAT * 0.5
    total_steps = int(LOOP / step)
    for index in range(total_steps):
        if index % 8 in (0, 4):
            continue
        start = int(index * step * RATE)
        count = int(RATE * 0.028)
        values = [0.0] * count
        previous = 0.0
        for i in range(count):
            t = i / RATE
            noise = random.uniform(-1.0, 1.0)
            high = noise - previous
            previous = noise
            values[i] = high * math.exp(-t * 90.0) * 0.045
        wrap_add(start, values)


def main():
    render_pad()
    render_bass()
    render_kick()
    render_ticks()

    peak = max(abs(v) for v in buf) or 1.0
    target = 0.86
    scale = target / peak
    frames = bytearray()
    energy = 0.0
    for value in buf:
        sample = max(-1.0, min(1.0, value * scale))
        energy += sample * sample
        frames += struct.pack("<h", int(sample * 32767))

    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "bgm_loop.wav")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(bytes(frames))

    rms = math.sqrt(energy / N)
    print("wrote %s (%.1f s, peak %.2f, rms %.3f, %d bytes)" % (
        path, LOOP, target, rms, os.path.getsize(path)))


if __name__ == "__main__":
    main()
