const fs=require('fs'),path=require('path');
const base=path.resolve(__dirname,'..'),dir=path.join(base,'prj/media_b');
const from='MEDIA_SRAM_TEST_B_TF_20261005',to='MEDIA_SRAM_TEST_B_HOMESTAGE_R8_20261005';
const source=fs.readFileSync(path.join(dir,from+'.al'),'utf8');
const needle='hw_round4_20261005/image_tf_source_hw.v';
if(!source.includes(needle))throw Error('B baseline source not found');
fs.writeFileSync(path.join(dir,to+'.al'),source.split(from).join(to).replace(needle,'hw_round8_20261005/image_tf_source_hw.v'));
fs.writeFileSync(path.join(dir,'build_home_stage_r8.tcl'),fs.readFileSync(path.join(dir,'build_sram_test.tcl'),'utf8').split(from).join(to));
const folder=path.join(__dirname,'hw_round8_20261005');fs.mkdirSync(folder,{recursive:true});
let script=fs.readFileSync(path.join(__dirname,'hw_round6_20261005/run_boundary.do'),'utf8');
script=script.replace(/work_player_boundary6/g,'work_player_boundary8').replace(/hw_round6_20261005\//g,'hw_round8_20261005/');
script=script.replace('../rtl/hw_round8_20261005/audio_receipt_hw.v','../rtl/hw_round6_20261005/audio_receipt_hw.v');
script=script.replace('$hw4/image_tf_source_hw.v','../rtl/hw_round8_20261005/image_tf_source_hw.v');
fs.writeFileSync(path.join(folder,'run_boundary.do'),script);
let retry=fs.readFileSync(path.join(__dirname,'tb_home_source.v'),'utf8').replace(/tb_home_source/g,'tb_home_stage_retry');
retry=retry.replace('image_receipt_tx receipt(',`reg [3:0] dropped=0;
integer dropped_count=0,held_cycles=0;
wire drop_receipt=(packet_sequence==0 && !dropped[frame_index]) ||
 (packet_sequence==1199 && !dropped[2+frame_index]);
always @(posedge udp_clk)if(!rst && packet_done && drop_receipt)begin
 dropped_count=dropped_count+1;
 if(packet_sequence==0)dropped[frame_index]<=1;
 else dropped[2+frame_index]<=1;
end
reg [31:0] held_word;
reg held_first,was_blocked=0;
always @(posedge udp_clk)begin
 if(dut.bridge_udp_reset)was_blocked=0;
 else begin
  if(was_blocked && ({dut.staged_rgb,dut.staged_tag}!==held_word || dut.staged_first!==held_first || !dut.staged_valid))
   $fatal(1,"Held RGB/tag/first marker changed during packet wait/retry");
  was_blocked=dut.staged_valid && !dut.tx_source_ready;
  held_word={dut.staged_rgb,dut.staged_tag};held_first=dut.staged_first;
  if(was_blocked)held_cycles=held_cycles+1;
 end
end
defparam dut.u_packets.RETRY_CYCLES=8000;
image_receipt_tx receipt(`);
retry=retry.replace('.event_valid(packet_done)','.event_valid(packet_done && !drop_receipt)');
retry=retry.replace('if(received!=614400)','if(received!=614400 || dropped_count!=4 || held_cycles==0)');
retry=retry.replace('PASS home source: actual 100/125 MHz CDC + indexed sender, 614400 words, both storage directions and backpressure',
 'PASS home stage retry: 614400 exact RGB/tags, both directions, 4 first/final ACK losses, held-pixel stability and backpressure');
fs.writeFileSync(path.join(__dirname,'tb_home_stage_retry.v'),retry);
let guarded=script.replace('tb_player_b_boundary.v tb_home_source.v','tb_home_stage_retry.v');
const begin=guarded.indexOf('vsim -voptargs=+acc');
const next=guarded.indexOf('vsim -voptargs=+acc',begin+1);
guarded=guarded.slice(0,begin)+guarded.slice(next);
guarded=guarded.replace(/tb_home_source/g,'tb_home_stage_retry').replace(/home_source_boundary.wlf/g,'home_stage_retry.wlf');
fs.writeFileSync(path.join(folder,'run_retry.do'),guarded);
console.log('Prepared isolated B one-pixel staging candidate; audio, atlas, constraints and old bits unchanged.');
