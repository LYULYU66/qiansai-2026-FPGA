// Mechanical branch/project cloning only; never modify the dual-song baseline.
const fs=require('fs'),path=require('path');
const base=__dirname,root=path.resolve(base,'../..');
const branch=path.join(base,'rtl/b_hdmi_20261006');
if(fs.existsSync(branch))throw Error('B HDMI branch already exists');
fs.mkdirSync(branch,{recursive:true});
for(const f of ['image_media_board_b_hw.v','image_tf_source_hw.v'])
  fs.copyFileSync(path.join(base,'rtl/dualsong_20261005',f),path.join(branch,f));
const old='MEDIA_SRAM_TEST_B_DUALSONG_20261005',name='MEDIA_B_HDMI_IMAGE2_20261006';
const original=path.join(base,'prj/dualsong_b_20261005');
const dest=path.join(base,'prj/b_hdmi_20261006');
fs.mkdirSync(dest);
let xml=fs.readFileSync(path.join(original,old+'.al'),'utf8')
  .replaceAll(original.replaceAll('\\','/'),dest.replaceAll('\\','/')).replaceAll(old,name);
xml=xml.replaceAll('constraints/media_b.adc','rtl/b_hdmi_20261006/media_b.adc')
       .replaceAll('constraints/media_b.sdc','rtl/b_hdmi_20261006/media_b.sdc');
for(const f of ['image_media_board_b_hw.v','image_tf_source_hw.v'])
  xml=xml.replaceAll('rtl/dualsong_20261005/'+f,'rtl/b_hdmi_20261006/'+f);
const extra=[
  'dual_board/image_link/rtl/b_hdmi_20261006/b_image_capture.v',
  'dual_board/image_link/rtl/b_hdmi_20261006/b_hdmi_preview.v',
  'dual_board/image_link/rtl/hw_round7_20261005/frame_read_write_hw.v',
  'src/user_source/hdl_source/SD/frame_fifo_read.v',
  'src/user_source/hdl_source/SD/frame_fifo_write.v',
  'src/user_source/hdl_source/SD/sdram.v',
  'src/user_source/hdl_source/SD/color_bar.v',
  'src/user_source/hdl_source/SD/video_timing_data.v',
  'src/user_source/hdl_source/SD/video_delay.v',
  'src/user_source/hdl_source/include/global_def.v',
  'src/user_source/hdl_source/include/sdr_as_ram.enc.v',
  'src/user_source/hdl_source/include/sdr_init_ref.enc.v',
  'src/user_source/hdl_source/include/sdr_wrrd.enc.v',
  'src/user_source/hdl_source/IP/afifo_16_32_256.v',
  'src/user_source/hdl_source/video_rgb_to_axis_640x480.v',
  'src/user_source/hdl_source/startup_pulse.v',
  'src/user_source/hdl_source/hdmi_phy_warpper.v',
  'src/user_source/hdl_source/lane_lvds_10_1.v',
  'src/user_source/hdl_source/hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v'
];
const entries=extra.map((f,i)=>`      <File Path="${path.join(root,f).replaceAll('\\','/')}"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="${400+i}"/></FileInfo></File>`).join('\n');
xml=xml.replace('</Verilog>',entries+'\n    </Verilog>');
fs.writeFileSync(path.join(dest,name+'.al'),xml);
let tcl=fs.readFileSync(path.join(original,'build_dualsong.tcl'),'utf8').replaceAll(old,name)
  .replaceAll('../../constraints/media_b.adc','../../rtl/b_hdmi_20261006/media_b.adc')
  .replaceAll('../../constraints/media_b.sdc','../../rtl/b_hdmi_20261006/media_b.sdc');
fs.writeFileSync(path.join(dest,'build_b_hdmi.tcl'),tcl);
let adc=fs.readFileSync(path.join(base,'constraints/media_b.adc'),'utf8');
const aadc=fs.readFileSync(path.join(base,'rtl/dualsong_20261005/media_a.adc'),'utf8');
adc+='\n# Same board HDMI OUTPUT connector, not HDMI input.\n'+aadc.split(/\r?\n/).filter(l=>l.startsWith('set_pin_assignment { HDMI_')).join('\n')+'\n';
fs.writeFileSync(path.join(branch,'media_b.adc'),adc);
fs.copyFileSync(path.join(base,'constraints/media_b.sdc'),path.join(branch,'media_b.sdc'));
console.log('Isolated B HDMI branch prepared. A and dual-song baseline untouched.');
