// Versioned mechanical clones emitted only as apply_patch; baseline untouched.
const fs=require('fs'),p=require('path'),base=__dirname;
const read=f=>fs.readFileSync(p.join(base,f),'utf8'),jobs=[];
const branch='rtl/stars_opt_20261007',sim='sim/stars_opt_20261007';
function sub(s,a,b){if(!s.includes(a))throw Error('Missing '+a);return s.replace(a,b);}
let s=read('rtl/yilu_replace_20261006/remote_audio_compute_hw.v');
s=sub(s,'reg [31:0] written_gray, analysed_gray;','// The history ring is1024 words with a896-word occupancy bound. An11-bit\n// modulo pointer (one wrap bit) is sufficient for CDC occupancy; absolute\n// 32-bit written/analysed/session/feedback counters remain unchanged.\nreg [10:0] written_gray, analysed_gray;');
s=s.replace('reg [31:0] written_g0, written_g1, analysed_g0, analysed_g1;','reg [10:0] written_g0, written_g1, analysed_g0, analysed_g1;')
 .replace('reg [31:0] written_local, analysed_local;','reg [10:0] written_local, analysed_local;')
 .replace('wire [31:0] written_decoded, analysed_decoded;','wire [10:0] written_decoded, analysed_decoded;')
 .replace('reg [31:0] backlog_q;','reg [10:0] backlog_q;')
 .replace('wire [31:0] backlog=written-analysed_local;','wire [10:0] backlog=written[10:0]-analysed_local;')
 .replace('analysed!=written_local','analysed[10:0]!=written_local')
 .replace('backlog_q<32\'d894','backlog_q<11\'d894')
 .replace('((written+1\'b1)>>1)^(written+1\'b1)','((written[10:0]+11\'d1)>>1)^(written[10:0]+11\'d1)')
 .replace('((analysed+1\'b1)>>1)^(analysed+1\'b1)','((analysed[10:0]+11\'d1)>>1)^(analysed[10:0]+11\'d1)')
 .replace('assign written_decoded[31]=written_g1[31];','assign written_decoded[10]=written_g1[10];')
 .replace('assign analysed_decoded[31]=analysed_g1[31];','assign analysed_decoded[10]=analysed_g1[10];')
 .replace('for(g=30;g>=0;g=g-1)','for(g=9;g>=0;g=g-1)');
jobs.push([branch+'/remote_audio_compute_hw.v',s]);
s=read('rtl/hw_round4_20261005/audio_visual_packet_hw.v');
s=sub(s,'parameter integer UPDATE_CYCLES=2083333','parameter integer UPDATE_CYCLES=2083333,\n    parameter SHARED_SNAPSHOT=0');
s=sub(s,'output wire udp_request, udp_valid,','output wire udp_request, udp_valid,\n    output wire snapshot_hold,');
s=sub(s,'reg [1:0] state;','reg [2:0] state;');
s=sub(s,'always @(posedge clk) begin\n    if(state==0', 'generate if(!SHARED_SNAPSHOT) begin:private_payload\nalways @(posedge clk) begin\n    if(state==0');
s=sub(s,'end\nassign udp_request=state==1;', 'end\nend endgenerate\n// Freeze the already coherent CDC snapshot instead of copying/shifting264bits.\n// ARM(4) captures tags after the destination has been locked; RELEASE(5)\n// gives the CDC one accepting edge even for very short UPDATE_CYCLES.\nassign snapshot_hold=SHARED_SNAPSHOT && state!=0 && state!=5;\nwire [7:0] payload_byte=SHARED_SNAPSHOT ?\n    visual_state[(index-6\'d12)*8 +: 8] : payload[7:0];\nassign udp_request=state==1;');
s=sub(s,'default: udp_data=payload[7:0];','default: udp_data=payload_byte;');
s=sub(s,'session<=session_id; progress<=analysed_words;\n                timer<=0; state<=3;', 'if(SHARED_SNAPSHOT) state<=4;\n                else begin session<=session_id;progress<=analysed_words;timer<=0;state<=3;end');
s=sub(s,'3: if(udp_ready) state<=1;', '4:begin session<=session_id;progress<=analysed_words;timer<=0;state<=3;end\n            5:state<=0;\n            3: if(udp_ready) state<=1;');
s=sub(s,'if(index==46) state<=0;', 'if(index==46) state<=SHARED_SNAPSHOT ? 5 : 0;');
s=sub(s,'parameter FRAME_BOUNDARY=1,','parameter FRAME_BOUNDARY=1,\n    parameter DESTINATION_HOLD=0,');
s=sub(s,'input wire update_valid, publish_enable,','input wire update_valid, publish_enable,\n    input wire hold_capture,');
s=sub(s,'if((!FRAME_BOUNDARY || (frame_vs && !previous_vs)) && req_sync[1]!=acknowledge_toggle)', 'if((!DESTINATION_HOLD || !hold_capture) &&\n           (!FRAME_BOUNDARY || (frame_vs && !previous_vs)) && req_sync[1]!=acknowledge_toggle)');
jobs.push([branch+'/audio_visual_packet_hw.v',s]);
s=read('rtl/manual_dual_20261007/image_media_board_b_hw.v');
s=sub(s,'wire [295:0] visual_snapshot;','wire [295:0] visual_snapshot;\nwire visual_snapshot_hold;');
s=sub(s,'audio_visual_cdc #(.WIDTH(296),.FRAME_BOUNDARY(0)) u_compute_snapshot', 'audio_visual_cdc #(.WIDTH(296),.FRAME_BOUNDARY(0),.DESTINATION_HOLD(1)) u_compute_snapshot');
s=sub(s,'.frame_state(visual_snapshot),.capture_valid(snapshot_valid)', '.hold_capture(visual_snapshot_hold),.frame_state(visual_snapshot),.capture_valid(snapshot_valid)');
s=sub(s,'audio_visual_tx u_visual_packets (','audio_visual_tx #(.SHARED_SNAPSHOT(1)) u_visual_packets (');
s=sub(s,'.udp_ready(visual_ready),.udp_ack(visual_ack),', '.snapshot_hold(visual_snapshot_hold),.udp_ready(visual_ready),.udp_ack(visual_ack),');
jobs.push([branch+'/image_media_board_b_hw.v',s]);
const replacements=[
 ['rtl/firefly_video_20261006/video_dual_star_overlay.v',branch+'/video_dual_star_overlay.v'],
 ['rtl/yilu_replace_20261006/remote_audio_compute_hw.v',branch+'/remote_audio_compute_hw.v'],
 ['rtl/hw_round4_20261005/audio_visual_packet_hw.v',branch+'/audio_visual_packet_hw.v'],
 ['rtl/manual_dual_20261007/image_media_board_b_hw.v',branch+'/image_media_board_b_hw.v']
];
for(const [board,seed] of [['a',1],['b',3]]){
 const old='prj/manual_dual_'+board+'_s'+seed+'_20261007',dest='prj/stars_opt_'+board+'_20261007';
 const stem='MEDIA_'+board.toUpperCase()+'_MANUAL_DUAL_S'+seed+'_20261007',name='MEDIA_'+board.toUpperCase()+'_STARS_OPT_20261007';
 let xml=read(old+'/'+stem+'.al').replaceAll(old,dest).replaceAll(stem,name);
 // A changes only the star shader; shared-snapshot optimizations stay on B.
 for(const [a,b] of replacements)if(board==='b'||a.includes('video_dual_star'))xml=xml.replaceAll(a,b);
 jobs.push([dest+'/'+name+'.al',xml]);
 jobs.push([dest+'/build_flow.tcl',read(old+'/build_flow.tcl').replaceAll(stem,name)]);
}
s=read('sim/tb_remote_compute.v');
s=sub(s,'wire [31:0] available=dut.written_local-analysed;', 'wire [10:0] available=dut.written_local-analysed[10:0];');
s=sub(s,'available==0 || available[31]', 'available==0');
s=sub(s,'dut.written_gray=(32\'hfffffff0>>1)^32\'hfffffff0;', 'dut.written_gray=(11\'h7f0>>1)^11\'h7f0;');
s=sub(s,'dut.analysed_gray=(32\'hfffffff0>>1)^32\'hfffffff0;', 'dut.analysed_gray=(11\'h7f0>>1)^11\'h7f0;');
jobs.push([sim+'/tb_remote_compute.v',s]);
jobs.push([sim+'/remote_compute_reference.v',read('rtl/yilu_replace_20261006/remote_audio_compute_hw.v').replace('module remote_audio_compute #','module remote_audio_compute_reference #')]);
s=read('sim/tb_audio_offload.v');
s=sub(s,'wire [295:0] snapshot;', 'wire [295:0] snapshot;\nwire snapshot_hold;');
s=sub(s,'audio_visual_cdc #(.WIDTH(296),.FRAME_BOUNDARY(0)) compute_cdc','audio_visual_cdc #(.WIDTH(296),.FRAME_BOUNDARY(0),.DESTINATION_HOLD(1)) compute_cdc');
s=sub(s,'.frame_state(snapshot),.capture_valid(snapshot_valid)', '.hold_capture(snapshot_hold),.frame_state(snapshot),.capture_valid(snapshot_valid)');
s=sub(s,'audio_visual_tx #(.UPDATE_CYCLES(125000)) vis_tx', 'audio_visual_tx #(.UPDATE_CYCLES(125000),.SHARED_SNAPSHOT(1)) vis_tx');
s=sub(s,'.udp_request(v_req),.udp_valid(v_valid),', '.snapshot_hold(snapshot_hold),.udp_request(v_req),.udp_valid(v_valid),');
jobs.push([sim+'/tb_audio_offload.v',s]);
for(const f of ['run_audio.do','run_features.do','run_cover.do']){
 s=read('sim/yilu_replace_20261006/'+f).replaceAll('work_yilu_','work_stars_opt_').replaceAll('yilu_replace_20261006/${test}.wlf','stars_opt_20261007/${test}.wlf');
 for(const [a,b] of replacements)s=s.replaceAll('../'+a,'../'+b);
 if(f==='run_audio.do')s=s.replace(' tb_audio_offload.v tb_remote_compute.v',' stars_opt_20261007/tb_audio_offload.v stars_opt_20261007/tb_remote_compute.v');
 jobs.push([sim+'/'+f,s]);
}
s=read('sim/manual_dual_20261007/run_boundary.do').replaceAll('work_manual_dual_boundary','work_stars_opt_boundary');
for(const [a,b] of replacements)s=s.replaceAll('../'+a,'../'+b);
s=s.replace('$branch/image_media_board_b_hw.v','../'+branch+'/image_media_board_b_hw.v').replace('$hw4/audio_visual_packet_hw.v','../'+branch+'/audio_visual_packet_hw.v')
 .replace('manual_dual_20261007/b_boundary.wlf','stars_opt_20261007/b_boundary.wlf');
jobs.push([sim+'/run_boundary.do',s]);
s=read('sim/manual_dual_20261007/run_preview.do').replaceAll('work_manual_dual_preview','work_stars_opt_preview')
 .replace('+incdir+firefly_video_20261006','+incdir+stars_opt_20261007')
 .replace('manual_dual_20261007/tb_b_hdmi_preview.v','stars_opt_20261007/tb_b_hdmi_preview.v')
 .replace('manual_dual_20261007/preview.wlf','stars_opt_20261007/preview.wlf');
for(const [a,b] of replacements)s=s.replaceAll('../'+a,'../'+b);
jobs.push([sim+'/run_preview.do',s]);
jobs.push([sim+'/tb_b_hdmi_preview.v',read('sim/manual_dual_20261007/tb_b_hdmi_preview.v')]);
s=read('sim/firefly_video_20261006/tb_dual_stars.v').replace('repeat(30)@(negedge clk)','repeat(160)@(negedge clk)');
jobs.push([sim+'/tb_dual_stars.v',s]);
jobs.push([sim+'/tb_star_motion.v',read('sim/firefly_video_20261006/tb_star_motion.v')]);
jobs.push([sim+'/tb_star_control.v',read('sim/firefly_video_20261006/tb_star_control.v')]);
console.log('*** Begin Patch');
for(const [file,data] of jobs.filter(([f])=>!process.argv[2]||f.startsWith(process.argv[2]))){
 if(fs.existsSync(p.join(base,file)))throw Error('Exists '+file);
 console.log('*** Add File: dual_board/image_link/'+file);for(const l of data.trimEnd().split(/\r?\n/))console.log('+'+l);
}
console.log('*** End Patch');
