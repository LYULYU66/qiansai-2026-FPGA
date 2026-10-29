// Emit an apply_patch patch; never overwrite the preserved baseline.
const fs=require('fs'),p=require('path');
const base=__dirname, dir='rtl/manual_dual_20261007', jobs=[];
const read=f=>fs.readFileSync(p.join(base,f),'utf8');
function sub(s,a,b){if(!s.includes(a))throw Error('Missing anchor '+a);return s.replace(a,b);}
let s=read('rtl/dual_stars_20261006/image_tf_source_hw.v');
s=sub(s,'parameter LOCAL_PREVIEW=0, parameter [1:0] PREVIEW_INDEX=2\'d1','parameter LOCAL_PREVIEW=0, parameter LOCAL_PAIR=0, parameter [1:0] PREVIEW_INDEX=2\'d1');
s=sub(s,'input wire preview_ready,','input wire preview_ready, preview_finish,');
s=sub(s,'output wire [1:0] preview_index,','output wire [2:0] preview_index,');
s=sub(s,'wire [1:0] write_index;','wire [2:0] write_index;');
s=sub(s,'reg [1:0] index_latched;','reg [2:0] index_latched;');
s=sub(s,'.PIPELINED_CLUSTER_ADDR(1),.FAST_AUDIO_START(0),.DUAL_SONG(DUAL_SONG)', '.PIPELINED_CLUSTER_ADDR(1),.FAST_AUDIO_START(0),.DUAL_SONG(DUAL_SONG),\n             .TOTAL_IMAGES(LOCAL_PAIR ? 6 : 4),.SCAN_TARGET_COUNT(LOCAL_PAIR ? 3\'d6 : 3\'d4)');
s=sub(s,'reg [1:0] udp_index;','reg [2:0] udp_index;');
s=sub(s,'wire stage_load=pixel_valid && pixel_ready;', 'wire pixel_consume=pixel_valid && pixel_ready;\nwire local_frame=LOCAL_PAIR && udp_index[2];\nwire stage_load=pixel_consume && !local_frame;');
s=sub(s,'.start(start_sync[2]^start_sync[1]),', '.start((start_sync[2]^start_sync[1]) && (!LOCAL_PAIR || !index_latched[2])),');
s=sub(s,'.consume(pixel_valid && pixel_ready),.frame_index(index_latched),', '.consume(stage_load),.frame_index(index_latched[1:0]),');
s=sub(s,'assign preview_valid=stage_load && udp_index==PREVIEW_INDEX;', 'assign preview_valid=LOCAL_PAIR ? (pixel_consume && local_frame) : (stage_load && udp_index=={1\'b0,PREVIEW_INDEX});');
s=sub(s,'assign pixel_ready=udp_active && !staged_valid && ui_ready &&\n                   (!LOCAL_PREVIEW || udp_index!=PREVIEW_INDEX || preview_ready);', 'assign pixel_ready=udp_active && (local_frame ? preview_ready :\n                   (!staged_valid && ui_ready &&\n                   (!LOCAL_PREVIEW || LOCAL_PAIR || udp_index!={1\'b0,PREVIEW_INDEX} || preview_ready)));');
s=sub(s,'if(pixel_valid && pixel_ready) source_count<=source_count+1\'b1;', 'if(pixel_consume) source_count<=source_count+1\'b1;');
s=sub(s,'if(frame_sent) begin udp_active<=0; finish_toggle<=~finish_toggle; end', 'if(udp_active && (local_frame ? preview_finish : frame_sent)) begin\n            udp_active<=0; finish_toggle<=~finish_toggle;\n        end');
s=sub(s,'.source_valid(staged_valid && udp_active),', '.source_valid(staged_valid && udp_active && !local_frame),');
s=sub(s,'.source_frame_index(udp_index),', '.source_frame_index(udp_index[1:0]),');
jobs.push([dir+'/image_tf_source_hw.v',s]);
s=read('rtl/dual_stars_20261006/image_media_board_b_hw.v');
s=sub(s,'input wire uart_rx,','input wire uart_rx,\n    input wire key_next, key_prev, // physical KEY2 / KEY4, manual only');
s=sub(s,'// One shared elaboration-time selection: TF/A picture #3 is zero-based index 2.\nlocalparam [1:0] PREVIEW_INDEX=2\'d2;', '// TF pictures #5/#6 are local-only; A still receives pictures #1..#4.');
s=sub(s,'media_control_tx #(.STAR_SYNC(1))', 'wire [7:0] local_page_token;\nmedia_control_tx #(.STAR_SYNC(1),.PAGE_SYNC(1))');
s=sub(s,'.star_phase(star_phase_master),', '.star_phase(star_phase_master),.page_token(local_page_token),');
s=sub(s,'wire [1:0] preview_index;', 'wire [2:0] preview_index;\nwire preview_finish;');
s=sub(s,'image_tf_source #(.SESSION_GUARD(1),.DUAL_SONG(1),.LOCAL_PREVIEW(1),.PREVIEW_INDEX(PREVIEW_INDEX))', 'image_tf_source #(.SESSION_GUARD(1),.DUAL_SONG(1),.LOCAL_PREVIEW(1),.LOCAL_PAIR(1))');
s=sub(s,'.preview_ready(preview_ready),.preview_start(preview_start),', '.preview_ready(preview_ready),.preview_finish(preview_finish),.preview_start(preview_start),');
s=sub(s,'b_hdmi_preview #(.PREVIEW_INDEX(PREVIEW_INDEX))', 'b_hdmi_preview');
s=sub(s,'.star_phase_udp(star_phase_master),', '.star_phase_udp(star_phase_master),.key_next(key_next),.key_prev(key_prev),\n    .page_token(local_page_token),.frame_loaded(preview_finish),');
jobs.push([dir+'/image_media_board_b_hw.v',s]);
let adc=read('rtl/dual_stars_20261006/media_b.adc');
adc+='\n# Physical KEY2 and KEY4: next/previous between exactly two cached pages.\nset_pin_assignment { key_next } { LOCATION = B2; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }\nset_pin_assignment { key_prev } { LOCATION = C1; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }\n';
jobs.push([dir+'/media_b.adc',adc]);
jobs.push([dir+'/media_b.sdc',read('rtl/dual_stars_20261006/media_b.sdc')]);
for(const b of ['a','b']){
 const old='prj/firefly_video_'+b+'_20261006', dest='prj/manual_dual_'+b+'_20261007';
 const oldName='MEDIA_'+b.toUpperCase()+'_FIREFLY_VIDEO_20261006', name='MEDIA_'+b.toUpperCase()+'_MANUAL_DUAL_20261007';
 let xml=read(old+'/'+oldName+'.al').replaceAll(old,dest).replaceAll(oldName,name);
 const replacements=[
  ['rtl/dual_stars_20261006/media_control_packet.v',dir+'/media_control_packet.v'],
  ['rtl/image_remote_display_control.v',dir+'/image_remote_display_control.v'],
  ['rtl/yilu_replace_20261006/top_dual_image_hw.v',dir+'/top_dual_image_hw.v'],
  ['rtl/dual_stars_20261006/image_tf_source_hw.v',dir+'/image_tf_source_hw.v'],
  ['rtl/dual_stars_20261006/image_media_board_b_hw.v',dir+'/image_media_board_b_hw.v'],
  ['rtl/dual_stars_20261006/b_image_capture.v',dir+'/b_image_capture.v'],
  ['rtl/dual_stars_20261006/b_hdmi_preview.v',dir+'/b_hdmi_preview.v'],
  ['rtl/dualsong_20261005/sd_card_bmp_remote.v',dir+'/sd_card_bmp_remote.v'],
  ['rtl/dualsong_20261005/bmp_read.v',dir+'/bmp_read.v'],
  ['rtl/dual_stars_20261006/media_b.adc',dir+'/media_b.adc'],
  ['rtl/dual_stars_20261006/media_b.sdc',dir+'/media_b.sdc']
 ];
 for(const [a,z] of replacements)xml=xml.replaceAll(a,z);
 jobs.push([dest+'/'+name+'.al',xml]);
 let t=read(old+'/build_flow.tcl').replaceAll(oldName,name);
 for(const [a,z] of replacements)t=t.replaceAll(a.replace('rtl/','../../rtl/'),z.replace('rtl/','../../rtl/'));
 jobs.push([dest+'/build_flow.tcl',t]);
}
console.log('*** Begin Patch');
for(const [file,data] of jobs){
 if(fs.existsSync(p.join(base,file)))throw Error('Already exists '+file);
 console.log('*** Add File: dual_board/image_link/'+file);
 for(const l of data.trimEnd().split(/\r?\n/))console.log('+'+l);
}
console.log('*** End Patch');
