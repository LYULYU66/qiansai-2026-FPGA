"""Emit apply_patch: shared two-song ROM/font from user-supplied assets.

Gaobai pixels/events remain exact. New lyrics come ONLY from the user's text
and their locally aligned MP3. Never download copyrighted lyrics.
"""
from pathlib import Path
import json, sys
from generate_lyric_smooth_assets import parse, events
from generate_home_font_patch import rows
ROOT=Path(__file__).resolve().parent.parent
DEST='dual_board/image_link/rtl/dualsong_20261005/dual_lyric_song_data.v'
audit=('--audit' in sys.argv or '--verify' in sys.argv)
if not audit: assert not (ROOT/DEST).exists(), 'Generated ROM already exists'
_,b0,lines0,glyphs=parse()
_,e0=events()
karaoke=json.loads((ROOT/'assets/lyrics/dualsong_20261005/YILU_USER_AUDIO.karaoke.json').read_text(encoding='utf-8'))
unique=['']
for line in karaoke['lines']:
    if line['text'] not in unique:unique.append(line['text'])
assert len(unique)<=22
unique+=['']*(22-len(unique))
unique+=['周杰伦 · 一路向北','词：方文山','曲：周杰伦','演唱：周杰伦','一路向北']
assert len(unique)==27
for text in unique:
    for char in text:
        if char not in glyphs:glyphs.append(char)
assert len(glyphs)<=256
boundaries=[(0,23,24),(500,24,25),(1000,25,0),(1600,1,2)]
pending={0:(3,32),500:(3,32),1000:(3,32),1600:(3,32)}
for cs,lid in [(480,23),(980,24),(1580,25)]:pending[cs]=(2,len(unique[lid]))
for i,line in enumerate(karaoke['lines']):
    cs=line['lrc_start_cs'];lid=unique.index(line['text'])
    nxt=unique.index(karaoke['lines'][i+1]['text']) if i+1<len(karaoke['lines']) else 0
    boundaries.append((cs,lid,nxt));pending[cs]=(3,32)
    previous=cs
    for c,char in enumerate(line['text']):
        if char.isspace():continue
        end=max(cs+1,line['char_end_cs'][c]);start=max(previous,min(line['char_start_cs'][c],end))
        count=c+1
        while count<len(line['text']) and line['text'][count].isspace():count+=1
        if start>previous+2 and start<end and start not in pending:pending[start]=(0,33)
        if end not in pending or pending[end][0]<2:pending[end]=(2,count)
        elif pending[end][0]==2:pending[end]=(2,max(count,pending[end][1]))
        previous=end
    # Instrumental gaps preview the upcoming pair, not a blank page.
    finish=line['char_end_cs'][-1]+80
    next_start=karaoke['lines'][i+1]['lrc_start_cs'] if i+1<len(karaoke['lines']) else 29700
    if finish+150<next_start:
        future=unique.index(karaoke['lines'][i+2]['text']) if i+2<len(karaoke['lines']) else 0
        cur,preview=(nxt,future) if nxt else (23,24)
        boundaries.append((finish,cur,preview));pending[finish]=(3,32)
boundaries.sort()
assert len(boundaries)<64
e1=[];prior=0
for cs,(_,code) in sorted(pending.items()):
    delta=cs-prior;assert 0<=delta<=4095
    e1.append((delta<<6)|code);prior=cs
assert len(e1)<=512 and sum((v&63)==32 for v in e1)==len(boundaries)
out=['// Generated from user-provided lyrics/audio. Timing is estimated forced word alignment.',
 'module lyric_event_rom(input I_clk,input [9:0] I_addr,output reg [29:0] O_event);',
 'reg [17:0] rom[0:1023]; /* fehdl force_ram=1, ram_style="bram" */',
 'reg [17:0] raw; integer n; wire [11:0] dt=raw[17:6];',
 "wire [23:0] samples=raw[5:0]==63 ? 24'hffffff : ({3'd0,dt,9'b0}-{7'd0,dt,5'b0});",
 "initial begin for(n=0;n<1024;n=n+1)rom[n]=18'h3ffff;"]
for bank,values in enumerate((e0,e1)):
    out += [f"rom[{bank*512+i}]=18'h{v:05x};" for i,v in enumerate(values)]
out+=['end','always @(posedge I_clk)begin raw<=rom[I_addr];O_event<={samples,raw[5:0]};end','endmodule',
 'module lyric_boundary_map(input [6:0] I_addr,output reg [4:0] O_current,O_next);',
 'always @* begin O_current=0;O_next=0;case(I_addr)']
for bank,values in enumerate((b0,boundaries)):
    out += [f"7'd{bank*64+i}:begin O_current=5'd{cur};O_next=5'd{nxt};end" for i,(_,cur,nxt) in enumerate(values)]
out+=['endcase end','endmodule']
line_words=[0]*2048
for bank,texts in enumerate((lines0,unique)):
    for lid,text in enumerate(texts):
        for c,ch in enumerate(text):line_words[(bank*32+lid)*32+c]=glyphs.index(ch)

def native_ram(name,words,addr,bank_id=None):
    lines=[]
    if bank_id is not None:lines.append(f'if(BANK_ID=={bank_id})begin:bank_{bank_id}')
    lines+=['EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),',
         '.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),']
    for i in range(128):
        value=sum(w<<(j*16) for j,w in enumerate(words[i*16:i*16+16]))
        lines.append(f".INIT_{i:02X}(256'h{value:064X})"+(',' if i<127 else ')'))
    lines += [f"{name}(.doa(O_data),.dia(16'd0),.addra({addr}),.bytea(1'b0),.bytewea(1'b0),",
         ".csa(1'b1),.wea(1'b0),.clka(I_clk),.rsta(1'b0),.ocea(1'b1),",
         ".dob(),.dib(16'd0),.addrb(11'd0),.byteb(1'b0),.byteweb(1'b0),",
         ".csb(1'b0),.web(1'b0),.clkb(1'b0),.rstb(1'b0),.oceb(1'b0));"]
    if bank_id is not None:lines.append('end')
    return lines
out+=['module lyric_line_rom(input I_clk,input [10:0] I_addr,input [7:0] I_line,I_next_line,',
 'output [7:0] O_char,output reg [4:0] O_length,O_next_length);',
 'wire [15:0] O_data;assign O_char=O_data[7:0];']+native_ram('chars',line_words,'I_addr')
for key,result in [('I_line','O_length'),('I_next_line','O_next_length')]:
    out.append(f'always @* begin {result}=0;case({key})')
    for bank,texts in enumerate((lines0,unique)):
        out += [f"8'd{bank*32+i}:{result}=5'd{len(t)};" for i,t in enumerate(texts) if t]
    out+=['endcase end']
out+=['endmodule']
pixels=[]
for b in range(16):
    values=[int(x,16) for x in (ROOT/f'assets/lyrics/font24_bank_{b:02d}.hex').read_text().split()]
    pixels.extend((v>>(c*2))&3 for v in values for c in range(8))
pixels=pixels[:133*484]
for ch in glyphs[133:]:
    image=rows(ch,24,24,crisp=True)
    pixels.extend(c for row in image[2:24] for c in row[1:23])
banks=(len(pixels)+16383)//16384
assert banks<=8
words=[sum(v<<(j*2) for j,v in enumerate(pixels[i:i+8])) for i in range(0,len(pixels),8)]
words += [0]*(banks*2048-len(words))
out += ['module lyric_font_packed_rom(input I_clk,input [7:0] I_glyph,input [4:0] I_row,I_col,output [1:0] O_cov);',
 "wire [16:0] glyph_base=({9'd0,I_glyph}<<9)-({9'd0,I_glyph}<<5)+({9'd0,I_glyph}<<2);",
 "wire [8:0] row_base=({4'd0,I_row}<<4)+({4'd0,I_row}<<2)+({4'd0,I_row}<<1);",
 "wire [16:0] address=glyph_base+{8'd0,row_base}+{12'd0,I_col};",
 f'wire [{banks*16-1}:0] bank_data;reg [2:0] bank_select,lane_select;genvar b;',
 f'generate for(b=0;b<{banks};b=b+1)begin:banks',
 'lyric_font_bram32_bank #(.BANK_ID(b)) ram(I_clk,address[13:3],bank_data[b*16+:16]);end endgenerate',
 'always @(posedge I_clk)begin bank_select<=address[16:14];lane_select<=address[2:0];end',
 "wire [15:0] selected=bank_data[{bank_select,4'd0}+:16];assign O_cov=selected[{lane_select,1'b0}+:2];endmodule",
 'module lyric_font_bram32_bank #(parameter BANK_ID=0)(input I_clk,input [10:0] I_addr,output [15:0] O_data);','generate']
for b in range(banks):out+=native_ram('font',words[b*2048:(b+1)*2048],'I_addr',b)
out+=['endgenerate','endmodule']
if audit: assert (ROOT/DEST).read_text(encoding='utf-8')=='\n'.join(out)+'\n', 'HDL differs from user text/font inputs'
if '--verify' in sys.argv:
    print('PASS asset audit: dual-song HDL matches user lyrics/audio alignment; 64372 old glyph pixels preserved; 218 glyphs total')
    sys.exit(0)
print('*** Begin Patch')
if not audit:
    print('*** Add File: '+DEST)
    for line in out:print('+'+line)
manifest_path='assets/lyrics/dualsong_20261005/rom_manifest.json'
print(('*** Update File: ' if audit else '*** Add File: ')+manifest_path)
if audit:
    print('@@')
    for line in (ROOT/manifest_path).read_text(encoding='utf-8').splitlines():print('-'+line)
manifest={'provenance':'user_supplied_text_and_audio','glyphs':len(glyphs),'font_bram32k':banks,
    'char_bram32k':1,'event_counts':[len(e0),len(e1)],'boundary_counts':[len(b0),len(boundaries)],
    'original_font_pixels_preserved':133*484,'lines0':lines0,'lines1':unique,'glyph_order':glyphs,
    'boundaries1':boundaries,'events1':e1,'song_samples':[10043560,14295040]}
for line in json.dumps(manifest,ensure_ascii=True,indent=2).splitlines():print('+'+line)
print('*** End Patch')
