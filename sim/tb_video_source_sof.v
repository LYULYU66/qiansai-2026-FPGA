`timescale 1ns/1ps
module tb_video_source_sof;
reg clk=0, rst=1, trigger=0;
wire user, valid, last;
wire [23:0] data;
integer x=0, y=0, frames=0, pixels=0;
always #20 clk=~clk;
video_source_test #(.HTOTAL(800),.HACTIVE(640),.HFP(16),.HSA(96),.HBP(48),
 .VTOTAL(525),.VACTIVE(480),.VFP(10),.VSA(2),.VBP(33)) dut(
 .I_clk(clk),.I_rst(rst),.I_tpg_trig_en(trigger),.O_video_user(user),
 .O_video_valid(valid),.O_video_last(last),.O_video_data(data),.I_video_ready(1'b1));
always @(posedge clk) begin
    #1;
    if(!rst) begin
        if(!valid && (user || last)) $fatal(1,"Sideband outside VALID");
        if(valid) begin
            if(user !== (x==0 && y==0)) $fatal(1,"Test source SOF mismatch x=%0d y=%0d",x,y);
            if(last !== (x==639)) $fatal(1,"Test source EOL mismatch x=%0d y=%0d",x,y);
            if(data !== {16'd0,x[7:0]}) $fatal(1,"Test source RGB mismatch");
            pixels=pixels+1;
            if(x==639) begin
                x=0;
                if(y==479) begin
                    y=0; frames=frames+1;
                    if(frames==2) begin
                        $display("PASS VIDEO_SOURCE_SOF frames=%0d pixels=%0d",frames,pixels);
                        $finish;
                    end
                end else y=y+1;
            end else x=x+1;
        end
    end
end
initial begin repeat(5) @(negedge clk); rst=0; trigger=1; end
initial begin #40000000; $fatal(1,"timeout"); end
endmodule
