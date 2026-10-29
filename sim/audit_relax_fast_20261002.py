"""Read-only release gate for the page-3 music-responsive ambient overlay."""
import json,re,sys
from audit_bmp_resize_20261002 import ROOT,sha,log_result
from check_resource_all_logs_20261002 import GROUPS

def main():
    seed=int(sys.argv[1]) if len(sys.argv)>1 else 7
    run=ROOT/f'src/td_project/resopt_Runs/phy_relax_fast_s{seed}_20261002'
    syn=ROOT/'src/td_project/resopt_Runs/syn_relax_fast_20261002'
    assert (run/'.bitgen.end.f').is_file() and (run/'.opt_route.end.f').is_file()
    assert not list(run.glob('*.error.f')),'A TD stage failed'
    tdlog=max(run.glob('td_*.log'),key=lambda p:p.stat().st_mtime)
    assert not re.search(r'\b(?:SYN|PHY|BIT|RUN)-\d+\s+ERROR:',tdlog.read_text(errors='replace'))
    baseline=json.loads((ROOT/'best_result/page3_relax_music_20261002_manifest.json').read_text())
    old_bit=ROOT/baseline['delivery_bit']
    assert sha(old_bit)==baseline['bit_sha256'],'Rollback bit changed'
    unchanged=[]
    for path,digest in baseline['source_hashes'].items():
        if path not in ('src/user_source/hdl_source/top_tf_hdmi_audio.v','src/user_source/hdl_source/video_relax_overlay.v','src/user_source/hdl_source/SD/bmp_read.v','src/user_source/hdl_source/SD/sd_card_bmp.v'):
            assert sha(ROOT/path)==digest,(path,'Unrelated source changed')
            unchanged.append(path)
    assert len(unchanged)==74
    paths=sorted(p for base in (ROOT/'src/user_source',ROOT/'src/td_project/al_ip')
                 for p in base.rglob('*') if p.is_file() and p.suffix.lower() in
                 ('.v','.sv','.vhd','.tcl','.sdc','.adc'))
    assert len(paths)==78
    assert all(p.stat().st_mtime<=(syn/'.opt_gate.end.f').stat().st_mtime for p in paths)
    area=(run/'lab_ex5_i2s_v1.0_phy.area').read_text()
    resources={key:int(re.search(r'^\s*#'+key+r'\s+(\d+)',area,re.M)[1])
               for key in ('lut','reg','bram9k','bram32k','dsp','pll')}
    assert resources['lut']<19600
    assert all(resources[k]==baseline['resources'][k] for k in ('bram9k','bram32k','dsp','pll'))
    timing=(run/'lab_ex5_i2s_v1.0_pr.timing').read_text()
    clocks=[]
    for line in timing.splitlines():
        if re.match(r'\s*clk\d+\s+local\s',line):
            v=line.split();clocks.append({'id':v[0],'mhz':float(v[5]),
                                          'setup_ns':float(v[8]),'hold_ns':float(v[10])})
    logs=[]
    for folder,names in GROUPS.items():
        for name in names:
            logs.append(log_result(folder+'/'+(name if folder.endswith('lyrics_20261001') else 'tb_'+name)+'.log'))
    logs.append(log_result('sim/resource_all_20261002/bram32_font.log'))
    assert len(logs)==42
    assert all(x['modified']>(ROOT/'src/user_source/hdl_source/top_tf_hdmi_audio.v').stat().st_mtime for x in logs)
    for name in ('tb_relax_page_policy','tb_video_relax_overlay','tb_relax_audio_response','tb_relax_scene_preview'):
        logs.append(log_result('sim/relax_20261002/'+name+'.log'))
    for name in ('cache','silence','slow'):
        logs.append(log_result('sim/fast_audio_20261002/'+name+'.log'))
    for name in ('reader','cache_pcm','orientation','status','bmp_lut_stress'):
        logs.append(log_result('sim/bmp_resize_20261002/'+name+'.log'))
    assert len(logs)==54
    inherited=[]
    bmp_baseline=json.loads((ROOT/'best_result/bmp_bilinear_downscale_20261002_manifest.json').read_text())
    for x in bmp_baseline['regressions'][42:46]:
        evidence=log_result(x['log'])
        assert evidence['sha256']==x['sha256']
        inherited.append(evidence)
    assert len(inherited)==4
    bit=run/'lab_ex5_i2s_v1.0.bit'
    assert bit.stat().st_size==baseline['bit_bytes']
    pcm=ROOT/'best_result/gaobai_qiqiu_full_20261001/MUSIC.PCM'
    assert sha(pcm)==baseline['pcm_sha256']
    build_files=(ROOT/'src/td_project/lab_ex5_i2s_v1.0.al',syn/'lab_ex5_i2s_v1.0.prj',
                 syn/'settings.cfg',syn/'lab_ex5_i2s_v1.0.tcl',run/'lab_ex5_i2s_v1.0.prj',
                 run/'settings.cfg',run/'lab_ex5_i2s_v1.0.tcl')
    top=(ROOT/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text()
    assert '.FAST_AUDIO_START  (1)' in top
    assert 'u_audio_fallback_tone' not in top
    assert '.I_i2s_DOUT         (audio_i2s_dout)' in top
    result={'release':'page3_relax_music_20261002','seed':seed,'board_verified':False,'timing_closed':False,
            'resources':resources,'baseline_resources':baseline['resources'],
            'resource_delta':{k:resources[k]-baseline['resources'][k] for k in resources},
            'setup_wns_ns':float(re.search(r'SWNS: (-?[\d.]+)ns',timing)[1]),
            'setup_tns_ns':float(re.search(r'STNS: (-?[\d.]+)ns',timing)[1]),
            'hold_wns_ns':float(re.search(r'HWNS: (-?[\d.]+)ns',timing)[1]),
            'hold_tns_ns':float(re.search(r'HTNS: (-?[\d.]+)ns',timing)[1]),'clocks':clocks,
            'source_bit':bit.relative_to(ROOT).as_posix(),'bit_sha256':sha(bit),'bit_bytes':bit.stat().st_size,
            'rollback_bit':baseline['delivery_bit'],'rollback_sha256':sha(old_bit),'pcm_sha256':sha(pcm),
            'source_hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in paths},
            'build_files':{p.relative_to(ROOT).as_posix():sha(p) for p in build_files},
            'unchanged_source_files':unchanged,'fresh_regressions':logs,
            'inherited_unchanged_bmp_regressions':inherited,
            'previews':{'sim/relax_20261002/relax_music.bmp':sha(ROOT/'sim/relax_20261002/relax_music.bmp'),
                        'sim/relax_20261002/relax_music_later.bmp':sha(ROOT/'sim/relax_20261002/relax_music_later.bmp'),
                        'sim/relax_20261002/relax_quiet.bmp':sha(ROOT/'sim/relax_20261002/relax_quiet.bmp')},
            'scope':'Page3 has 16 warm lights from 8 shared anchors, doubled horizontal and quadrupled vertical motion. Startup scale removed; FAST_AUDIO_START=1 sector-level BMP/PCM scheduling, existing 128-sample prefill retained. Pages1/2/4 and safety priority preserved.',
            'audio_visuals':'Existing VU/Goertzel drive eight anchors and eight secondary mirrored lights; one line cache and glow renderer. No new analyzer/DSP/BRAM. PCM starts before image caches finish in transport-model tests; initialization and scan delays remain.',
            'preview_audio':'Controlled VU/band fixtures, not a replay of the song. Separate real 48kHz PCM/analyzer integration test passes.'}
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
