"""程序化合成《迷失太空》专属科幻音效与复古音响循环节拍（纯 Python 标准库生成 WAV）"""

import math
import os
import random
import struct
import wave

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(REPO, "game", "assets", "audio", "rebuild")
SR = 22050


def save_wav(filename, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames.extend(struct.pack("<h", int(v * 32767.0)))
        wf.writeframes(bytes(frames))
    print(f"SFX {filename} ({len(samples)/SR:.2f}s)")


def gen_bounce():
    # 弹跳垫：厚重低音回弹 + 科幻上升滑音
    dur = 0.55
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        freq = 130.0 + 460.0 * (1.0 - math.exp(-t * 9.0)) + 28.0 * math.sin(t * 55.0)
        phase += 2.0 * math.pi * freq / SR
        env = math.exp(-t * 5.2) * min(1.0, t / 0.01)
        sub = math.sin(2.0 * math.pi * (85.0 * math.exp(-t * 4.0)) * t) * math.exp(-t * 9.0)
        out.append(0.55 * math.sin(phase) * env + 0.35 * sub)
    save_wav("sfx_bounce.wav", out)


def gen_boombox_loop():
    # 复古极地磁力音响：4 小节 120 BPM（8.0 秒无缝循环）太空迪斯科合成器节拍！
    bpm = 120.0
    beat_sec = 60.0 / bpm
    total_beats = 16
    dur = total_beats * beat_sec
    n = int(SR * dur)
    rng = random.Random(42)
    bass_notes = [110.0, 110.0, 146.83, 130.81]  # A2, A2, D3, C3
    arp_freqs = [440.0, 523.25, 659.25, 783.99, 659.25, 523.25, 587.33, 659.25]
    out = []
    for i in range(n):
        t = i / SR
        b = t / beat_sec
        step16 = int(b * 4.0)
        frac16 = (b * 4.0) - step16
        t16 = frac16 * (beat_sec / 4.0)
        bar = int(b // 4) % 4
        beat_in_bar = b % 4.0

        # 1. 四四拍底鼓 (Kick)
        kt = (b % 1.0) * beat_sec
        kick = math.sin(2.0 * math.pi * (50.0 + 110.0 * math.exp(-kt * 28.0)) * kt) * math.exp(-kt * 16.0) * 0.42

        # 2. 反拍清脆军鼓 (Snare on beats 1 and 3)
        snare = 0.0
        if int(beat_in_bar) in (1, 3):
            st = (beat_in_bar % 1.0) * beat_sec
            snare = (rng.uniform(-1.0, 1.0) * 0.7 + math.sin(2.0 * math.pi * 210.0 * st) * 0.3) * math.exp(-st * 26.0) * 0.24

        # 3. 16 分音符律动贝斯
        bf = bass_notes[bar] * (1.0 if (step16 % 2 == 0) else 2.0)
        bass_env = math.exp(-t16 * 12.0)
        bass = (0.65 * math.sin(2.0 * math.pi * bf * t) + 0.35 * math.sin(4.0 * math.pi * bf * t)) * bass_env * 0.25

        # 4. 明亮太空合成器琶音旋律
        af = arp_freqs[(step16 + bar * 2) % len(arp_freqs)]
        arp_env = math.exp(-t16 * 9.5) * (1.0 if step16 % 4 != 3 else 0.45)
        arp = (math.sin(2.0 * math.pi * af * t) + 0.3 * math.sin(6.0 * math.pi * af * t)) * arp_env * 0.16

        # 5. 高帽节拍 Hi-hat
        hat = rng.uniform(-1.0, 1.0) * math.exp(-t16 * 55.0) * (0.08 if step16 % 2 == 1 else 0.03)
        out.append((kick + snare + bass + arp + hat) * 0.85)
    save_wav("sfx_boombox_loop.wav", out)


def gen_thermos_sip():
    # 热可可：两口咕咚声 + 暖融融上升和弦提示
    dur = 0.75
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = 0.0
        for g_start in (0.04, 0.24):
            dt = t - g_start
            if 0.0 <= dt < 0.16:
                f = 220.0 + 280.0 * (dt / 0.16)
                s += math.sin(2.0 * math.pi * f * dt) * math.sin(math.pi * dt / 0.16) * 0.38
        if t > 0.36:
            dt = t - 0.36
            env = math.exp(-dt * 5.0) * min(1.0, dt / 0.02)
            s += (math.sin(2.0 * math.pi * 523.25 * dt) + 0.7 * math.sin(2.0 * math.pi * 659.25 * dt) + 0.5 * math.sin(2.0 * math.pi * 783.99 * dt)) * env * 0.22
        out.append(s)
    save_wav("sfx_thermos_sip.wav", out)


def gen_flare_ignite():
    # 极光信号弹：清脆打火咔哒 + 镁芯滋滋燃烧喷射声
    dur = 0.85
    n = int(SR * dur)
    rng = random.Random(7)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / SR
        click = math.sin(2.0 * math.pi * 1400.0 * t) * math.exp(-t * 85.0) * 0.55
        white = rng.uniform(-1.0, 1.0)
        hp = white - 0.82 * prev
        prev = white
        hiss_env = min(1.0, t / 0.06) * math.exp(-t * 2.2)
        out.append(click + hp * hiss_env * 0.32)
    save_wav("sfx_flare_ignite.wav", out)


def gen_orb_bounce():
    # 碰碰球：高弹性反重力“邦！”
    dur = 0.36
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 190.0 + 340.0 * math.exp(-t * 14.0)
        phase += 2.0 * math.pi * f / SR
        env = math.exp(-t * 9.5)
        out.append((math.sin(phase) * 0.7 + math.sin(phase * 2.0) * 0.25) * env * 0.65)
    save_wav("sfx_orb_bounce.wav", out)


def gen_explosion():
    # 低温燃料罐/无人机爆炸：厚重冲击低频 + 冰晶崩裂清脆高频
    dur = 1.05
    n = int(SR * dur)
    rng = random.Random(99)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        white = rng.uniform(-1.0, 1.0)
        lp = lp * 0.90 + white * 0.10
        boom = math.sin(2.0 * math.pi * (75.0 * math.exp(-t * 4.5) + 28.0) * t) * math.exp(-t * 4.2) * 0.55
        crackle = white * math.exp(-t * 12.0) * 0.25
        rumble = lp * math.exp(-t * 2.6) * 1.6
        out.append(max(-0.95, min(0.95, boom + crackle + rumble)))
    save_wav("sfx_explosion.wav", out)


def gen_lever_clunk():
    # 重型工业拉杆：厚重金属咔哒 + 清亮通电确认双音
    dur = 0.42
    n = int(SR * dur)
    rng = random.Random(13)
    out = []
    for i in range(n):
        t = i / SR
        clunk = (math.sin(2.0 * math.pi * 165.0 * t) + 0.5 * rng.uniform(-1.0, 1.0)) * math.exp(-t * 38.0) * 0.55
        chime = 0.0
        if t > 0.08:
            dt = t - 0.08
            f = 587.33 if dt < 0.09 else 880.0
            chime = math.sin(2.0 * math.pi * f * dt) * math.exp(-dt * 11.0) * 0.34
        out.append(clunk + chime)
    save_wav("sfx_lever_clunk.wav", out)


def gen_robot_chirp():
    # 呆萌科考小机器人开心问候：WALL-E 风格三连上扬电子啾啾声！
    dur = 0.56
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        if t < 0.16:
            f = 620.0 + 380.0 * (t / 0.16)
            env = math.sin(math.pi * t / 0.16)
        elif t < 0.22:
            f = 700.0
            env = 0.0
        elif t < 0.48:
            dt = t - 0.22
            f = 840.0 + 460.0 * (dt / 0.26) + 35.0 * math.sin(dt * 65.0)
            env = math.sin(math.pi * dt / 0.26)
        else:
            f = 800.0
            env = 0.0
        phase += 2.0 * math.pi * f / SR
        out.append((math.sin(phase) * 0.75 + math.sin(phase * 2.0) * 0.20) * env * 0.45)
    save_wav("sfx_robot_chirp.wav", out)


def gen_robot_bonk():
    # 小机器人被碰碰球撞到：委屈下滑“呜哇~”
    dur = 0.52
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 780.0 - 460.0 * (t / dur) + 32.0 * math.sin(t * 50.0)
        phase += 2.0 * math.pi * f / SR
        env = math.sin(math.pi * t / dur)
        out.append(math.sin(phase) * env * 0.45)
    save_wav("sfx_robot_bonk.wav", out)


def gen_polar_wind_loop():
    # 极地柔和呼啸风雪环境音（6 秒平滑无缝循环）
    dur = 6.0
    n = int(SR * dur)
    rng = random.Random(2026)
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    # 双级低通平滑成温暖低沉的极地风声
    lp1 = 0.0
    lp2 = 0.0
    out = []
    for i in range(n):
        t = i / SR
        lp1 = lp1 * 0.965 + raw[i] * 0.035
        lp2 = lp2 * 0.94 + lp1 * 0.06
        swell = 0.55 + 0.45 * math.sin(2.0 * math.pi * t / dur)
        whistle = math.sin(2.0 * math.pi * (240.0 + 65.0 * swell) * t) * 0.015 * swell
        out.append(max(-0.6, min(0.6, lp2 * 4.5 * swell + whistle)))
    # 淡入淡出衔接首尾避免循环咔哒声
    fade = int(SR * 0.25)
    for k in range(fade):
        w = k / fade
        out[k] = out[k] * w + out[n - fade + k] * (1.0 - w)
    save_wav("sfx_polar_wind_loop.wav", out)


if __name__ == "__main__":
    gen_bounce()
    gen_boombox_loop()
    gen_thermos_sip()
    gen_flare_ignite()
    gen_orb_bounce()
    gen_explosion()
    gen_lever_clunk()
    gen_robot_chirp()
    gen_robot_bonk()
    gen_polar_wind_loop()
    print("ALL 10 PROCEDURAL SFX GENERATED ->", OUT_DIR)
