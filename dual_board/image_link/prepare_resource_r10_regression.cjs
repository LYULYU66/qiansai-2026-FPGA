// Derive isolated runners from accepted regression scripts, not old logs.
const fs=require('fs'),path=require('path');
const sim=path.join(__dirname,'sim'), out=path.join(sim,'resource_round10_20261005');
const inputs=[
 ['audio_offload','hw_round6_20261005/run_offload_modelsim.do'],
 ['audio_media','hw_round6_20261005/run_audio_modelsim.do'],
 ['native_home','run_home_native_read.do'],
 ['writer_full','run_writer_full_frame.do'],
 ['boundary','hw_round8_20261005/run_boundary.do'],
 ['retry','hw_round8_20261005/run_retry.do']
];
for(const [name,file] of inputs) {
  let text=fs.readFileSync(path.join(sim,file),'utf8');
  text=text.replace(/work_player_round6_audio/g,'work_resource10_audio')
           .replace(/work_home_native7/g,'work_resource10_native')
           .replace(/work_writer_full7/g,'work_resource10_writer')
           .replace(/work_player_boundary8/g,'work_resource10_boundary');
  text=text.replace(/\$(source_path|source4)\/audio_waveform_analyzer\.v/g,'../rtl/resource_round10_20261005/audio_waveform_analyzer.v');
  text=text.replace(/-wlf (?:hw_round6_20261005|hw_round7_20261005|hw_round8_20261005)\//g,'-wlf resource_round10_20261005/');
  text=text.replace(/^quit -code 0\s*$/gm,'');
  fs.writeFileSync(path.join(out,'run_'+name+'.do'),text);
}
console.log('Prepared six isolated R10 integrated regression runners. Execute master from image_link/sim.');
