"""Read-only check of routed resources, build completion and preserved assets."""
from pathlib import Path
import argparse
import hashlib
import json
import re
ROOT=Path(__file__).resolve().parent.parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def area(path):
    text=path.read_text(encoding='utf-8',errors='replace')
    return {name:{'used':int(used),'total':int(total),'percent':float(percent)}
            for name,used,total,percent in re.findall(r'^#(lut|reg|bram|bram32k|dsp|pll)\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%',text,re.M)}

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--run',required=True)
    args=parser.parse_args()
    run=ROOT/'src/td_project/resopt_Runs'/args.run
    name='lab_ex5_i2s_v1.0'
    finish=run/'.bitgen.end.f'
    assert finish.is_file(), 'incomplete bitgen'
    assert (run/'.opt_route.end.f').is_file(), 'routing not completed'
    assert not any(p.stat().st_mtime>=finish.stat().st_mtime for p in run.glob('.*.error.f')), 'build error after bitgen'
    bit=run/f'{name}.bit'
    assert bit.is_file() and bit.stat().st_size>600000
    source_paths=sorted(p for base in (ROOT/'src/user_source',ROOT/'src/td_project/al_ip')
                        for p in base.rglob('*') if p.is_file() and p.suffix.lower() in ('.v','.sv','.vhd','.tcl','.sdc','.adc'))
    assert len(source_paths)==76,len(source_paths)
    assert all(p.stat().st_mtime<=finish.stat().st_mtime for p in source_paths),'source newer than bit'
    resources=area(run/f'{name}_phy.area')
    assert resources['bram']['used']==45 and resources['bram32k']['used']==5,resources
    assert resources['dsp']['used']==5 and resources['pll']['used']==3,resources
    assert resources['lut']['used']<16507,'LUT not reduced against delivered baseline'
    baseline=ROOT/'best_result/lab_ex5_i2s_v1.0_page2_music_card_dual_intro_20261002.bit'
    assert sha(baseline)=='DFA40F3436E036DDD1431D007D70408A0702864D988B17C9288B65E37BA6A474'
    pcm=ROOT/'best_result/gaobai_qiqiu_full_20261001/MUSIC.PCM'
    assert sha(pcm)=='8512A513C526C26A4F5E4C7BFD0A4DFB449F97FAED4FAE4C1016FB99CB3A1831'
    timing=(run/f'{name}_pr.timing').read_text(encoding='utf-8',errors='replace')
    status=re.search(r'SWNS: ([\d.-]+)ns, STNS: ([\d.-]+)ns\s+HWNS: ([\d.-]+)ns, HTNS: ([\d.-]+)ns',timing)
    assert status
    clocks=[line.strip() for line in timing.splitlines() if re.match(r'\s+clk\d+\s+local',line)]
    result={'run':args.run,'bit':bit.relative_to(ROOT).as_posix(),'bit_bytes':bit.stat().st_size,'bit_sha256':sha(bit),
            'resources':resources,'timing':dict(zip(('setup_wns_ns','setup_tns_ns','hold_wns_ns','hold_tns_ns'),map(float,status.groups()))),
            'clock_summary':clocks,'source_hashes':{p.relative_to(ROOT).as_posix():sha(p) for p in source_paths},
            'preserved_old_bit':sha(baseline),'preserved_music_pcm':sha(pcm)}
    print(json.dumps(result,ensure_ascii=False,indent=2))
