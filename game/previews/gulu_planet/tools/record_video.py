"""把连续截图合成为 MP4（可选 GIF）。

用法:
    python tools/record_video.py <帧目录> <输出 mp4> [fps]

帧目录一般来自 Godot 的 Movie Maker：
    godot --path . --write-movie <帧目录>/k.png --fixed-fps 30 -- --record
它会输出 k00000000.png、k00000001.png ……（30 FPS、1280×800）。
也兼容旧版 `--record` 写出的 f0000.png 序列。

本脚本只用本地 ffmpeg（imageio-ffmpeg 提供）与 Pillow，不上传任何东西。
"""
import glob
import os
import re
import subprocess
import sys


def ffmpeg_exe() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        pass
    local = os.path.join(os.path.dirname(__file__), "ffmpeg.exe")
    if os.path.exists(local):
        return local
    raise SystemExit("找不到 ffmpeg：pip install imageio-ffmpeg 或把 ffmpeg.exe 放在 tools/ 下")


def frame_pattern(frames_dir: str) -> str:
    """从第一张 PNG 推出 printf 模式，例如 k00000000.png -> k%08d.png。"""
    files = sorted(glob.glob(os.path.join(frames_dir, "*.png")))
    if not files:
        raise SystemExit("帧目录里没有 png：%s" % frames_dir)
    name = os.path.basename(files[0])
    match = re.match(r"^(.*?)(\d+)\.png$", name)
    if not match:
        raise SystemExit("帧文件名不含序号，无法推断模式：%s" % name)
    prefix, digits = match.group(1), match.group(2)
    return prefix + "%0" + str(len(digits)) + "d.png", len(files)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    frames_dir = sys.argv[1]
    out_mp4 = sys.argv[2]
    fps = int(sys.argv[3]) if len(sys.argv) > 3 else 30

    pattern, count = frame_pattern(frames_dir)
    print("frames=%d pattern=%s fps=%d" % (count, pattern, fps))

    cmd = [
        ffmpeg_exe(), "-y", "-loglevel", "error",
        "-framerate", str(fps),
        "-i", os.path.join(frames_dir, pattern),
        "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        out_mp4,
    ]
    subprocess.run(cmd, check=True)
    print("wrote %s (%.1f MB)" % (out_mp4, os.path.getsize(out_mp4) / 1048576.0))

    # GIF 只在小尺寸/低帧率时才划算，这里不默认生成，避免几十 MB 的附件。
    try:
        from PIL import Image
        out_gif = os.path.splitext(out_mp4)[0] + ".gif"
        probe = Image.open(sorted(glob.glob(os.path.join(frames_dir, "*.png")))[0])
        if probe.width <= 720 and fps <= 15:
            images = [Image.open(p).convert("RGB")
                      for p in sorted(glob.glob(os.path.join(frames_dir, "*.png")))]
            images[0].save(out_gif, save_all=True, append_images=images[1:],
                           duration=int(1000 / fps), loop=0, optimize=True)
            print("wrote %s (%.1f MB)" % (out_gif, os.path.getsize(out_gif) / 1048576.0))
    except Exception as error:
        print("gif skipped: %s" % error)


if __name__ == "__main__":
    main()
