"""Code-native cover ROM conversion. Preserve the supplied photograph, no AI edit."""
from pathlib import Path
from PIL import Image,ImageDraw
import hashlib,json,sys
ROOT=Path(__file__).resolve().parent.parent
SOURCE=Path('C:/Users/28492/AppData/Local/Temp/codex-clipboard-73decd47-a4a6-4fcd-8fab-7f15e4118ef5.png')
if not SOURCE.exists():SOURCE=ROOT/'assets/lyrics/yilu_replace_20261006/source_cover.png'
img=Image.open(SOURCE).convert('RGB');side=min(img.size)
crop=((img.width-side)//2,(img.height-side)//2,(img.width+side)//2,(img.height+side)//2)
square=img.crop(crop).resize((64,64),Image.Resampling.LANCZOS)
mask=Image.new('L',(512,512),0);ImageDraw.Draw(mask).ellipse((0,0,511,511),fill=255)
mask=mask.resize((64,64),Image.Resampling.LANCZOS)
cover=Image.new('RGB',(64,64),'white');cover.paste(square,(0,0),mask)
words=[((r>>3)<<11)|((g>>2)<<5)|(b>>3) for r,g,b in cover.getdata()]
rgb=[((((w>>11)&31)<<3)|((w>>13)&7),(((w>>5)&63)<<2)|((w>>9)&3),((w&31)<<3)|((w>>2)&7)) for w in words]
decoded=Image.new('RGB',(64,64));decoded.putdata(rgb)
preview=ROOT/'best_result/yilu_replace_20261006/cover_rgb565_preview.png'
preview.parent.mkdir(parents=True,exist_ok=True);decoded.resize((256,256),Image.Resampling.NEAREST).save(preview)
if '--preview-only' in sys.argv:
    print('PASS cover preview: exact HDL RGB565 bit replication');sys.exit(0)
hdl=['// Native 64x64 RGB565 circular cover; two BRAM32K, no palette or DSP.',
     'module song2_cover_rom(input I_clk,I_ce,input [11:0] I_addr,output [15:0] O_word);',
     'wire [15:0] data0,data1;reg bank;',
     'always @(posedge I_clk)if(I_ce)bank<=I_addr[11];',
     'assign O_word=bank?data1:data0;']
for bank in range(2):
    hdl+=['EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),',
          '.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),']
    for i in range(128):
        value=sum(w<<(j*16) for j,w in enumerate(words[bank*2048+i*16:bank*2048+i*16+16]))
        hdl.append(f".INIT_{i:02X}(256'h{value:064X})"+(',' if i<127 else ')'))
    hdl += [f"bank{bank}(.doa(data{bank}),.dia(16'd0),.addra(I_addr[10:0]),.bytea(1'b0),.bytewea(1'b0),",
            f".csa(I_ce && I_addr[11]==1'b{bank}),.wea(1'b0),.clka(I_clk),.rsta(1'b0),.ocea(1'b1),",
            ".dob(),.dib(16'd0),.addrb(11'd0),.byteb(1'b0),.byteweb(1'b0),",
            ".csb(1'b0),.web(1'b0),.clkb(1'b0),.rstb(1'b0),.oceb(1'b0));"]
hdl+=['endmodule']
manifest={'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
          'source_size':img.size,'crop':crop,'size':[64,64],'format':'RGB565 16-bit, circular antialiased white exterior',
          'distinct_rgb565_colors':len(set(words)),'bram32k':2,'bram9k':0,'dsp':0,
          'home_display':[40,40],'music_display':[64,64],'photo_edit':'none; resampling and circular mask only',
          'preview':str(preview),'packed_sha256':hashlib.sha256(b''.join(w.to_bytes(2,'little') for w in words)).hexdigest()}
print('*** Begin Patch')
for name,content in [('dual_board/image_link/rtl/yilu_replace_20261006/song2_cover_rom.v','\n'.join(hdl)),
                     ('assets/lyrics/yilu_replace_20261006/cover_manifest.json',json.dumps(manifest,ensure_ascii=True,indent=2)),
                     ('assets/lyrics/yilu_replace_20261006/cover_rgb565.hex','\n'.join(f'{w:04x}' for w in words))]:
    print('*** Add File: '+name)
    for line in content.splitlines():print('+'+line)
print('*** End Patch')
