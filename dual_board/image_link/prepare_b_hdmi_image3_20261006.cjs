// Isolate the third-picture selection from the accepted second-picture build.
const fs=require('fs'),path=require('path');
const base=__dirname;
const oldBranch=path.join(base,'rtl/b_hdmi_20261006');
const branch=path.join(base,'rtl/b_hdmi_image3_20261006');
const oldProject=path.join(base,'prj/b_hdmi_20261006');
const project=path.join(base,'prj/b_hdmi_image3_20261006');
const oldName='MEDIA_B_HDMI_IMAGE2_20261006',name='MEDIA_B_HDMI_IMAGE3_20261006';
const oldSim=path.join(base,'sim/b_hdmi_20261006'),sim=path.join(base,'sim/b_hdmi_image3_20261006');
for(const dir of [branch,project,sim]){
 if(fs.existsSync(dir))throw Error('Already exists: '+dir);
 fs.mkdirSync(dir,{recursive:true});
}
for(const file of fs.readdirSync(oldBranch))fs.copyFileSync(path.join(oldBranch,file),path.join(branch,file));
const slash=s=>s.replaceAll('\\','/');
const xml=fs.readFileSync(path.join(oldProject,oldName+'.al'),'utf8')
 .replaceAll(slash(oldProject),slash(project)).replaceAll(slash(oldBranch),slash(branch)).replaceAll(oldName,name);
fs.writeFileSync(path.join(project,name+'.al'),xml);
const tcl=fs.readFileSync(path.join(oldProject,'build_b_hdmi.tcl'),'utf8')
 .replaceAll('rtl/b_hdmi_20261006','rtl/b_hdmi_image3_20261006').replaceAll(oldName,name);
fs.writeFileSync(path.join(project,'build_b_hdmi.tcl'),tcl);
for(const f of ['b_hdmi_models.v','tb_b_preview_source.v','tb_b_hdmi_boundary.v'])
 fs.copyFileSync(path.join(oldSim,f),path.join(sim,f));
let boundary=fs.readFileSync(path.join(oldSim,'run_boundary.do'),'utf8')
 .replaceAll('work_b_hdmi_boundary','work_b_hdmi_image3_boundary')
 .replaceAll('b_hdmi_20261006','b_hdmi_image3_20261006');
fs.writeFileSync(path.join(sim,'run_boundary.do'),boundary);
console.log('Third-image branch/project/tests cloned; second-image baseline preserved.');
