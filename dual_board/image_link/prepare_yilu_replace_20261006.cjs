// Emit isolated source/project clones as apply_patch; released inputs stay intact.
const fs=require('fs'),p=require('path'),base=__dirname,root=p.resolve(base,'../..');
const slash=s=>s.replaceAll('\\','/'),branch='rtl/yilu_replace_20261006';
const jobs=[
 ['rtl/dual_stars_20261006/top_dual_image_hw.v',branch+'/top_dual_image_hw.v'],
 ...['audio_lyric_timeline.v','remote_audio_compute_hw.v'].map(f=>['rtl/dualsong_20261005/'+f,branch+'/'+f]),
];
const group=process.argv[2];
let files=[];
if(group==='rtl')for(const [old,dest] of jobs){
 let text=fs.readFileSync(p.join(base,old),'utf8').replaceAll('14295040','14122496').replaceAll('57180160','56489984');
 files.push([p.join('dual_board/image_link',dest),text]);
}
if(group==='generator'){
 let s=fs.readFileSync(p.join(root,'sim/generate_dualsong_lyrics_20261005.py'),'utf8')
 .replaceAll('rtl/dualsong_20261005','rtl/yilu_replace_20261006')
 .replaceAll('assets/lyrics/dualsong_20261005','assets/lyrics/yilu_replace_20261006')
 .replaceAll('29700','29421').replaceAll('14295040','14122496');
 files.push(['sim/generate_yilu_replace_lyrics_20261006.py',s]);
}
if(group==='projects')for(const board of ['a','b']){
 const oldDir=p.join(base,'prj/dual_stars_'+board+'_20261006');
 const newDir=p.join(base,'prj/yilu_replace_'+board+'_20261006');
 const oldName='MEDIA_'+board.toUpperCase()+'_DUAL_STARS_20261006';
 const name='MEDIA_'+board.toUpperCase()+'_YILU_REPLACE_20261006';
 let xml=fs.readFileSync(p.join(oldDir,oldName+'.al'),'utf8').replaceAll(slash(oldDir),slash(newDir)).replaceAll(oldName,name);
 for(const [old,dest] of jobs)xml=xml.replaceAll(slash(p.join(base,old)),slash(p.join(base,dest)));
 for(const f of ['dual_lyric_song_data.v','song2_cover_rom.v','video_song_cover_overlay.v'])
  xml=xml.replaceAll('/rtl/dualsong_20261005/'+f,'/'+branch+'/'+f);
 files.push([slash(p.relative(root,p.join(newDir,name+'.al'))),xml]);
 let tcl=fs.readFileSync(p.join(oldDir,'build_stars.tcl'),'utf8').replaceAll(oldName,name);
 files.push([slash(p.relative(root,p.join(newDir,'build_replace.tcl'))),tcl]);
}
if(!files.length)throw Error('Select rtl, generator, or projects');
console.log('*** Begin Patch');
for(const [dest,text] of files){if(fs.existsSync(p.join(root,dest)))throw Error('Already exists '+dest);
 console.log('*** Add File: '+slash(dest));for(const l of text.trimEnd().split(/\r?\n/))console.log('+'+l);
}console.log('*** End Patch');
