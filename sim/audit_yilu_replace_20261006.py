"""Independent preservation, PCM format/content and ROM-source consistency audit."""
from pathlib import Path
import hashlib,json,re,subprocess
import numpy as np
ROOT=Path(__file__).resolve().parent.parent
asset=ROOT/'assets/lyrics/yilu_replace_20261006'
new=ROOT/'dual_board/image_link/rtl/yilu_replace_20261006'
old=ROOT/'dual_board/image_link/rtl/dualsong_20261005'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
baseline=json.loads((ROOT/'dual_board/image_link/board_test_20261006/dual_stars/manifest.json').read_text(encoding='utf-8'))
for s in baseline['sources']:assert digest(ROOT/s['file'])==s['sha256'],s['file']
for a in baseline['artifacts']:assert digest(ROOT/'dual_board/image_link/board_test_20261006/dual_stars'/a['file'])==a['sha256']
oldhdl=(old/'dual_lyric_song_data.v').read_text(encoding='utf-8');newhdl=(new/'dual_lyric_song_data.v').read_text(encoding='utf-8')
assert oldhdl.split('module lyric_line_rom',1)[1]==newhdl.split('module lyric_line_rom',1)[1],'Font/character ROM changed'
entries=lambda s:{int(a):int(b,16) for a,b in re.findall(r"rom\[(\d+)\]=18'h([0-9a-f]+);",s)}
a=entries(oldhdl);b=entries(newhdl)
assert {k:v for k,v in a.items() if k<512}=={k:v for k,v in b.items() if k<512}
m=json.loads((asset/'rom_manifest.json').read_text(encoding='utf-8'));lyrics=json.loads((asset/'YILU_USER_AUDIO.karaoke.json').read_text(encoding='utf-8'))
prior=json.loads((ROOT/'assets/lyrics/dualsong_20261005/YILU_USER_AUDIO.karaoke.json').read_text(encoding='utf-8'))
assert [r['text'] for r in lyrics['lines']]==[r['text'] for r in prior['lines']]
assert m['glyphs']==218 and m['event_counts']==[373,360]
assert [b[512+i] for i in range(360)]==m['events1']
for row in lyrics['lines']:
    assert len(row['text'])==len(row['char_start_cs'])==len(row['char_end_cs'])
    assert row['lrc_start_cs']==row['char_start_cs'][0]
    assert all(s<=e for s,e in zip(row['char_start_cs'],row['char_end_cs']))
    assert all(a<=b for a,b in zip(row['char_end_cs'],row['char_end_cs'][1:]))
pcm=ROOT/'best_result/yilu_replace_20261006/TF_CARD/MUSIC2.PCM'
manifest=json.loads((pcm.parent.parent/'pcm_manifest.json').read_text(encoding='utf-8'))
decoded=subprocess.run(['C:/Users/28492/AppData/Local/kzip_sogou/ffmpeg.exe','-v','error','-nostdin','-i',lyrics['source'],'-vn','-map','0:a:0','-ar','48000','-ac','2','-c:a','pcm_s16le','-f','s16le','pipe:1'],check=True,stdout=subprocess.PIPE).stdout
raw=pcm.read_bytes();assert raw[:len(decoded)]==decoded,'PCM differs from source decode'
assert len(raw)==56489984 and len(raw)%512==0 and not any(raw[len(decoded):])
assert len(raw)//4==lyrics['song_samples']==14122496 and digest(pcm)==manifest['sha256'].upper()
for f in ['top_dual_image_hw.v','remote_audio_compute_hw.v','audio_lyric_timeline.v']:
    s=(new/f).read_text(encoding='utf-8');assert '14295040' not in s and '57180160' not in s
    assert ('14122496' in s or '56489984' in s)
color=json.loads((asset/'cover_manifest.json').read_text(encoding='utf-8'))
assert color['size']==[64,64] and color['distinct_rgb565_colors']>500
checks={'baseline_sources_unchanged':len(baseline['sources']),'baseline_bits_unchanged':2,
        'gaobai_events_unchanged':373,'char_and_font_roms_byte_identical':True,
        'user_lyric_rows_preserved':len(lyrics['lines']),'replacement_events':360,
        'pcm_exact_source_decode':True,'padding_ms':manifest['padding_sample_frames']/48,
        'cover_native_pixels':4096,'cover_distinct_colors':color['distinct_rgb565_colors'],
        'alignment_status':'Estimated local word alignment, syllables need on-board audition'}
print('*** Begin Patch\n*** Add File: best_result/yilu_replace_20261006/asset_audit.json')
for line in json.dumps(checks,indent=2).splitlines():print('+'+line)
print('*** End Patch')
