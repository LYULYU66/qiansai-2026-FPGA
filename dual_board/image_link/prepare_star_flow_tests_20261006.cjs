const fs=require('fs'),p=require('path'),base=__dirname;
const src='sim/dual_stars_20261006',dst='sim/dual_star_flow_20261006';
const jobs=[];
for(const f of ['tb_dual_stars.v','tb_star_control.v','tb_b_hdmi_preview.v']){
 let s=fs.readFileSync(p.join(base,src,f),'utf8');
 if(f==='tb_star_control.v')s=s.replace('if(wraps!=1)$fatal(1,"motion modulus incorrect, wraps=%0d",wraps);','if(time_master.speed_q4>64)$fatal(1,"motion velocity out of range");')
  .replace('1280-pixel wrap','eased bidirectional animation (modulus tested separately)');
 if(f==='tb_dual_stars.v')s=s.replace('if(lit_a<1000 || lit_b<1000 || seam_lights==0)',
  'if(lit_a<10000 || lit_b<10000 || seam_lights==0)')
  .replace('fractional shift, frame atomicity','fractional shift, 3 sizes/brightness layers, frame atomicity');
 jobs.push([dst+'/'+f,s]);
}
for(const f of ['run_stars.do','run_preview.do']){
 let s=fs.readFileSync(p.join(base,src,f),'utf8')
  .replaceAll('work_dual_stars_pixels','work_star_flow_pixels').replaceAll('work_dual_stars_preview','work_star_flow_preview')
  .replaceAll('+incdir+dual_stars_20261006','+incdir+dual_star_flow_20261006')
  .replaceAll('../rtl/dual_stars_20261006/video_dual_star_overlay.v','../rtl/dual_star_flow_20261006/video_dual_star_overlay.v');
 for(const t of ['tb_dual_stars.v','tb_star_control.v','tb_b_hdmi_preview.v'])s=s.replaceAll('dual_stars_20261006/'+t,'dual_star_flow_20261006/'+t);
 s=s.replaceAll('-wlf dual_stars_20261006/','-wlf dual_star_flow_20261006/');
 if(f==='run_stars.do')s=s.replace('vlog -sv -work $w +incdir+','vlog -sv -work $w dual_star_flow_20261006/tb_star_motion.v\nvlog -sv -work $w +incdir+')
  .replace('vsim -voptargs=+acc -onfinish stop -wlf dual_star_flow_20261006/star_control.wlf',
   'vsim -voptargs=+acc -onfinish stop -wlf dual_star_flow_20261006/motion.wlf $w.tb_star_motion\nlog -r /*\nrun -all\nquit -sim\nvsim -voptargs=+acc -onfinish stop -wlf dual_star_flow_20261006/star_control.wlf');
 jobs.push([dst+'/'+f,s]);
}
console.log('*** Begin Patch');for(const [f,s] of jobs){if(fs.existsSync(p.join(base,f)))throw Error('Already exists '+f);
 console.log('*** Add File: dual_board/image_link/'+f);for(const l of s.trimEnd().split(/\r?\n/))console.log('+'+l);
}console.log('*** End Patch');
