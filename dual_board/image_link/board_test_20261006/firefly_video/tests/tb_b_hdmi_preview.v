`timescale 1ns/1ps
module tb_b_hdmi_preview;
reg udp_clk=0,mem_clk=0,video_clk=0;
always #4 udp_clk=~udp_clk;
initial begin #3;forever #5 mem_clk=~mem_clk;end
always #20 video_clk=~video_clk;
reg rst=1,start=0,abort=1,top=1,valid=0;
reg [1:0] index=0;
reg [23:0] rgb=0;
wire ready;
b_hdmi_preview #(.PREVIEW_INDEX(2'd2)) dut(.udp_clk(udp_clk),.mem_clk(mem_clk),.mem_shift_clk(~mem_clk),
 .video_clk(video_clk),.serial_clk(udp_clk),.reset_request(rst),
 .star_phase_udp(16'd1360),.source_start(start),.source_top_down(top),.source_abort(abort),.source_index(index),
 .pixel_valid(valid),.pixel_rgb(rgb),.pixel_ready(ready),.HDMI_DDC_SCL(),.HDMI_DDC_SDA(),
 .HDMI_CLK_P(),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P());
`include "star_reference.vh"
integer accepted=0,axis_count=0,black_frames=0,visible0=0,visible1=0,visible2=0;
integer underflow=0,cycle=0,written=0,source_n=0;
reg [23:0] slot_base[0:1];
reg [23:0] expected;
reg view_valid,view_index;
reg [14:0] view_phase;
always @(posedge udp_clk)if(!dut.udp_reset && dut.write_en)begin
 accepted=accepted+1;
 if(dut.u_frames.write_buf.rst || dut.u_frames.write_buf.wr_rst)
  $fatal(1,"preview accepted a pixel in write FIFO reset window");
end
always @(posedge mem_clk)if(!dut.mem_reset && dut.app_wr_en)begin
 if(dut.app_wr_data!=={rgb_for_check(written),8'd0})
  $fatal(1,"preview FIFO write data mismatch word=%0d got=%h",written,dut.app_wr_data);
 written=written+1;
end
// Source generation is set before each capture; the writer must preserve it.
reg [23:0] source_base=0;
reg source_orientation=1;
function [23:0] rgb_for_check;
 input integer n;
 integer at;
 begin at=source_orientation ? n : (479-n/640)*640+n%640;
  rgb_for_check=source_base+at;end
endfunction
always @(posedge video_clk) begin
 if(!dut.video_reset && dut.read_en && dut.frame_valid && dut.u_frames.read_empty_a)
  $fatal(1,"B preview read FIFO underflow at frame pixel %0d",axis_count);
 #2;
 if(!dut.video_reset && dut.axis_valid)begin
  if(dut.axis_user)begin
   if(axis_count!=0 && axis_count!=307200)$fatal(1,"SOF before previous frame finished");
   axis_count=0;view_valid=dut.frame_valid;view_index=dut.frame_index;
   view_phase=dut.u_stars.frame_phase;
  end else if(axis_count==0)$fatal(1,"first active pixel missing SOF");
  if(dut.axis_last!==(axis_count%640==639))$fatal(1,"EOL pixel alignment");
  expected=view_valid ? star_reference(slot_base[view_index]+axis_count,640+axis_count%640,axis_count/640,view_phase) : 24'd0;
  if(dut.axis_rgb!==expected)
   $fatal(1,"B preview pixel mismatch p=%0d valid=%b slot=%b phase=%0d got=%h expected=%h",axis_count,view_valid,view_index,view_phase,dut.axis_rgb,expected);
  axis_count=axis_count+1;
  if(axis_count==307200)begin
   if(!view_valid)black_frames=black_frames+1;
   else if(slot_base[view_index]==24'h200000)visible0=visible0+1;
   else if(slot_base[view_index]==24'h800000)visible1=visible1+1;
   else if(slot_base[view_index]==24'hb00000)visible2=visible2+1;
  end
 end
end
task begin_capture;
 input orient;input [23:0] base;
 begin
  @(negedge udp_clk);index=2;top=orient;start=1;
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
 input new_slot;input [23:0] base;
 begin
  wait(dut.committed_valid && dut.committed_index==new_slot);
  if(written!=307200)$fatal(1,"committed before exact full SDRAM write");
  slot_base[new_slot]=base;
 end
endtask
initial begin
 slot_base[0]=0;slot_base[1]=0;
 repeat(15)@(negedge udp_clk);rst=0;
 repeat(15)@(negedge udp_clk);abort=0;
 // Other three image indices cannot start a local writer.
 for(index=0;index<3;index=index+1)if(index!=2)begin
  @(negedge udp_clk);start=1;
  @(negedge udp_clk);start=0;
  repeat(10)@(negedge udp_clk);
  if(dut.write_req || ready || dut.committed_valid)$fatal(1,"wrong image selected");
 end
 @(negedge udp_clk);index=3;start=1;
 @(negedge udp_clk);start=0;
 repeat(10)@(negedge udp_clk);
 if(dut.write_req || ready)$fatal(1,"image 4 preview selected");
 // Bottom-up BMP must be normalized to top-to-bottom SDRAM/video output.
 begin_capture(0,24'h200000);send_pixels(307200);wait_commit(0,24'h200000);
 wait(visible0>=1);
 // Abort a partial reload; the previous display slot stays intact.
 begin_capture(1,24'h400000);send_pixels(2048);
 repeat(600)@(negedge udp_clk);
 @(negedge udp_clk);abort=1;
 repeat(18)@(negedge udp_clk);abort=0;
 if(!dut.committed_valid || dut.committed_index!=0)$fatal(1,"abort lost cached display");
 wait(visible0>=2);
 // Then reload successfully, with a negative BMP height/top-down stream.
 begin_capture(1,24'h800000);send_pixels(307200);wait_commit(1,24'h800000);
 // Immediate new capture: slot 0 is still being displayed until VS, so SAFE
 // must hold all input pixels until the display acknowledges publication.
 begin_capture(0,24'hb00000);
 repeat(30)@(negedge udp_clk);
 if(dut.frame_index==0 && ready)$fatal(1,"reused still-displayed slot");
 send_pixels(307200);wait_commit(0,24'hb00000);
 wait(visible1>=1 && visible2>=1);
 if(accepted!=3*307200+2048 || view_phase!=1360)$fatal(1,"capture/phase coverage count mismatch");
 $display("PASS B third-image star preview: 3 complete 640x480 captures, both BMP orientations, exact raw RGB/DE/SOF/EOL, native FIFO credit, refresh stalls, partial abort retention and immediate reload slot protection; zero local audio");
 $finish;
end
initial begin #180000000;$fatal(1,"B preview timeout state=%d accepted=%0d writes=%0d visible=%0d/%0d/%0d",dut.u_capture.state,accepted,written,visible0,visible1,visible2);end
endmodule
