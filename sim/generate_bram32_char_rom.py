"""Emit an exact native-ROM mapping for the synchronous lyric character table."""
from pathlib import Path
import re
from generate_bram32_lyric_font import bank_text
ROOT=Path(__file__).resolve().parent.parent
target=ROOT/'src/user_source/hdl_source/lyric_song_data.v'
source=target.read_text(encoding='utf-8')
body=source.split('module lyric_line_rom',1)[1].split('endmodule',1)[0]
data=[0]*2048
for addr,gid in re.findall(r"rom\[(\d+)\]=8'd(\d+);",body):
    data[int(addr)]=int(gid)
assert not any(data[864:])
native=bank_text(0,data).replace('if(BANK_ID==0) begin: bank_0\n','').removesuffix('\nend')
native=native.replace('.doa(O_data)','.doa(char_data)')
hdl='''// Native BRAM32K replaces the distributed lyric-character lookup mux.
// The original inline character table above remains the independent sim reference.
module lyric_char_bram32_rom(input I_clk,input [10:0] I_addr,output [7:0] O_char);
wire [15:0] char_data;
assign O_char=char_data[7:0];
'''+native+'\nendmodule\n'
print('*** Begin Patch')
print(f'*** Update File: {target.as_posix()}\n@@')
print('-always @(posedge I_clk) O_char<=rom[I_addr];')
print('''+`ifdef LYRIC_FAST_SIM
+always @(posedge I_clk) O_char<=rom[I_addr];
+`else
+wire [7:0] native_char;
+lyric_char_bram32_rom u_character_rom(I_clk,I_addr,native_char);
+always @(*) O_char=native_char;
+`endif''')
print('@@\n endgenerate\n `endif\n endmodule')
for line in ('\n'+hdl).splitlines():print('+'+line)
print('*** Add File: assets/lyrics/char_bram32_reference.hex')
for word in data:print(f'+{word:02X}')
print('*** End Patch')
