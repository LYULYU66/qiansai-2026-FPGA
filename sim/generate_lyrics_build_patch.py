"""Emit isolated synthesis/route scripts; preserve all previous build runs."""
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
TD=ROOT/"src/td_project"
RUNS=TD/"resopt_Runs"
FILES=("audio_lyric_timeline.v","video_lyric_overlay.v","lyric_song_data.v")
def entries(prefix):
    return "\n".join(f'''            <File Path="{prefix}{name}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{61+i}"/>
                </FileInfo>
            </File>''' for i,name in enumerate(FILES))
def add(path,text):
    assert not path.exists(),path
    print(f"*** Add File: {path.as_posix()}")
    for line in text.splitlines(): print("+"+line)
if __name__=="__main__":
    print("*** Begin Patch")
    base=(RUNS/"syn/lab_ex5_i2s_v1.0.prj").read_text(encoding="utf-8")
    # Anlogic exports unescaped ampersands in attribute values. Keep its own
    # project spelling consistently, while only appending the new files.
    source_entries=entries("../../../user_source/hdl_source/").replace("P&amp;R","P&R")
    prj=base.replace("        </Verilog>",source_entries+"\n        </Verilog>")
    for name,template in [("syn_lyrics_20261001","syn"),
                          ("phy_lyrics_20261001","phy_home_tpms_car_20260930")]:
        target=RUNS/name
        add(target/"lab_ex5_i2s_v1.0.prj",prj)
        add(target/"lab_ex5_i2s_v1.0.tcl",(RUNS/template/"lab_ex5_i2s_v1.0.tcl").read_text(encoding="utf-8"))
        cfg=(RUNS/template/"settings.cfg").read_text(encoding="utf-8")
        if name.startswith("phy_"): cfg=cfg.replace("set parent ../syn","set parent ../syn_lyrics_20261001")
        add(target/"settings.cfg",cfg)
    main=TD/"lab_ex5_i2s_v1.0.al"
    print(f"*** Update File: {main.as_posix()}\n@@")
    print("-        </Verilog>")
    for line in entries("../user_source/hdl_source/").replace("P&amp;R","P&R").splitlines(): print("+"+line)
    print("+        </Verilog>")
    print("*** End Patch")
