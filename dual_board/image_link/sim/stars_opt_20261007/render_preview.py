"""Diagnostic rendering of the FPGA integer equations, not a hardware capture."""
from pathlib import Path
import subprocess
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE / 'software_preview'
OUT.mkdir(exist_ok=True)
assets = HERE.parents[1] / 'assets/relax_panorama_20261007'
left = Image.open(assets / 'relax_A_left_640x480.png').convert('RGB')
right = Image.open(assets / 'relax_B_right_640x480.png').convert('RGB')
assert left.size == right.size == (640, 480)
base = np.concatenate([np.asarray(left, dtype=np.int16), np.asarray(right, dtype=np.int16)], axis=1)
FFMPEG = r'C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe'
bx = np.array([43,53,40,47,56,39,50,44,54,48])
by = np.array([55,92,38,76,64,26,88,50,104,68])
seed = np.array([16,107,50,185,224,141,84,12,172,61])
point = np.arange(6)[None,:]
offset = np.array([0,683,1365,2048,2731,3413])[None,:]
lane = np.arange(10)[:,None]
size = np.where((lane % 3 == 0) & (point % 3 == 0), 2,
                np.where((lane % 3 != 0) & (point % 3 == 1), 1, 0))
assert dict(zip(*np.unique(size, return_counts=True))) == {0:40,1:12,2:8}

def ease(value):
    value = np.asarray(value) % 4096
    t = np.where(value >= 2048, 4095-value, value)
    part, r = t//512, t%512
    return np.select([part==0,part==1,part==2], [r//4,128+r*3//4,512+r*3//4], default=896+r//4)

def frame(phase):
    if phase >= 20480:
        phase = 0
    fast = (phase % 4096)*4
    px = np.where(point%3==0,bx[:,None],np.where(point%3==1,120-bx[:,None],bx[:,None]+25))
    cx = (px-16)*4 + ease(fast+seed[:,None]*16+point*512)//8
    cy = (by[:,None]+point*64-16)*4 + ease(fast//2+(seed[:,None]^147)*16+offset)//8
    breath = ease(np.where(size==2,(fast%1024)*4,(fast%2048)*2)+seed[:,None]*16+offset)
    amp = np.where(size==2,80+breath//8,np.where(size==1,32+breath//16,12+breath//32))
    delta = np.abs(np.arange(480)[:,None,None]*4-cy[None,:,:])
    near = np.argmin(delta,axis=2)
    rows, lanes = np.indices((480,10))
    distance = np.minimum(delta[rows,lanes,near],255)
    xpos, amps, scales = cx[lanes,near],amp[lanes,near],size[lanes,near]
    world = (np.arange(1280)*16-int(ease(phase%4096))*3)%20480
    selected = world//2048
    dx = np.abs(world[None,:]%2048//4-xpos[:,selected]) >> scales[:,selected]
    dy = distance[:,selected] >> scales[:,selected]
    radius = np.maximum(dx,dy)+np.minimum(dx,dy)//2
    core = np.maximum(0,amps[:,selected]-radius*16)
    halo = np.maximum(0,amps[:,selected]-radius*6)//8
    light = np.where((dx<64)&(dy<64)&(radius<32),core+halo,0)
    rgb = np.stack([light-light//16,light,np.where(radius<=2,light-light//4,light//16)],axis=2)
    return np.clip(base+rgb,0,255).astype(np.uint8)

assert np.array_equal(frame(0),frame(4096))
assert np.array_equal(frame(0),frame(16384))
for seconds in [0,2,4,8,16,32]:
    Image.fromarray(frame(seconds*128)).save(OUT/f'preview_{seconds:02d}s.png')
video = OUT/'stars60_dual_screen_12s.mp4'
if video.exists():
    raise FileExistsError(video)
process = subprocess.Popen([FFMPEG,'-hide_banner','-loglevel','error','-nostdin','-n',
    '-f','rawvideo','-pixel_format','rgb24','-video_size','1280x480','-framerate','30',
    '-i','pipe:0','-an','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p',str(video)],stdin=subprocess.PIPE)
try:
    for i in range(360):
        process.stdin.write(frame(i*128//30).tobytes())
    process.stdin.close()
    if process.wait()!=0:
        raise RuntimeError('Preview encoding failed')
finally:
    if process.poll() is None:
        process.terminate()
print(f'Software equations only,60 stars,4x speed,A left/B right:{video}')
