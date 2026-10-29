"""Emit apply_patch only: 24px AA font, compact delta events and intro credits."""
from pathlib import Path
import argparse
import json
import re
import sys
from generate_lyric_assets import parse as parse_old
from generate_home_font_patch import rows

ROOT=Path(__file__).resolve().parent.parent
TARGET=ROOT/'src/user_source/hdl_source/lyric_song_data.v'
CREDITS=['周杰伦 · 告白气球','词：方文山','曲：周杰伦','编曲：林迈可','告白气球']
INTRO_BASE=22
PITCH=32
FONT_SIZE=24
CROP_X,CROP_Y,CROP_W,CROP_H=1,2,22,22

def parse():
    original,unique,glyphs=parse_old()
    assert len(unique)==INTRO_BASE
    for text in CREDITS:
        unique.append(text)
        for char in text:
            if char not in glyphs: glyphs.append(char)
    assert max(map(len,unique))<=16 and len(glyphs)*484<=65536
    boundaries=[]
    for i,(sample,lid) in enumerate(original):
        future=[j for _,j in original[i+1:] if j]
        if sample==0: cur,nxt=INTRO_BASE+1,INTRO_BASE+2
        elif lid: cur,nxt=lid,(future[0] if future else 0)
        else:
            if not future:
                # Outro prepares the next loop's song information, never
                # previews the first verse before returning to credits.
                cur,nxt=INTRO_BASE+1,INTRO_BASE+2
            else:
                assert len(future)>=2
                cur,nxt=future[:2]
        boundaries.append((sample//480,cur,nxt))
    boundaries.extend([(500,INTRO_BASE+2,INTRO_BASE+3),(1000,INTRO_BASE+3,0),
                       (1600,original[1][1],original[2][1])])
    boundaries.sort()
    assert len(boundaries)<64
    return original,boundaries,unique,glyphs

def events():
    original,boundaries,unique,_=parse()
    pending={cs:(3,32) for cs,_,_ in boundaries}
    # Reuse the same sample-paced sweep for all letters of each credit line.
    # Leave 0.2s after each complete line before advancing to the next stage.
    for cs,lid in ((480,23),(980,24),(1580,25)):
        assert cs not in pending
        pending[cs]=(2,len(unique[lid]))
    source=json.loads((ROOT/'assets/lyrics/GAOBAI_3D_USER_AUDIO.karaoke.json').read_text(encoding='utf-8'))
    aligned=iter(source['lines'])
    for i,(sample,lid) in enumerate(original):
        if not lid: continue
        line=next(aligned); text=unique[lid]; cs=sample//480
        assert line['text']==text and line['lrc_start_cs']==cs
        starts=line['char_start_cs']; ends=line['char_end_cs']
        previous=cs; deadline=original[i+1][0]//480-1
        for c,char in enumerate(text):
            if char.isspace(): continue
            end=max(cs+1,min(ends[c],deadline)); start=max(previous,min(starts[c],end))
            count=c+1
            while count<len(text) and text[count].isspace(): count+=1
            if start>previous+2 and start<end:
                if start not in pending: pending[start]=(0,33)
            if end not in pending or pending[end][0]<2:
                pending[end]=(2,count)
            elif pending[end][0]==2:
                pending[end]=(2,max(count,pending[end][1]))
            previous=end
    assert next(aligned,None) is None
    seq=sorted((cs,code) for cs,(_,code) in pending.items())
    assert len(seq)<=512
    packed=[]; previous=0
    for cs,code in seq:
        delta=cs-previous
        assert 0<=delta<=4095 and code<=33
        packed.append((delta<<6)|code); previous=cs
    assert sum(code==32 for _,code in seq)==len(boundaries)
    return seq,packed

def font_pixels():
    glyphs=parse()[3]; result=[]
    for char in glyphs:
        source=rows(char,24,24,crisp=True)
        for y,row in enumerate(source):
            for x,cov in enumerate(row):
                if not (1<=x<23 and 2<=y<24): assert cov==0,(char,x,y,cov)
        result.extend(c for row in source[2:24] for c in row[1:23])
    return result

def scaffold():
    _,boundaries,unique,glyphs=parse(); seq,packed=events(); banks=(len(glyphs)*484+4095)//4096
    out=['// Generated from the supplied MP3; estimated word-aligned start/end spans.',
         '// Native 24px Noto Sans SC Medium, full 2-bit AA; only zero margins cropped.',
         f'// {len(glyphs)} glyphs, {len(seq)} delta events, {len(boundaries)} boundaries.',
         'module lyric_event_rom(input I_clk,input [8:0] I_addr,output reg [29:0] O_event);',
         '// One 512x18 BRAM: delta centiseconds[11:0], command[5:0].',
         '// 32=next boundary; 33=start span; 0..20=end column; 63=sentinel.',
         'reg [17:0] rom[0:511]; reg [17:0] raw; integer n;',
         'wire [11:0] dt=raw[17:6];',
         "wire [23:0] samples=(raw[5:0]==6'd63)?24'hFFFFFF:",
         "    ({3'd0,dt,9'b0}-{7'd0,dt,5'b0});",
         "initial begin for(n=0;n<512;n=n+1) rom[n]=18'h3FFFF;"]
    out.extend(f"    rom[{i}]=18'h{value:05X};" for i,value in enumerate(packed))
    out.extend(['end','always @(posedge I_clk) begin raw<=rom[I_addr]; O_event<={samples,raw[5:0]}; end','endmodule','',
         'module lyric_boundary_map(input [5:0] I_addr,output reg [4:0] O_current,O_next);',
         'always @(*) begin O_current=0; O_next=0; case(I_addr)'])
    out.extend(f"    6'd{i}: begin O_current=5'd{cur}; O_next=5'd{nxt}; end" for i,(_,cur,nxt) in enumerate(boundaries))
    out.extend(['endcase end','endmodule','',
         'module lyric_line_rom(input I_clk,input [10:0] I_addr,input [7:0] I_line,I_next_line,',
         '    output reg [7:0] O_char,output reg [4:0] O_length,O_next_length);',
         f'reg [7:0] rom[0:{len(unique)*32-1}]; integer n;',
         f'initial begin for(n=0;n<{len(unique)*32};n=n+1) rom[n]=0;'])
    for lid,text in enumerate(unique):
        for col,char in enumerate(text): out.append(f"    rom[{lid*32+col}]=8'd{glyphs.index(char)};")
    out.extend(['end','always @(posedge I_clk) O_char<=rom[I_addr];'])
    for key,value in [('I_line','O_length'),('I_next_line','O_next_length')]:
        out.extend([f'always @(*) begin {value}=0; case({key})'])
        out.extend(f"    8'd{i}: {value}=5'd{len(text)};" for i,text in enumerate(unique) if text)
        out.append('endcase end')
    out.extend(['endmodule','',
         'module lyric_font_rom(input I_clk,input [15:0] I_addr,output [1:0] O_cov);',
         f'wire [{banks*2-1}:0] bank_cov; reg [3:0] bank_select; genvar b;',
         f'generate for(b=0;b<{banks};b=b+1) begin: banks',
         '    lyric_font_bank #(.BANK_ID(b)) bank(I_clk,I_addr[11:0],bank_cov[b*2+:2]);',
         'end endgenerate',
         "always @(posedge I_clk) bank_select<=I_addr[15:12];",
         "assign O_cov=bank_cov[{bank_select,1'b0}+:2];",'endmodule','',
         'module lyric_font_bank #(parameter integer BANK_ID=0)(input I_clk,input [11:0] I_addr,output reg [1:0] O_cov);',
         'reg [1:0] rom[0:4095]; integer n;',
         '`ifdef LYRIC_FAST_SIM','reg [15:0] packed_init[0:511];','`endif','initial begin','`ifdef LYRIC_FAST_SIM','case(BANK_ID)'])
    out.extend(f'    {i}: $readmemh("assets/lyrics/font24_bank_{i:02d}.hex",packed_init);' for i in range(banks))
    out.extend(['endcase',"for(n=0;n<4096;n=n+1) rom[n]=packed_init[n>>3][(n&7)*2+:2];",'`else',
         'for(n=0;n<4096;n=n+1) rom[n]=0;','case(BANK_ID)'])
    for i in range(banks): out.extend([f'{i}: begin',f'// FONT24_BANK_{i:02d}','end'])
    out.extend(['endcase','`endif','end','task set_word; input integer address; input [15:0] data; integer p;',
         'begin for(p=0;p<8;p=p+1) rom[address*8+p]=data[p*2+:2]; end endtask',
         'always @(posedge I_clk) O_cov<=rom[I_addr];','endmodule'])
    return out

def emit_replace(path,lines):
    print(f'*** Update File: {path.as_posix()}\n@@' if path.exists() else f'*** Add File: {path.as_posix()}')
    if path.exists():
        for line in path.read_text(encoding='utf-8').splitlines(): print('-'+line)
    for line in lines: print('+'+line)

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--part',required=True); args=parser.parse_args()
    seq,_=events()
    print(f'smooth_events={len(seq)} boundaries={len(parse()[1])} glyphs={len(parse()[3])}',file=sys.stderr)
    print('*** Begin Patch')
    if args.part=='scaffold':
        # Old native font data is large; replace just the non-font prefix and
        # font module structure separately to keep each apply_patch bounded.
        old=TARGET.read_text(encoding='utf-8'); split=old.index('module lyric_font_rom')
        new='\n'.join(scaffold())+'\n'; ns=new.index('module lyric_font_rom')
        print(f'*** Update File: {TARGET.as_posix()}\n@@')
        for line in old[:split].splitlines(): print('-'+line)
        for line in new[:ns].splitlines(): print('+'+line)
        # Font suffix removal is delegated to the explicit skeleton part.
    elif args.part.startswith('prune'):
        bank=int(args.part[5:]); old=TARGET.read_text(encoding='utf-8')
        font=old[old.index('module lyric_font_bank'):]
        body=re.search(rf'        {bank}: begin\n.*?\n        end',font,re.S)[0]
        print(f'*** Update File: {TARGET.as_posix()}\n@@')
        for line in body.splitlines(): print('-'+line)
        print(f'+        {bank}: begin\n+        end')
    elif args.part=='font_skeleton':
        old=TARGET.read_text(encoding='utf-8'); new='\n'.join(scaffold())+'\n'
        print(f'*** Update File: {TARGET.as_posix()}\n@@')
        for line in old[old.index('module lyric_font_rom'):].splitlines(): print('-'+line)
        for line in new[new.index('module lyric_font_rom'):].splitlines(): print('+'+line)
    else:
        bank=int(args.part); pixels=font_pixels(); words=[]; native=[]
        for word in range(512):
            start=bank*4096+word*8
            value=sum(c<<(i*2) for i,c in enumerate(pixels[start:start+8]))
            words.append(f'{value:04X}')
            if value: native.append(f"    set_word({word},16'h{value:04X});")
        print(f'*** Update File: {TARGET.as_posix()}\n@@\n-// FONT24_BANK_{bank:02d}')
        for line in native: print('+'+line)
        emit_replace(ROOT/f'assets/lyrics/font24_bank_{bank:02d}.hex',words)
    print('*** End Patch')
