"""Read-only release gate for 42 distinct resource-optimization benches."""
from pathlib import Path
import json
import re

ROOT=Path(__file__).resolve().parent.parent
GROUPS={
    'sim/resource_all_20261002':[
        'alarm_switch_control','audio_alarm_mixer','audio_visualizer_overlay',
        'video_image_adjust','video_status_overlay','osd_alpha_overlay',
        'video_frame_valid_gate','video_rgb_to_axis_640x480','video_pixel_diagnostics',
        'video_frame_crc_monitor','audio_spectrum_analyzer','audio_waveform_analyzer',
        'audio_visual_volume_mapping','uart_audio_control','hdmi_audio_pcm_i2s',
        'hdmi_audio_chain','bmp_pcm_stream','sd_card_bmp_playback',
        'audio_spectrum_resource_equivalence','bmp_resource_equivalence',
        'waveform_resource_equivalence','visualizer_latest_equivalence',
        'visualizer_latest_sequence','spectrum_abort_recovery','smooth_math_exhaustive'],
    'sim/vehicle_warning_4dir_20260930':[
        'vehicle_hazard_overlay','video_transition_effects','warning_preload',
        'warning_direct_switch','transition_resource_equivalence','vehicle_warning_page'],
    'sim/home_nav_app_20260930':[
        'home_light_apps','video_home_overlay','home_navigation_card',
        'home_dashboard_combined','nav_toolbar_alignment'],
    'sim/lyrics_20261001':[
        'audio_lyric_timeline','video_lyric_overlay','packed_font','actual','shared_card']}
if __name__=='__main__':
    results=[]
    for folder,names in GROUPS.items():
        for name in names:
            filename=(name if folder.endswith('lyrics_20261001') else 'tb_'+name)+'.log'
            path=ROOT/folder/filename
            text=path.read_text(encoding='utf-8',errors='replace')
            assert not re.search(r'\*\* (?:Error|Fatal):|\bFAIL\b',text),str(path)
            messages=[line.removeprefix('# ').strip() for line in text.splitlines()
                      if line.startswith('# PASS')]
            assert messages and 'Errors: 0' in text,(str(path),'missing completion PASS/zero errors')
            results.append({'log':path.relative_to(ROOT).as_posix(),'pass':messages})
    path=ROOT/'sim/resource_all_20261002/bram32_font.log'
    text=path.read_text(encoding='utf-8',errors='replace')
    assert not re.search(r'\*\* (?:Error|Fatal):|\bFAIL\b',text),str(path)
    messages=[line.removeprefix('# ').strip() for line in text.splitlines() if line.startswith('# PASS')]
    assert messages and 'Errors: 0' in text
    results.append({'log':path.relative_to(ROOT).as_posix(),'pass':messages})
    assert len(results)==42,len(results)
    print(json.dumps({'count':len(results),'results':results},ensure_ascii=False,indent=2))
