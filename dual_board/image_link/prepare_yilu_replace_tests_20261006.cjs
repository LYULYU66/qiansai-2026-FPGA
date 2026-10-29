const fs=require('fs'),p=require('path'),base=__dirname,root=p.resolve(base,'../..');
const dir='sim/yilu_replace_20261006';
const manifest=JSON.parse(fs.readFileSync(p.join(root,'assets/lyrics/yilu_replace_20261006/rom_manifest.json'),'utf8'));
const jobs=[
 ['sim/dualsong_20261005/run_features.do',dir+'/run_features.do'],
 ['sim/dualsong_20261005/tb_dualsong_timeline.v',dir+'/tb_dualsong_timeline.v'],
 ['sim/dualsong_20261005/run_audio.do',dir+'/run_audio.do'],
 ['sim/dual_stars_20261006/run_boundary.do',dir+'/run_boundary.do'],
 ['sim/dual_stars_20261006/tb_b_hdmi_boundary.v',dir+'/tb_b_hdmi_boundary.v'],
 ['sim/dualsong_20261005/run_reader.do',dir+'/run_reader.do'],
];
console.log('*** Begin Patch');
for(const [old,dest] of jobs){
 let s=fs.readFileSync(p.join(base,old),'utf8');
 s=s.replaceAll('work_dualsong_features','work_yilu_features').replaceAll('work_dualsong_rx','work_yilu_rx')
  .replaceAll('work_dualsong_audio','work_yilu_audio').replaceAll('work_dual_stars_boundary','work_yilu_boundary')
  .replaceAll('work_dualsong_reader','work_yilu_reader');
 for(const f of ['audio_lyric_timeline.v','dual_lyric_song_data.v','remote_audio_compute_hw.v'])
  s=s.replaceAll('../rtl/dualsong_20261005/'+f,'../rtl/yilu_replace_20261006/'+f);
 s=s.replaceAll('14295040','14122496').replaceAll('14295039','14122495').replaceAll('57180160','56489984');
 if(old.endsWith('tb_dualsong_timeline.v')){
  s=s.replace('count_events=bank?358:373;',`count_events=bank?${manifest.event_counts[1]}:373;`)
   .replace('reg [4:0] expected_current,expected_next;','reg [4:0] expected_current,expected_next;\nreg [17:0] ref_events[0:1023];\ninteger expected_due;')
   .replace('repeat(5)@(negedge clk);rst=0;',`$readmemh("../../../assets/lyrics/yilu_replace_20261006/events_ref.hex",ref_events);\n repeat(5)@(negedge clk);rst=0;`)
   .replace('count_events=bank?', 'expected_due=0;\n  count_events=bank?')
   .replace('code=dut.due_code;saved_index=dut.event_index;',
    'code=dut.due_code;saved_index=dut.event_index;\n   expected_due=expected_due+(ref_events[bank*512+event_no]>>6)*480;\n   if(dut.event_due!=expected_due||code!=ref_events[bank*512+event_no][5:0])$fatal(1,"ROM/audio timestamp mismatch");');
 }
 if(old.endsWith('run_features.do'))s=s.replaceAll('dualsong_20261005/tb_dualsong_timeline.v','yilu_replace_20261006/tb_dualsong_timeline.v');
 if(old.endsWith('tb_b_hdmi_boundary.v'))s=s.replace('$fatal(1,"B top song-match CDC mismatch");',
  '$fatal(1,"B top song-match CDC mismatch");\n  if(dut.u_remote_compute.song_type_sync[1] !== (expected_samples==14122496))$fatal(1,"new song bank selection wrong");');
 if(old.endsWith('run_boundary.do'))s=s.replaceAll('dual_stars_20261006/tb_b_hdmi_boundary.v','yilu_replace_20261006/tb_b_hdmi_boundary.v');
 // Keep unchanged benchmark paths; only put new traces in the isolated directory.
 s=s.replaceAll('-wlf dualsong_20261005/','-wlf yilu_replace_20261006/').replaceAll('-wlf dual_stars_20261006/','-wlf yilu_replace_20261006/');
 console.log('*** Add File: dual_board/image_link/'+dest);for(const l of s.trimEnd().split(/\r?\n/))console.log('+'+l);
}
const oldHDL=fs.readFileSync(p.join(base,'rtl/dualsong_20261005/dual_lyric_song_data.v'),'utf8');
let ref=new Array(1024).fill(0x3ffff);
for(const m of oldHDL.matchAll(/rom\[(\d+)\]=18'h([0-9a-f]+);/g))if(Number(m[1])<512)ref[Number(m[1])]=parseInt(m[2],16);
manifest.events1.forEach((v,i)=>ref[512+i]=v);
console.log('*** Add File: assets/lyrics/yilu_replace_20261006/events_ref.hex');for(const v of ref)console.log('+'+v.toString(16).padStart(5,'0'));
console.log('*** End Patch');
