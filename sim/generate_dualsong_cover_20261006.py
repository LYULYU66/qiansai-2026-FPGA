"""Encode supplied cover as a tiny HDL bitmap, output edits through apply_patch."""
from pathlib import Path
from PIL import Image
import hashlib,json
ROOT=Path(__file__).resolve().parent.parent
SOURCE=Path('C:/Users/28492/AppData/Local/Temp/codex-clipboard-73decd47-a4a6-4fcd-8fab-7f15e4118ef5.png')
DEST='dual_board/image_link/rtl/dualsong_20261005/song2_cover_rom.v'
assert not (ROOT/DEST).exists()
img=Image.open(SOURCE).convert('RGB')
side=min(img.size);left=(img.width-side)//2;top=(img.height-side)//2
img=img.crop((left,top,left+side,top+side)).resize((40,40),Image.Resampling.LANCZOS)
q=img.quantize(colors=15,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
pal=q.getpalette();palette=[0xffffff]+[(pal[i*3]<<16)|(pal[i*3+1]<<8)|pal[i*3+2] for i in range(15)]
pixels=[]
for y in range(40):
    for x in range(40):
        pixels.append(q.getpixel((x,y))+1 if (2*x-39)**2+(2*y-39)**2<=40**2 else 0)
words=[sum(pixels[i+j]<<(j*4) for j in range(4)) for i in range(0,1600,4)]
hdl=['// Supplied cover, 40x40 circular crop, 15 colors + white. One 512x16 BRAM.',
 'module song2_cover_rom(input I_clk,input [8:0] I_addr,output reg [15:0] O_word);',
 'reg [15:0] rom[0:511]; /* fehdl force_ram=1, ram_style="bram" */',
 'integer n; initial begin for(n=0;n<512;n=n+1)rom[n]=0;']
hdl += [f"rom[{i}]=16'h{w:04x};" for i,w in enumerate(words)]
hdl += ['end','always @(posedge I_clk)O_word<=rom[I_addr];','endmodule',
 'module song2_cover_palette(input [3:0] I_index,output reg [23:0] O_rgb);',
 'always @(*)case(I_index)']
hdl += [f"4'd{i}:O_rgb=24'h{c:06x};" for i,c in enumerate(palette)]
hdl += ["default:O_rgb=24'hffffff;",'endcase','endmodule']
manifest={'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
 'format':'40x40 4-bit palette, white circular exterior, 512x16 RAM','palette_rgb':palette,
 'expected_rgb':[palette[i] for i in pixels]}
files={DEST:'\n'.join(hdl)+'\n','assets/lyrics/dualsong_20261005/cover_manifest.json':json.dumps(manifest,ensure_ascii=False,indent=2)+'\n'}
print('*** Begin Patch')
for path,contents in files.items():
    print('*** Add File: '+path)
    for line in contents.splitlines():print('+'+line)
for board in 'ab':
    folder=f'dual_board/image_link/prj/dualsong_{board}_20261005'
    path=next((ROOT/folder).glob('*.al'));old=path.read_text(encoding='utf-8')
    new=old.replace('/dualsong_20261005/lyric_song_data.v','/dualsong_20261005/dual_lyric_song_data.v')
    if board=='a':
        modules=['video_song_cover_overlay.v','song2_cover_rom.v']
        insertion='\n'.join(f'            <File Path="{(ROOT/"dual_board/image_link/rtl/dualsong_20261005"/name).as_posix()}"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/></FileInfo></File>' for name in modules)
        new=new.replace('</Verilog>',insertion+'\n        </Verilog>')
    print('*** Update File: '+path.relative_to(ROOT).as_posix())
    print('@@')
    for line in old.splitlines():print('-'+line)
    for line in new.splitlines():print('+'+line)
print('*** End Patch')
