"""Emit apply_patch for lossless 9-pixel/18-bit font packing, same 1clk port.

The original native font remains an uninstantiated reference for verification.
No font rasterization, resampling, thresholding, or glyph changes are performed.
"""
from pathlib import Path
import argparse
import re

ROOT=Path(__file__).resolve().parent.parent
TARGET=ROOT/'src/user_source/hdl_source/lyric_song_data.v'
MARKER='// LOSSLESS_PACKED_FONT_20261002'


def pixels():
    data=[]
    for b in range(16):
        words=[int(x,16) for x in (ROOT/f'assets/lyrics/font24_bank_{b:02d}.hex').read_text().split()]
        assert len(words)==512
        data.extend((word>>(lane*2))&3 for word in words for lane in range(8))
    assert not any(data[64372:])
    return data[:64372]


def packed():
    data=pixels()
    # ID 0 is the completely empty space glyph. Give every other glyph
    # a fixed 54-word stride: 484 real pixels plus TWO ZERO padding pixels.
    # This keeps all coverage exact but removes the large glyph-base table
    # and cross-glyph lane correction from the pixel-critical address path.
    assert not any(data[:484])
    words=[]
    for glyph in range(1,133):
        block=data[glyph*484:(glyph+1)*484]+[0,0]
        words.extend(sum(c<<(i*2) for i,c in enumerate(block[start:start+9]))
                     for start in range(0,len(block),9))
    assert len(words)==7128
    return words+[0]*(14*512-len(words))


def hdl(words):
    out=[MARKER,
         '// Identical native 24px coverage: 64372 pixels in fourteen 512x18 ROMs.',
         '// The empty space glyph is bypassed; all 132 other glyphs use stride 54.',
         '// Row quotient/remainder descriptors avoid pixel-path division.',
         'module lyric_font_packed_rom(input I_clk,input [7:0] I_glyph,',
         '    input [4:0] I_row,I_col,output [1:0] O_cov);',
         "wire [7:0] slot=I_glyph-8'd1;",
         "wire [12:0] base_word=({5'd0,slot}<<6)-({5'd0,slot}<<3)-({5'd0,slot}<<1);"]
    out+=['reg [5:0] row_word; reg [3:0] row_lane;',
          'always @(*) begin row_word=0; row_lane=0; case(I_row)']
    for row in range(22):
        q,r=divmod(row*22,9)
        out.append(f"    5'd{row}: begin row_word=6'd{q}; row_lane=4'd{r}; end")
    out+=['endcase end',
          "wire [1:0] col_word=I_col>=18?2'd2:I_col>=9?2'd1:2'd0;",
          "wire [3:0] col_lane=I_col>=18?I_col-5'd18:I_col>=9?I_col-5'd9:I_col;",
          "wire [4:0] lane_sum={1'b0,row_lane}+{1'b0,col_lane};",
          "wire carry_word=lane_sum>=5'd9;",
          "wire [3:0] lane=carry_word?lane_sum-5'd9:lane_sum;",
          "wire [5:0] word_offset=row_word+{4'd0,col_word}+{5'd0,carry_word};",
          "wire [12:0] address=base_word+{7'd0,word_offset};",
          'wire [447:0] bank_data; reg [3:0] bank_select,lane_select; reg blank; genvar b;',
          'generate for(b=0;b<14;b=b+1) begin: banks',
          '    lyric_packed_font_bank #(.BANK_ID(b)) bank(I_clk,address[8:0],bank_data[b*32+:18]);',
          "    assign bank_data[b*32+18+:14]=14'd0;",
          'end endgenerate',
          "always @(posedge I_clk) begin bank_select<=address[12:9]; lane_select<=lane; blank<=(I_glyph==0); end",
          "wire [17:0] selected=bank_data[{bank_select,5'd0}+:18];",
          "assign O_cov=blank?2'd0:selected[{lane_select,1'b0}+:2];",'endmodule','',
          'module lyric_packed_font_bank #(parameter integer BANK_ID=0)',
          '(input I_clk,input [8:0] I_addr,output reg [17:0] O_data);',
          'reg [17:0] rom[0:511]; /* fehdl force_ram=1, ram_style="bram" */',
          'integer n; initial begin','`ifdef LYRIC_FAST_SIM','case(BANK_ID)']
    for bank in range(14):
        out.append(f'    {bank}: $readmemh("assets/lyrics/font24_packed_{bank:02d}.hex",rom);')
    out+=['endcase','`else',"for(n=0;n<512;n=n+1) rom[n]=18'd0;",'case(BANK_ID)']
    for bank in range(14):
        out.append(f'{bank}: begin')
        for addr,word in enumerate(words[bank*512:(bank+1)*512]):
            if word: out.append(f"    rom[{addr}]=18'h{word:05X};")
        out.append('end')
    out+=['endcase','`endif','end','always @(posedge I_clk) O_data<=rom[I_addr];','endmodule']
    return '\n'.join(out)+'\n'


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--part',choices=('all','top'),default='all')
    parser.add_argument('--bank',type=int)
    args=parser.parse_args()
    words=packed();new=hdl(words);old=TARGET.read_text(encoding='utf-8')
    if args.part=='top':
        old=old[old.index(MARKER):].split('module lyric_packed_font_bank',1)[0]
        new=new.split('module lyric_packed_font_bank',1)[0]
    elif args.bank is not None:
        assert 0<=args.bank<14
        pattern=rf'\n{args.bank}: begin\n.*?\nend'
        old=re.search(pattern,old.split(MARKER,1)[1].split('`else',1)[1],re.S).group().strip('\n')
        new=re.search(pattern,new.split('`else',1)[1],re.S).group().strip('\n')
    print('*** Begin Patch')
    print(f'*** Update File: {TARGET.as_posix()}\n@@')
    if args.part=='top' or args.bank is not None:
        for line in old.splitlines(): print('-'+line)
    elif MARKER in old:
        for line in old[old.index(MARKER):].splitlines(): print('-'+line)
    else:
        print(' always @(posedge I_clk) O_cov<=rom[I_addr];\n endmodule')
    for line in new.splitlines():print('+'+line)
    for bank in ([args.bank] if args.bank is not None else [] if args.part=='top' else range(14)):
        path=ROOT/f'assets/lyrics/font24_packed_{bank:02d}.hex'
        print(f'*** Update File: {path.as_posix()}\n@@' if path.exists() else f'*** Add File: {path.as_posix()}')
        if path.exists():
            for line in path.read_text().splitlines():print('-'+line)
        for word in words[bank*512:(bank+1)*512]: print(f'+{word:05X}')
    print('*** End Patch')
