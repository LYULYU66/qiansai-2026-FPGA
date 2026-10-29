// Load-time, separable bilinear DOWNscaler. Source dimensions must be at
// least OUT_WIDTH x OUT_HEIGHT (enforced by the BMP header validator).
// No full-frame on-chip storage; no low-resolution enlargement path.
// BGR bytes arrive in BMP file-row order; the frame writer handles orientation.
// Two target-width Q8 RGB lines retain horizontal precision. One signed
// multiplier is time-shared by all channels and both interpolation passes.
module bmp_bilinear_stream #(
    parameter integer OUT_WIDTH = 640,
    parameter integer OUT_HEIGHT = 480
)(
    input wire clk, rst, start,
    input wire [15:0] source_width, source_height,
    input wire byte_valid,
    input wire [7:0] byte_data,
    input wire pixel_ready,
    output wire sector_ready,
    output reg busy, done, overflow,
    output reg pixel_valid,
    output reg [23:0] pixel_rgb
);
localparam IDLE=0, DIVIDE=1, DIV_Y=2, READ=3, BYTE=4,
           H_CHECK=5, H_SETUP=6, MUL=7, ACC=8, H_WRITE=9,
           H_NEXT=10, NEXT_PIXEL=11, ROW_DONE=12,
           V_READ=13, V_SETUP=14, V_SAVE=15, V_NEXT=16,
           X_CARRY=17, Y_CARRY=18, Y_CHECK=19, Y_PREP=20;
reg [4:0] state;
reg [15:0] width_r, height_r, source_x, source_y;
reg [9:0] dest_x, dest_y;
reg [23:0] x_pos, y_pos, x_step, y_step;
reg [9:0] x_rem, y_rem, x_err, y_err;
reg x_carry,y_carry;
// width_r/height_r hold the inclusive last source coordinate. Computing
// minus-one once avoids subtract+compare chains in every pixel/row decision.
wire [1:0] row_pad=width_r[1:0]+2'd1;
reg [23:0] div_shift, div_quot;
reg [9:0] div_rem, div_den;
reg [4:0] div_count;
reg div_axis;
wire [10:0] trial_rem={div_rem,div_shift[23]};
wire div_bit=(trial_rem >= {1'b0,div_den});
wire [10:0] next_rem=div_bit ? trial_rem-{1'b0,div_den} : trial_rem;
wire [23:0] next_quot={div_quot[22:0],div_bit};
wire [10:0] x_err_sum={1'b0,x_err}+{1'b0,x_rem};
wire [10:0] y_err_sum={1'b0,y_err}+{1'b0,y_rem};
// Destination row coordinates change only between output rows. Register
// both neighbors once rather than placing compare/add/mux before every
// source-row decision and FSM register enable at 100 MHz.
reg [15:0] want_y0,want_y1;
reg identity_height;
wire [15:0] want_x1=(x_pos[23:8] < width_r) ? x_pos[23:8]+16'd1 : x_pos[23:8];
wire needed_row=(source_y==want_y0)||(source_y==want_y1);

// Sector-level credit: reserve a full 512-byte burst before requesting it.
// Synchronous block RAM, no RAM reset (pointers/count provide validity).
(* ram_style="block" *) reg [7:0] fifo [0:1023];
reg [9:0] wr_ptr, rd_ptr;
reg [10:0] used;
reg [7:0] fifo_q;
wire push=busy && byte_valid;
wire pop=busy && state==READ && used!=0;
assign sector_ready=busy && used<=11'd512;
always @(posedge clk) begin
    if(push && used<11'd1024) fifo[wr_ptr]<=byte_data;
    if(pop) fifo_q<=fifo[rd_ptr];
end
always @(posedge clk or posedge rst) begin
    if(rst) begin wr_ptr<=0; rd_ptr<=0; used<=0; overflow<=0; end
    else if(start) begin wr_ptr<=0; rd_ptr<=0; used<=0; overflow<=0; end
    else if(busy) begin
        if(push && used==11'd1024 && !pop) overflow<=1;
        if(push) wr_ptr<=wr_ptr+1'b1;
        if(pop) rd_ptr<=rd_ptr+1'b1;
        case({push,pop})
            2'b10: used<=used+1'b1;
            2'b01: used<=used-1'b1;
            default: ;
        endcase
    end
end

reg [1:0] byte_phase, pad_left, channel;
reg padding;
reg [23:0] left_rgb, right_rgb;
reg [15:0] bg;
reg signed [16:0] mul_delta;
reg signed [8:0] mul_frac;
reg [15:0] mul_base;
reg signed [25:0] product, result;
reg vertical;
reg [7:0] h_left, h_right;
always @(*) begin
    case(channel)
        0: begin h_left=left_rgb[7:0]; h_right=right_rgb[7:0]; end
        1: begin h_left=left_rgb[15:8]; h_right=right_rgb[15:8]; end
        default: begin h_left=left_rgb[23:16]; h_right=right_rgb[23:16]; end
    endcase
end
wire [10:0] line_addr=({1'b0,dest_x}<<1)+dest_x+channel;
wire [15:0] line0_q, line1_q;
wire line_we=busy && state==H_WRITE;
wire [15:0] v_a=want_y0[0] ? line1_q : line0_q;
wire [15:0] v_b=want_y1[0] ? line1_q : line0_q;
// 1920 words/line fit one 2048x16 BRAM32K. Both read ports are synchronous.
`ifdef BILINEAR_FAST_SIM
reg [15:0] line0 [0:2047], line1 [0:2047];
reg [15:0] line0_read, line1_read;
assign line0_q=line0_read; assign line1_q=line1_read;
always @(posedge clk) begin
    if(line_we && !source_y[0]) line0[line_addr]<=result[15:0];
    if(line_we && source_y[0]) line1[line_addr]<=result[15:0];
    line0_read<=line0[line_addr]; line1_read<=line1[line_addr];
end
`else
EG_PHY_BRAM32K u_line0 (
    .doa(), .dia(result[15:0]), .addra(line_addr), .bytea(1'b0), .bytewea(1'b0),
    .csa(1'b1), .wea(line_we && !source_y[0]), .clka(clk), .rsta(1'b0), .ocea(1'b1),
    .dob(line0_q), .dib(16'd0), .addrb(line_addr), .byteb(1'b0), .byteweb(1'b0),
    .csb(1'b1), .web(1'b0), .clkb(clk), .rstb(1'b0), .oceb(1'b1));
EG_PHY_BRAM32K u_line1 (
    .doa(), .dia(result[15:0]), .addra(line_addr), .bytea(1'b0), .bytewea(1'b0),
    .csa(1'b1), .wea(line_we && source_y[0]), .clka(clk), .rsta(1'b0), .ocea(1'b1),
    .dob(line1_q), .dib(16'd0), .addrb(line_addr), .byteb(1'b0), .byteweb(1'b0),
    .csb(1'b1), .web(1'b0), .clkb(clk), .rstb(1'b0), .oceb(1'b1));
`endif

always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE; busy<=0; done<=0; pixel_valid<=0; pixel_rgb<=0;
        width_r<=0; height_r<=0; source_x<=0; source_y<=0;
        want_y0<=0; want_y1<=0; identity_height<=0;
        dest_x<=0; dest_y<=0; x_pos<=0; y_pos<=0; x_step<=0; y_step<=0;
        x_rem<=0; y_rem<=0; x_err<=0; y_err<=0;
        x_carry<=0; y_carry<=0;
        div_shift<=0; div_quot<=0; div_rem<=0; div_den<=1; div_count<=0; div_axis<=0;
        byte_phase<=0; pad_left<=0; padding<=0; channel<=0;
        left_rgb<=0; right_rgb<=0; bg<=0; vertical<=0;
        mul_delta<=0; mul_frac<=0; mul_base<=0; product<=0; result<=0;
    end else begin
        pixel_valid<=0;
        if(start) begin
            busy<=1; done<=0; state<=DIVIDE;
            width_r<=source_width-16'd1; height_r<=source_height-16'd1;
            want_y0<=0; want_y1<=source_height>1 ? 16'd1 : 16'd0;
            identity_height<=source_height==OUT_HEIGHT;
            source_x<=0; source_y<=0; dest_x<=0; dest_y<=0;
            x_pos<=0; y_pos<=0; x_err<=0; y_err<=0;
            div_shift<={(source_width-16'd1),8'd0};
            div_quot<=0; div_rem<=0; div_den<=OUT_WIDTH-1; div_count<=24; div_axis<=0;
            byte_phase<=0; padding<=0; pad_left<=0; channel<=0;
        end else case(state)
            DIVIDE: begin
                div_shift<={div_shift[22:0],1'b0}; div_quot<=next_quot;
                div_rem<=next_rem[9:0]; div_count<=div_count-1'b1;
                if(div_count==1) begin
                    if(!div_axis) begin x_step<=next_quot; x_rem<=next_rem[9:0]; state<=DIV_Y; end
                    else begin y_step<=next_quot; y_rem<=next_rem[9:0]; state<=READ; end
                end
            end
            DIV_Y: begin
                div_shift<={height_r,8'd0}; div_quot<=0; div_rem<=0;
                div_den<=OUT_HEIGHT-1; div_count<=24; div_axis<=1; state<=DIVIDE;
            end
            READ: if(pop) state<=BYTE;
            BYTE: begin
                if(padding) begin
                    pad_left<=pad_left-1'b1;
                    if(pad_left==1) begin padding<=0; state<=ROW_DONE; end
                    else state<=READ;
                end else case(byte_phase)
                    0: begin bg[7:0]<=fifo_q; byte_phase<=1; state<=READ; end
                    1: begin bg[15:8]<=fifo_q; byte_phase<=2; state<=READ; end
                    default: begin
                        left_rgb<=(source_x==0) ? {fifo_q,bg} : right_rgb;
                        right_rgb<={fifo_q,bg}; byte_phase<=0;
                        state<=needed_row ? H_CHECK : NEXT_PIXEL;
                    end
                endcase
            end
            H_CHECK: begin
                if(source_x==want_x1) begin channel<=0; state<=H_SETUP; end
                else state<=NEXT_PIXEL;
            end
            H_SETUP: begin
                // Last-column/single-column interpolation clamps both neighbors.
                mul_base<={8'd0,(x_pos[23:8]==width_r ? h_right : h_left)};
                mul_delta<=(x_pos[23:8]==width_r) ? 17'sd0 :
                    $signed({1'b0,h_right})-$signed({1'b0,h_left});
                mul_frac<=$signed({1'b0,x_pos[7:0]}); vertical<=0; state<=MUL;
            end
            MUL: begin product<=mul_delta*mul_frac; state<=ACC; end
            ACC: begin
                result<=$signed({2'b0,mul_base,8'd0})+product+(vertical ? 26'sd32768 : 26'sd0);
                state<=vertical ? V_SAVE : H_WRITE;
            end
            H_WRITE: begin
                if(channel==2) state<=H_NEXT;
                else begin channel<=channel+1'b1; state<=H_SETUP; end
            end
            H_NEXT: begin
                if(dest_x==OUT_WIDTH-1) state<=NEXT_PIXEL;
                else begin
                    x_pos<=x_pos+x_step;
                    x_carry<=(x_err_sum>=OUT_WIDTH-1);
                    x_err<=(x_err_sum>=OUT_WIDTH-1) ? x_err_sum-(OUT_WIDTH-1) : x_err_sum;
                    state<=X_CARRY;
                end
            end
            X_CARRY: begin
                if(x_carry) x_pos<=x_pos+24'd1;
                dest_x<=dest_x+1'b1; channel<=0;
                // Downscaling advances to a new source column after each
                // destination sample. Only identity scaling's last column
                // reuses the current pair for its clamped final endpoint.
                state<=(source_x==width_r) ? H_SETUP : NEXT_PIXEL;
            end
            NEXT_PIXEL: begin
                if(source_x==width_r) begin
                    pad_left<=row_pad; padding<=|row_pad;
                    state<=(row_pad==0) ? ROW_DONE : READ;
                end else begin source_x<=source_x+1'b1; state<=READ; end
            end
            ROW_DONE: begin
                dest_x<=0; channel<=0;
                if(source_y==want_y1) state<=V_READ;
                else begin source_y<=source_y+1'b1; source_x<=0; x_pos<=0; x_err<=0; state<=READ; end
            end
            V_READ: state<=V_SETUP;
            V_SETUP: begin
                mul_base<=v_a;
                mul_delta<=$signed({1'b0,v_b})-$signed({1'b0,v_a});
                mul_frac<=$signed({1'b0,y_pos[7:0]}); vertical<=1; state<=MUL;
            end
            V_SAVE: if(channel!=2 || pixel_ready) begin
                case(channel)
                    0: pixel_rgb[7:0]<=result[23:16];
                    1: pixel_rgb[15:8]<=result[23:16];
                    default: pixel_rgb[23:16]<=result[23:16];
                endcase
                if(channel==2) begin pixel_valid<=1; state<=V_NEXT; end
                else begin channel<=channel+1'b1; state<=V_READ; end
            end
            V_NEXT: begin
                channel<=0;
                if(dest_x!=OUT_WIDTH-1) begin dest_x<=dest_x+1'b1; state<=V_READ; end
                else if(dest_y==OUT_HEIGHT-1) begin done<=1; busy<=0; state<=IDLE; end
                else begin
                    dest_x<=0; dest_y<=dest_y+1'b1; y_pos<=y_pos+y_step;
                    y_carry<=(y_err_sum>=OUT_HEIGHT-1);
                    y_err<=(y_err_sum>=OUT_HEIGHT-1) ? y_err_sum-(OUT_HEIGHT-1) : y_err_sum;
                    state<=Y_CARRY;
                end
            end
            Y_CARRY: begin
                if(y_carry) y_pos<=y_pos+24'd1;
                state<=Y_PREP;
            end
            Y_PREP: begin
                want_y0<=y_pos[23:8];
                want_y1<=y_pos[23:8]<height_r ? y_pos[23:8]+16'd1 : y_pos[23:8];
                state<=Y_CHECK;
            end
            Y_CHECK: begin
                // No repeated/intermediate output rows for enlargement.
                // Identity scaling alone reuses the last row for its endpoint.
                if(dest_y==OUT_HEIGHT-1 && identity_height) state<=V_READ;
                else begin
                    source_y<=source_y+1'b1; source_x<=0; x_pos<=0; x_err<=0;
                    state<=READ;
                end
            end
            default: ;
        endcase
    end
end
endmodule
