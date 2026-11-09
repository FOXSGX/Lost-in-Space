"""把 `--record` 产生的连续截图合成为 MP4 / GIF。

用法:
    python tools/record_video.py <帧目录> <输出 mp4 路径>

帧来自 `godot --path . -- --record`，写入 user://gulu_record/f0000.png...
本脚本只用本地已有的 ffmpeg（通过 imageio-ffmpeg 提供）与 Pillow，不上传任何东西。
"""
import glob
import os
import subprocess
import sys

FPS = 8
SCALE = "960:600"


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


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    frames_dir = sys.argv[1]
    out_mp4 = sys.argv[2] if len(sys.argv) > 2 else os.path.join(frames_dir, "clip.mp4")

    frames = sorted(glob.glob(os.path.join(frames_dir, "f*.png")))
    if not frames:
        raise SystemExit("帧目录里没有 f*.png：%s" % frames_dir)
    print("frames=%d" % len(frames))

    cmd = [
        ffmpeg_exe(), "-y", "-loglevel", "error",
        "-framerate", str(FPS),
        "-i", os.path.join(frames_dir, "f%04d.png"),
        "-vf", "scale=%s:flags=lanczos" % SCALE,
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        out_mp4,
    ]
    subprocess.run(cmd, check=True)
    print("wrote %s (%.1f KB)" % (out_mp4, os.path.getsize(out_mp4) / 1024.0))

    # 同时出一份 GIF，方便直接贴到聊天/文档里预览
    try:
        from PIL import Image
        out_gif = os.path.splitext(out_mp4)[0] + ".gif"
        images = [Image.open(path).convert("RGB") for path in frames]
        images[0].save(out_gif, save_all=True, append_images=images[1:],
                       duration=int(1000 / FPS), loop=0, optimize=True)
        print("wrote %s (%.1f KB)" % (out_gif, os.path.getsize(out_gif) / 1024.0))
    except Exception as error:  # GIF 只是附赠，失败不影响 MP4
        print("gif skipped: %s" % error)


if __name__ == "__main__":
    main()
