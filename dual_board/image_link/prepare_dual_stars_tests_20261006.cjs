// Mechanical cloning of established benches, preserving released evidence.
const fs=require('fs'),path=require('path'),base=__dirname;
const sim=path.join(base,'sim/dual_stars_20261006');
function emit(name,s){if(fs.existsSync(path.join(sim,name)))throw Error('Exists: '+name);fs.writeFileSync(path.join(sim,name),s);}
let p=fs.readFileSync(path.join(base,'sim/b_hdmi_20261006/tb_b_hdmi_preview.v'),'utf8')
 .replace('b_hdmi_preview dut','b_hdmi_preview #(.PREVIEW_INDEX(2\'d2)) dut')
 .replace('.source_start(start)','.star_phase_udp(16\'d1360),.source_start(start)')
 .replace('integer accepted=0','`include "star_reference.vh"\ninteger accepted=0')
 .replace("expected=view_valid ? slot_base[view_index]+axis_count : 24'd0;",
 "expected=view_valid ? star_reference(slot_base[view_index]+axis_count,640+axis_count%640,axis_count/640,1360) : 24'd0;")
 .replace('@(negedge udp_clk);index=1;top=orient','@(negedge udp_clk);index=2;top=orient')
 .replace('if(index!=1)','if(index!=2)')
 .replace('PASS B HDMI preview:','PASS B third-image star preview:');
emit('tb_b_hdmi_preview.v',p);
let d=fs.readFileSync(path.join(base,'sim/b_hdmi_20261006/run_preview.do'),'utf8')
 .replaceAll('work_b_preview_20261006','work_dual_stars_preview')
 .replaceAll('b_hdmi_20261006','dual_stars_20261006')
 .replace('vlog -sv -work $w +incdir+','vlog -sv -work $w +incdir+dual_stars_20261006 +incdir+')
 .replace('vsim -voptargs', 'vlog -sv -work $w ../rtl/dual_stars_20261006/video_dual_star_overlay.v ../rtl/hw_round4_20261005/audio_visual_packet_hw.v\nvsim -voptargs');
emit('run_preview.do',d);
let control=fs.readFileSync(path.join(base,'sim/tb_media_control.v'),'utf8')
 .replaceAll('tb_media_control','tb_media_control_stars')
 .replace('media_control_tx #(.UPDATE_CYCLES(2000))','media_control_tx #(.STAR_SYNC(1),.UPDATE_CYCLES(2000))')
 .replace('.settings(source_state)','.settings(source_state),.star_phase(16\'d12345)')
 .replace('media_control_rx rx','wire [15:0] star_phase;\nmedia_control_rx #(.STAR_SYNC(1)) rx')
 .replace('net_length==12','net_length==14')
 .replace('.settings(received_state)','.settings(received_state),.star_phase(star_phase)')
 .replace('$display("PASS media control:', 'if(star_phase!==12345)$fatal(1,"UART/control lost star phase");\n    $display("PASS CTL3 UART control:');
emit('tb_media_control_stars.v',control);
console.log('Native third-picture star preview + real UART/CTL3 benches prepared.');
