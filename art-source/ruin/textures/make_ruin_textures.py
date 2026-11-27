"""腐墟星 · bio（菌群）2K 材质家族生成器。

与 ART-SAMPLE-002 的 make_textures_2k.py 同一套算法语言（FFT 粉红噪声 + 环形绕边绘制），
但只生成腐墟星需要的 bio 家族，且四个通道语义按《美术制作与 AI 协作指南》方法二：

    2048²  bio_normal.png   菌盖分节、同心生长纹、湿润脉络、孔蚀
    2048²  bio_rough.png    干菌膜（0.55–0.75）与湿润脉络（0.15）的粗糙度差
    1024²  bio_mask.png     R=菌膜剥落  G=粗糙度偏移  B=色差

运行：
    <bundled python> art-source/ruin/textures/make_ruin_textures.py

注意：这是项目内自有算法实现，不修改 art-source/third-party 里的 ART-SAMPLE-002 原件。
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "game", "assets", "ruin", "textures")

S = 2048
SM = 1024


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


def blobs(seed, count, rmin, rmax, soft=1.6, size=S, value=(0.45, 1.0)):
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    for _ in range(count):
        cx, cy = rng.uniform(0, size, 2)
        r = rng.uniform(rmin, rmax)
        v = int(255 * rng.uniform(*value))
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


def normal_map(height, strength=1.0):
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    n = np.dstack((-dx * strength, -dy * strength, np.ones_like(height)))
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255.0).astype(np.uint8)


def norm01(a):
    a = a - a.min()
    m = a.max() - a.min()
    return a / (m if m > 1e-9 else 1.0)


def down(a, size=SM):
    img = Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8), mode="L")
    return np.asarray(img.resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0


def save_gray(name, a):
    Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8), mode="L").save(
        os.path.join(OUT, name))
    print("TEX %-26s gray" % name)


def save_rgb(name, a):
    arr = np.clip(a, 0, 255).astype(np.uint8)
    Image.fromarray(arr, mode="RGB").save(os.path.join(OUT, name))
    print("TEX %-26s rgb" % name)


def save_mask(name, r, g, b):
    r, g, b = down(r), down(g), down(b)
    arr = np.dstack([np.clip(r * 255, 0, 255).astype(np.uint8),
                     np.clip(g * 255, 0, 255).astype(np.uint8),
                     np.clip(b * 255, 0, 255).astype(np.uint8)])
    Image.fromarray(arr, mode="RGB").save(os.path.join(OUT, name))
    print("TEX %-26s mask" % name)


def bio():
    """菌群：大菌落 → 同心生长纹 → 湿润脉络 → 孔蚀。

    同心纹不是贴图上的圆环，而是把低频菌落场做正弦调制：
    沿菌落梯度出现一圈圈生长脊，天然跟着菌落形状走，不会读成水波纹。
    """
    colony = blobs(3101, 26, 90, 260, soft=26.0)
    colony2 = blobs(3102, 120, 24, 80, soft=10.0)
    field = norm01(lowfreq(46, 3103)) * 0.55 + norm01(lowfreq(120, 3104)) * 0.45
    rings = 0.5 + 0.5 * np.sin((field * 18.0 + colony * 5.0) * math.pi)
    veins = lines(3105, 210, width=(1.0, 3.2), length=(120, 700), curve=0.62,
                  value=(80, 210))
    pores = blobs(3106, 2400, 1.6, 5.5, soft=1.0)
    wet = blobs(3107, 34, 70, 220, soft=30.0)
    peel = blobs(3108, 70, 24, 100, soft=8.0)

    h = norm01(colony * 0.55 + colony2 * 0.25 + rings * 0.22
               + veins * 0.30 - pores * 0.70 - peel * 0.35)
    save_rgb("bio_normal.png", normal_map(h, 2.3))

    rough = np.clip(0.62 + 0.16 * norm01(rings) + 0.10 * norm01(pores)
                    - 0.40 * wet + 0.08 * peel, 0.12, 0.95)
    save_gray("bio_rough.png", rough)

    save_mask("bio_mask.png",
              np.clip(peel * 1.15 + pores * 0.35, 0, 1),
              np.clip(norm01(veins) * 0.85 + norm01(pores) * 0.5, 0, 1),
              np.clip(norm01(colony * 0.6 + rings * 0.4), 0, 1))


def main():
    os.makedirs(OUT, exist_ok=True)
    bio()
    print("RUIN_BIO_TEXTURES_OK ->", OUT)


if __name__ == "__main__":
    main()
