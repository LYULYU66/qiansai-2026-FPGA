"""Local forced alignment of the user's lyric text against their MP3.

Only estimated word alignment, not verified syllables. No audio upload and no
web lyric ingestion. Writes isolated generated timing artifacts.
"""
from pathlib import Path
import json, os, re, subprocess, sys
ROOT=Path(__file__).resolve().parent.parent
CACHE=ROOT/'tmp/lyrics_asr_20261001'
OUT=ROOT/'assets/lyrics/dualsong_20261005'
sys.path.insert(0,str(CACHE/'deps'))
os.environ['HF_HUB_DISABLE_XET']='1'
from faster_whisper import WhisperModel
from faster_whisper.tokenizer import Tokenizer
from faster_whisper.audio import pad_or_trim
import numpy as np
data=json.loads((ROOT/'assets/lyrics/yilu_user_transcript_20261005.json').read_text(encoding='utf-8'))
decoded=subprocess.run([r'C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe','-v','error','-nostdin',
    '-i',data['source'],'-map','0:a:0','-vn','-ac','1','-ar','16000','-f','f32le','pipe:1'],
    check=True,stdout=subprocess.PIPE).stdout
audio=np.frombuffer(decoded,dtype='<f4')
model=WhisperModel('small',device='cpu',compute_type='int8',cpu_threads=6,
    download_root=str(CACHE/'models'),local_files_only=True)
tokenizer=Tokenizer(model.hf_tokenizer,True,task='transcribe',language='zh')
lines=[]
for bi,b in enumerate(data['blocks']):
    texts=data['groups'][b['group']]
    features=model.feature_extractor(audio[int(b['start']*16000):int(b['end']*16000)])
    words=model.find_alignment(tokenizer,[tokenizer.encode(' '.join(texts))],
        model.encode(pad_or_trim(features)),min(features.shape[-1],3000))[0]
    chars=[]
    for w in words:
        plain=re.sub(r'\s+','',w['word'])
        start=b['start']+float(w['start']);end=b['start']+float(w['end'])
        for i,ch in enumerate(plain):
            chars.append((ch,start+(end-start)*i/len(plain),start+(end-start)*(i+1)/len(plain)))
    assert ''.join(c[0] for c in chars)==re.sub(r'\s+','',''.join(texts))
    offset=0
    for text in texts:
        starts=[];ends=[]
        for ch in text:
            if ch.isspace():
                starts.append(ends[-1]);ends.append(ends[-1])
            else:
                assert ch==chars[offset][0]
                starts.append(round(chars[offset][1]*100));ends.append(round(chars[offset][2]*100));offset+=1
        begin=starts[0]
        # Enforce monotonic printable columns even when word alignment is flat.
        for i in range(len(starts)):
            starts[i]=max(begin,starts[i],ends[i-1] if i else begin)
            ends[i]=max(starts[i]+(not text[i].isspace()),ends[i])
        assert len(text)<=16
        lines.append({'lrc_start_cs':begin,'text':text,'char_start_cs':starts,'char_end_cs':ends})
    print(f'Aligned block {bi+1}/{len(data["blocks"])} at {b["start"]:.1f}s',flush=True)
for i in range(len(lines)-1):
    if lines[i]['char_end_cs'][-1]>lines[i+1]['lrc_start_cs']:
        print(f'Boundary overlap at row {i}: end={lines[i]["char_end_cs"][-1]}, next={lines[i+1]["lrc_start_cs"]}',flush=True)
        # Quantised flat word boundaries can carry a few 10 ms ticks across
        # a line. Do not conceal larger block/window errors.
        assert lines[i]['char_end_cs'][-1]-lines[i+1]['lrc_start_cs']<=20
        deadline=lines[i+1]['lrc_start_cs']
        lines[i]['char_end_cs']=[min(v,deadline) for v in lines[i]['char_end_cs']]
        lines[i]['char_start_cs']=[min(v,lines[i]['char_end_cs'][j]) for j,v in enumerate(lines[i]['char_start_cs'])]
assert all(lines[i]['lrc_start_cs']<lines[i+1]['lrc_start_cs'] for i in range(len(lines)-1))
OUT.mkdir(parents=True,exist_ok=True)
target=OUT/'YILU_USER_AUDIO.karaoke.json'
if target.exists():raise SystemExit('Refusing to overwrite existing alignment')
result={'version':1,'provenance':data['provenance'],'source':data['source'],
    'time_unit':'centiseconds','sample_rate':48000,'song_samples':data['song_samples'],
    'alignment_method':'Local forced word alignment; characters subdivide word spans; estimated, requires on-board audition',
    'lines':lines}
target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
lrc=['[ti:一路向北]','[ar:周杰伦]','[offset:0]']
for line in lines:
    cs=line['lrc_start_cs'];lrc.append(f'[{cs//6000:02d}:{cs//100%60:02d}.{cs%100:02d}]{line["text"]}')
(OUT/'YILU_USER_AUDIO.lrc').write_text('\n'.join(lrc)+'\n',encoding='utf-8')
print(f'Saved {len(lines)} aligned display lines.',flush=True)
