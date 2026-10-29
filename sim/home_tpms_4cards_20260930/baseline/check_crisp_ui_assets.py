"""Independent packed-asset and actual ModelSim pixel checks for crisp UI."""
from pathlib import Path
import re
from PIL import Image
from generate_home_font_patch import rows
from generate_crisp_ui_fonts import HOME, STATUS, rom_lines
from generate_bottom_nav_icons import tiles, PLACEMENTS, rgb
from generate_album_cover_rom import packed_cover, packed_qq

ROOT=Path(__file__).resolve().parent.parent
HDL=ROOT/"src/user_source/hdl_source"
frame=Image.open(ROOT/"sim/home_nav_app_20260930/preview.ppm").convert("RGB")
background=Image.open(ROOT/"best_result/CAR01.BMP").convert("RGB")
checked=0

for filename,kind in (("video_home_overlay.v","home"),("video_status_overlay.v","status"),
                      ("osd_alpha_overlay.v","osd"),("vehicle_hazard_overlay.v","warning")):
    source=(HDL/filename).read_text(encoding="utf-8")
    for line in rom_lines(kind).splitlines():
        assert line in source,(filename,line)
    # Also reject stale nonzero words which were removed by sharpening.
    pattern=(r"    set_row\(8'h[0-9A-F]+, 32'h[0-9A-F]+\);[^\n]*" if kind=="osd" else
             r"    rom\[9'h[0-9A-F]+\] = (?:32|12|16)'h[0-9A-F]+;[^\n]*")
    assert re.findall(pattern,source)==rom_lines(kind).splitlines(),filename

def check(x,y,expected):
    global checked
    assert frame.getpixel((x,y))==expected,(x,y,frame.getpixel((x,y)),expected)
    checked+=1

# Compare the entire footer, including blank margins, both temperatures and
# every antialiased boundary; this also detects a one-pixel synchronous skew.
expected=Image.new("RGB",(640,40),(255,255,255))
data=tiles()
for tile,ox,oy,width,height in PLACEMENTS:
    _,_,pixels=data[tile]
    for y in range(height):
        for x in range(width):
            expected.putpixel((ox+x,oy-440+y),rgb(pixels[y*width+x],tile))
for y in range(40):
    for x in range(640):check(x,y+440,expected.getpixel((x,y)))
source=(HDL/"video_home_overlay.v").read_text(encoding="utf-8")
words=[0]*1024
for a,w in re.findall(r"rom\[10'd(\d+)\] = 16'h([0-9A-F]+);",source):words[int(a)]=int(w,16)
address=0
for width,height,pixels in data:
    for base in range(0,len(pixels),8):
        word=sum(pixels[base+lane]<<(14-2*lane) for lane in range(8))
        assert words[address]==word,(address,word,words[address]);address+=1
assert address==1008 and not any(words[address:])

# Cover and QQ logo must coexist in one BRAM, with independent palettes.
art=(HDL/"video_album_cover_rom.v").read_text(encoding="utf-8")
indices=[0]*2048
for a,index in re.findall(r"rom\[11'd(\d+)\] = 4'd(\d+);",art):indices[int(a)]=int(index)
for ox,oy,size,base,getter in ((234,338,40,0,packed_cover),(384,338,20,1600,packed_qq)):
    pixels,colors,_=getter()
    for y in range(size):
        for x in range(size):
            index=pixels[y*size+x]
            assert indices[base+y*size+x]==index
            color=(255,255,255) if not index else (
                (116,204,238) if base==0 and index==15 else colors[index-1])
            check(ox+x,oy+y,color)
assert not any(indices[2000:])

def label(ox,oy,text,colors,shadow=None):
    for n,ch in enumerate(text):
        bitmap=rows(ch,crisp=True)
        for y,line in enumerate(bitmap):
            for x,cov in enumerate(line):
                px=ox+n*16+x;py=oy+y
                color=colors[cov] if cov else (shadow if shadow and x and line[x-1] else
                      background.getpixel((px,py)) if oy<100 else
                      (220,228,235) if px==16 else (255,255,255))
                check(px,py,color)

clock=[None,(220,233,240),(242,247,250),(255,255,255)]
for ox,oy,text in ((504,54,"10月1日"),(592,54,"周一"),(544,82,"09:00")):
    label(ox,oy,text,clock,(7,19,28))
for ox,text in ((16,"搜索目的地"),(112,"回家"),(160,"公司")):
    label(ox,375,text,[None,(173,185,197),(97,116,134),(36,57,75)])
label(288,340,"告白气球",[None,(167,180,192),(89,109,128),(29,48,66)])

for ox,text,width in ((18,"BRI:100",84),(114,"CON: 25",84),(210,"VOL:8",60)):
    for y in range(14):
        for dx in range(width):
            cell,col=divmod(dx,12)
            bitmap=rows(text[cell] if cell<len(text) else " ",10,14,crisp=True)
            cov=bitmap[y][col] if col<10 else 0
            left=bitmap[y][col-1] if 0<col<10 else 0
            color=([None,(168,186,198),(212,225,233),(244,249,252)][cov] if cov else
                   (19,33,46) if left else background.getpixel((ox+dx,16+y)))
            check(ox+dx,16+y,color)
print(f"PASS crisp UI: four font ROMs, 1008 toolbar words, 2000 cover/logo words; {checked} actual ModelSim pixels")
