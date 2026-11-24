"""ART-SAMPLE-002 · 2K 多尺度材质贴图（P1）

与 ART-SAMPLE-001 的 1024² 单层噪声的区别
----------------------------------------
1. **多尺度**：每个族至少三层频率（大形 20–60 周、中频 200–600 周、高频 2k+ 周），
   而不是一层噪声放大缩小；
2. **按族区分**：喷漆是"橘皮 + 起皮 + 划痕"，铸铁是"砂型麻点 + 气孔 + 轻微橘皮"，
   岩石是"解理沟 + 颗粒 + 崩落坑"，混凝土是"模板木纹 + 气孔 + 骨料"——
   **没有任何两个族用同一张噪声**；
3. **通道组织**：每族产出
   - `<族>_normal.png`（2048²，切线空间法线）
   - `<族>_rough.png`（2048²，粗糙度，独立空间变化）
   - `<族>_mask.png`（1024²，R=起皮/破损 G=粗糙度偏移 B=色差），供 shader 叠加
4. **显存**：法线与粗糙度在 Godot 里用 VRAM 压缩导入（见 04_MATERIAL_LIBRARY 的说明），
   2K×4 族 ≈ 44 MB，比 12 张未压缩 1K 还省。

运行：python tools/make_textures_2k.py
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
OUT = os.path.join(ROOT, "project", "assets", "textures", "aqs002")
S = 2048
SM = 1024          # 掩膜分辨率


# ------------------------------------------------------------------ 可平铺噪声
def _band(shape, beta, seed):
    rng = np.random.default_rng(seed)
    w = rng.standard_normal(shape)
    f = np.fft.rfft2(w)
    fy = np.fft.fftfreq(shape[0])[:, None]
    fx = np.fft.rfftfreq(shape[1])[None, :]
    r = np.sqrt(fx ** 2 + fy ** 2)
    r[0, 0] = 1e-6
    f *= 1.0 / (r ** beta)
    out = np.fft.irfft2(f, s=shape)
    out -= out.mean()
    return out / (out.std() + 1e-9)


def fbm(beta=1.8, octaves=5, seed=0, gain=0.55, size=S):
    total = np.zeros((size, size))
    amp, b = 1.0, beta
    for i in range(octaves):
        total += amp * _band((size, size), b, seed + i * 31)
        amp *= gain
        b = max(1.2, b - 0.35)
    return total / (octaves ** 0.5)


def lowfreq(scale, seed, size=S):
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((size, size))
    f = np.fft.rfft2(w)
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.rfftfreq(size)[None, :] * size
    r = np.sqrt(fx ** 2 + fy ** 2)
    f *= 1.0 / (1.0 + (r / float(scale)) ** 2)
    out = np.fft.irfft2(f, s=(size, size))
    out -= out.mean()
    return out / (out.std() + 1e-9)


def blobs(seed, count, rmin, rmax, soft=1.6, size=S):
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    for _ in range(count):
        cx, cy = rng.uniform(0, size, 2)
        r = rng.uniform(rmin, rmax)
        v = int(255 * rng.uniform(0.45, 1.0))
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d.ellipse([cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r], fill=v)
    img = img.filter(ImageFilter.GaussianBlur(soft))
    return np.asarray(img, dtype=np.float32) / 255.0


def lines(seed, count, width=(0.6, 2.2), length=(60, 420), curve=0.4,
          value=(90, 255), size=S):
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    for _ in range(count):
        x, y = rng.uniform(0, size, 2)
        ang = rng.uniform(0, 2 * math.pi)
        L = rng.uniform(*length)
        w = int(max(1, rng.uniform(*width)))
        v = int(rng.uniform(*value))
        pts = [(x, y)]
        steps = max(2, int(L / 24))
        for _k in range(steps):
            ang += rng.normal(0, curve)
            x += math.cos(ang) * L / steps
            y += math.sin(ang) * L / steps
            pts.append((x, y))
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d.line([(px + ox, py + oy) for px, py in pts], fill=v, width=w)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    return np.asarray(img, dtype=np.float32) / 255.0


def streaks(seed, count, size=S):
    """各向异性长条（岩石解理沟 / 混凝土模板纹）：沿 x 拉长的细线。"""
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    for _ in range(count):
        y = rng.uniform(0, size)
        x = rng.uniform(0, size)
        L = rng.uniform(size * 0.2, size)
        w = int(max(1, rng.uniform(1, 3)))
        v = int(rng.uniform(70, 190))
        wob = rng.uniform(2, 10)
        pts = []
        n = 8
        for i in range(n + 1):
            pts.append((x + L * i / n, y + math.sin(i * 0.9 + seed) * wob))
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d.line([(px + ox, py + oy) for px, py in pts], fill=v, width=w)
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    return np.asarray(img, dtype=np.float32) / 255.0


# ------------------------------------------------------------------ 工具
def normal_map(height, strength=1.0):
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    n = np.dstack((-dx * strength, -dy * strength, np.ones_like(height)))
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255.0).astype(np.uint8)


def norm01(a):
    a = a - a.min()
    m = a.max() - a.min()
    return (a - a.min()) / (m if m > 1e-9 else 1.0)


def down(a, size=SM):
    img = Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8), mode="L")
    return np.asarray(img.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0


def save_gray(name, a):
    Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8), mode="L").save(
        os.path.join(OUT, name))
    print("TEX %-26s gray" % name)


def save_rgb(name, a):
    img = np.clip(a, 0, 255)
    if img.ndim == 3:
        arr = img.astype(np.uint8)
    else:
        arr = np.dstack([np.clip(a * 255.0, 0, 255).astype(np.uint8)] * 3)
    Image.fromarray(arr, mode="RGB").save(os.path.join(OUT, name))
    print("TEX %-26s rgb" % name)


def save_mask(name, r, g, b):
    # 掩膜统一降到 1024²（法线 2K、掩膜 1K：掩膜是低频信息，不需要 2K 显存）
    r, g, b = down(r), down(g), down(b)
    a = np.dstack([np.clip(r * 255, 0, 255).astype(np.uint8),
                   np.clip(g * 255, 0, 255).astype(np.uint8),
                   np.clip(b * 255, 0, 255).astype(np.uint8)])
    Image.fromarray(a, mode="RGB").save(os.path.join(OUT, name))
    print("TEX %-26s mask" % name)


# ------------------------------------------------------------------ 四个族
def paint():
    """喷漆金属：橘皮（中频）+ 起皮（大斑块）+ 细划痕（高频）+ 落尘点。"""
    peel_m = lowfreq(120, 2101) * 0.6
    peel_s = lowfreq(420, 2102) * 0.4
    chip_big = blobs(2103, 90, 26, 90, soft=9.0)
    chip_small = blobs(2104, 420, 6, 22, soft=3.0)
    scr = lines(2105, 420, width=(0.6, 1.6), length=(60, 620), value=(60, 190))
    dust = blobs(2106, 700, 2, 6, soft=1.2)
    # 高度：橘皮为主，起皮处凹陷（漆掉了），划痕是浅沟
    h = norm01(peel_m * 0.55 + peel_s * 0.35 - chip_big * 0.55
               - chip_small * 0.25 - scr * 0.30 + dust * 0.10)
    save_rgb("paint_normal.png", normal_map(h, 2.0))
    rough = np.clip(0.46 + 0.12 * norm01(peel_m) + 0.16 * scr
                    - 0.05 * norm01(dust) + 0.10 * chip_big, 0.05, 1.0)
    save_gray("paint_rough.png", rough)
    save_mask("paint_mask.png",
              np.clip(chip_big * 1.1 + chip_small * 0.5, 0, 1),
              down(norm01(peel_s)),
              down(norm01(scr)))


def cast():
    """铸铁：砂型麻点（稀疏小坑）+ 微气孔 + 极轻橘皮（砂型本身有粒度）。"""
    pores = blobs(2201, 2600, 1.5, 5.0, soft=0.9)
    pits = blobs(2202, 900, 4.0, 16.0, soft=2.2)
    grain = lowfreq(700, 2203) * 0.5 + fbm(1.7, 5, 2204) * 0.5
    h = norm01(-pores * 0.85 - pits * 0.55 + grain * 0.35)
    save_rgb("cast_normal.png", normal_map(h, 2.6))
    save_gray("cast_rough.png", np.clip(0.62 + 0.22 * h, 0, 1))
    save_mask("cast_mask.png", down(norm01(pits)),
              down(norm01(grain)), down(norm01(pores)))


def rock():
    """岩石：解理沟（各向异性长条）+ 粒间起伏 + 崩落坑 + 细裂隙。"""
    cleav = streaks(2301, 220)
    cleav2 = streaks(2302, 90)
    grain = fbm(1.55, 6, 2303) * 0.55 + lowfreq(260, 2304) * 0.45
    pits = blobs(2305, 1400, 3, 18, soft=3.0)
    crack = lines(2306, 160, width=(0.8, 2.6), length=(120, 700), curve=0.55)
    h = norm01(cleav * 0.35 + cleav2 * 0.25 + grain * 0.45 - pits * 0.55 - crack * 0.45)
    save_rgb("rock_normal.png", normal_map(h, 2.2))
    save_gray("rock_rough.png", np.clip(0.84 + 0.12 * h - 0.06 * pits, 0.4, 1.0))
    save_mask("rock_mask.png", down(norm01(crack)),
              down(norm01(grain)), down(norm01(cleav)))


def concrete():
    """混凝土：模板木纹（长条）+ 气孔（密集小坑）+ 骨料（中尺度凸起）+ 砂浆脱落斑。"""
    board = streaks(2401, 120)
    fibre = lowfreq(900, 2402) * 0.5
    pores = blobs(2403, 3000, 1.2, 4.5, soft=0.8)
    aggregate = blobs(2404, 420, 10, 30, soft=4.0)
    spall = blobs(2405, 40, 40, 120, soft=14.0)
    h = norm01(board * 0.30 + fibre * 0.30 + aggregate * 0.45
               - pores * 0.75 - spall * 0.40)
    save_rgb("conc_normal.png", normal_map(h, 1.9))
    save_gray("conc_rough.png", np.clip(0.80 + 0.14 * h - 0.08 * norm01(aggregate), 0.4, 1.0))
    save_mask("conc_mask.png", down(norm01(spall)),
              down(norm01(pores)), down(norm01(aggregate)))


def machined():
    """机加工面：单向刀纹（低频波纹 + 高频细纹）+ 少量划痕。"""
    ys = np.mgrid[0:S, 0:S][0].astype(np.float32)
    warp = lowfreq(24, 2501)
    a = 0.5 + 0.5 * np.sin(ys * (2 * math.pi * 420.0 / S) + warp * 2.2)
    b = 0.5 + 0.5 * np.sin(ys * (2 * math.pi * 1180.0 / S) + warp * 4.6)
    scr = lines(2502, 120, width=(0.6, 1.4), length=(80, 400))
    h = norm01(a * 0.55 + b * 0.25 + scr * 0.2 + lowfreq(120, 2503) * 0.3)
    save_rgb("mach_normal.png", normal_map(h, 1.1))
    save_gray("mach_rough.png", np.clip(0.24 + 0.22 * h, 0.05, 1.0))
    save_mask("mach_mask.png", down(norm01(scr)), down(norm01(h)), down(norm01(a)))


def main():
    os.makedirs(OUT, exist_ok=True)
    paint()
    cast()
    rock()
    concrete()
    machined()
    print("TEXTURES_2K_OK ->", OUT)


main()



