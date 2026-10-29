"""Align user-provided text to the replacement recording using cached local model."""
from pathlib import Path
import sys,os,json,re,subprocess
ROOT=Path(__file__).resolve().parent.parent
CACHE=ROOT/'tmp/lyrics_asr_20261001'
sys.path.insert(0,str(CACHE/'deps'))
os.environ['HF_HUB_DISABLE_XET']='1'
from faster_whisper import WhisperModel
from faster_whisper.tokenizer import Tokenizer
from faster_whisper.audio import pad_or_trim
import numpy as np
data=json.loads((ROOT/'assets/lyrics/yilu_user_transcript_20261005.json').read_text(encoding='utf-8'))
source='C:/Users/28492/Desktop/车载图片/周杰伦 一路向北.mp3'
# Vocal onsets located by the draft, with a small lead-in. Alignment's first
# token otherwise absorbs a long instrumental prefix and starts too early.
windows=[(35.72,62,'verse1'),(63.3,89.65,'verse2'),(89.65,118,'chorus'),
         (139.22,166.5,'verse1'),(167.24,193.4,'verse2'),(193.4,221.8,'chorus'),
         (221.92,251.3,'final'),(251.96,258,'outro')]
audio=np.frombuffer(subprocess.run(['C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe','-v','error','-nostdin','-i',source,'-vn','-ac','1','-ar','16000','-f','f32le','pipe:1'],check=True,stdout=subprocess.PIPE).stdout,dtype='<f4')
model=WhisperModel('small',device='cpu',compute_type='int8',cpu_threads=6,download_root=str(CACHE/'models'),local_files_only=True)
tokenizer=Tokenizer(model.hf_tokenizer,True,task='transcribe',language='zh')
lines=[]
for bi,(start,stop,group) in enumerate(windows):
    texts=data['groups'][group]
    features=model.feature_extractor(audio[round(start*16000):round(stop*16000)])
    words=model.find_alignment(tokenizer,[tokenizer.encode(' '.join(texts))],model.encode(pad_or_trim(features)),min(features.shape[-1],3000))[0]
    chars=[]
    for word in words:
        plain=re.sub(r'\s+','',word['word'])
        a=start+float(word['start']);b=start+float(word['end'])
        chars.extend((ch,a+(b-a)*i/len(plain),a+(b-a)*(i+1)/len(plain)) for i,ch in enumerate(plain))
    assert ''.join(c[0] for c in chars)==re.sub(r'\s+','',''.join(texts))
    offset=0
    for text in texts:
        starts=[];ends=[]
        for ch in text:
            if ch.isspace():starts.append(ends[-1]);ends.append(ends[-1])
            else:
                assert ch==chars[offset][0]
                starts.append(round(chars[offset][1]*100));ends.append(round(chars[offset][2]*100));offset+=1
        begin=starts[0]
        for i in range(len(starts)):
            starts[i]=max(begin,starts[i],ends[i-1] if i else begin)
            ends[i]=max(starts[i]+(not text[i].isspace()),ends[i])
        assert len(text)<=16
        lines.append({'lrc_start_cs':begin,'text':text,'char_start_cs':starts,'char_end_cs':ends})
    print(f'Aligned replacement block {bi+1}/8',flush=True,file=sys.stderr)
for i in range(len(lines)-1):
    if lines[i]['char_end_cs'][-1]>lines[i+1]['lrc_start_cs']:
        deadline=lines[i+1]['lrc_start_cs']
        assert lines[i]['char_end_cs'][-1]-deadline<=20,(i,lines[i],lines[i+1])
        lines[i]['char_end_cs']=[min(v,deadline) for v in lines[i]['char_end_cs']]
        lines[i]['char_start_cs']=[min(v,lines[i]['char_end_cs'][j]) for j,v in enumerate(lines[i]['char_start_cs'])]
assert all(lines[i]['lrc_start_cs']<lines[i+1]['lrc_start_cs'] for i in range(len(lines)-1))
result={'version':2,'provenance':'User-supplied lyrics, locally aligned to replacement MP3; no internet transcription',
        'source':source,'time_unit':'centiseconds','sample_rate':48000,'song_samples':14122496,
        'alignment_method':'Cached Whisper forced word alignment; character spans subdivided within words; estimated, needs audition',
        'windows':windows,'lines':lines}
lrc=['[ti:一路向北]','[ar:周杰伦]','[offset:0]']
for line in lines:
    cs=line['lrc_start_cs'];lrc.append(f'[{cs//6000:02d}:{cs//100%60:02d}.{cs%100:02d}]{line["text"]}')
print('*** Begin Patch')
for path,content in [('YILU_USER_AUDIO.karaoke.json',json.dumps(result,ensure_ascii=True,indent=2)),('YILU_USER_AUDIO.lrc','\n'.join(lrc))]:
    dest='assets/lyrics/yilu_replace_20261006/'+path
    if (ROOT/dest).exists():
        print('*** Update File: '+dest);print('@@')
        for line in (ROOT/dest).read_text(encoding='utf-8').splitlines():print('-'+line)
    else:print('*** Add File: '+dest)
    for line in content.splitlines():print('+'+line)
print('*** End Patch')
