`timescale 1ns/1ps
module tb_b_hdmi_preview;
reg udp_clk=0,mem_clk=0,video_clk=0;
always #4 udp_clk=~udp_clk;
initial begin #3;forever #5 mem_clk=~mem_clk;end
always #20 video_clk=~video_clk;
reg rst=1,start=0,abort=1,top=1,valid=0,key=1;
reg [2:0] index=0;
reg [23:0] rgb=0;
wire ready,loaded;
wire [7:0] token;
b_hdmi_preview #(.KEY_CLK_FREQ(1000),.KEY_DEBOUNCE_MS(1)) dut(
 .udp_clk(udp_clk),.mem_clk(mem_clk),.mem_shift_clk(~mem_clk),
 .video_clk(video_clk),.serial_clk(udp_clk),.reset_request(rst),
 .star_phase_udp(16'd1360),.source_start(start),.source_top_down(top),
 .source_abort(abort),.source_index(index),.pixel_valid(valid),.pixel_rgb(rgb),
 .key_next(key),.page_token(token),.frame_loaded(loaded),.pixel_ready(ready),
 .HDMI_DDC_SCL(),.HDMI_DDC_SDA(),.HDMI_CLK_P(),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P());
`include "star_reference.vh"
integer accepted=0,axis_count=0,black_frames=0,raw0=0,relax0=0,relax1=0,relax2=0,raw1=0;
integer cycle=0,written=0,commits=0,request_changes=0,token_entries=0;
integer pixel_checks=0;
integer prior_raw0=0,prior_relax2=0;
reg [23:0] slot_base[0:3];
reg [23:0] expected,source_base=0;
reg source_orientation=1;
reg view_valid,view_page;
reg [1:0] view_index;
reg [14:0] view_phase;
reg prev_frame_valid=0,prev_frame_page=0,prev_request=0;
reg [1:0] prev_frame_index=0;
reg [7:0] prev_token=0;
reg boundary;

function [23:0] rgb_for_check;
 input integer n;
 integer at;
 begin
  at=source_orientation ? n : (479-n/640)*640+n%640;
  rgb_for_check=source_base+at;
 end
endfunction

always @(posedge udp_clk)if(!dut.udp_reset)begin
 if(dut.write_en)begin
  accepted=accepted+1;
  if(dut.u_frames.write_buf.rst || dut.u_frames.write_buf.wr_rst)
   $fatal(1,"accepted pixel during write FIFO reset window");
 end
 #2;
 if(loaded)commits=commits+1;
 if(dut.requested_page!=prev_request)begin
  request_changes=request_changes+1;prev_request=dut.requested_page;
 end
 // A token changes atomically: rising relax bit carries the new epoch in the
 // same byte; a TF5 return preserves the epoch; bank reloads produce no entry.
 if(token!=prev_token)begin
  if(token[7] && !prev_token[7])begin
   if(token[6:0]!==((prev_token[6:0]+7'd1)&7'h7f))
    $fatal(1,"relax bit and epoch not atomic prev=%h now=%h",prev_token,token);
   token_entries=token_entries+1;
  end else if(token[6:0]!==prev_token[6:0])
   $fatal(1,"epoch changed without a newly visible TF6 entry");
  prev_token=token;
 end
end

always @(posedge mem_clk)if(!dut.mem_reset && dut.app_wr_en)begin
 if(dut.app_wr_data!=={rgb_for_check(written),8'd0})
  $fatal(1,"write FIFO data mismatch word=%0d got=%h expected=%h",written,dut.app_wr_data,{rgb_for_check(written),8'd0});
 if(dut.app_wr_addr/307200!==dut.write_index)
  $fatal(1,"write not routed to requested four-slot bank");
 if(dut.frame_valid && dut.app_wr_addr/307200==dut.frame_index)
  $fatal(1,"writer overwrote a currently displayed slot");
 written=written+1;
end

always @(posedge video_clk)begin
 boundary=dut.vs_prev && !dut.vs_0;
 if(!dut.video_reset && dut.read_en && dut.frame_valid && dut.u_frames.read_empty_a)
  $fatal(1,"read FIFO underflow at pixel %0d",axis_count);
 #2;
 if(!dut.video_reset)begin
  if({dut.frame_valid,dut.frame_page,dut.frame_index}!=={prev_frame_valid,prev_frame_page,prev_frame_index} && !boundary)
   $fatal(1,"page/bank changed away from VS boundary");
  prev_frame_valid=dut.frame_valid;prev_frame_page=dut.frame_page;prev_frame_index=dut.frame_index;
  if(dut.axis_valid)begin
   if(dut.axis_user)begin
    if(axis_count!=0 && axis_count!=307200)$fatal(1,"SOF before previous frame ended");
    axis_count=0;view_valid=dut.frame_valid;view_page=dut.frame_page;view_index=dut.frame_index;
    view_phase=dut.u_stars.frame_phase;
    if(view_valid && view_index[1]!==view_page)$fatal(1,"visible TF page and bank disagree");
   end else if(axis_count==0)$fatal(1,"first active pixel missing SOF");
   if(dut.axis_last!==(axis_count%640==639))$fatal(1,"EOL pixel alignment");
   expected=view_valid ? slot_base[view_index]+axis_count : 24'd0;
   if(view_valid && view_page)
    expected=star_reference(expected,640+axis_count%640,axis_count/640,view_phase);
   if(dut.axis_rgb!==expected)
    $fatal(1,"pixel mismatch p=%0d valid=%b page=%b slot=%d phase=%0d got=%h expected=%h",axis_count,view_valid,view_page,view_index,view_phase,dut.axis_rgb,expected);
   axis_count=axis_count+1;pixel_checks=pixel_checks+1;
   if(axis_count==307200)begin
    if(!view_valid)black_frames=black_frames+1;
    else case(slot_base[view_index])
     24'h200000:raw0=raw0+1;
     24'h600000:relax0=relax0+1;
     24'ha00000:relax1=relax1+1;
     24'hc00000:relax2=relax2+1;
     24'he00000:raw1=raw1+1;
     default:$fatal(1,"displayed uncommitted/partial source base=%h",slot_base[view_index]);
    endcase
   end
  end
 end
end

task begin_capture;
 input [2:0] image;input orient;input [23:0] base;
 begin
  @(negedge udp_clk);index=image;top=orient;start=1;
  source_base=base;source_orientation=orient;written=0;
  @(negedge udp_clk);start=0;
 end
endtask
task send_pixels;
 input integer count;
 integer n;
 begin
  n=0;cycle=0;
  while(n<count)begin
   @(negedge udp_clk);cycle=cycle+1;
   valid=ready && cycle%11!=0;rgb=rgb_for_check(n);
   if(valid)n=n+1;
  end
  @(negedge udp_clk);valid=0;
 end
endtask
task wait_commit;
 input page;input [1:0] new_slot;input [23:0] base;
 begin
  wait(dut.committed_mask[page] && (page ? dut.committed_slot1 : dut.committed_slot0)==new_slot);
  if(written!=307200)$fatal(1,"commit preceded exact full SDRAM frame write");
  slot_base[new_slot]=base;
 end
endtask
task press_key;
 input integer held_cycles;
 begin
  @(negedge udp_clk);key=0;
  repeat(held_cycles)@(negedge udp_clk);
  key=1;repeat(20)@(negedge udp_clk);
 end
endtask

initial begin
 slot_base[0]=0;slot_base[1]=0;slot_base[2]=0;slot_base[3]=0;
 repeat(15)@(negedge udp_clk);rst=0;
 repeat(15)@(negedge udp_clk);abort=0;
 // A's four sources may not start B's local writer.
 for(index=0;index<4;index=index+1)begin
  @(negedge udp_clk);start=1;
  @(negedge udp_clk);start=0;
  repeat(10)@(negedge udp_clk);
  if(dut.write_req || ready || dut.committed_mask!=0)$fatal(1,"wrong TF index captured");
 end
 // First page: #5, bottom-up BMP, exact raw image with no star overlay.
 begin_capture(4,0,24'h200000);send_pixels(307200);wait_commit(0,0,24'h200000);
 wait(raw0>=1);
 if(dut.frame_page || token!=0)$fatal(1,"first TF5 page not initial raw display");
 press_key(20); // #6 does not yet exist: ignored, not queued.
 if(dut.requested_page || request_changes || token!=0)$fatal(1,"missing TF6 press accepted");
 // Sub-cycle bounce is not sampled by the physical input synchronizer.
 @(negedge udp_clk);#1;key=0;#1;key=1;
 repeat(20)@(negedge udp_clk);
 if(dut.requested_page || request_changes)$fatal(1,"short bounce changed page");
 wait(raw0>=2);
 if(token!=0)$fatal(1,"manual-only page changed while idle");
 // Loading #6 must only cache it. It cannot auto-select or notify A.
 begin_capture(5,1,24'h600000);send_pixels(307200);wait_commit(1,2,24'h600000);
 wait(raw0>=3);
 if(dut.frame_page || dut.requested_page || token!=0)$fatal(1,"TF6 preload caused automatic display change");
 wait(dut.axis_valid && axis_count==10000);
 press_key(100); // Long hold: exactly one transition, no repeated carousel.
 if(request_changes!=1 || !dut.requested_page)$fatal(1,"long KEY2 hold not a single transition");
 wait(relax0>=1);
 if(token!==8'h81 || token_entries!=1)$fatal(1,"first TF6 entry token incorrect");
 // A partial #6 reload uses slot3 but must not replace slot2 or its token.
 begin_capture(5,1,24'h800000);send_pixels(2048);
 repeat(600)@(negedge udp_clk);
 @(negedge udp_clk);abort=1;
 repeat(18)@(negedge udp_clk);abort=0;
 if(dut.committed_mask!=3 || dut.committed_slot1!=2)$fatal(1,"partial abort lost either cached page");
 wait(relax0>=2);
 if(token!==8'h81 || token_entries!=1)$fatal(1,"abort created a fake TF6 entry");
 // A successful #6 reload commits slot3; immediate next reload needs slot2,
 // which is still displayed until VS. Credit must remain low while unsafe.
 begin_capture(5,0,24'ha00000);send_pixels(307200);wait_commit(1,3,24'ha00000);
 begin_capture(5,1,24'hc00000);
 repeat(30)@(negedge udp_clk);
 if(dut.frame_index==2 && ready)$fatal(1,"immediate reload reused still-displayed slot2");
 send_pixels(307200);wait_commit(1,2,24'hc00000);
 wait(relax1>=1 && relax2>=1);
 if(token!==8'h81 || token_entries!=1)$fatal(1,"bank reload created a fake TF6 entry");
 prior_raw0=raw0;press_key(20);wait(raw0>prior_raw0);
 if(token!==8'h01 || token_entries!=1)$fatal(1,"TF5 return forced a new entry epoch");
 prior_relax2=relax2;press_key(20);wait(relax2>prior_relax2);
 if(token!==8'h82 || token_entries!=2)$fatal(1,"second manual TF6 entry epoch incorrect");
 // Exercise the fourth SDRAM slot: #5 reload to slot1 while #6 stays visible.
 begin_capture(4,1,24'he00000);send_pixels(307200);wait_commit(0,1,24'he00000);
 if(!dut.frame_page || token!==8'h82)$fatal(1,"TF5 reload auto-selected the wrong page");
 press_key(20);wait(raw1>=1);
 if(token!==8'h02 || token_entries!=2 || request_changes!=4)$fatal(1,"final manual token/key transition coverage mismatch");
 if(accepted!=5*307200+2048 || commits!=5 || view_phase!=1360)
  $fatal(1,"capture/commit/phase coverage count mismatch accepted=%0d commits=%0d phase=%0d",accepted,commits,view_phase);
 $display("PASS B manual TF5/TF6 preview: five complete 640x480 captures across four native SDRAM slots, both BMP orientations, %0d exact raw/star RGB pixels with DE/SOF/EOL, missing-page key ignore, short bounce, long-hold single transition, VS-only switch, atomic two-entry epoch, no auto-switch on cache/reload, refresh stalls, partial abort retention, immediate reload displayed-slot protection, HDMI silent",pixel_checks);
 $finish;
end
initial begin
 #350000000;
 $fatal(1,"B manual preview timeout state=%d accepted=%0d writes=%0d raw=%0d/%0d relax=%0d/%0d/%0d",dut.u_capture.state,accepted,written,raw0,raw1,relax0,relax1,relax2);
end
endmodule
