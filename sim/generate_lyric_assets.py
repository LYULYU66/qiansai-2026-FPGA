"""Pack supplied-audio LRC and shared Noto glyphs into synchronous ROMs.

Only emits apply_patch; no HDL files are written directly by this generator.
20x20 two-bit AA glyphs are tightly packed (400 pixels), not 32x32 padded.
Repeated lines and characters are deduplicated to minimize BRAM use.
"""
from pathlib import Path
import difflib
import json
import re
import sys
from generate_home_font_patch import rows

ROOT=Path(__file__).resolve().parent.parent
LRC=ROOT/"assets/lyrics/GAOBAI_3D_USER_AUDIO.lrc"
KARAOKE=ROOT/"assets/lyrics/GAOBAI_3D_USER_AUDIO.karaoke.json"
TARGET=ROOT/"src/user_source/hdl_source/lyric_song_data.v"
SONG_SAMPLES=10043560

def parse():
    events=[]
    unique=[""]
    glyphs=[" "]
    for line in LRC.read_text(encoding="utf-8").splitlines():
        m=re.fullmatch(r"\[(\d+):(\d+)\.(\d{2})\](.*)",line)
        if not m: continue
        cs=int(m[1])*6000+int(m[2])*100+int(m[3])
        text=m[4].strip()
        assert len(text)<=20,text
        if text not in unique: unique.append(text)
        for char in text:
            if char not in glyphs: glyphs.append(char)
        events.append((cs*480,unique.index(text)))
    assert len(events)<=64 and len(unique)<=32 and len(glyphs)*400<=65536
    assert all(events[i][0]<events[i+1][0] for i in range(len(events)-1))
    assert events[0]==(0,0) and events[-1][0]<SONG_SAMPLES
    return events,unique,glyphs


def karaoke_events():
    """Return (centiseconds,current line,next line,sung displayed columns).

    Each canonical LRC boundary resets the sung count. Character events are
    bounded strictly before the following LRC entry, so delayed word alignment
    can never restore an old lyric after the next line has begun. Spaces are
    counted together with the preceding letter without their own events.
    """
    boundaries,unique,_=parse()
    data=json.loads(KARAOKE.read_text(encoding="utf-8"))
    assert data["sample_rate"]==48000 and data["song_samples"]==SONG_SAMPLES
    aligned=iter(data["lines"])
    result=[]
    for index,(sample_time,line_id) in enumerate(boundaries):
        cs=sample_time//480
        following=next((lid for _,lid in boundaries[index+1:] if lid),0) if line_id else 0
        result.append((cs,line_id,following,0))
        if not line_id: continue
        text=unique[line_id]
        line=next(aligned)
        assert line["lrc_start_cs"]==cs and line["text"]==text
        endings=line["char_end_cs"]
        assert len(endings)==len(text)
        assert all(endings[i]<=endings[i+1] for i in range(len(endings)-1))
        deadline=(boundaries[index+1][0]//480-1) if index+1<len(boundaries) else SONG_SAMPLES//480
        for char_index,char in enumerate(text):
            if char.isspace(): continue
            sung=char_index+1
            while sung<len(text) and text[sung].isspace(): sung+=1
            end_cs=max(cs+1,min(int(endings[char_index]),deadline))
            entry=(end_cs,line_id,following,sung)
            if result[-1][0]==end_cs:
                assert result[-1][1:3]==entry[1:3]
                result[-1]=entry
            else:
                assert result[-1][0]<end_cs
                result.append(entry)
    assert next(aligned,None) is None
    assert len(result)<=512 and result[0]==(0,0,0,0)
    assert all(0<=cs<0x7FFF and current<32 and following<32 and sung<=20
               for cs,current,following,sung in result)
    assert all(result[i][0]<result[i+1][0] for i in range(len(result)-1))
    return result


def generate():
    events,unique,glyphs=parse()
    karaoke=karaoke_events()
    out=["// Generated from the corrected user-supplied audio transcript and its",
         "// locally aligned LRC; native 20px Noto Sans SC Medium, 2-bit AA.",
         f"// {len(events)} canonical line entries, {len(karaoke)} karaoke events,",
         f"// {len(unique)-1} distinct nonempty lines, {len(glyphs)} unchanged glyphs.",
         "// Characters inside one aligned word use equal-duration estimates.",
         "module lyric_event_rom(input wire I_clk,input wire [8:0] I_addr,output reg [38:0] O_event);",
         "// 512x30 packed BRAM: {centiseconds[14:0],current[4:0],next[4:0],sung[4:0]}.",
         "// Two synchronous stages: raw ROM read, then explicit shift/subtract x480.",
         "reg [29:0] rom [0:511];", "reg [29:0] raw;", "integer n;",
         "wire [14:0] cs = raw[29:15];",
         "wire [23:0] sample_time = (cs == 15'h7FFF) ? 24'hFFFFFF :",
         "                         ({cs,9'b0} - {4'b0,cs,5'b0});",
         "initial begin", "    for(n=0;n<512;n=n+1) rom[n]=30'h3FFF8000;"]
    for index,(cs,current,following,sung) in enumerate(karaoke):
        packed=(cs<<15)|(current<<10)|(following<<5)|sung
        out.append(f"    rom[{index}] = 30'h{packed:08X};")
    out.extend(["end", "always @(posedge I_clk) begin",
         "    raw <= rom[I_addr];", "    O_event <= {sample_time,raw[14:0]};", "end",
         "endmodule", "",
         "module lyric_line_rom(input wire I_clk,input wire [10:0] I_addr,",
         "    input wire [7:0] I_line,input wire [7:0] I_next_line,",
         "    output reg [7:0] O_char,output reg [4:0] O_length,output reg [4:0] O_next_length);",
         f"reg [7:0] rom [0:{len(unique)*32-1}];","integer n;","initial begin",
         f"    for(n=0;n<{len(unique)*32};n=n+1) rom[n]=8'd0;"])
    for lid,text in enumerate(unique):
        for col,char in enumerate(text):
            out.append(f"    rom[{lid*32+col}] = 8'd{glyphs.index(char)};")
    out.extend(["end","always @(posedge I_clk) O_char <= rom[I_addr];",
         "always @(*) begin", "    case(I_line)"])
    for lid,text in enumerate(unique):
        if text: out.append(f"        8'd{lid}: O_length=5'd{len(text)};")
    out.extend(["        default: O_length=5'd0;", "    endcase", "end",
         "always @(*) begin", "    case(I_next_line)"])
    for lid,text in enumerate(unique):
        if text: out.append(f"        8'd{lid}: O_next_length=5'd{len(text)};")
    out.extend(["        default: O_next_length=5'd0;", "    endcase", "end", "endmodule", "",
         "// Explicit 4096x2 banks prevent TD padding a deep/wide ROM into",
         "// more BRAMs. All bank reads and the bank selector share one cycle.",
         "module lyric_font_rom(input wire I_clk,input wire [15:0] I_addr,output wire [1:0] O_cov);",
         f"wire [{((len(glyphs)*400+4095)//4096)*2-1}:0] bank_cov;",
         "reg [3:0] bank_select;", "genvar b;", "generate",
         f"    for(b=0;b<{(len(glyphs)*400+4095)//4096};b=b+1) begin: banks",
         "        lyric_font_bank #(.BANK_ID(b)) bank(",
         "            .I_clk(I_clk),.I_addr(I_addr[11:0]),.O_cov(bank_cov[b*2 +: 2]));",
         "    end", "endgenerate", "always @(posedge I_clk) bank_select <= I_addr[15:12];",
         "assign O_cov = bank_cov[{bank_select,1'b0} +: 2];", "endmodule", "",
         "module lyric_font_bank #(parameter integer BANK_ID=0)(",
         "    input wire I_clk,input wire [11:0] I_addr,output reg [1:0] O_cov);",
         "reg [1:0] rom [0:4095];", "integer n;",
         "`ifdef LYRIC_FAST_SIM", "reg [15:0] packed_init [0:511];", "`endif",
         "initial begin", "`ifdef LYRIC_FAST_SIM", "    case(BANK_ID)"])
    for bank in range((len(glyphs)*400+4095)//4096):
        out.append(f'        {bank}: $readmemh("assets/lyrics/font_bank_{bank:02d}.hex",packed_init);')
    out.extend(["    endcase", "    for(n=0;n<4096;n=n+1)",
         "        rom[n]=packed_init[n>>3][(n&7)*2 +: 2];", "`else",
         "    for(n=0;n<4096;n=n+1) rom[n]=2'd0;", "    case(BANK_ID)"])
    pixels=[]
    for gid,char in enumerate(glyphs):
        for row in rows(char,20,20,crisp=True): pixels.extend(row)
    assert len(pixels)%8==0
    for bank in range((len(pixels)+4095)//4096):
        out.append(f"        {bank}: begin")
        for addr in range(512):
            start=bank*4096+addr*8
            packed=sum(cov << (x*2) for x,cov in enumerate(pixels[start:start+8]))
            if packed: out.append(f"            set_word({addr},16'h{packed:04X});")
        out.append("        end")
    out.extend(["    endcase", "`endif", "end", "task set_word;", "    input integer address;",
         "    input [15:0] word_data;", "    integer p;", "    begin",
         "        for(p=0;p<8;p=p+1) rom[address*8+p]=word_data[p*2 +: 2];",
         "    end", "endtask", "always @(posedge I_clk) O_cov <= rom[I_addr];", "endmodule", ""])
    print(f"line_events={len(events)} karaoke_events={len(karaoke)} "
          f"unique_lines={len(unique)} glyphs={len(glyphs)} font_bits={len(glyphs)*800}",file=sys.stderr)
    return "\n".join(out)

def emit_file_patch(path,new_lines,encoding="utf-8"):
    if path.exists():
        old_lines=path.read_text(encoding=encoding).splitlines()
        if old_lines==new_lines: return
        print(f"*** Update File: {path.as_posix()}")
        diff=list(difflib.unified_diff(old_lines,new_lines,n=3))
        for line in diff[2:]:
            print("@@" if line.startswith("@@") else line)
    else:
        print(f"*** Add File: {path.as_posix()}")
        for line in new_lines: print("+"+line)


if __name__=="__main__":
    text=generate()
    print("*** Begin Patch")
    emit_file_patch(TARGET,text.splitlines())
    events,unique,glyphs=parse()
    pixels=[c for char in glyphs for row in rows(char,20,20,crisp=True) for c in row]
    for bank in range((len(pixels)+4095)//4096):
        path=ROOT/f"assets/lyrics/font_bank_{bank:02d}.hex"
        words=[]
        for word in range(512):
            start=bank*4096+word*8
            packed=sum(cov << (x*2) for x,cov in enumerate(pixels[start:start+8]))
            words.append(f"{packed:04X}")
        emit_file_patch(path,words,encoding="ascii")
    print("*** End Patch")
