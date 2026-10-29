const fs=require('fs'),p=require('path'),crypto=require('crypto');
const base=__dirname,root=p.resolve(base,'../..'),rel='dual_board/image_link/board_test_20261008/startup_fix';
const out=p.join(root,rel),sim=p.join(base,'sim/startup_fix_20261008');
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
if(fs.existsSync(p.join(out,'review_validation.json')))throw Error('Supplement already published');
const m=JSON.parse(fs.readFileSync(p.join(out,'manifest.json'),'utf8'));
for(const s of m.sources)if(hash(p.join(root,s.file))!==s.sha256)throw Error('Source changed: '+s.file);
for(const e of m.evidence)if(hash(p.join(out,e.file))!==e.sha256)throw Error('Evidence changed: '+e.file);
const log=fs.readFileSync(p.join(sim,'lock.log'),'utf8');
const pass=log.split(/\r?\n/).filter(l=>l.startsWith('# PASS scheduler locked request:'));
if(pass.length!==1||/\*\* (Fatal|Error)|Errors: [1-9]/.test(log))throw Error('Supplement failed');
const evidence=[];
for(const [src,dst] of [['lock.log','evidence/lock.log'],['tb_scheduler_lock.v','tests/tb_scheduler_lock.v'],['run_lock.do','tests/run_lock.do']]){
 const target=p.join(out,dst);if(fs.existsSync(target))throw Error('Exists '+dst);
 fs.copyFileSync(p.join(sim,src),target);evidence.push({file:dst,sha256:hash(target)});
}
const supplement={created_at:new Date().toISOString(),base_manifest_sha256:hash(p.join(out,'manifest.json')),added_pass_count:1,total_pass_count:m.total_pass_count+1,pass_lines:pass,evidence,
 review:'Independent read-only review found no new scheduler protocol bug. Added a port-only delayed-ACK test after a coverage gap was identified. Five reboot tests do not constitute exhaustive reset-phase coverage.',hardware_verified:false,timing_closed:false};
console.log('*** Begin Patch\n*** Add File: '+rel+'/review_validation.json');
for(const l of JSON.stringify(supplement,null,2).split('\n'))console.log('+'+l);console.log('*** End Patch');
