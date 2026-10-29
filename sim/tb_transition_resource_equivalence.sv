`timescale 1ns/1ps
module tb_transition_resource_equivalence;
reg clk=0,rst=1,vs=1,de=0,valid=0;
reg [1:0] request=0;
reg [23:0] a=0,b=0;
reg [31:0] noise=32'h73ab45cd;
wire [23:0] actual,expected;
wire [15:0] control_a,control_b;
integer scene,frame,x,y,pixels=0;
always #5 clk=~clk;
`define PORTS(R,C) .I_clk(clk),.I_rst(rst),.I_frame_vs(vs),.I_hs(1'b1), \
 .I_vs(vs),.I_de(de),.I_rgb_a(a),.I_rgb_b(b),.I_display_valid(valid),.I_requested_idx(request), \
 .O_read_idx_a(C[1:0]),.O_read_idx_b(C[3:2]),.O_read_b_enable(C[4]),.O_display_idx(C[6:5]), \
 .O_transition_active(C[7]),.O_transition_kind(C[9:8]),.O_transition_step(C[15:10]), \
 .O_hs(),.O_vs(),.O_de(),.O_rgb(R)
video_transition_effects #(.V_ACTIVE(8)) dut(`PORTS(actual,control_a),
 .I_frame_read_req(1'b0),.I_force_warning(1'b0),.I_warning_ready(1'b0));
video_transition_effects_resource2_reference #(.V_ACTIVE(8)) ref_dut(`PORTS(expected,control_b));
`undef PORTS
always @(posedge clk) begin
    #1;
    if (!rst) begin
        if(control_a!==control_b) $fatal(1,"transition control mismatch");
        if(dut.O_de) begin
            if(actual!==expected)
                $fatal(1,"transition pixel mismatch scene=%0d frame=%0d x=%0d y=%0d got=%h expected=%h",scene,frame,x,y,actual,expected);
            pixels=pixels+1;
        end
    end
end
initial begin
    repeat(4) @(negedge clk); rst=0; valid=1;
    repeat(8) @(negedge clk);
    for(scene=0;scene<4;scene=scene+1) begin
        request=(scene+1)%4;
        repeat(8) @(negedge clk);
        for(frame=0;frame<33;frame=frame+1) begin
            vs=1; repeat(3) @(negedge clk);
            vs=0; repeat(3) @(negedge clk);
            for(y=0;y<8;y=y+1) begin
                for(x=0;x<640;x=x+1) begin
                    de=1;
                    noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
                    a=noise[23:0]; b={noise[15:0],noise[31:24]};
                    @(negedge clk);
                end
                de=0;
                repeat(1+y%4) @(negedge clk);
            end
        end
    end
    $display("PASS TRANSITION_EQ %0d pixels all 32 steps, four effects, short blanking",pixels);
    $finish;
end
endmodule
