"""Software reference preview, not hardware capture. Actual indexed car/FPGA equations."""
from pathlib import Path
from PIL import Image
import json,numpy as np,subprocess
ROOT=Path(__file__).resolve().parents[4]
ASSET=ROOT/'dual_board/image_link/assets/car_intro_20261007'
OUT=Path(__file__).resolve().parent/'software_preview'
OUT.mkdir(exist_ok=True)
meta=json.loads((ASSET/'packing.json').read_text())
indices=np.frombuffer((ASSET/'sprite_indices.bin').read_bytes(),dtype=np.uint8).reshape(96,256)
palette=np.array(meta['colors'],dtype=np.int32)
base=np.array(Image.open(ROOT/'dual_board/image_link/assets/instrument_background_20261006/instrument_background_640x480.png').convert('RGB'),dtype=np.int32)
yy,xx=np.indices((480,640));dx=abs(xx-320);dy=abs(yy-457)*16
radius=np.maximum(dx,dy)+np.minimum(dx,dy)//2
def frame(age,pulse):
    rgb=base.copy();reach=(age+1)*8 if age<16 else 128
    breath=pulse if pulse<64 else 127-pulse
    glow=np.where(radius+6>=reach,92,np.where(radius+16>=reach,48,12+breath//4))
    hit=(xx>=176)&(xx<464)&(yy>=443)&(yy<473)&(radius<=reach)
    ground=np.stack((glow//8,glow//2,glow),axis=-1)
    rgb=np.minimum(255,rgb+ground*hit[:,:,None])
    alpha=0 if age<16 else (16 if age>=144 else (age-16)//8)
    if alpha:
        lift=max(0,12-alpha);top=368+lift
        sprite=palette[indices].copy()
        separation=np.abs(np.arange(256)-((age%64)*4))
        shine=np.where(separation<2,72,np.where(separation<4,40,np.where(separation<8,16,0))) if 64<=age<128 else np.zeros(256,dtype=np.int32)
        sprite=np.minimum(255,sprite+np.stack((shine//2,shine,shine),axis=-1)[None,:,:])
        area=rgb[top:top+96,192:448]
        result=(area*(16-alpha)+sprite*alpha+8)//16
        area[indices!=0]=result[indices!=0]
    return rgb.astype(np.uint8)
ff='C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe'
proc=subprocess.Popen([ff,'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','640x480','-r','30','-i','pipe:0','-an','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/'car_intro_5s.mp4')],stdin=subprocess.PIPE)
for n in range(150):
    ticks=int(n*(25_000_000/(800*525))/30)+1
    im=frame(min(191,ticks),ticks%128)
    proc.stdin.write(im.tobytes())
    if n in (9,36,60,99):Image.fromarray(im).save(OUT/f'preview_{n:03}.png')
proc.stdin.close()
assert proc.wait()==0,'ffmpeg failed'
print('Generated car_intro_5s.mp4 and4 frame previews; indexed256x96 car, not hardware capture')
