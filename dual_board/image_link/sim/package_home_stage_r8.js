const fs=require('fs'),path=require('path'),crypto=require('crypto');
const base=path.resolve(__dirname,'..'),root=path.resolve(base,'../..');
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex').toUpperCase();
const resolve=p=>path.isAbsolute(p)?p:path.join(root,p);
const old=JSON.parse(fs.readFileSync(path.join(base,'board_test_20261005/manifest.json'),'utf8'));
for(const b of old.builds){if(sha(resolve(b.bit.file))!==b.bit.sha256)throw Error('Previous SRAM bit changed');}
const main=JSON.parse(fs.readFileSync(path.join(base,'board_test_20261005/imagefix_r7_manifest.json'),'utf8'));
if(sha(main.bit)!==main.sha256)throw Error('A R7 bit changed');
const tests=[['sim/hw_round7_20261005/modelsim_home_native_read.log',['PASS native home read:']],
 ['sim/hw_round8_20261005/modelsim_boundary.log',['PASS player B boundary:','PASS home source:']],
 ['sim/hw_round8_20261005/modelsim_retry.log',['PASS home stage retry:']]];
const results=tests.map(([file,markers])=>{
 const p=path.join(base,file),t=fs.readFileSync(p,'utf8');
 if(markers.some(m=>!t.includes(m))||/\*\* (Fatal|Error):|Errors: [1-9]/.test(t)||!t.includes('# End time:'))throw Error('Test incomplete or failed: '+file);
 return {file:p,sha256:sha(p),passed:markers};
});
const name='MEDIA_SRAM_TEST_B_HOMESTAGE_R8_20261005',dir=path.join(base,'prj/media_b');
const log=path.join(dir,'td_20261005_172408.log'),build=fs.readFileSync(log,'utf8');
if(/ERROR|Error:/.test(build)||!build.includes('Generate bits file '+name+'.bit.'))throw Error('B build failed or incomplete');
const area=fs.readFileSync(path.join(dir,name+'_phy.area'),'utf8');
if(!area.includes('#lut                    11847'))throw Error('Unexpected routed area');
const timing=fs.readFileSync(path.join(dir,name+'_pr.timing'),'utf8');
if(!timing.includes('Confidence          : Routed')||!timing.includes('SWNS: -3.487ns'))throw Error('Unexpected timing');
const sources=[];
const project=fs.readFileSync(path.join(dir,name+'.al'),'utf8');
for(const match of project.matchAll(/<File Path="([^"]+)"/g)){
 const p=path.resolve(dir,match[1]);
 sources.push({file:p,sha256:sha(p)});
}
// Check exactly one source was replaced and no clock/IP/constraint mutation.
const previous=fs.readFileSync(path.join(dir,'MEDIA_SRAM_TEST_B_TF_20261005.al'),'utf8');
const expected=previous.replaceAll('MEDIA_SRAM_TEST_B_TF_20261005',name).replace('hw_round4_20261005/image_tf_source_hw.v','hw_round8_20261005/image_tf_source_hw.v');
if(project!==expected)throw Error('Unexpected B project difference');
const source=path.join(dir,name+'.bit'),out=path.join(base,'board_test_20261005',name+'.bit');
if(fs.existsSync(out)&&sha(out)!==sha(source))throw Error('Refuse different overwrite');
fs.copyFileSync(source,out);
fs.writeFileSync(path.join(base,'board_test_20261005','home_stage_r8_manifest.json'),JSON.stringify({
 generated_at:new Date().toISOString(),hardware_verified:false,
 release_status:'EXPERIMENTAL_SRAM_ONLY_NOT_TIMING_CLOSED',root_cause_confirmed:false,
 reported_issue:'Home application icon area partly corrupted after A R7 image startup fix.',
 change:'B-only one-pixel RGB/tag/first-marker staging removes packet-ready-to-home-consume cone.',
 paired_A:{file:main.bit,sha256:main.sha256},bit:{file:out,sha256:sha(out)},tests:results,
 area:{lut:11847,registers:7770,bram9k:28,bram32k:9,dsp:3,pll:3},
 timing:{global_setup_ns:-3.487,global_hold_ns:-1.540,udp_same_domain_setup_ns:-0.525},
 caveat:'UDP domain improved, global worst setup worsened. Behavioral application-memory model cannot prove physical SDRAM or network correctness.',
 source_manifest:sources,build_log:{file:log,sha256:sha(log)},
 reports:['phy.area','pr.timing'].map(s=>{const p=path.join(dir,name+'_'+s);return {file:p,sha256:sha(p)};})
},null,2));
console.log(out);console.log(sha(out));
