`timescale 1ns/1ps
module tb_audio_lyric_timeline;
reg aclk=0,vclk=0,rst=1,enabled=1,song_ok=1,sample_read=0;
wire [7:0] current,nextline; wire [4:0] sung; wire [9:0] pixels;
audio_lyric_timeline #(.SONG_SAMPLES(24'd512)) dut(aclk,vclk,rst,enabled,song_ok,sample_read,current,nextline,sung,pixels);
always #5 aclk=~aclk; always #7 vclk=~vclk;
integer i,loopnum,wanted,cur,nxt,lastp;
task settle; begin repeat(48) @(negedge aclk); end endtask
task consume; begin @(negedge aclk); sample_read=1; @(negedge aclk); sample_read=0; settle; end endtask
task check;
 input integer pos;
 begin
    if(pos<128) begin cur=23;nxt=10;wanted=pos/4;end
    else if(pos<192) begin cur=23;nxt=10;wanted=32;end
    else if(pos<320) begin cur=23;nxt=10;wanted=32+(pos-192)/2;end
    else if(pos<352) begin cur=23;nxt=10;wanted=96;end
    else if(pos<416) begin cur=10;nxt=21;wanted=(pos-352)/2;end
    else if(pos<480) begin cur=10;nxt=21;wanted=32;end
    else begin cur=1;nxt=2;wanted=0;end
    if(current!==cur || nextline!==nxt || int'(pixels)<wanted-1 || int'(pixels)>wanted+1)
        $fatal(1,"smooth timeline pos=%0d state=%0d/%0d/%0d expected=%0d/%0d/%0d",pos,current,nextline,pixels,cur,nxt,wanted);
    if(sung!==pixels[9:5]) $fatal(1,"torn red/sung mailbox");
 end
endtask
initial begin
    settle;rst=0;settle;check(0);
    for(loopnum=0;loopnum<200;loopnum=loopnum+1) begin
        for(i=1;i<512;i=i+1) begin
            consume;check(i);
            if(loopnum==0 && (i==80 || i==160 || i==260 || i==490)) begin
                lastp=pixels; repeat(400) @(negedge aclk);
                if(pixels!==lastp || dut.sample_count!==i) $fatal(1,"underflow advanced sweep");
            end
        end
        consume;
        if(dut.sample_count!==0) $fatal(1,"EOF drift");
        check(0);
    end
    enabled=0;settle;
    if(current!==0 || nextline!==0 || pixels!==0) $fatal(1,"stop failed");
    enabled=1;song_ok=0;repeat(5) consume;
    if(dut.sample_count!==0 || current!==0) $fatal(1,"wrong song enabled");
    song_ok=1;settle;check(0);
    @(negedge aclk);
    dut.sample_count=9;dut.last_due=0;dut.event_index=300;
    dut.boundary_index=3;dut.due_valid=0;dut.rate=0;dut.div_busy=0;
    settle;
    if(current==31) $fatal(1,"future event triggered early");
    consume;
    if(current!==31 || nextline!==23 || pixels!==0 || dut.event_index!==301)
        $fatal(1,"9-bit compact event failed");
    $display("PASS smooth PCM timeline: per-sample interpolation within 1px, silent-gap holds, 200 exact loops, interlude preview, underflow freeze, stop/wrong-file, two-stage ROM and atomic CDC");
    $finish;
end
initial begin #80000000;$fatal(1,"timeline timeout");end
endmodule
module lyric_event_rom(input I_clk,input [8:0] I_addr,output reg [29:0] O_event);
reg [29:0] first;
always @(posedge I_clk) begin
 case(I_addr)
  0:first<={24'd0,6'd32};
  1:first<={24'd128,6'd1};
  2:first<={24'd64,6'd33};
  3:first<={24'd128,6'd3};
  4:first<={24'd32,6'd32};
  5:first<={24'd64,6'd1};
  6:first<={24'd64,6'd32};
  300:first<={24'd10,6'd32};
  default:first<={24'hFFFFFF,6'd63};
 endcase
 O_event<=first;
end
endmodule
module lyric_boundary_map(input [5:0] I_addr,output reg [4:0] O_current,O_next);
always @(*) begin
 case(I_addr)
  0:begin O_current=23;O_next=10;end
  1:begin O_current=10;O_next=21;end
  2:begin O_current=1;O_next=2;end
  3:begin O_current=31;O_next=23;end
  default:begin O_current=0;O_next=0;end
 endcase
end
endmodule
