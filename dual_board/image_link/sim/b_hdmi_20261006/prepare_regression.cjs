// Mechanical copies of accepted tests; changes are patched separately.
const fs=require('fs'),path=require('path');
const dir=__dirname,sim=path.dirname(dir);
for(const [src,dest] of [
 ['tb_home_source.v','tb_b_preview_source.v'],
 ['dualsong_20261005/tb_dualsong_b_boundary.v','tb_b_hdmi_boundary.v']
]){
 if(fs.existsSync(path.join(dir,dest)))throw Error('Test already exists: '+dest);
 fs.copyFileSync(path.join(sim,src),path.join(dir,dest));
}
let text=fs.readFileSync(path.join(sim,'dualsong_20261005/run_boundary.do'),'utf8');
text=text.replaceAll('work_dualsong_boundary','work_b_hdmi_boundary')
 .replaceAll('../rtl/dualsong_20261005/image_media_board_b_hw.v','../rtl/b_hdmi_20261006/image_media_board_b_hw.v')
 .replaceAll('../rtl/dualsong_20261005/image_tf_source_hw.v','../rtl/b_hdmi_20261006/image_tf_source_hw.v')
 .replaceAll('dualsong_20261005/tb_dualsong_b_boundary.v','b_hdmi_20261006/tb_b_hdmi_boundary.v')
 .replaceAll('tb_home_source.v','b_hdmi_20261006/tb_b_preview_source.v')
 .replaceAll('$work4.tb_home_source','$work4.tb_b_preview_source')
 .replaceAll('/tb_home_source/','/tb_b_preview_source/')
 .replaceAll('dualsong_20261005/player_b_boundary.wlf','b_hdmi_20261006/b_boundary.wlf')
 .replaceAll('dualsong_20261005/home_source_boundary.wlf','b_hdmi_20261006/source.wlf');
text=text.replace('vsim -voptargs',
 'vlog -sv -work $work4 +incdir+$sd4 ../rtl/b_hdmi_20261006/b_hdmi_preview.v ../rtl/b_hdmi_20261006/b_image_capture.v ../rtl/hw_round7_20261005/frame_read_write_hw.v $sd4/frame_fifo_write.v $sd4/frame_fifo_read.v $source4/IP/afifo_16_32_256.v $sd4/color_bar.v $sd4/video_timing_data.v $sd4/video_delay.v $source4/video_rgb_to_axis_640x480.v $source4/startup_pulse.v b_hdmi_20261006/b_hdmi_models.v\nvsim -voptargs');
fs.writeFileSync(path.join(dir,'run_boundary.do'),text);
console.log('B HDMI isolated boundary/source regressions cloned.');
