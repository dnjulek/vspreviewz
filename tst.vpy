import vapoursynth as vs
from vapoursynth import core

source = core.std.BlankClip(width=1920, height=1080, color=(0, 255, 0), format=vs.YUV420P8, length=1000, fpsnum=24000, fpsden=1001)
source.text.FrameNum().set_output(0)

# src = core.lsmas.LWLibavSource(r"C:\Users\dnjul\Downloads\ok-[smol] Kizumonogatari (BD 1080p HEVC Opus)\[smol] Monogatari - 9x02 - Kizumonogatari - Nekketsu-hen.mkv")
# src.set_output(0)