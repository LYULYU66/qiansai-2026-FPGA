`timescale 1ns/1ps
// Star-sky motion engine (20261020), B board, udp_clk. B renders from it and
// sends the same output bundle to A every 250 us (CTL4), so both screens
// step one shared 1280-px sky together.
//   tick   : 2^TICK_BITS clocks (15.26 kHz at 125 MHz)
//   phase  : near-layer offset, px Q20, wraps at 2560 px; far layer = phase/2.
//            It only ever increases: the sky drifts one way (left to right).
//   speed  : every 4.3 s a random target (lull 4-11, gentle 14-29, brisk
//            36-66, gust 70-100 px/s); the speed follows it with a ~2.1 s
//            exponential ease, so the flow slows and quickens smoothly.
//   meteor : one 2.15 s slot each (20261021, was 8.6 s), 7 in 8 slots carry
//            a 1.07 s meteor moving right and slightly down (slope 1/8) at
//            500-980 px/s: about one meteor every 2.5 s.
// The bundle is a function of registers that only change on a tick, so it
// is stable between ticks; bundle_toggle flips one clock after each tick
// (once the new bundle has settled) to qualify the A/B clock crossings.
// No multipliers: a free-running LFSR supplies the random draws.
module star_motion_engine #(
    parameter integer TICK_BITS=13
)(
    input  wire        clk, rst,
    output reg  [75:0] bundle,          // {near_q4,far_q4,twinkle,meteor_on,
                                        //  meteor_x_q4,meteor_y_q4,meteor_env}
    output reg         bundle_toggle
);
localparam [31:0] PHASE_WRAP=32'hA000_0000;   // 2560 px << 20
reg  [TICK_BITS-1:0] divider;
reg  [16:0] time_ticks;
reg  [31:0] phase_q20, speed_acc, lfsr;
reg  [15:0] target;
reg  [2:0]  tick_d;
wire tick=divider=={TICK_BITS{1'b1}};
wire [15:0] speed=speed_acc[31:16];            // px/tick Q20
wire [32:0] phase_sum={1'b0,phase_q20}+{17'd0,speed};
wire [31:0] phase_next=phase_sum>={1'b0,PHASE_WRAP} ? phase_sum[31:0]-PHASE_WRAP : phase_sum[31:0];
wire [15:0] phase_px_q4=phase_q20[31:16];
// speed_acc += (target - speed) / 2^15 (Q16 fraction kept for smoothness)
wire signed [32:0] ease={1'b0,target,16'd0}-{1'b0,speed_acc};
wire [31:0] speed_acc_next=speed_acc+{{15{ease[32]}},ease[32:15]};
function [15:0] pick_target;
    input [9:0] r;
    begin
        case(r[9:8])
            2'd0: pick_target=16'd275 +{7'd0,r[7:0],1'b0};    // lull    4-11 px/s
            2'd1: pick_target=16'd962 +{6'd0,r[7:0],2'b0};    // gentle 14-29 px/s
            2'd2: pick_target=16'd2474+{5'd0,r[7:0],3'b0};    // brisk  36-66 px/s
            default: pick_target=16'd4810+{5'd0,r[7:0],3'b0}; // gust   70-100 px/s
        endcase
    end
endfunction
// meteor
reg         m_slot_has, m_active, m_bright;
reg  [1:0]  m_start;              // start offset in the slot, 4096-tick units
reg  [13:0] m_t;
reg  [11:0] m_vm;                 // px/tick Q16 minus 2147
reg  [27:0] m_x;                  // Q16 px, signed
reg  [24:0] m_y;                  // Q16 px
wire [7:0]  m_prog=m_t[13:6];
wire [7:0]  m_fall=8'd255-m_prog;
wire [9:0]  env_fall={1'b0,m_fall,1'b0}+{2'd0,m_fall[7:2]};       // (255-p)*9/4
wire [7:0]  env_lin=m_prog<8'd32 ? {m_prog[4:0],3'd0} :
                    m_prog<8'd140 ? 8'd255 :
                    env_fall>10'd255 ? 8'd255 : env_fall[7:0];
wire [15:0] vm={4'd0,m_vm}+16'd2147;
// 20261021 timing: the bundle is produced through two register stages
// (envelope/phase wrap, then the dimmer and final pack) instead of being a
// combinational function of the motion registers, and bundle_toggle moves
// two clocks later with it. Consumers still see the toggle only after the
// new bundle has settled; the bundle is simply two clocks later.
reg  [7:0]  env_lin_q;
reg         m_active_q, m_bright_q;
reg  [14:0] near_q;
reg  [14:0] far_q;
reg  [7:0]  twinkle_q;
reg  [15:0] meteor_x_q;
reg  [12:0] meteor_y_q;
wire [7:0]  env_now=!m_active_q ? 8'd0 : m_bright_q ? env_lin_q :
                    env_lin_q-{3'd0,env_lin_q[7:3]}-{4'd0,env_lin_q[7:4]};
always @(posedge clk) begin
    env_lin_q<=env_lin; m_active_q<=m_active; m_bright_q<=m_bright;
    near_q<=phase_px_q4>=16'd20480 ? phase_px_q4-16'd20480 : phase_px_q4[14:0];
    far_q<=phase_q20[31:17]; twinkle_q<=time_ticks[14:7];
    meteor_x_q<=m_x[27:12]; meteor_y_q<=m_y[24:12];
    bundle<={near_q,far_q,twinkle_q,m_active_q,meteor_x_q,meteor_y_q,env_now};
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        divider<=0; time_ticks<=0; phase_q20<=0; speed_acc<={16'd962,16'd0};
        target<=16'd962; lfsr<=32'h1D87_2B41; tick_d<=0;
        m_slot_has<=0; m_active<=0; m_bright<=0; m_start<=0; m_t<=0; m_vm<=0; m_x<=0; m_y<=0;
        bundle_toggle<=0;
    end else begin
        divider<=divider+1'b1;
        tick_d<={tick_d[1:0],tick};
        if(tick_d[2]) bundle_toggle<=~bundle_toggle;
        if(tick) begin
            // Galois LFSR x^32+x^22+x^2+x+1, stepped every tick
            lfsr<=lfsr[0] ? (lfsr>>1)^32'h8020_0003 : lfsr>>1;
            time_ticks<=time_ticks+1'b1;
            phase_q20<=phase_next;
            speed_acc<=speed_acc_next;
            if(time_ticks[15:0]==16'hFFFF) target<=pick_target(lfsr[9:0]);
            if(time_ticks[14:0]==15'h7FFF) begin
                // draw the next slot's meteor (independent LFSR fields);
                // start 0..3 x 4096 + 16384 ticks always ends inside the slot
                m_slot_has<=lfsr[2:0]!=3'd0;
                m_start<=lfsr[4:3];
                m_vm<={1'b0,lfsr[17:7]};                                // 500-977 px/s
                m_x<={3'd0,lfsr[26:18],16'd0}-{12'd64,16'd0};           // -64..447 px
                m_y<={3'd0,lfsr[30:27],2'd0,16'd0}+{9'd24,16'd0};      // 24..84 px
                m_bright<=lfsr[31];
            end else if(!m_active && m_slot_has && time_ticks[14:12]=={1'b0,m_start} &&
                        time_ticks[11:0]==12'd0) begin
                m_active<=1; m_t<=0; m_slot_has<=0;
            end else if(m_active) begin
                m_x<=m_x+{12'd0,vm};
                m_y<=m_y+{12'd0,vm[15:3]};
                m_t<=m_t+1'b1;
                if(m_t==14'h3FFF) m_active<=0;
            end
        end
    end
end
endmodule

// Toggle-qualified CDC for a slowly changing bundle (20261020). The source
// changes 'data' together with a flip of 'toggle' and then holds it for far
// longer than the 3-clock destination synchroniser, so sampling the data
// after the synchronised flip is coherent. No source-side mailbox needed.
module star_bundle_cdc #(parameter integer WIDTH=76)(
    input  wire dst_clk, dst_rst,
    input  wire src_toggle,
    input  wire [WIDTH-1:0] src_data,
    output reg  [WIDTH-1:0] dst_data
);
(* async_reg="true" *) reg [2:0] sync;
always @(posedge dst_clk or posedge dst_rst) begin
    if(dst_rst) begin sync<=0; dst_data<=0; end
    else begin
        sync<={sync[1:0],src_toggle};
        if(sync[2]^sync[1]) dst_data<=src_data;
    end
end
endmodule
