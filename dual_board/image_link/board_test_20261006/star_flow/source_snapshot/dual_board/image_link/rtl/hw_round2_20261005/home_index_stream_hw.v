`timescale 1ns/1ps
// B: lossless static UI expansion. Advancing only on accepted image pixels
// means packet retries, TF stalls and arbiter backpressure never move the UI.
// BMP storage direction affects the row address, not the visual coordinates.
module home_index_stream(
    input wire clk,rst,start,consume,
    input wire [1:0] frame_index,
    input wire top_down,
    output wire ready,
    output wire [7:0] index
);
localparam ROW_READ=0,ROW_WAIT=1,RUN_READ=2,RUN_WAIT=3,PIXELS=4,RUN_COUNT=5;
reg [2:0] state;
reg active,page,direction;
reg [9:0] x;
reg [8:0] y;
reg [13:0] run_address;
reg [8:0] remaining;
reg [7:0] ink;
reg [7:0] run_count;
wire [13:0] row_start;
wire [15:0] run_word;
home_row_rom rows(.clk(clk),.enable(active && state==ROW_READ),
    .address({page,y}),.data(row_start));
home_run_rom runs(.clk(clk),.enable(active && state==RUN_READ),
    .address(run_address),.data(run_word));
assign ready=!active || state==PIXELS;
assign index=active ? ink : 8'd0;
always @(posedge clk or posedge rst) begin
    if(rst) begin state<=ROW_READ;active<=0;page<=0;direction<=1;
        x<=0;y<=0;run_address<=0;remaining<=0;ink<=0;run_count<=0;end
    else if(start) begin
        active<=frame_index<2;page<=frame_index[0];direction<=top_down;
        x<=0;y<=top_down ? 0 : 479;state<=ROW_READ;ink<=0;
    end else if(active) begin
        case(state)
            ROW_READ:state<=ROW_WAIT;
            ROW_WAIT:begin run_address<=row_start;state<=RUN_READ;end
            RUN_READ:state<=RUN_WAIT;
            // Split BRAM clock-to-Q from the length increment. ready stays
            // low for one extra UDP clock per run; coordinates/palette tags
            // continue to advance ONLY on accepted image pixels.
            RUN_WAIT:begin run_count<=run_word[15:8];
                ink<=run_word[7:0];state<=RUN_COUNT;end
            RUN_COUNT:begin remaining<={1'b0,run_count}+9'd1;state<=PIXELS;end
            PIXELS:if(consume) begin
                if(x==639) begin
                    x<=0;
                    if((direction && y==479)||(!direction && y==0)) active<=0;
                    else begin y<=direction ? y+1'b1 : y-1'b1;state<=ROW_READ;end
                end else begin
                    x<=x+1'b1;
                    if(remaining==1) begin run_address<=run_address+1'b1;state<=RUN_READ;end
                    else remaining<=remaining-1'b1;
                end
            end
            default:state<=ROW_READ;
        endcase
    end
end
endmodule
