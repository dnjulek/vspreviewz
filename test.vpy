import vapoursynth as vs
from vapoursynth import core
from vstools import set_output

s1 = core.std.BlankClip(width=1920, height=1080, color=(40, 0, 180), format=vs.YUV420P8, length=1000).text.FrameNum()#.set_output(0)
s2 = core.std.BlankClip(width=1920, height=1080, color=(40, 180, 0), format=vs.YUV420P8, length=1000).text.FrameNum()#.set_output(3)
s3 = core.std.BlankClip(width=1920, height=1080, color=(0, 180, 40), format=vs.YUV420P8, length=1000).text.FrameNum()#.set_output(4)


set_output(s1, "ss1")
set_output(s2, "ss2")
set_output(s3, "ss3")
 