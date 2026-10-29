// Mechanical isolation only. Never rewrite a released project or source branch.
const fs=require('fs'),path=require('path'),base=__dirname;
const slash=p=>p.replaceAll('\\','/');
const branch=path.join(base,'rtl/dual_stars_20261006');
const sim=path.join(base,'sim/dual_stars_20261006');
for(const p of [branch,sim]){if(fs.existsSync(p))throw Error('Already exists: '+p);fs.mkdirSync(p,{recursive:true});}
for(const f of fs.readdirSync(path.join(base,'rtl/b_hdmi_image3_20261006')))
 fs.copyFileSync(path.join(base,'rtl/b_hdmi_image3_20261006',f),path.join(branch,f));
for(const [old,f] of [['rtl/dualsong_20261005','top_dual_image_hw.v'],['rtl','media_control_packet.v']])
 fs.copyFileSync(path.join(base,old,f),path.join(branch,f));
function cloneProject(oldDir,oldName,newDir,name,isA){
 const oldP=path.join(base,'prj',oldDir),newP=path.join(base,'prj',newDir);
 if(fs.existsSync(newP))throw Error('Already exists: '+newP);fs.mkdirSync(newP,{recursive:true});
 let xml=fs.readFileSync(path.join(oldP,oldName+'.al'),'utf8')
  .replaceAll(slash(oldP),slash(newP)).replaceAll(oldName,name)
  .replaceAll(slash(path.join(base,'rtl/b_hdmi_image3_20261006')),slash(branch))
  .replaceAll(slash(path.join(base,'rtl/media_control_packet.v')),slash(path.join(branch,'media_control_packet.v')));
 if(isA)xml=xml.replaceAll(slash(path.join(base,'rtl/dualsong_20261005/top_dual_image_hw.v')),slash(path.join(branch,'top_dual_image_hw.v')));
 const entry=`<File Path="${slash(path.join(branch,'video_dual_star_overlay.v'))}"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="450"/></FileInfo></File>`;
 xml=xml.replace('</Verilog>',entry+'\n</Verilog>');
 fs.writeFileSync(path.join(newP,name+'.al'),xml);
 let tcl=fs.readFileSync(path.join(oldP,isA?'build_dualsong.tcl':'build_b_hdmi.tcl'),'utf8').replaceAll(oldName,name);
 if(!isA)tcl=tcl.replaceAll('rtl/b_hdmi_image3_20261006','rtl/dual_stars_20261006');
 fs.writeFileSync(path.join(newP,'build_stars.tcl'),tcl);
}
cloneProject('dualsong_a_20261005','MEDIA_SRAM_TEST_A_DUALSONG_20261005','dual_stars_a_20261006','MEDIA_A_DUAL_STARS_20261006',true);
cloneProject('b_hdmi_image3_20261006','MEDIA_B_HDMI_IMAGE3_20261006','dual_stars_b_20261006','MEDIA_B_DUAL_STARS_20261006',false);
for(const f of ['tb_b_hdmi_boundary.v','tb_b_preview_source.v','tb_preview_selection.v','b_hdmi_models.v'])
 fs.copyFileSync(path.join(base,'sim/b_hdmi_image3_20261006',f),path.join(sim,f));
for(const f of ['run_boundary.do','run_selection.do']){
 let code=fs.readFileSync(path.join(base,'sim/b_hdmi_image3_20261006',f),'utf8')
  .replaceAll('b_hdmi_image3_20261006','dual_stars_20261006')
  .replaceAll('work_b_hdmi_image3','work_dual_stars')
  .replaceAll('../rtl/media_control_packet.v','../rtl/dual_stars_20261006/media_control_packet.v');
 if(f==='run_boundary.do')code=code.replace('vsim -voptargs', 'vlog -sv -work $work4 ../rtl/dual_stars_20261006/video_dual_star_overlay.v\nvsim -voptargs');
 fs.writeFileSync(path.join(sim,f),code);
}
console.log('Isolated A+B star projects and tests created. Released bits untouched.');
