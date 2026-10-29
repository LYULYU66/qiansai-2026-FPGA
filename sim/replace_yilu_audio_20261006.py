"""Decode the replacement recording; preserve prior delivered audio/artifacts."""
from pathlib import Path
import hashlib,json,subprocess,sys
import numpy as np
ROOT=Path(__file__).resolve().parent.parent
FF='C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe'
SOURCE=Path('C:/Users/28492/Desktop/车载图片/周杰伦 一路向北.mp3')
OUT=ROOT/'best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM'
def decode(source,old=False):
    args=['-f','s16le','-ar','48000','-ac','2'] if old else []
    b=subprocess.run([FF,'-v','error','-nostdin',*args,'-i',str(source),'-vn','-ac','1','-ar','2000','-f','f32le','pipe:1'],check=True,stdout=subprocess.PIPE).stdout
    return np.frombuffer(b,dtype='<f4')
if '--convert' in sys.argv:
    assert not OUT.exists(),'Refusing to overwrite replacement PCM'
    OUT.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run([FF,'-v','error','-nostdin','-n','-i',str(SOURCE),'-map','0:a:0','-vn','-ar','48000','-ac','2','-c:a','pcm_s16le','-f','s16le',str(OUT)],check=True)
    decoded_bytes=OUT.stat().st_size
    assert decoded_bytes%4==0
    pad=(-decoded_bytes)%512
    if pad:
        with OUT.open('ab') as f:f.write(bytes(pad))
    pcm=np.memmap(OUT,dtype='<i2',mode='r');v=pcm.astype(np.float64)/32768
    data={'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'output':str(OUT),'format':'raw signed 16-bit little-endian, 48000 Hz stereo interleaved, no header',
        'decoded_sample_frames':decoded_bytes//4,'padding_sample_frames':pad//4,
        'sample_frames':OUT.stat().st_size//4,'bytes':OUT.stat().st_size,'duration_seconds':OUT.stat().st_size/192000,
        'sha256':hashlib.sha256(OUT.read_bytes()).hexdigest(),'gain':'unchanged',
        'peak_dbfs':float(20*np.log10(np.max(np.abs(v)))),'rms_dbfs':float(20*np.log10(np.sqrt(np.mean(v*v)))),
        'nonzero_samples':int(np.count_nonzero(pcm))}
    print('*** Begin Patch\n*** Add File: best_result/yilu_replace_20261006/pcm_manifest.json')
    for line in json.dumps(data,ensure_ascii=True,indent=2).splitlines():print('+'+line)
    print('*** End Patch')
elif '--compare' in sys.argv:
    new=decode(SOURCE);old=decode(ROOT/'best_result/yiluxiangbei_full_20261005/MUSIC.PCM',True)
    # Compare 6-second mono excerpts over +/- 8 seconds using normalized correlation.
    # Distinguishes constant offset from a different mix or time-stretched recording.
    for t in [20,35,50,65,80,95,110,140,155,170,185,200,215,230,245,270]:
        n=12000;a=old[int(t*2000):int(t*2000)+n].astype(np.float64);a-=a.mean()
        lo=max(0,int((t-8)*2000));b=new[lo:int((t+14)*2000)].astype(np.float64)
        fftn=1<<(len(b)+n-2).bit_length()
        c=np.fft.irfft(np.fft.rfft(b,fftn)*np.fft.rfft(a[::-1],fftn),fftn)[n-1:len(b)]
        integral=np.r_[0,np.cumsum(b*b)];energy=integral[n:]-integral[:-n]
        corr=c/np.sqrt(np.maximum(energy,1e-20)*np.dot(a,a))
        k=int(np.argmax(np.abs(corr)));print(f'old {t:6.2f}s -> new {(lo+k)/2000:7.3f}s; shift={(lo+k)/2000-t:+7.3f}s; correlation={corr[k]:.4f}',flush=True)
