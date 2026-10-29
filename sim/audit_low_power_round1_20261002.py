"""Read-only release gate. Activity counts are NOT a watt/power estimate."""
import json,re,sys
from audit_bmp_resize_20261002 import ROOT,sha,log_result
from check_resource_all_logs_20261002 import GROUPS

def main():
 seed=int(sys.argv[1]) if len(sys.argv)>1 else 7
 run=ROOT/f'src/td_project/resopt_Runs/phy_lowpower1_s{seed}_20261002'
 syn=ROOT/'src/td_project/resopt_Runs/syn_lowpower1_20261002'
 baseline=json.loads((ROOT/'best_result/clock_startup_fix_20261002_manifest.json').read_text())
 rollback='best_result/lab_ex5_i2s_v1.0_clock_startup_fix_20261002.bit'
 assert sha(ROOT/rollback)==baseline['bit_sha256']
 changed={f'src/user_source/hdl_source/{name}.v' for name in (
  'top_tf_hdmi_audio','audio_spectrum_analyzer','video_relax_overlay',
  'video_lyric_overlay','video_unified_clock','video_clock_digit_rom')}
 actual_changed={p for p,d in baseline['source_hashes'].items() if sha(ROOT/p)!=d}
 assert actual_changed==changed,actual_changed
 assert len(baseline['source_hashes'])==80
 for p in changed:
  assert sha(ROOT/'backup_before_low_power_round1_20261002'/(ROOT/p).name)==baseline['source_hashes'][p],p
 assert (run/'.bitgen.end.f').is_file() and (run/'.opt_route.end.f').is_file()
 assert not list(run.glob('*.error.f'))
 tdlog=max(run.glob('td_*.log'),key=lambda p:p.stat().st_mtime)
 assert not re.search(r'\b(?:SYN|PHY|BIT|RUN)-\d+\s+ERROR:',tdlog.read_text(errors='replace'))
 paths=sorted(p for base in (ROOT/'src/user_source',ROOT/'src/td_project/al_ip') for p in base.rglob('*')
              if p.is_file() and p.suffix.lower() in ('.v','.sv','.vhd','.tcl','.sdc','.adc'))
 assert len(paths)==80 and all(p.stat().st_mtime<=(syn/'.opt_gate.end.f').stat().st_mtime for p in paths)
 romfile='src/user_source/hdl_source/video_clock_digit_rom.v'
 entries=lambda s:dict(re.findall(r"rom\[9'd(\d+)\]\s*=\s*(16'h[0-9a-fA-F]+)",s))
 before=entries((ROOT/'backup_before_low_power_round1_20261002'/(ROOT/romfile).name).read_text())
 after=entries((ROOT/romfile).read_text())
 assert len(before)==480 and before==after,'clock font content changed'
 assert 'for(i=0;i<512;i=i+1)rom[i]=0;' in (ROOT/romfile).read_text()
 top=(ROOT/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text()
 assert top.count('.LOW_POWER(1)')==4 and top.count('(visual_analysis_enable)')==2
 assert '.PIPELINED_CLUSTER_ADDR (1)' in top
 area=(run/'lab_ex5_i2s_v1.0_phy.area').read_text()
 resources={k:int(re.search(r'^\s*#'+k+r'\s+(\d+)',area,re.M)[1]) for k in ('lut','reg','bram9k','bram32k','dsp','pll')}
 assert resources['lut']<19600
 assert all(resources[k]==baseline['resources'][k] for k in ('bram9k','bram32k','dsp','pll'))
 timing=(run/'lab_ex5_i2s_v1.0_pr.timing').read_text()
 clock_names=dict(re.findall(r'^\s*(clk\d+):\s+[\d.]+\s+\d+\s+(\S+)',timing,re.M))
 clocks=[]
 for s in timing.splitlines():
  if re.match(r'\s*clk\d+\s+local\s',s):
   v=s.split();clocks.append({'id':v[0],'name':clock_names[v[0]],'mhz':float(v[5]),'setup_ns':float(v[8]),'hold_ns':float(v[10])})
 logs=[]
 for folder,names in GROUPS.items():
  for name in names:logs.append(log_result(folder+'/'+(name if folder.endswith('lyrics_20261001') else 'tb_'+name)+'.log'))
 logs.append(log_result('sim/resource_all_20261002/bram32_font.log'))
 assert len(logs)==42
 for name in ('tb_unified_clock','tb_clock_overlay','tb_home_clock_replacement'):
  logs.append(log_result('sim/unified_clock_20261002/'+name+'.log'))
 for name in ('cache','silence'):logs.append(log_result('sim/fast_audio_20261002/'+name+'.log'))
 lpnames=('tb_low_power_idle','tb_low_power_spectrum','tb_video_lyric_overlay','tb_clock_overlay',
          'tb_video_relax_overlay','tb_relax_audio_response','tb_relax_clock_preview','tb_lyric_actual_pixels')
 for name in lpnames:logs.append(log_result('sim/low_power_round1_20261002/'+name+'.log'))
 assert len(logs)==55 and all(x['modified']>max((ROOT/p).stat().st_mtime for p in changed) for x in logs)
 identical_assets={}
 for name in ('font_cov.hex','events.hex','actual_pixels.hex','preview.ppm','intro.ppm','interlude.ppm'):
  old=ROOT/'sim/lyrics_20261001'/name
  new=ROOT/'sim/low_power_round1_20261002/actual_lyrics'/name
  assert sha(old)==sha(new),name
  identical_assets[name]=sha(new)
 spectrum=(ROOT/'sim/low_power_round1_20261002/tb_low_power_spectrum.log').read_text()
 a,b=map(int,re.search(r'RAM reads\s+(\d+) ->\s+(\d+)',spectrum).groups())
 clock=(ROOT/'sim/low_power_round1_20261002/tb_clock_overlay.log').read_text()
 c,d=map(int,re.search(r'CLOCK_READ_ENABLE enabled=\s*(\d+) / total=\s*(\d+) LOW_POWER=\s*1',clock).groups())
 bit=run/'lab_ex5_i2s_v1.0.bit';assert bit.stat().st_size>600000
 pcm=ROOT/'best_result/gaobai_qiqiu_full_20261001/MUSIC.PCM';assert sha(pcm)==baseline['pcm_sha256']
 buildfiles=[ROOT/'src/td_project/lab_ex5_i2s_v1.0.al']+[p/n for p in (syn,run) for n in ('lab_ex5_i2s_v1.0.prj','settings.cfg','lab_ex5_i2s_v1.0.tcl')]
 result={'release':'low_power_round1_20261002','seed':seed,'board_verified':False,'timing_closed':False,
  'baseline_user_reported_board_normal':True,'baseline_resources':baseline['resources'],'resources':resources,
  'resource_delta':{k:resources[k]-baseline['resources'][k] for k in resources},'clocks':clocks,
  'setup_wns_ns':float(re.search(r'SWNS: (-?[\d.]+)ns',timing)[1]),
  'hold_wns_ns':float(re.search(r'HWNS: (-?[\d.]+)ns',timing)[1]),
  'source_bit':bit.relative_to(ROOT).as_posix(),'bit_sha256':sha(bit),'bit_bytes':bit.stat().st_size,
  'delivery_bit':'best_result/lab_ex5_i2s_v1.0_low_power_round1_20261002.bit',
  'rollback_bit':rollback,'rollback_sha256':sha(ROOT/rollback),'pcm_sha256':sha(pcm),
  'source_hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in paths},
  'build_files':{p.relative_to(ROOT).as_posix():sha(p) for p in buildfiles},
  'report_hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in (run/'lab_ex5_i2s_v1.0_phy.area',run/'lab_ex5_i2s_v1.0_pr.timing')},
  'changed_sources':sorted(changed),'unchanged_source_count':74,'fresh_regressions':logs,
  'bit_exact_lyric_artifacts_against_default_mode':identical_assets,
  'activity_fixture':{'spectrum_continuous_reads':a,'spectrum_low_power_reads':b,
   'spectrum_read_enable_reduction_percent':round((1-b/a)*100,3),
   'clock_total_cycles':d,'clock_read_enabled_cycles':c,'clock_read_enable_reduction_percent':round((1-c/d)*100,3),
   'hidden_point_and_row_writes':0,'unchanged_lyric_pair_reloads':0,
   'measured_board_watts':None,'note':'Simulation enable requests only; not a total power estimate. No clock tree gating or voltage changes.'},
  'scope':'Page-gated visual analyzers, suspended hidden star work, change-only lyric character cache, clock ROM and spectrum history read enables. PCM, song timeline, alarms, memory/SD/HDMI core, clocks, constraints and TF content unchanged.'}
 print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
