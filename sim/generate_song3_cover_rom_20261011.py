"""Pack the supplied third-song cover as a small indexed RGB565 ROM."""
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
source = Path(r"C:/Users/28492/AppData/Local/Temp/codex-clipboard-abb5a47f-07a0-4963-8d36-04a8757b65c1.png")
image = Image.open(source).convert("RGB")
image = ImageOps.fit(image, (40, 40), method=Image.Resampling.LANCZOS,
                     centering=(0.50, 0.48))
quant = image.quantize(colors=15, method=Image.Quantize.MEDIANCUT)
palette = quant.getpalette()
colors = [tuple(palette[i:i+3]) for i in range(0, 15*3, 3)]
pixels = list(quant.getdata())
words = []
for y in range(40):
    for group in range(10):
        word = 0
        for lane in range(4):
            x = group*4 + lane
            dx, dy = x-19.5, y-19.5
            index = (pixels[y*40+x] + 1) if dx*dx + dy*dy <= 19.5*19.5 else 0
            word |= (index & 0xF) << (lane*4)
        words.append(word)
out = [
    "// Third-song supplied cover: 40x40 circular indexed RGB565, one BRAM9K.",
    "module song3_cover_rom(input I_clk,input [8:0] I_addr,output reg [15:0] O_word);",
    "reg [15:0] rom[0:511]; /* fehdl force_ram=1, ram_style=\"bram\" */",
    "integer n; initial begin for(n=0;n<512;n=n+1) rom[n]=16'h0000;",
]
for i, word in enumerate(words): out.append(f"rom[{i}]=16'h{word:04x};")
out += ["end", "always @(posedge I_clk) O_word<=rom[I_addr];", "endmodule",
        "module song3_cover_palette(input [3:0] I_index,output reg [23:0] O_rgb);",
        "always @(*)case(I_index)", "4'd0:O_rgb=24'hffffff;"]
for i, (r,g,b) in enumerate(colors, 1):
    out.append(f"4'd{i}:O_rgb=24'h{r:02x}{g:02x}{b:02x};")
out += ["default:O_rgb=24'hffffff;", "endcase", "endmodule", ""]
target = ROOT / "dual_board/image_link/rtl/dualsong_20261005/song3_cover_rom.v"
target.write_text("\n".join(out), encoding="utf-8")
print(f"wrote {target} ({len(words)} pixels words)")
