"""Emit apply_patch for a bit-exact native BRAM32K font prototype.

Read existing coverage only: no rasterization or image resampling.
"""
from pathlib import Path
import argparse

ROOT=Path(__file__).resolve().parent.parent
OUT='sim/resource_all_20261002/bram32_font'

def words():
    result=[]
    for bank in range(16):
        block=[int(x,16) for x in (ROOT/f'assets/lyrics/font24_bank_{bank:02d}.hex').read_text().split()]
        assert len(block)==512
        result+=block
    assert len(result)==8192 and all(x<65536 for x in result)
    return result

def header(name='lyric_font_bram32_rom'):
    return f'''// Exact original two-bit antialias coverage, four 2048x16 native ROMs.
module {name}(input I_clk,input [7:0] I_glyph,
    input [4:0] I_row,I_col,output [1:0] O_cov);
wire [15:0] glyph_base=({{8'd0,I_glyph}}<<9)-({{8'd0,I_glyph}}<<5)+({{8'd0,I_glyph}}<<2);
wire [8:0] row_base=({{4'd0,I_row}}<<4)+({{4'd0,I_row}}<<2)+({{4'd0,I_row}}<<1);
wire [15:0] address=glyph_base+{{7'd0,row_base}}+{{11'd0,I_col}};
wire [63:0] bank_data; reg [1:0] bank_select; reg [2:0] lane_select;
genvar b;
generate for(b=0;b<4;b=b+1) begin: banks
    lyric_font_bram32_bank #(.BANK_ID(b)) bank(I_clk,address[13:3],bank_data[b*16+:16]);
end endgenerate
always @(posedge I_clk) begin bank_select<=address[15:14]; lane_select<=address[2:0]; end
wire [15:0] selected=bank_data[{{bank_select,4'd0}}+:16];
assign O_cov=selected[{{lane_select,1'b0}}+:2];
endmodule

module lyric_font_bram32_bank #(parameter integer BANK_ID=0)
(input I_clk,input [10:0] I_addr,output [15:0] O_data);
'''

def bank_text(bank,data):
    out=[f'if(BANK_ID=={bank}) begin: bank_{bank}',
         'EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),',
         ' .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),']
    for n in range(128):
        value=sum(w<<(16*i) for i,w in enumerate(data[bank*2048+n*16:bank*2048+n*16+16]))
        comma=',' if n<127 else ')'
        out.append(f" .INIT_{n:02X}(256'h{value:064X}){comma}")
    out+=[' ram(.doa(O_data),.dia(16\'d0),.addra(I_addr),.bytea(1\'b0),.bytewea(1\'b0),',
           ' .csa(1\'b1),.wea(1\'b0),.clka(I_clk),.rsta(1\'b0),.ocea(1\'b1),',
           ' .dob(),.dib(16\'d0),.addrb(11\'d0),.byteb(1\'b0),.byteweb(1\'b0),',
           ' .csb(1\'b0),.web(1\'b0),.clkb(1\'b0),.rstb(1\'b0),.oceb(1\'b0));','end']
    return '\n'.join(out)

def hdl(fast=False,name='lyric_font_bram32_rom'):
    data=words();out=header(name)
    if fast:
        out+='''`ifdef LYRIC_FAST_SIM
reg [15:0] rom[0:2047]; reg [15:0] data;
assign O_data=data;
initial begin case(BANK_ID)
'''
        for b in range(4):out+=f' {b}: $readmemh("assets/lyrics/font24_bram32_{b:02d}.hex",rom);\n'
        out+='endcase end\nalways @(posedge I_clk) data<=rom[I_addr];\n`else\n'
    out+='generate\n'+'\n'.join(bank_text(b,data) for b in range(4))+'\nendgenerate\n'
    if fast:out+='`endif\n'
    return out+'endmodule\n'

def add(path,content):
    print(f'*** Add File: {path}')
    for line in content.splitlines():print('+'+line)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--production',action='store_true')
    args=parser.parse_args();print('*** Begin Patch')
    if args.production:
        target='src/user_source/hdl_source/lyric_song_data.v'
        old=(ROOT/target).read_text(encoding='utf-8').split('// LOSSLESS_PACKED_FONT_20261002',1)[1]
        # Preserve the prior implementation as an uninstantiated reference.
        print(f'*** Update File: {target}\n@@')
        print('-module lyric_font_packed_rom(input I_clk,input [7:0] I_glyph,')
        print('+module lyric_font_packed9_reference(input I_clk,input [7:0] I_glyph,')
        print('@@')
        anchor=old.splitlines()[-3:]
        for line in anchor:print(' '+line)
        for line in ('\n// NATIVE_BRAM32_FONT_20261002\n'+hdl(True,'lyric_font_packed_rom')).splitlines():print('+'+line)
        data=words()
        for bank in range(4):add(f'assets/lyrics/font24_bram32_{bank:02d}.hex','\n'.join(f'{x:04X}' for x in data[bank*2048:(bank+1)*2048])+'\n')
    else:
        add(OUT+'/lyric_font_bram32_rom.v',hdl())
        add(OUT+'/font.prj','''<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" RunTime="2026-10-02T12:00:00">
<Project_Created_Time></Project_Created_Time><TD_Version>6.2.168116</TD_Version><Name>font</Name>
<HardWare><Family>EG4</Family><Device>EG4S20BG256</Device><Speed/></HardWare>
<Source_Files><Verilog><File Path="lyric_font_bram32_rom.v"><FileInfo>
<Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/>
<Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="1"/>
</FileInfo></File></Verilog></Source_Files>
<FileSets><FileSet Name="design_1" Type="DesignFiles"/><FileSet Name="constraint_1" Type="ConstrainFiles"/></FileSets>
<TOP_MODULE><LABEL>lyric_font_bram32_rom</LABEL><MODULE>lyric_font_bram32_rom</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>
<Property/><Device_Settings/><Configurations/></Project>
''')
        add(OUT+'/font.tcl',(ROOT/'src/td_project/resopt_Runs/syn_resource_final_20261002/lab_ex5_i2s_v1.0.tcl').read_text())
        add(OUT+'/settings.cfg','''set ADCList {}
set SDCList {}
set area_option -packarea
set device_name eagle_s20.db
set package_name EG4S20BG256
set prj_name font
set run_type syn
set start_step read_design
set end_step opt_gate
set top_model_name lyric_font_bram32_rom
''')
    print('*** End Patch')
