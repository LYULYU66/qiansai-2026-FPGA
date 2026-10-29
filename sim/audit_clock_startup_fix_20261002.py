"""Read-only fingerprint, regression and routed-report gate for startup fix."""
import json,re,sys
from audit_bmp_resize_20261002 import ROOT,sha,log_result
from check_resource_all_logs_20261002 import GROUPS
def main():
 seed=int(sys.argv[1]) if len(sys.argv)>1 else 7
 run=ROOT/f'src/td_project/resopt_Runs/phy_clockfix_rows_s{seed}_20261002'
 syn=ROOT/'src/td_project/resopt_Runs/syn_clockfix_rows_20261002'
 assert (run/'.bitgen.end.f').is_file() and (run/'.opt_route.end.f').is_file()
 assert not list(run.glob('*.error.f'))
 tdlog=max(run.glob('td_*.log'),key=lambda p:p.stat().st_mtime)
 assert not re.search(r'\b(?:SYN|PHY|BIT|RUN)-\d+\s+ERROR:',tdlog.read_text(errors='replace'))
 baseline=json.loads((ROOT/'best_result/unified_clock_20261002_manifest.json').read_text())
 stable=json.loads((ROOT/'best_result/page3_relax_fast_audio_20261002_manifest.json').read_text())
 assert sha(ROOT/stable['delivery_bit'])==stable['bit_sha256']
 assert sha(ROOT/baseline['delivery_bit'])==baseline['bit_sha256']
 changed={'src/user_source/hdl_source/top_tf_hdmi_audio.v','src/user_source/hdl_source/SD/bmp_read.v','src/user_source/hdl_source/SD/sd_card_bmp.v','src/user_source/hdl_source/SD/bmp_bilinear_stream.v'}
 for path,digest in baseline['source_hashes'].items():
  if path not in changed: assert sha(ROOT/path)==digest,path
 paths=sorted(p for base in (ROOT/'src/user_source',ROOT/'src/td_project/al_ip') for p in base.rglob('*')
              if p.is_file() and p.suffix.lower() in ('.v','.sv','.vhd','.tcl','.sdc','.adc'))
 assert len(paths)==80
 assert all(p.stat().st_mtime<=(syn/'.opt_gate.end.f').stat().st_mtime for p in paths)
 area=(run/'lab_ex5_i2s_v1.0_phy.area').read_text()
 resources={k:int(re.search(r'^\s*#'+k+r'\s+(\d+)',area,re.M)[1]) for k in ('lut','reg','bram9k','bram32k','dsp','pll')}
 assert resources['lut']<19600
 assert all(resources[k]==baseline['resources'][k] for k in ('bram9k','bram32k','dsp','pll'))
 timing=(run/'lab_ex5_i2s_v1.0_pr.timing').read_text()
 clocks=[]
 for line in timing.splitlines():
  if re.match(r'\s*clk\d+\s+local\s',line):
   v=line.split();clocks.append({'id':v[0],'mhz':float(v[5]),'setup_ns':float(v[8]),'hold_ns':float(v[10])})
 logs=[]
 for folder,names in GROUPS.items():
  for name in names: logs.append(log_result(folder+'/'+(name if folder.endswith('lyrics_20261001') else 'tb_'+name)+'.log'))
 logs.append(log_result('sim/resource_all_20261002/bram32_font.log'))
 assert len(logs)==42
 for name in ('tb_unified_clock','tb_clock_overlay','tb_home_clock_replacement'):
  logs.append(log_result('sim/unified_clock_20261002/'+name+'.log'))
 for name in ('cache','silence','slow_pipeline','cluster_pipeline'):
  logs.append(log_result('sim/fast_audio_20261002/'+name+'.log'))
 assert len(logs)==49
 for name in ('small','native_small','full','high_resolution','clockfix_1280x960'):
  logs.append(log_result('sim/bmp_resize_20261002/'+name+'.log'))
 assert len(logs)==54
 scaler_mtime=(ROOT/'src/user_source/hdl_source/SD/bmp_bilinear_stream.v').stat().st_mtime
 assert all(x['modified']>scaler_mtime for x in logs[-5:])
 assert all(x['modified']>(ROOT/'src/user_source/hdl_source/top_tf_hdmi_audio.v').stat().st_mtime for x in logs)
 bit=run/'lab_ex5_i2s_v1.0.bit'
 assert bit.stat().st_size>600000
 pcm=ROOT/'best_result/gaobai_qiqiu_full_20261001/MUSIC.PCM'
 assert sha(pcm)==stable['pcm_sha256']
 top=(ROOT/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text()
 assert '.PIPELINED_CLUSTER_ADDR (1)' in top
 result={'release':'clock_startup_fix_20261002','seed':seed,'board_verified':False,'timing_closed':False,
 'resources':resources,'clocks':clocks,'source_bit':bit.relative_to(ROOT).as_posix(),
 'bit_sha256':sha(bit),'bit_bytes':bit.stat().st_size,'rollback_bit':stable['delivery_bit'],
 'rollback_sha256':stable['bit_sha256'],'rejected_bit':baseline['delivery_bit'],
 'source_hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in paths},
 'fresh_regressions':logs,'pcm_sha256':sha(pcm),
 'setup_wns_ns':float(re.search(r'SWNS: (-?[\d.]+)ns',timing)[1]),
 'hold_wns_ns':float(re.search(r'HWNS: (-?[\d.]+)ns',timing)[1]),
 'scope':'Separate cluster shift from sector addition with one FSM cycle; preserve BMP byte position; cache bilinear row neighbors once per destination row with one Y_PREP cycle; precision and clock visuals unchanged. Board validation required.',
 'root_cause_status':'Known timing risk addressed; board failure cause not yet confirmed.',
 'waveform':'sim/fast_audio_20261002/cluster_pipeline.vcd'}
 print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
