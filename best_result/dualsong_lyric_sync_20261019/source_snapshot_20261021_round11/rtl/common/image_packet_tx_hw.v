`timescale 1ns/1ps

// IMGF/IMG2/IMG3/IMG4 pixel stream -> UDP payload. The source and
// this module share clk; the future TF 100 MHz -> UDP 125 MHz boundary must
// use a proper dual-clock FIFO before this interface.
module image_packet_tx #(
    parameter integer FRAME_PACKETS = 1200,
    parameter integer INTER_PACKET_CYCLES = 700,
    parameter integer RELIABLE = 0,
    parameter integer RETRY_CYCLES = 12_500_000,
    parameter integer EXTERNAL_TOKEN = 0,
    parameter integer UI_TAG = 0,
    parameter integer RESOLUTION = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        source_valid,
    output wire        source_ready,
    input  wire [23:0] source_rgb,
    input  wire [7:0]  source_tag,
    input  wire        source_frame_start,
    input  wire [1:0]  source_frame_index,
    input  wire        source_top_down,
    input  wire [31:0] source_resolution,
    input  wire        udp_ready,
    input  wire        udp_ack,
    output wire        udp_request,
    output wire        udp_valid,
    output reg  [7:0]  udp_data,
    output wire [15:0] udp_length,
    output reg         frame_sent,
    output reg  [15:0] packets_sent,
    input  wire        receipt_valid,
    input  wire [31:0] receipt_token,
    input  wire [15:0] receipt_sequence,
    output wire [31:0] transfer_token,
    output wire [15:0] packet_sequence,
    input wire [31:0] frame_token
);

localparam [2:0] ST_NEW_FRAME = 3'd0;
localparam [2:0] ST_FILL      = 3'd1;
localparam [2:0] ST_WAIT      = 3'd2;
localparam [2:0] ST_REQUEST   = 3'd3;
localparam [2:0] ST_PRIME     = 3'd4;
localparam [2:0] ST_BYTES     = 3'd5;
localparam [2:0] ST_GAP       = 3'd6;
localparam [2:0] ST_RECEIPT   = 3'd7;
localparam [15:0] LAST_PACKET = FRAME_PACKETS - 1;
localparam integer HEADER_BYTES = RESOLUTION ? 16 : (RELIABLE ? 12 : 8);
localparam integer CRC_OFFSET = HEADER_BYTES + (UI_TAG ? 1024 : 768);
localparam integer PACKET_BYTES = CRC_OFFSET + 2;
localparam integer B_WIDTH = UI_TAG ? 16 : 8;
localparam [1:0] LAST_PHASE = UI_TAG ? 2'd3 : 2'd2;

function [15:0] crc16_byte;
    input [15:0] old_crc;
    input [7:0] value;
    reg [15:0] c;
    integer i;
    begin
        c = old_crc ^ {value, 8'h00};
        for (i=0;i<8;i=i+1)
            c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
        crc16_byte = c;
    end
endfunction

reg [15:0] packet_rg [0:255]; /* fehdl force_ram=1, ram_style="bram" */
reg [B_WIDTH-1:0] packet_b [0:255]; /* fehdl force_ram=1, ram_style="bram" */
reg [2:0] state;
reg [7:0] fill_index;
reg [1:0] frame_index;
reg       top_down;
reg [31:0] resolution;
reg [15:0] sequence_no;
reg [10:0] byte_index;
reg [7:0] payload_index;
reg [1:0] byte_phase;
reg [15:0] packet_rg_out;
reg [B_WIDTH-1:0] packet_b_out;
wire [31:0] ram_pixel = UI_TAG ? {packet_rg_out,packet_b_out} :
                                                   {packet_rg_out,packet_b_out,8'd0};
// Isolate BRAM clock-to-output from the byte mux and both CRC engines.
// This register is always loaded before a payload is visible, including
// retries and the first packet following an abort; no RAM/reset clear needed.
reg [31:0] payload_pixel;
reg [15:0] crc_running;
reg [15:0] gap_count;
reg [31:0] token;
reg [31:0] retry_count;
// 20261021 timing: the 48-bit receipt match is registered and acted on one
// clock later (token/sequence_no are constant while waiting for the receipt).
reg receipt_match_q;
assign transfer_token = token;
assign packet_sequence = sequence_no;

assign source_ready = (state == ST_NEW_FRAME) || (state == ST_FILL);
assign udp_request = (state == ST_REQUEST);
assign udp_valid = (state == ST_BYTES);
assign udp_length = PACKET_BYTES;

wire packet_write_enable = source_valid &&
    (((state == ST_NEW_FRAME) && source_frame_start) ||
     (state == ST_FILL));
wire [7:0] packet_write_addr =
    (state == ST_NEW_FRAME) ? 8'd0 : fill_index;
wire packet_read_enable = (state == ST_PRIME) ||
    ((state == ST_BYTES) && (byte_index >= HEADER_BYTES) &&
     (byte_index < CRC_OFFSET) && (byte_phase == LAST_PHASE-1'b1) &&
     (payload_index != 8'd255));
wire [7:0] packet_read_addr =
    (state == ST_PRIME) ? 8'd0 : (payload_index + 8'd1);

always @(posedge clk) begin
    if (packet_write_enable) begin
        packet_rg[packet_write_addr] <= source_rgb[23:8];
        packet_b[packet_write_addr] <= UI_TAG ? {source_rgb[7:0],source_tag} : source_rgb[7:0];
    end
    if (packet_read_enable) begin
        packet_rg_out <= packet_rg[packet_read_addr];
        packet_b_out <= packet_b[packet_read_addr];
    end
    // Header clocks prime pixel 0. For subsequent pixels, prefetch RAM one
    // byte early, keep the old held pixel for its last byte, then capture the
    // prefetched word at that last-byte edge. Valid/request/data timing at
    // the application port is exactly the same as the original transmitter.
    if(state==ST_BYTES && (byte_index==HEADER_BYTES-1 ||
       (byte_index>=HEADER_BYTES && byte_index<CRC_OFFSET &&
        byte_phase==LAST_PHASE && payload_index!=8'd255)))
        payload_pixel<=ram_pixel;
end

always @* begin
    case (byte_index)
        10'd0: udp_data = "I";
        10'd1: udp_data = "M";
        10'd2: udp_data = "G";
        10'd3: udp_data = RESOLUTION ? "4" : (UI_TAG ? "3" : (RELIABLE ? "2" : "F"));
        10'd4: udp_data = {6'd0,frame_index};
        10'd5: udp_data = sequence_no[7:0];
        10'd6: udp_data = sequence_no[15:8];
        10'd7: udp_data = {7'd0,top_down};
        CRC_OFFSET: udp_data = crc_running[15:8];
        CRC_OFFSET+1: udp_data = crc_running[7:0];
        default: begin
            if (RELIABLE && byte_index == 10'd8) udp_data = token[7:0];
            else if (RELIABLE && byte_index == 10'd9) udp_data = token[15:8];
            else if (RELIABLE && byte_index == 10'd10) udp_data = token[23:16];
            else if (RELIABLE && byte_index == 10'd11) udp_data = token[31:24];
            else if (RESOLUTION && byte_index == 12) udp_data = resolution[23:16];
            else if (RESOLUTION && byte_index == 13) udp_data = resolution[31:24];
            else if (RESOLUTION && byte_index == 14) udp_data = resolution[7:0];
            else if (RESOLUTION && byte_index == 15) udp_data = resolution[15:8];
            else case (byte_phase)
                2'd0: udp_data = payload_pixel[31:24];
                2'd1: udp_data = payload_pixel[23:16];
                2'd2: udp_data = payload_pixel[15:8];
                default: udp_data = payload_pixel[7:0];
            endcase
        end
    endcase
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= ST_NEW_FRAME;
        fill_index <= 8'd0;
        frame_index <= 2'd0;
        top_down <= 1'b0;
        resolution <= 32'h028001e0;
        sequence_no <= 16'd0;
        byte_index <= 10'd0;
        payload_index <= 8'd0;
        byte_phase <= 2'd0;
        crc_running <= 16'hffff;
        gap_count <= 16'd0;
        frame_sent <= 1'b0;
        packets_sent <= 16'd0;
        token <= 32'd0;
        retry_count <= 32'd0;
        receipt_match_q <= 1'b0;
    end else begin
        frame_sent <= 1'b0;
        receipt_match_q <= (state == ST_RECEIPT) && receipt_valid &&
                           receipt_token == token && receipt_sequence == sequence_no;
        case (state)
            ST_NEW_FRAME: begin
                if (source_valid && source_frame_start) begin
                    token <= EXTERNAL_TOKEN ? frame_token : token + 32'd1;
                    frame_index <= source_frame_index;
                    top_down <= source_top_down;
                    if(RESOLUTION) resolution <= source_resolution;
                    sequence_no <= 16'd0;
                    fill_index <= 8'd1;
                    state <= ST_FILL;
                end
            end
            ST_FILL: begin
                if (source_valid) begin
                    if (fill_index == 8'd255)
                        state <= ST_WAIT;
                    else
                        fill_index <= fill_index + 8'd1;
                end
            end
            ST_WAIT: begin
                if (udp_ready)
                    state <= ST_REQUEST;
            end
            ST_REQUEST: begin
                if (udp_ack)
                    state <= ST_PRIME;
            end
            ST_PRIME: begin
                payload_index <= 8'd0;
                byte_phase <= 2'd0;
                byte_index <= 10'd0;
                crc_running <= 16'hffff;
                state <= ST_BYTES;
            end
            ST_BYTES: begin
                if (byte_index < CRC_OFFSET)
                    crc_running <= crc16_byte(crc_running,udp_data);

                if ((byte_index >= HEADER_BYTES) && (byte_index < CRC_OFFSET)) begin
                    if (byte_phase == LAST_PHASE) begin
                        byte_phase <= 2'd0;
                        if (payload_index != 8'd255) begin
                            payload_index <= payload_index + 8'd1;
                        end
                    end else begin
                        byte_phase <= byte_phase + 2'd1;
                    end
                end

                if (byte_index == PACKET_BYTES-1) begin
                    packets_sent <= packets_sent + 16'd1;
                    if (RELIABLE) begin
                        retry_count <= 32'd0;
                        state <= ST_RECEIPT;
                    end else if (sequence_no == LAST_PACKET) begin
                        frame_sent <= 1'b1;
                        state <= ST_NEW_FRAME;
                    end else begin
                        sequence_no <= sequence_no + 16'd1;
                        fill_index <= 8'd0;
                        gap_count <= INTER_PACKET_CYCLES;
                        state <= ST_GAP;
                    end
                end else begin
                    byte_index <= byte_index + 10'd1;
                end
            end
            ST_GAP: begin
                if (gap_count == 16'd0)
                    state <= ST_FILL;
                else
                    gap_count <= gap_count - 16'd1;
            end
            ST_RECEIPT: begin
                if (receipt_match_q) begin
                    if (sequence_no == LAST_PACKET) begin
                        frame_sent <= 1'b1;
                        state <= ST_NEW_FRAME;
                    end else begin
                        sequence_no <= sequence_no + 16'd1;
                        fill_index <= 8'd0;
                        state <= ST_FILL;
                    end
                end else if (retry_count == RETRY_CYCLES-1) begin
                    retry_count <= 32'd0;
                    state <= ST_WAIT;
                end else retry_count <= retry_count + 32'd1;
            end
            default: state <= ST_NEW_FRAME;
        endcase
    end
end

endmodule
