"""Split the supplied car toolbar and rebuild crisp code-native icon assets.

Original crops remain available for comparison. Geometry is redrawn offline
at 4x, reduced once, and packed into a two-bit atlas. Runtime needs only a
1024x16 synchronous ROM, not full-color textures or a framebuffer.
"""
from pathlib import Path
import argparse
import sys
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets/bottom_nav_icons_20260930"
OUT = ROOT / "src/user_source/hdl_source/video_home_overlay.v"
SCALE = 4
NAMES = ["home", "vehicle", "pages", "seat_left", "airflow", "recirculation",
         "fan", "front_defrost", "rear_defrost", "seat_right", "volume",
         "storage", "screen"]
BOXES = [(22,9,49,32), (64,8,93,31), (105,6,136,30), (210,4,239,31),
         (262,3,290,29), (302,5,337,29), (352,1,386,32), (400,2,430,28),
         (447,2,478,28), (496,2,524,28), (596,1,625,27), (637,1,668,27),
         (681,0,710,26)]
# 15 equally spaced groups; temperature tile is shared by left and right.
PLACEMENTS = [(0,20,448,24,24), (1,62,448,24,24), (2,104,448,24,24),
              (13,140,452,36,16), (3,188,448,24,24), (4,230,448,24,24),
              (5,272,448,24,24), (6,314,448,24,24), (7,356,448,24,24),
              (8,398,448,24,24), (9,440,448,24,24), (13,476,452,36,16),
              (10,524,448,24,24), (11,566,448,24,24), (12,608,448,24,24)]


def geometry(name, size=24):
    image = Image.new("L", (24*SCALE, 24*SCALE), 0)
    draw = ImageDraw.Draw(image)

    def line(points, width=1.5):
        pts = [(round(x*SCALE), round(y*SCALE)) for x,y in points]
        draw.line(pts, fill=255, width=round(width*SCALE), joint="curve")
        r=width*SCALE/2
        for x,y in (pts[0],pts[-1]):
            draw.ellipse((x-r,y-r,x+r,y+r),fill=255)

    def ellipse(box, fill=False, width=1.4):
        draw.ellipse(tuple(round(v*SCALE) for v in box),
                     fill=255 if fill else None, outline=255,
                     width=round(width*SCALE))

    def curve(points, width=1.5):
        # Cubic Bezier is flattened only by the offline asset generator.
        p0,p1,p2,p3=points
        samples=[]
        for n in range(41):
            t=n/40;u=1-t
            samples.append(tuple(u*u*u*p0[c]+3*u*u*t*p1[c]+
                                 3*u*t*t*p2[c]+t*t*t*p3[c] for c in (0,1)))
        line(samples,width)

    if name == "home":
        line([(3,11),(12,3.5),(21,11)])
        line([(5,10),(5,20),(19,20),(19,10)])
        line([(9.5,20),(9.5,14),(14.5,14),(14.5,20)],1.3)
    elif name == "vehicle":
        line([(4,13),(6,6),(18,6),(20,13),(20,18),(4,18),(4,13)])
        line([(5,12),(19,12)],1.2)
        line([(4.5,18),(4.5,20)],2);line([(19.5,18),(19.5,20)],2)
        line([(6.5,15),(8.5,15)]);line([(15.5,15),(17.5,15)])
    elif name == "pages":
        line([(6,8),(6,20),(18,20),(18,8),(6,8)])
        line([(9,4),(21,4),(21,16)],1.4)
    elif name in ("seat_left", "seat_right"):
        line([(5,5),(6,15),(10,18),(20,18)],1.7)
        line([(9,5),(10,12),(17,12)],1.8)
        line([(10,12),(12,15),(19,15)],1.4)
        for x in (14,17,20):
            curve([(x,9),(x-2,7),(x+2,5),(x,3)],1.1)
        if name == "seat_right":
            image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    elif name == "airflow":
        ellipse((13,3,17,7),True)
        line([(13,9),(12,14),(7,19)],1.9)
        line([(12,14),(17,14),(19,19)],1.8)
        line([(3,8),(9,8)],1.2);line([(7,6),(9,8),(7,10)],1.2)
        line([(3,14),(8,14)],1.2);line([(6,12),(8,14),(6,16)],1.2)
    elif name == "recirculation":
        line([(2.5,13),(5,8),(19,8),(21.5,13),(21.5,16),(2.5,16),(2.5,13)],1.3)
        line([(6,16),(6,18)],1.7);line([(18,16),(18,18)],1.7)
        curve([(7,13),(9,10),(13,10),(16,13)],1.2)
        line([(14,11),(16,13),(13.5,13.5)],1.2)
    elif name == "fan":
        for rotate in (0,90,180,270):
            petal=Image.new("L",image.size,0)
            d=ImageDraw.Draw(petal)
            d.ellipse((9*SCALE,2.5*SCALE,14*SCALE,10.5*SCALE),fill=255)
            image=ImageChops.lighter(image,petal.rotate(rotate))
        draw=ImageDraw.Draw(image)
        draw.ellipse((9.5*SCALE,9.5*SCALE,13.5*SCALE,13.5*SCALE),fill=255)
    elif name in ("front_defrost", "rear_defrost"):
        if name == "front_defrost":
            curve([(3,9),(6,3),(18,3),(21,9)],1.4)
            line([(3,9),(5,17)]);line([(21,9),(19,17)])
        else:
            line([(3,6),(21,6),(21,17),(3,17),(3,6)],1.3)
        for x in (8,12,16):
            curve([(x,20),(x-1.5,17),(x+1.5,14),(x,11)],1.1)
            line([(x-1.5,12.5),(x,11),(x+1.5,12.5)],1.0)
    elif name == "volume":
        line([(3,9),(7,9),(12,5),(12,19),(7,15),(3,15),(3,9)],1.5)
        curve([(15,8),(18,10),(18,14),(15,16)],1.3)
        curve([(18,5),(22,8),(22,16),(18,19)],1.3)
    elif name == "storage":
        line([(4,10),(4,20),(20,20),(20,10),(4,10)],1.4)
        line([(7,10),(7,4),(15,4),(19,8),(19,10)],1.4)
        line([(15,4),(15,8),(19,8)],1.2)
        line([(8,14),(16,14)],1.2)
    elif name == "screen":
        line([(3,4),(21,4),(19,13),(5,13),(3,4)],1.4)
        line([(12,13),(12,21)],1.4)
        line([(9,18),(12,21),(15,18)],1.4)
    else:
        raise ValueError(name)
    if size != 96:
        image=image.resize((size,size),Image.Resampling.LANCZOS)
    return image


def quantized(image):
    # Suppress resampling halos. Coverage is deterministic, not a GPU shader.
    return [0 if a<48 else 1 if a<116 else 2 if a<196 else 3
            for a in (image.getpixel((x,y)) for y in range(image.height)
                      for x in range(image.width))]


def tiles():
    bitmaps=[(24,24,quantized(geometry(name))) for name in NAMES]
    image=Image.new("L",(36*SCALE,16*SCALE),0)
    font=ImageFont.truetype("C:/Windows/Fonts/Noto Sans SC Medium (TrueType).otf",15*SCALE)
    ImageDraw.Draw(image).text((18*SCALE,8*SCALE),"21.0",font=font,
                              fill=255,anchor="mm")
    image=image.resize((36,16),Image.Resampling.LANCZOS)
    bitmaps.append((36,16,quantized(image)))
    return bitmaps


def rgb(index, tile):
    return ([(255,255,255),(222,241,238),(104,205,190),(20,166,143)] if tile==6 else
            [(255,255,255),(174,184,193),(105,119,133),(43,59,74)])[index]


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--extract-only",action="store_true")
    args=parser.parse_args()
    source=Image.open(ASSETS/"source.png").convert("RGB")
    sheet=Image.new("RGB",(13*112,112),(255,255,255))
    for i,(name,box) in enumerate(zip(NAMES,BOXES)):
        crop=source.crop(box)
        crop.save(ASSETS/"raw"/(name+".png"))
        enlarged=crop.resize((96,80),Image.Resampling.NEAREST)
        sheet.paste(enlarged,(i*112+8,8))
    sheet.save(ASSETS/"source_crops.png")
    if args.extract_only:
        return
    bitmaps=tiles();words=[]
    preview=Image.new("RGB",(640,40),(255,255,255))
    for tile,(width,height,pixels) in enumerate(bitmaps):
        native=Image.new("RGBA",(width,height))
        for y in range(height):
            for x in range(width):
                index=pixels[y*width+x]
                native.putpixel((x,y),(*rgb(index,tile),255 if index else 0))
        name=NAMES[tile] if tile<13 else "temperature_21_0"
        native.save(ASSETS/"clean"/(name+"_native.png"))
        if tile<13:
            alpha=geometry(name,96)
            master=Image.new("RGBA",(96,96),rgb(3,tile)+(0,));master.putalpha(alpha)
            master.save(ASSETS/"clean"/(name+"_96.png"))
        for base in range(0,len(pixels),8):
            words.append(sum(pixels[base+lane]<<(14-2*lane) for lane in range(8)))
    assert len(words)==1008
    for tile,ox,oy,width,height in PLACEMENTS:
        _,_,pixels=bitmaps[tile]
        for y in range(height):
            for x in range(width):
                preview.putpixel((ox+x,oy-440+y),rgb(pixels[y*width+x],tile))
    preview.save(ASSETS/"toolbar_native.png")
    preview.save(ASSETS/"toolbar_native.ppm")
    preview.resize((1280,80),Image.Resampling.NEAREST).save(ASSETS/"toolbar_2x.png")
    lines=["// Supplied toolbar parsed/redrawn by sim/generate_bottom_nav_icons.py.",
           "// Thirteen 24px icons + one shared 36x16 temperature: 1008 words.",
           "module video_bottom_nav_rom (",
           "    input wire I_clk, input wire [9:0] I_addr,",
           "    input wire [2:0] I_lane, input wire I_fan,",
           "    output wire [1:0] O_cov, output reg [23:0] O_rgb",
           ");",
           'reg [15:0] rom [0:1023]; /* fehdl force_ram=1, ram_style="bram" */',
           "integer i;", "initial begin",
           "    for (i=0;i<1024;i=i+1) rom[i]=16'd0;"]
    lines += [f"    rom[10'd{a}] = 16'h{w:04X};" for a,w in enumerate(words) if w]
    lines += ["end", "reg [15:0] word_d; reg [2:0] lane_d; reg fan_d;",
              "always @(posedge I_clk) begin",
              "    word_d <= rom[I_addr]; lane_d <= I_lane; fan_d <= I_fan;",
              "end", "assign O_cov = word_d[(7-lane_d)*2 +: 2];",
              "always @(*) begin", "    case (O_cov)",
              "        2'd0: O_rgb=24'hFFFFFF;",
              "        2'd1: O_rgb=fan_d ? 24'hDEF1EE : 24'hAEB8C1;",
              "        2'd2: O_rgb=fan_d ? 24'h68CDBE : 24'h697785;",
              "        default: O_rgb=fan_d ? 24'h14A68F : 24'h2B3B4A;",
              "    endcase", "end", "endmodule"]
    new="\n".join(lines)
    source=OUT.read_text(encoding="utf-8")
    marker="// Supplied toolbar parsed/redrawn by sim/generate_bottom_nav_icons.py."
    print("*** Begin Patch\n*** Update File: "+OUT.relative_to(ROOT).as_posix()+"\n@@")
    if marker in source:
        old=source[source.index(marker):].rstrip()
        print("\n".join("-"+l for l in old.splitlines()))
    else:
        print(" always @(posedge I_clk) O_row <= rom[I_addr];\n endmodule")
    print("\n".join("+"+l for l in new.splitlines()))
    print("*** End Patch")


if __name__=="__main__":
    main()
