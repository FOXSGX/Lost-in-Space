"""生成奶龙星试玩用的短音效（纯 stdlib，无第三方素材）。

音色全部由正弦/噪声合成，来源为本仓库脚本，可直接复现：
    python make_sfx.py <输出目录>

输出：22050 Hz / 单声道 / 16-bit PCM WAV。
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


def notice(t, total):
    freq = 340.0 + 260.0 * (t / total) ** 0.7
    env = envelope(t, total, 0.008, 0.09)
    return 0.42 * env * math.sin(2 * math.pi * freq * t)


def windup(t, total):
    freq = 110.0 + 130.0 * (t / total)
    trem = 0.6 + 0.4 * math.sin(2 * math.pi * 11.0 * t)
    env = envelope(t, total, 0.05, 0.18)
    return 0.34 * env * trem * math.sin(2 * math.pi * freq * t)


def release(t, total):
    # 气流噪声 + 下滑音，模拟“张嘴、货飞出去”
    noise = random.uniform(-1.0, 1.0) * max(0.0, 1.0 - t / total) ** 2
    freq = 520.0 - 300.0 * (t / total)
    env = envelope(t, total, 0.004, 0.20)
    return 0.30 * env * (0.75 * noise + 0.55 * math.sin(2 * math.pi * freq * t))


def loaded(t, total):
    # 两声上行提示音，明确“入仓确认”
    first = math.sin(2 * math.pi * 660.0 * t) if t < 0.13 else 0.0
    second = math.sin(2 * math.pi * 990.0 * max(0.0, t - 0.13)) if t >= 0.13 else 0.0
    env = envelope(t, total, 0.006, 0.16)
    return 0.26 * env * (first + second)


def chomp(t, total):
    noise = random.uniform(-1.0, 1.0)
    env = math.exp(-t * 26.0)
    return 0.30 * env * (0.6 * noise + 0.7 * math.sin(2 * math.pi * 150.0 * t))


OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)
random.seed(20261029)
make("dragon_notice.wav", 0.20, notice)
make("dragon_windup.wav", 0.55, windup)
make("fuel_release.wav", 0.40, release)
make("fuel_loaded.wav", 0.45, loaded)
make("dragon_chomp.wav", 0.18, chomp)
