"""Offline format packing of the generated transparent sprite; no new art.
PNG/binary outputs are mechanical; Verilog/test constants emitted as apply_patch.
"""
from pathlib import Path
from PIL import Image
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
source=HERE/'car_master.png'
im=Image.open(source).convert('RGBA')
box=im.getchannel('A').getbbox()
assert box,'Missing transparent cutout'
im=im.crop(box)
im.thumbnail((248,88),Image.Resampling.LANCZOS)
canvas=Image.new('RGBA',(256,96))
canvas.alpha_composite(im,((256-im.width)//2,(96-im.height)//2))
canvas.save(HERE/'car_native256x96.png')
# 15 opaque colours + index0 transparent. Full-size, no runtime resampling.
quant=canvas.convert('RGB').quantize(colors=15,method=Image.Quantize.MEDIANCUT)
pal=quant.getpalette();colors=[(0,0,0)]+[tuple(pal[3*i:3*i+3]) for i in range(15)]
pixels=bytes(0 if a<96 else q+1 for a,q in zip(canvas.getchannel('A').get_flattened_data(),quant.get_flattened_data()))
assert len(pixels)==24576 and max(pixels)<=15
(HERE/'sprite_indices.bin').write_bytes(pixels)
preview=Image.new('RGBA',(256,96));preview.putdata([(*colors[i],255 if i else 0) for i in pixels]);preview.save(HERE/'car_indexed256x96.png')
words=[sum(pixels[a+i]<<(4*i) for i in range(4)) for a in range(0,len(pixels),4)]
lines=['// Generated from car_master.png:256x96,16-colour indexed with index0 transparent.',
'// Three native32K ROMs. Source pixels/nibble order checked in ModelSim.',
'module car_intro_rom(input wire clk,enable,input wire [14:0] address,output wire [3:0] index,output reg [23:0] rgb);',
'wire [15:0] q[0:2];reg [1:0] bank,nibble;reg [15:0] word_q;',
'always @(posedge clk)if(enable)begin bank<=address[14:13];nibble<=address[1:0];end',
"always @* begin case(bank)0:word_q=q[0];1:word_q=q[1];2:word_q=q[2];default:word_q=0;endcase end",
'assign index=word_q[nibble*4 +:4];',
'always @* begin case(index)']
for i,color in enumerate(colors):lines.append(f"4'd{i}:rgb=24'h{color[0]:02x}{color[1]:02x}{color[2]:02x};")
lines+=['default:rgb=0;endcase end']
for bank in range(3):
    data=words[bank*2048:(bank+1)*2048]
    lines+=['EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),.REGMODE_A("NOREG"),']
    for n in range(128):
        value=sum(data[n*16+i]<<(16*i) for i in range(16))
        lines.append(f".INIT_{n:02X}(256'h{value:064x})"+(',' if n<127 else ''))
    lines += [f') ram{bank}(.doa(q[{bank}]),.dia(16\'d0),.addra(address[12:2]),.bytea(1\'b0),.bytewea(1\'b0),',
              f'.csa(enable&&address[14:13]==2\'d{bank}),.wea(1\'b0),.clka(clk),.rsta(1\'b0),.ocea(1\'b1),',
              '.dib(16\'d0),.addrb(11\'d0),.byteb(1\'b0),.byteweb(1\'b0),.csb(1\'b0),.web(1\'b0),.clkb(clk),.rstb(1\'b0),.oceb(1\'b0));']
lines+=['endmodule']
# Independent ROM reference embedded in the bench, no runtime absolute paths.
ref=['reg [3:0] ref_pixels[0:24575];','integer init_pixel;','initial begin']
for a in range(0,len(pixels),64):
    # Constant packed slice copied into the unpacked reference array in a loop.
    hexdata=''.join(f'{v:x}' for v in reversed(pixels[a:a+64]))
    ref+= [f'ref_chunk_{a//64}();']
ref+=['end']
for a in range(0,len(pixels),64):
    h=''.join(f'{v:x}' for v in reversed(pixels[a:a+64]))
    ref+= [f'task ref_chunk_{a//64};reg [255:0] bits;integer j;begin bits=256\'h{h};for(j=0;j<64;j=j+1)ref_pixels[{a}+j]=bits[j*4 +:4];end endtask']
ref += ['function [23:0] ref_color;input integer idx;begin case(idx)']
for i,color in enumerate(colors):ref.append(f"{i}:ref_color=24'h{color[0]:02x}{color[1]:02x}{color[2]:02x};")
ref+=['default:ref_color=0;endcase end endfunction']
meta={'size':[256,96],'colors':colors,'transparent_index':0,'bits_per_pixel':4,'native_bram32k':3,'master_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'indices_sha256':hashlib.sha256(pixels).hexdigest()}
print('*** Begin Patch')
for name,file,data in [('rom','dual_board/image_link/rtl/car_intro_20261007/car_intro_rom.v','\n'.join(lines)),('reference','dual_board/image_link/sim/car_intro_20261007/sprite_reference.vh','\n'.join(ref)),('meta','dual_board/image_link/assets/car_intro_20261007/packing.json',json.dumps(meta,indent=2))]:
    if len(sys.argv)>1 and sys.argv[1]!=name:continue
    if (ROOT/file).exists():raise RuntimeError('Output already exists:'+file)
    print('*** Add File: '+file)
    for line in data.splitlines():print('+'+line)
print('*** End Patch')
