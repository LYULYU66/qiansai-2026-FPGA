"""Local draft timestamps for locating the user-supplied lyrics in the new mix."""
from pathlib import Path
import sys,os,subprocess,json
ROOT=Path(__file__).resolve().parent.parent
CACHE=ROOT/'tmp/lyrics_asr_20261001'
sys.path.insert(0,str(CACHE/'deps'))
os.environ['HF_HUB_DISABLE_XET']='1'
from faster_whisper import WhisperModel
import numpy as np
source='C:/Users/28492/Desktop/车载图片/周杰伦 一路向北.mp3'
audio=np.frombuffer(subprocess.run(['C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe','-v','error','-nostdin','-i',source,'-vn','-ac','1','-ar','16000','-f','f32le','pipe:1'],check=True,stdout=subprocess.PIPE).stdout,dtype='<f4')
model=WhisperModel('small',device='cpu',compute_type='int8',cpu_threads=6,download_root=str(CACHE/'models'),local_files_only=True)
segments,info=model.transcribe(audio,language='zh',beam_size=5,word_timestamps=True,vad_filter=False,condition_on_previous_text=False)
data={'source':source,'status':'draft_not_lyrics_authority','segments':[]}
for s in segments:
    data['segments'].append({'start':s.start,'end':s.end,'text':s.text,'words':[{'start':w.start,'end':w.end,'word':w.word} for w in s.words or []]})
    print(f'Local ASR located {s.end:.1f}s / {info.duration:.1f}s',flush=True,file=sys.stderr)
print('*** Begin Patch\n*** Add File: tmp/yilu_replace_20261006/transcription_draft.json')
for line in json.dumps(data,ensure_ascii=True,indent=2).splitlines():print('+'+line)
print('*** End Patch')
