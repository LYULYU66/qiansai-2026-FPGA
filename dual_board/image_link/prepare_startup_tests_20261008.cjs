const fs=require('fs'),p=require('path'),base=__dirname,jobs=[];
const rd=f=>fs.readFileSync(p.join(base,f),'utf8');
let s=rd('rtl/media_udp_arbiter.v');
s=s.slice(s.indexOf('module media_udp_scheduler #(')).replace('module media_udp_scheduler #(','module media_udp_scheduler_legacy #(');
jobs.push(['sim/startup_fix_20261008/media_udp_scheduler_legacy.v','`timescale 1ns/1ps\n// A remains the original scheduler in the actual unchanged A bit.\n'+s]);
s=rd('sim/tb_media_restart.v');
s=s.replace('parameter integer FLAT_SCHEDULER=0, USE_FIXED_UDP=0','parameter integer FLAT_SCHEDULER=0, USE_FIXED_UDP=0, FRAME_PACKETS=16');
s=s.replaceAll('.FRAME_PACKETS(1)','.FRAME_PACKETS(FRAME_PACKETS)');
s=s.replaceAll('pixel_count<256','pixel_count<FRAME_PACKETS*256').replaceAll('received_frame==256','received_frame==FRAME_PACKETS*256');
s=s.replaceAll('writes[i]!=256','writes[i]!=FRAME_PACKETS*256').replaceAll('expected_writes[i]=256','expected_writes[i]=FRAME_PACKETS*256').replaceAll('expected_writes[i]+256','expected_writes[i]+FRAME_PACKETS*256');
const point=s.indexOf('end endgenerate\ninteger played=0');
if(point<0)throw Error('A scheduler boundary');
const first=s.indexOf('media_udp_scheduler #(.CHANNELS(3)');
if(first<0 || first>point)throw Error('A scheduler not found');
s=s.slice(0,first)+s.slice(first).replace('media_udp_scheduler #(.CHANNELS(3)','media_udp_scheduler_legacy #(.CHANNELS(3)');
s=s.replace('PASS fixed UDP media restart: framed LNK1/IMG4/AUD2/receipts, five B resets, protected caches, native FIFO and exact playback head','PASS startup pipeline: original A + pipelined B, real IPv4/UDP LNK1/IMG4/AUD2/receipts, 16 packets per image, four-cache preload, five B resets, protected caches and exact PCM playback head');
jobs.push(['sim/startup_fix_20261008/tb_media_restart.v',s]);
jobs.push(['sim/startup_fix_20261008/run_restart.do',`onerror {quit -code 1}
set w work_startup_fix_restart
if {![file exists $w]} {vlib $w}
set source_path ../../../src/user_source/hdl_source
vlog -sv -work $w ../rtl/fixed_peer_udp.v fixed_udp_test_link.v ../rtl/startup_fix_20261008/media_udp_arbiter.v startup_fix_20261008/media_udp_scheduler_legacy.v ../rtl/image_packet_rx.v ../rtl/hw_round5_20261005/image_packet_tx_hw.v ../rtl/image_receipt.v ../rtl/image_sdram_sink.v ../rtl/image_main_ingress.v ../rtl/media_link_session.v ../rtl/media_audio_enable_cdc.v ../rtl/audio_packet_tx.v ../rtl/audio_packet_rx.v ../rtl/audio_receipt.v
vlog -sv -work $w $source_path/IP/afifo_32_16_256.v $source_path/hdmi_audio_pcm_i2s_64fs.v startup_fix_20261008/tb_media_restart.v
vsim -voptargs=+acc -onfinish stop -wlf startup_fix_20261008/restart.wlf $w.tb_media_restart_fixed
log /tb_media_restart_fixed/test/ag
log /tb_media_restart_fixed/test/bg
log /tb_media_restart_fixed/test/page
log /tb_media_restart_fixed/test/cache
log /tb_media_restart_fixed/test/a_ready
log /tb_media_restart_fixed/test/b_ready
log /tb_media_restart_fixed/test/played_words
log /tb_media_restart_fixed/test/flat_b/scheduler/remaining
run -all
quit -code 0
`]);
console.log('*** Begin Patch');for(const [f,t]of jobs){if(fs.existsSync(p.join(base,f)))throw Error('Exists '+f);console.log('*** Add File: dual_board/image_link/'+f);for(const l of t.split(/\r?\n/))console.log('+'+l);}console.log('*** End Patch');
