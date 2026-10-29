"""Read-only release check for the third logic optimization round."""
import json
import re
import sys
from audit_bmp_resize_20261002 import ROOT, sha, log_result
from check_resource_all_logs_20261002 import GROUPS


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    baseline = json.loads((ROOT / 'best_result/logic_round2_20261002_manifest.json').read_text())
    run = ROOT / f'src/td_project/resopt_Runs/phy_logic_r3_s{seed}_20261003'
    syn = ROOT / 'src/td_project/resopt_Runs/syn_logic_r3_20261003'
    source = 'src/user_source/hdl_source/video_status_overlay.v'
    changed = {p for p, digest in baseline['source_hashes'].items() if sha(ROOT / p) != digest}
    assert changed == {source}, changed
    assert len(baseline['source_hashes']) == 80
    assert sha(ROOT / 'backup_before_logic_round3_20261003/video_status_overlay.v') == baseline['source_hashes'][source]
    reference = (ROOT / 'sim/logic_round3_20261003/video_status_overlay_round2_reference.v').read_text()
    reference = reference.replace('video_status_overlay_round2_reference', 'video_status_overlay')
    reference = reference.replace('video_status_font_rom_round2_reference', 'video_status_font_rom')
    assert reference.strip() == (ROOT / 'backup_before_logic_round3_20261003/video_status_overlay.v').read_text().strip()
    assert sha(ROOT / 'best_result/lab_ex5_i2s_v1.0_logic_round2_20261002.bit') == baseline['bit_sha256']
    assert sha(ROOT / baseline['known_board_normal_rollback']) == baseline['known_board_normal_rollback_sha256']
    assert sha(ROOT / 'best_result/gaobai_qiqiu_full_20261001/MUSIC.PCM') == baseline['pcm_sha256']
    project = 'src/td_project/lab_ex5_i2s_v1.0.al'
    # The GUI-owned .al changed after round 2. This build uses the frozen .prj,
    # so preserve the user's .al while verifying that the run project is exact.
    old_prj = 'src/td_project/resopt_Runs/syn_logic_r2_20261002/lab_ex5_i2s_v1.0.prj'
    assert sha(syn / 'lab_ex5_i2s_v1.0.prj') == baseline['build_files'][old_prj]
    paths = sorted(p for base in (ROOT / 'src/user_source', ROOT / 'src/td_project/al_ip')
                   for p in base.rglob('*') if p.is_file() and p.suffix.lower() in
                   ('.v', '.sv', '.vhd', '.tcl', '.sdc', '.adc'))
    assert len(paths) == 80
    assert (syn / '.opt_gate.end.f').is_file()
    assert all(p.stat().st_mtime <= (syn / '.opt_gate.end.f').stat().st_mtime for p in paths)
    assert (run / '.opt_route.end.f').is_file() and (run / '.bitgen.end.f').is_file()
    assert not list(run.glob('*.error.f'))
    tdlog = max(run.glob('td_*.log'), key=lambda p: p.stat().st_mtime)
    assert not re.search(r'\b(?:SYN|PHY|BIT|RUN)-\d+\s+ERROR:', tdlog.read_text(errors='replace'))
    area = (run / 'lab_ex5_i2s_v1.0_phy.area').read_text()
    resources = {key: int(re.search(r'^\s*#' + key + r'\s+(\d+)', area, re.M)[1])
                 for key in ('lut', 'reg', 'bram9k', 'bram32k', 'dsp', 'pll')}
    assert resources['lut'] < baseline['resources']['lut'], resources
    assert all(resources[key] == baseline['resources'][key]
               for key in ('bram9k', 'bram32k', 'dsp', 'pll'))
    timing = (run / 'lab_ex5_i2s_v1.0_pr.timing').read_text()
    clock_names = dict(re.findall(r'^\s*(clk\d+):\s+[\d.]+\s+\d+\s+(\S+)', timing, re.M))
    clocks = []
    for line in timing.splitlines():
        if re.match(r'\s*clk\d+\s+local\s', line):
            cols = line.split()
            clocks.append(dict(id=cols[0], name=clock_names[cols[0]], mhz=float(cols[5]),
                               setup_ns=float(cols[8]), hold_ns=float(cols[10])))
    logs = []
    for folder, names in GROUPS.items():
        for name in names:
            logs.append(log_result(folder + '/' + (name if folder.endswith('lyrics_20261001')
                                                  else 'tb_' + name) + '.log'))
    logs.append(log_result('sim/resource_all_20261002/bram32_font.log'))
    assert len(logs) == 42
    for name in ('tb_unified_clock', 'tb_clock_overlay', 'tb_home_clock_replacement'):
        logs.append(log_result('sim/unified_clock_20261002/' + name + '.log'))
    for name in ('cache', 'silence'):
        logs.append(log_result('sim/fast_audio_20261002/' + name + '.log'))
    for name in ('tb_low_power_idle', 'tb_low_power_spectrum', 'tb_video_lyric_overlay',
                 'tb_clock_overlay', 'tb_video_relax_overlay', 'tb_relax_audio_response',
                 'tb_relax_clock_preview', 'tb_lyric_actual_pixels'):
        logs.append(log_result('sim/low_power_round1_20261002/' + name + '.log'))
    logs.append(log_result('sim/logic_round2_20261002/native_rom.log'))
    for name in ('equivalence', 'resolution_status'):
        logs.append(log_result('sim/logic_round3_20261003/' + name + '.log'))
    assert len(logs) == 58
    assert all(entry['modified'] > (ROOT / source).stat().st_mtime for entry in logs)
    identical_assets = {}
    for name in ('font_cov.hex', 'events.hex', 'actual_pixels.hex',
                 'preview.ppm', 'intro.ppm', 'interlude.ppm'):
        old = ROOT / 'sim/lyrics_20261001' / name
        new = ROOT / 'sim/low_power_round1_20261002/actual_lyrics' / name
        assert sha(old) == sha(new), name
        identical_assets[name] = sha(new)
    bit = run / 'lab_ex5_i2s_v1.0.bit'
    assert bit.stat().st_size > 600000
    report = {'release': 'logic_round3_20261003', 'seed': seed, 'board_verified': False,
              'timing_closed': False, 'baseline_resources': baseline['resources'],
              'resources': resources,
              'resource_delta': {key: resources[key] - baseline['resources'][key]
                                 for key in resources},
              'setup_wns_ns': float(re.search(r'SWNS: (-?[\d.]+)ns', timing)[1]),
              'hold_wns_ns': float(re.search(r'HWNS: (-?[\d.]+)ns', timing)[1]),
              'clocks': clocks, 'bit_sha256': sha(bit), 'bit_bytes': bit.stat().st_size,
              'source_sha256': sha(ROOT / source), 'backup_sha256': baseline['source_hashes'][source],
              'main_project_current_sha256': sha(ROOT / project),
              'main_project_round2_sha256': baseline['build_files'][project],
              'rollback_sha256': baseline['bit_sha256'],
              'known_board_normal_rollback_sha256': baseline['known_board_normal_rollback_sha256'],
              'fresh_modelsim_logs': len(logs), 'pixel_artifacts_identical': identical_assets,
              'area_sha256': sha(run / 'lab_ex5_i2s_v1.0_phy.area'),
              'timing_sha256': sha(run / 'lab_ex5_i2s_v1.0_pr.timing')}
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
