"""生成奶龙星射门试玩用的短音效（纯 stdlib，无第三方素材）。

音色全部由正弦/噪声合成，来源为本仓库脚本，可直接复现：
    python make_sfx.py <输出目录>

输出：22050 Hz / 单声道 / 16-bit PCM WAV。
本轮只保留三个：踢球、拦球、入仓确认。
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050


def envelope(t, total, attack=0.01, release=0.12):
    if t < attack:
        return t / attack
    if t > total - release:
        return max(0.0, (total - t) / release)
    return 1.0


def make(name, seconds, fn):
    frames = bytearray()
    total = seconds
    for i in range(int(RATE * seconds)):
        t = i / RATE
        value = fn(t, total)
        value = max(-1.0, min(1.0, value))
        frames += struct.pack("<h", int(value * 32000))
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(bytes(frames))
    print("wrote %s (%d bytes)" % (path, os.path.getsize(path)))


def ball_kick(t, total):
    # 踢球：低频“咚” + 鞋面摩擦的短噪声，0.16 s 内收干净
    thump = math.sin(2 * math.pi * (95.0 - 30.0 * (t / total)) * t)
    click = random.uniform(-1.0, 1.0) * max(0.0, 1.0 - t / 0.03)
    env = envelope(t, total, 0.002, 0.08)
    return 0.46 * env * (0.9 * thump + 0.5 * click)


def dragon_block(t, total):
    # 拦球：更低更闷的一记，加一点身体摩擦
    thud = math.sin(2 * math.pi * (150.0 - 60.0 * (t / total)) * t)
    rustle = random.uniform(-1.0, 1.0) * 0.35 * max(0.0, 1.0 - t / total)
    env = envelope(t, total, 0.004, 0.12)
    return 0.34 * env * (0.8 * thud + rustle)


def loaded(t, total):
    # 入仓确认：两声上行提示音
    first = math.sin(2 * math.pi * 660.0 * t) if t < 0.13 else 0.0
    second = math.sin(2 * math.pi * 990.0 * max(0.0, t - 0.13)) if t >= 0.13 else 0.0
    env = envelope(t, total, 0.006, 0.16)
    return 0.26 * env * (first + second)


OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)
random.seed(20261110)
make("ball_kick.wav", 0.16, ball_kick)
make("dragon_block.wav", 0.24, dragon_block)
make("fuel_loaded.wav", 0.45, loaded)
