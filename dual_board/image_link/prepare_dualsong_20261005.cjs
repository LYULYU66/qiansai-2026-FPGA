// Isolate the two-song work from both accepted hardware and R10 candidates.
const fs=require('fs'),path=require('path');
const base=__dirname,root=path.resolve(base,'../..');
const branch=path.join(base,'rtl/dualsong_20261005');
if(fs.existsSync(branch))throw Error('Two-song branch already exists');
fs.mkdirSync(branch,{recursive:true});
const files={
  'top_dual_image_hw.v':'rtl/hw_round3_20261005/top_dual_image_hw.v',
  'image_media_board_b_hw.v':'rtl/hw_round4_20261005/image_media_board_b_hw.v',
  'image_tf_source_hw.v':'rtl/hw_round8_20261005/image_tf_source_hw.v',
  'sd_card_bmp_remote.v':'rtl/sd_card_bmp_remote.v',
  'audio_receipt_a.v':'rtl/hw_20261005/audio_receipt_hw.v',
  'audio_receipt_b.v':'rtl/hw_round6_20261005/audio_receipt_hw.v',
  'remote_audio_compute_hw.v':'rtl/hw_round4_20261005/remote_audio_compute_hw.v',
};
for(const [dest,src] of Object.entries(files))fs.copyFileSync(path.join(base,src),path.join(branch,dest));
for(const file of ['audio_lyric_timeline.v','lyric_song_data.v','video_lyric_overlay.v','SD/bmp_read.v'])
  fs.copyFileSync(path.join(root,'src/user_source/hdl_source',file),path.join(branch,path.basename(file)));
fs.copyFileSync(path.join(base,'constraints/media_a.adc'),path.join(branch,'media_a.adc'));
for(const board of ['a','b']){
  const original=path.join(base,'prj',board==='a'?'media_a_res10_seed4':'media_b');
  const old=board==='a'?'MEDIA_SRAM_TEST_A_RESOPT_R10_S4_20261005':'MEDIA_SRAM_TEST_B_RESOPT_R10_20261005';
  const name='MEDIA_SRAM_TEST_'+board.toUpperCase()+'_DUALSONG_20261005';
  const dest=path.join(base,'prj','dualsong_'+board+'_20261005');
  fs.mkdirSync(dest);
  let xml=fs.readFileSync(path.join(original,old+'.al'),'utf8');
  xml=xml.replace(/Path="([^"]+)"/g,(whole,src)=>{
    if(src===original.replaceAll('\\','/'))return 'Path="'+dest.replaceAll('\\','/')+'"';
    let resolved=path.resolve(original,src);
    for(const [to,from] of Object.entries(files))
      if(resolved===path.resolve(base,from))resolved=path.join(branch,to);
    for(const file of ['audio_lyric_timeline.v','lyric_song_data.v','video_lyric_overlay.v','SD/bmp_read.v'])
      if(resolved===path.resolve(root,'src/user_source/hdl_source',file))resolved=path.join(branch,path.basename(file));
    if(board==='a'&&resolved===path.resolve(base,'constraints/media_a.adc'))resolved=path.join(branch,'media_a.adc');
    return 'Path="'+resolved.replaceAll('\\','/')+'"';
  }).replaceAll(old,name);
  fs.writeFileSync(path.join(dest,name+'.al'),xml);
  let tcl=fs.readFileSync(path.join(original,'build_resource_r10.tcl'),'utf8').replaceAll(old,name);
  if(board==='a')tcl=tcl.replace('read_adc ../../constraints/media_a.adc','read_adc ../../rtl/dualsong_20261005/media_a.adc');
  fs.writeFileSync(path.join(dest,'build_dualsong.tcl'),tcl);
}
console.log('Isolated two-song source/project copies prepared; no baseline changed.');
