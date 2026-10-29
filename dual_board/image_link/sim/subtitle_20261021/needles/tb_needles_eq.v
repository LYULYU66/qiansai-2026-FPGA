`timescale 1ns/1ps
module tb_needles_eq;
reg clk=0, rst=1; always #20 clk=~clk;
reg vs=0, de=0, key_n=1; reg [10:0] hx; reg [9:0] vy;
wire [23:0] bg={hx[7:0],vy[7:0],8'h40};
wire [23:0] o_old, o_new;
video_dashboard_needles_old #(.STEP_CYCLES(1_260_007),.DEBOUNCE_CYCLES(50)) u_old (
    .I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_boost_key_n(key_n),.I_rgb(bg),.O_rgb(o_old));
video_dashboard_needles #(.STEP_CYCLES(1_260_007),.DEBOUNCE_CYCLES(50)) u_new (
    .I_clk(clk),.I_rst(rst),.I_enable(1'b1),.I_vs(vs),.I_de(de),.I_boost_key_n(key_n),.I_rgb(bg),.O_rgb(o_new));
always @(posedge clk) begin
    if(rst) begin hx<=0; vy<=0; end
    else begin
        if(hx==799) begin hx<=0; vy<=(vy==524)?0:vy+1'b1; end else hx<=hx+1'b1;
    end
    vs<=!rst && vy<2; de<=!rst && vy>=35 && vy<515 && hx<640;
end
integer frame=0, compared=0, skipped=0, errs=0, frame_err=0, hits=0, frame_hits=0;
reg [2:0] st_start; reg dirty;
wire [2:0] st_old={u_old.key_stable, u_old.sweep_step};
reg [5:0] seen_states=0;
always @(posedge clk) if(!rst) begin
    if(hx==0 && vy==0) begin
        if(frame>0) begin
            if(dirty) skipped=skipped+1;
            else begin compared=compared+1; errs=errs+frame_err; hits=hits+frame_hits;
                seen_states[(st_start[2]?3:0)+(st_start[1:0]==0?0:st_start[1:0]==1?1:2)]=1; end
        end
        if(frame>0) $display("frame %0d state=%b dirty=%0d", frame, st_start, dirty);
        frame=frame+1; frame_err=0; frame_hits=0; dirty=0; st_start=st_old;
    end
    if(st_old!=st_start) dirty=1;
    if(de && !dirty) begin
        if(o_old!==o_new) begin frame_err=frame_err+1;
            if(errs+frame_err<5) $display("diff f=%0d x=%0d y=%0d old=%h new=%h st=%b",frame,hx,vy-35,o_old,o_new,st_old); end
        if(o_old!==bg) frame_hits=frame_hits+1;
    end
end
initial begin
    #100 rst=0;
    // key: released, pressed after ~6 frames, released after ~13 frames
    #(420000*40*14) key_n=0;
    #(420000*40*16) key_n=1;
    #(420000*40*10);
    $display("frames compared=%0d skipped(state change mid-frame)=%0d states=%b needle px=%0d errors=%0d",
             compared, skipped, seen_states, hits, errs);
    if(errs==0 && seen_states==6'b111111) $display("PASS"); else $display("FAIL");
    $finish;
end
endmodule
