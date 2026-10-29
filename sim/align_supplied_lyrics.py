"""Align the corrected supplied-audio transcript against the supplied MP3.

Emits apply_patch for word-derived character timing JSON. The existing LRC
remains the canonical line-boundary source and is never overwritten.
No lyrics are fetched from the network and no audio is uploaded.
"""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "tmp/lyrics_asr_20261001"
sys.path.insert(0,str(WORK / "deps"))
os.environ["HF_HUB_DISABLE_XET"]="1"
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"]="1"
import numpy as np
from faster_whisper import WhisperModel
from faster_whisper.tokenizer import Tokenizer
from faster_whisper.audio import pad_or_trim

source=Path(r"C:/Users/28492/xwechat_files/wxid_5n1i5mtgjsdh22_d795/temp/RWTemp/2026-09/9e20f478899dc29eb19741386f9343c8/周杰伦 - 告白气球 (3D环绕版).mp3")
data=json.loads((ROOT/"assets/lyrics/gaobai_supplied_transcript.json").read_text(encoding="utf-8"))
decoded=subprocess.run([r"C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe","-v","error","-nostdin",
    "-i",str(source),"-map","0:a:0","-vn","-ac","1","-ar","16000","-f","f32le","pipe:1"],
    check=True,stdout=subprocess.PIPE).stdout
audio=np.frombuffer(decoded,dtype="<f4")
model=WhisperModel("small",device="cpu",compute_type="int8",cpu_threads=6,
    download_root=str(WORK/"models"),local_files_only=True)
tokenizer=Tokenizer(model.hf_tokenizer,True,task="transcribe",language="zh")
events=[(0.0,"")]
alignment_detail=[]
for bi,b in enumerate(data["blocks"]):
    lines=data[b["group"]]
    if "slice" in b: lines=lines[slice(*b["slice"])]
    clip=audio[int(b["start"]*16000):int(b["end"]*16000)]
    features=model.feature_extractor(clip)
    encoded=model.encode(pad_or_trim(features))
    text=" ".join(lines)
    words=model.find_alignment(tokenizer,[tokenizer.encode(text)],encoded,
        min(features.shape[-1],3000))[0]
    char_times=[]
    for w in words:
        chars=re.sub(r"\s+","",w["word"])
        word_start=b["start"]+float(w["start"])
        word_end=b["start"]+float(w["end"])
        for ci,ch in enumerate(chars):
            # Whisper aligns words, not independently verified syllables.
            # Distribute each word's span evenly across its displayed letters.
            char_end=word_start+(word_end-word_start)*(ci+1)/len(chars)
            char_start=word_start+(word_end-word_start)*ci/len(chars)
            char_times.append((ch,word_start,word_end,char_end,char_start))
    actual="".join(c[0] for c in char_times)
    target=re.sub(r"\s+","",text)
    assert actual==target,(bi,actual,target)
    offset=0
    for line in lines:
        count=len(re.sub(r"\s+","",line))
        start=char_times[offset][1]
        # Alignment can assign a leading instrumental gap to one syllable.
        # Keep its last 0.7s, rather than showing a lyric seconds too early.
        if char_times[offset][2]-start>0.9:
            start=char_times[offset][2]-0.7
        end=char_times[offset+count-1][2]
        events.append((round(start,2),line))
        endings=[]
        beginnings=[]
        nonspace=0
        for char in line:
            if char.isspace():
                endings.append(endings[-1] if endings else round(start*100))
                beginnings.append(endings[-1])
            else:
                endings.append(round(char_times[offset+nonspace][3]*100))
                beginnings.append(round(char_times[offset+nonspace][4]*100))
                nonspace+=1
        alignment_detail.append({"start":round(start,2),"end":round(end,2),
            "text":line,"char_end_cs":endings,"char_start_cs":beginnings})
        print(f"aligned block={bi} start={start:.2f}s end={end:.2f}s",file=sys.stderr,flush=True)
        offset+=count
    if bi==2: events.append((87.0,""))
events.append((206.5,""))
assert all(events[i][0]<events[i+1][0] for i in range(len(events)-1)),events
lines=["[ti:告白气球]","[ar:周杰伦]","[length:03:29.24]","[offset:0]"]
for time,text in events:
    cs=round(time*100)
    lines.append(f"[{cs//6000:02d}:{cs//100%60:02d}.{cs%100:02d}]{text}")
path=ROOT/"assets/lyrics/GAOBAI_3D_USER_AUDIO.lrc"
canonical=[]
if path.exists():
    for line in path.read_text(encoding="utf-8").splitlines():
        match=re.fullmatch(r"\[(\d+):(\d+)\.(\d{2})\](.*)",line)
        if match:
            canonical.append((int(match[1])*6000+int(match[2])*100+int(match[3]),
                              match[4].strip()))
else:
    canonical=[(round(time*100),text) for time,text in events]

aligned_iter=iter(alignment_detail)
karaoke_lines=[]
clamped=0
for ei,(start_cs,text) in enumerate(canonical):
    if not text: continue
    aligned=next(aligned_iter)
    assert aligned["text"]==text, ("LRC/alignment line order differs",ei)
    deadline=canonical[ei+1][0]-1 if ei+1<len(canonical) else 20924
    assert deadline>start_cs
    endings=[]
    previous=start_cs+1
    for raw_end in aligned["char_end_cs"]:
        end=max(start_cs+1,min(raw_end,deadline),previous)
        if end!=raw_end: clamped+=1
        endings.append(end)
        previous=end
    assert len(endings)==len(text)
    starts=[max(start_cs,min(int(begin),endings[ci]))
            for ci,begin in enumerate(aligned["char_start_cs"])]
    for ci in range(1,len(starts)):
        starts[ci]=max(starts[ci],endings[ci-1])
    karaoke_lines.append({"lrc_start_cs":start_cs,"text":text,
        "char_start_cs":starts,"char_end_cs":endings})
assert next(aligned_iter,None) is None
karaoke={"version":1,"time_unit":"centiseconds","sample_rate":48000,
    "song_samples":10043560,
    "alignment_method":"Local forced word alignment of the user-supplied audio; "
        "characters within a word evenly divide its duration; start/end spans "
        "hold the highlight during silent gaps. LRC line boundaries "
        "take priority. These are estimated timings, not hand-verified syllable boundaries.",
    "lines":karaoke_lines}
json_path=ROOT/"assets/lyrics/GAOBAI_3D_USER_AUDIO.karaoke.json"
json_lines=json.dumps(karaoke,ensure_ascii=False,indent=2).splitlines()
print(f"karaoke lines={len(karaoke_lines)} displayed_characters="
      f"{sum(len(line['text']) for line in karaoke_lines)} clamped_endings={clamped}",
      file=sys.stderr,flush=True)
print("*** Begin Patch")
if not path.exists():
    print(f"*** Add File: {path.as_posix()}")
    for line in lines: print("+"+line)
if json_path.exists():
    print(f"*** Update File: {json_path.as_posix()}\n@@")
    for line in json_path.read_text(encoding="utf-8").splitlines(): print("-"+line)
else:
    print(f"*** Add File: {json_path.as_posix()}")
for line in json_lines: print("+"+line)
print("*** End Patch")
