"""Read-only evidence gate for the BMP resizer release; emits JSON to stdout."""
from pathlib import Path
import hashlib, json, re, sys
from check_resource_all_logs_20261002 import GROUPS

ROOT=Path(__file__).resolve().parent.parent
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def log_result(relative):
    path=ROOT/relative
    content=path.read_text(encoding='utf-8',errors='replace')
    assert not re.search(r'\*\* (?:Error|Fatal):|\bFAIL\b',content),relative
    passed=[s.strip().removeprefix('# ') for s in content.splitlines() if s.startswith('# PASS')]
    assert passed and 'Errors: 0' in content,(relative,'not completed')
    return {'log':relative,'sha256':sha(path),'pass':passed,
            'modified':path.stat().st_mtime}

def main():
    results=[]
    for folder,names in GROUPS.items():
        for name in names:
            file=(name if folder.endswith('lyrics_20261001') else 'tb_'+name)+'.log'
            results.append(log_result(folder+'/'+file))
    results.append(log_result('sim/resource_all_20261002/bram32_font.log'))
    assert len(results)==42
    for name in ('small','native_small','high_resolution','native_full','reader',
                 'status','orientation','cache_pcm','bmp_lut_stress'):
        file='cache_pcm' if name=='cache_pcm' else ('bmp_lut_stress' if name=='bmp_lut_stress' else name)
        results.append(log_result('sim/bmp_resize_20261002/'+file+'.log'))
    seed=int(sys.argv[1]) if len(sys.argv)>1 else 7
    run=ROOT/f'src/td_project/resopt_Runs/phy_bmp_downscale_s{seed}_20261002'
    syn=ROOT/'src/td_project/resopt_Runs/syn_bmp_downscale_20261002'
    assert (run/'.bitgen.end.f').is_file() and (run/'.opt_route.end.f').is_file()
    assert not list(run.glob('*.error.f')),'A TD stage failed'
    td_log=max(run.glob('td_*.log'),key=lambda p:p.stat().st_mtime)
    assert not re.search(r'\b(?:SYN|PHY|BIT|RUN)-\d+\s+ERROR:',
                         td_log.read_text(encoding='utf-8',errors='replace')),'TD routing/build error'
    paths=sorted(p for base in (ROOT/'src/user_source',ROOT/'src/td_project/al_ip')
                 for p in base.rglob('*') if p.is_file() and p.suffix.lower() in
                 ('.v','.sv','.vhd','.tcl','.sdc','.adc'))
    assert len(paths)==77,len(paths)
    syn_time=(syn/'.opt_gate.end.f').stat().st_mtime
    assert all(p.stat().st_mtime<=syn_time for p in paths),'Source changed after synthesis'
    area=(run/'lab_ex5_i2s_v1.0_phy.area').read_text()
    resources={}
    for key in ('lut','reg','bram9k','bram32k','dsp','pll'):
        resources[key]=int(re.search(r'^\s*#'+key+r'\s+(\d+)',area,re.M)[1])
    assert resources['lut']<19600 and resources['bram9k']==46 and resources['bram32k']==7
    assert resources['dsp']==6 and resources['pll']==3
    timing=(run/'lab_ex5_i2s_v1.0_pr.timing').read_text()
    clocks=[]
    for line in timing.splitlines():
        if re.match(r'\s*clk\d+\s+local\s',line):
            values=line.split()
            clocks.append({'clock_id':values[0],'constraint_mhz':float(values[5]),
                           'setup_ns':float(values[8]),'hold_ns':float(values[10])})
    bit=run/'lab_ex5_i2s_v1.0.bit'
    # Native line memories add BRAM configuration payload to this project.
    assert bit.stat().st_size==678512
    baseline=ROOT/'best_result/lab_ex5_i2s_v1.0_lut_opt_20261002.bit'
    assert sha(baseline)=='AA7AC009CE23FB89151439C7DADB66ABE680780C304D9F0170D634D1849AD32E'
    pcm=ROOT/'best_result/gaobai_qiqiu_full_20261001/MUSIC.PCM'
    assert sha(pcm)=='8512A513C526C26A4F5E4C7BFD0A4DFB449F97FAED4FAE4C1016FB99CB3A1831'
    result={
        'release':'bmp_bilinear_downscale_20261002','seed':seed,
        'board_verified':False,'timing_closed':False,
        'baseline_bit_sha256':sha(baseline),'pcm_sha256':sha(pcm),
        'resources':resources,'setup_wns_ns':float(re.search(r'SWNS: (-?[\d.]+)ns',timing)[1]),
        'hold_wns_ns':float(re.search(r'HWNS: (-?[\d.]+)ns',timing)[1]),'clocks':clocks,
        'setup_tns_ns':float(re.search(r'STNS: (-?[\d.]+)ns',timing)[1]),
        'hold_tns_ns':float(re.search(r'HTNS: (-?[\d.]+)ns',timing)[1]),
        'source_bit':bit.relative_to(ROOT).as_posix(),'bit_sha256':sha(bit),'bit_bytes':bit.stat().st_size,
        'source_hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in paths},
        'build_files':{p.relative_to(ROOT).as_posix():sha(p) for p in
                       (ROOT/'src/td_project/lab_ex5_i2s_v1.0.al',
                        syn/'lab_ex5_i2s_v1.0.prj',syn/'settings.cfg',syn/'lab_ex5_i2s_v1.0.tcl',
                        run/'lab_ex5_i2s_v1.0.prj',run/'settings.cfg',run/'lab_ex5_i2s_v1.0.tcl')},
        'report_hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in
                         (run/'lab_ex5_i2s_v1.0_phy.area',run/'lab_ex5_i2s_v1.0_pr.timing')},
        'regressions':results,
        'format':{'bitmap':'24-bit uncompressed BI_RGB, DIB >=40 bytes, planes=1',
                  'min_width':640,'min_abs_height':480,
                  'max_width':65535,'max_abs_height':65535,'output':[640,480],
                  'aspect_ratio':'stretch to full output; no crop/letterbox',
                  'coordinate_fraction_bits':8,'horizontal_intermediate':'RGB Q8, no intermediate rounding',
                  'final_rounding':'round half up','row_direction':'positive/negative BMP heights supported'},
        'scope':'Downscale/identity only. Low-resolution enlargement removed; a source smaller than 640 wide or 480 high is rejected.'}
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
