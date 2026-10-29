// Versioned integration; previous release and input hashes remain untouched.
const fs=require('fs'),p=require('path'),base=__dirname,jobs=[];
const rd=f=>fs.readFileSync(p.join(base,f),'utf8');
const branch='rtl/car_intro_20261007';
let s=rd('rtl/manual_dual_20261007/b_hdmi_preview.v');
s=s.replace('// No audio/ACR packets, fonts, frame effects or new PLL are instantiated.','// Instrument page has a local indexed-car introduction. No new PLL or audio.');
const old='video_rgb_to_axis_640x480 u_axis (.I_clk(video_clk),.I_rst(video_reset),\n    .I_vs(vs),.I_de(de),.I_rgb(frame_valid ? star_rgb : 24\'d0),';
if(!s.includes(old))throw Error('Missing axis connection');
s=s.replace(old,'wire car_vs,car_de;\nwire [23:0] car_rgb;\nvideo_car_intro u_car (.I_clk(video_clk),.I_rst(video_reset),\n    .I_enable(frame_valid && !frame_page),.I_vs(vs),.I_de(de),\n    .I_rgb(frame_valid ? star_rgb : 24\'d0),.O_vs(car_vs),.O_de(car_de),.O_rgb(car_rgb));\nvideo_rgb_to_axis_640x480 u_axis (.I_clk(video_clk),.I_rst(video_reset),\n    .I_vs(car_vs),.I_de(car_de),.I_rgb(car_rgb),');
jobs.push([branch+'/b_hdmi_preview.v',s]);
const oldfolder='prj/stars_opt_b_20261007',folder='prj/car_intro_b_20261007',oldstem='MEDIA_B_STARS_OPT_20261007',stem='MEDIA_B_CAR_INTRO_20261007';
s=rd(oldfolder+'/'+oldstem+'.al').replaceAll(oldfolder,folder).replaceAll(oldstem,stem).replaceAll('rtl/manual_dual_20261007/b_hdmi_preview.v',branch+'/b_hdmi_preview.v');
const root=p.resolve(base,'../..').replaceAll('\\','/');
s=s.replace('</Verilog>', ['video_car_intro.v','car_intro_rom.v'].map((f,i)=>'<File Path="'+root+'/dual_board/image_link/'+branch+'/'+f+'"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="'+(120+i)+'"/></FileInfo></File>').join('\n')+'\n</Verilog>');
jobs.push([folder+'/'+stem+'.al',s]);jobs.push([folder+'/build_flow.tcl',rd(oldfolder+'/build_flow.tcl').replaceAll(oldstem,stem)]);
// Boundary regression uses actual new B preview without changing SD/network.
s=rd('sim/stars_opt_20261007/run_boundary.do').replaceAll('work_stars_opt_boundary','work_car_intro_boundary').replaceAll('$branch/b_hdmi_preview.v','../'+branch+'/b_hdmi_preview.v').replaceAll('stars_opt_20261007/b_boundary.wlf','car_intro_20261007/b_boundary.wlf');
s=s.replace('vsim -voptargs','vlog -sv -work $w ../'+branch+'/video_car_intro.v ../'+branch+'/car_intro_rom.v\nvsim -voptargs');
jobs.push(['sim/car_intro_20261007/run_boundary.do',s]);
// Full native SDRAM/FIFO test is adapted only for the deliberate one-cycle
// compositor latency and independent car equation reference, not relaxed.
s=rd('sim/stars_opt_20261007/run_preview.do').replaceAll('work_stars_opt_preview','work_car_intro_preview').replaceAll('$branch/b_hdmi_preview.v','../'+branch+'/b_hdmi_preview.v').replaceAll('+incdir+stars_opt_20261007','+incdir+stars_opt_20261007 +incdir+car_intro_20261007').replaceAll('stars_opt_20261007/tb_b_hdmi_preview.v','car_intro_20261007/tb_b_hdmi_preview.v').replaceAll('stars_opt_20261007/preview.wlf','car_intro_20261007/preview.wlf');
s=s.replace('vsim -voptargs','vlog -sv -work $w ../'+branch+'/video_car_intro.v ../'+branch+'/car_intro_rom.v\nvsim -voptargs');jobs.push(['sim/car_intro_20261007/run_preview.do',s]);
console.log('*** Begin Patch');
for(const [f,t] of jobs){if(fs.existsSync(p.join(base,f)))throw Error('Exists '+f);console.log('*** Add File: dual_board/image_link/'+f);for(const l of t.split(/\r?\n/))console.log('+'+l);}console.log('*** End Patch');
