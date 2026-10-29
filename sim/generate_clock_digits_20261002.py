"""Print an apply_patch payload; render code-native ROM glyphs, write no files."""
from PIL import Image,ImageDraw,ImageFont
font=ImageFont.truetype('C:/Windows/Fonts/Noto Sans SC Medium (TrueType).otf',24*4)
lines=['module video_clock_digit_rom(input wire I_clk,input wire [8:0] I_address,output reg [15:0] O_row);',
       '// Same Noto Sans SC Medium family as existing screen text, native 16x24, 2-bit coverage.',
       'reg [15:0] rom[0:511];','integer i;','initial begin','    for(i=0;i<512;i=i+1)rom[i]=0;']
for digit in range(10):
    im=Image.new('L',(64,96),0)
    ImageDraw.Draw(im).text((32,48),str(digit),font=font,anchor='mm',fill=255)
    im=im.resize((16,24),Image.Resampling.LANCZOS)
    for y in range(24):
        value=0
        for x in range(16):
            a=im.getpixel((x,y));value=(value<<2)|(0 if a<40 else 1 if a<112 else 2 if a<196 else 3)
        lines.append(f"    rom[9'd{(digit*24+y)*2}]=16'h{value>>16:04X};")
        lines.append(f"    rom[9'd{(digit*24+y)*2+1}]=16'h{value&65535:04X};")
lines+=['end','always @(posedge I_clk)O_row<=rom[I_address];','endmodule']
print('*** Begin Patch\n*** Add File: src/user_source/hdl_source/video_clock_digit_rom.v')
print('\n'.join('+'+s for s in lines))
print('*** End Patch')
