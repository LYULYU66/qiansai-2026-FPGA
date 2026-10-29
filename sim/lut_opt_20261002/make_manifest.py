"""Write best_result/lut_opt_20261002_manifest.json for the LUT-optimised bit."""
import glob
import hashlib
import json
import os
import re

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
RUN = 'src/td_project/resopt_Runs/phy_lut_opt_s3_20261002'


def sha(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest().upper()


def norm(path):
    return path.replace(os.sep, '/')


sources = sorted(
    norm(p) for p in glob.glob('src/user_source/**/*', recursive=True) +
    glob.glob('src/td_project/al_ip/**/*', recursive=True)
    if os.path.isfile(p) and re.search(r'\.(v|sv|vhd|tcl|sdc|adc)$', p))
area = open(RUN + '/lab_ex5_i2s_v1.0_phy.area', encoding='utf-8', errors='replace').read()


def resource(key):
    m = re.search(r'^#' + key + r'\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%', area, re.M)
    return {'used': int(m[1]), 'total': int(m[2]), 'percent': float(m[3])}


timing = open(RUN + '/lab_ex5_i2s_v1.0_pr.timing', encoding='utf-8', errors='replace').read()
status = re.search(r'SWNS: (-?[\d.]+)ns, STNS: (-?[\d.]+)ns\s+HWNS: (-?[\d.]+)ns, HTNS: (-?[\d.]+)ns', timing)
clocks = [line.strip() for line in timing.splitlines() if re.match(r'^\s+clk\d\s+local', line)]
stress = open('sim/lut_opt_20261002/bmp_lutopt_stress.log', encoding='utf-8').read()
previous = json.load(open('best_result/global_resource_opt_20261002_manifest.json', encoding='utf-8'))
old_bit = 'best_result/lab_ex5_i2s_v1.0_global_resource_opt_20261002.bit'
pcm = 'best_result/gaobai_qiqiu_full_20261001/MUSIC.PCM'
manifest = {
    'run': 'phy_lut_opt_s3_20261002',
    'synthesis_run': 'syn_lut_opt_20261002',
    'place_seed': 3,
    'bit': RUN + '/lab_ex5_i2s_v1.0.bit',
    'bit_bytes': os.path.getsize(RUN + '/lab_ex5_i2s_v1.0.bit'),
    'bit_sha256': sha(RUN + '/lab_ex5_i2s_v1.0.bit'),
    'resources': {k: resource(k) for k in ['lut', 'reg', 'bram', 'bram32k', 'dsp', 'pll']},
    'timing': {'setup_wns_ns': float(status[1]), 'setup_tns_ns': float(status[2]),
               'hold_wns_ns': float(status[3]), 'hold_tns_ns': float(status[4])},
    'clock_summary': clocks,
    'changed_sources_vs_global_resource_opt_20261002':
        [p for p in sources if previous['source_hashes'].get(p) != sha(p)],
    'bmp_read_stress_equivalence':
        [l[2:].strip() for l in stress.splitlines() if l.startswith('# PASS BMP_LUTOPT_STRESS 2')],
    'source_hashes': {p: sha(p) for p in sources},
    'preserved_old_bit': {'path': old_bit, 'sha256': sha(old_bit),
                          'matches_previous_manifest': sha(old_bit) == previous['bit_sha256']},
    'preserved_music_pcm': {'path': pcm, 'sha256': sha(pcm)},
}
with open('best_result/lut_opt_20261002_manifest.json', 'w', encoding='utf-8') as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)
print(len(sources), 'sources; changed:', manifest['changed_sources_vs_global_resource_opt_20261002'])
print('old bit unchanged:', manifest['preserved_old_bit']['matches_previous_manifest'])
print('previous PCM record:', json.dumps(previous['preserved_music_pcm'])[:200])
print('PCM now:', manifest['preserved_music_pcm']['sha256'])
print(manifest['bit_sha256'], manifest['resources']['lut'])
