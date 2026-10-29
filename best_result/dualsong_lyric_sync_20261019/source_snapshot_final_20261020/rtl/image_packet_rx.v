`timescale 1ns/1ps

// One-packet, loss-detecting RGB888 receiver for the dual-board image link.
// A complete 640x480 frame has 1200 packets of 256 pixels each. No damaged or
// out-of-order frame may raise frame_complete. A caller must also wait for its
// SDRAM writer's write_finish before exposing the new frame to HDMI.
module image_packet_rx #(
    parameter integer FRAME_PACKETS = 1200,
    parameter integer RELIABLE = 0,
    parameter integer UI_TAG = 0,
    parameter integer RESOLUTION = 0,
    parameter integer SESSION_GUARD = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] generation,
    input  wire        rx_valid,
    input  wire [7:0]  rx_data,
    input  wire [15:0] rx_length,
    input  wire        pixel_ready,
    output wire        pixel_valid,
    output wire [23:0] pixel_rgb,
    output wire [7:0]  pixel_tag,
    output reg  [1:0]  frame_index,
    output reg         frame_top_down,
    output reg  [31:0] frame_resolution,
    output reg         frame_start,
    output reg         frame_complete,
    output reg         frame_abort,
    output reg  [15:0] good_packets,
    output reg  [15:0] bad_packets,
    output reg         packet_done,
    output reg         packet_duplicate,
    output reg  [31:0] packet_token,
    output reg  [15:0] packet_sequence
);

localparam [2:0] ST_IDLE  = 3'd0;
localparam [2:0] ST_RX    = 3'd1;
localparam [2:0] ST_FETCH = 3'd2;
localparam [2:0] ST_SEND  = 3'd3;
localparam [2:0] ST_DROP  = 3'd4;
localparam integer HEADER_BYTES = RESOLUTION ? 16 : (RELIABLE ? 12 : 8);
localparam integer CRC_OFFSET = HEADER_BYTES + (UI_TAG ? 1024 : 768);
localparam [15:0] PACKET_BYTES = CRC_OFFSET + 2;
localparam [15:0] LAST_PACKET = FRAME_PACKETS - 1;
localparam integer B_WIDTH = UI_TAG ? 16 : 8;
localparam [1:0] LAST_PHASE = UI_TAG ? 2'd3 : 2'd2;

function [15:0] crc16_byte;
    input [15:0] old_crc;
    input [7:0]  value;
    reg [15:0] c;
    integer i;
    begin
        c = old_crc ^ {value, 8'h00};
        for (i = 0; i < 8; i = i + 1)
            c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
        crc16_byte = c;
    end
endfunction

// Split 24-bit pixels into two supported BRAM port widths (16 + 8).
reg [15:0] packet_rg [0:255]; /* fehdl force_ram=1, ram_style="bram" */
reg [B_WIDTH-1:0] packet_b [0:255]; /* fehdl force_ram=1, ram_style="bram" */
reg [2:0]  state;
reg        rx_valid_d;
reg [10:0] byte_index;
reg [7:0]  write_pixel_index;
reg [1:0]  byte_phase;
reg [7:0] red_byte, green_byte, blue_byte;
reg [7:0]  incoming_frame;
reg [15:0] incoming_sequence;
reg        incoming_top_down;
reg        header_ok;
reg [15:0] crc_running, crc_received;
reg        active_frame;
reg [15:0] expected_sequence;
reg [7:0]  read_pixel_index;
reg        draining_last_packet;
reg [15:0] packet_rg_out;
reg [B_WIDTH-1:0] packet_b_out;
reg [31:0] incoming_token;
reg [31:0] active_token;
reg have_previous;
reg [31:0] incoming_resolution;
wire resolution_valid=!RESOLUTION ||
    (incoming_resolution[31:16]>=640 && incoming_resolution[15:0]>=480);
wire resolution_same=!RESOLUTION || incoming_resolution==frame_resolution;
wire generation_ok=!SESSION_GUARD || incoming_token[31:16]==generation;
// 20261019 timing: every header comparison is registered once the header is
// complete (first payload byte). The end-of-packet decision then combines
// only these flags with the CRC compare. active_token, expected_sequence,
// frame_* and generation cannot change while a packet is being received.
reg hdr_gen_ok_q, hdr_tok_eq_q, hdr_seq0_q, hdr_seq_exp_q, hdr_seq_prev_q;
reg hdr_frame_eq_q, hdr_top_eq_q, hdr_res_valid_q, hdr_res_same_q;
always @(posedge clk) begin
    if (rx_valid && byte_index == HEADER_BYTES + 1) begin
        hdr_gen_ok_q   <= generation_ok;
        hdr_tok_eq_q   <= incoming_token == active_token;
        hdr_seq0_q     <= incoming_sequence == 16'd0;
        hdr_seq_exp_q  <= incoming_sequence == expected_sequence;
        hdr_seq_prev_q <= incoming_sequence == expected_sequence - 16'd1;
        hdr_frame_eq_q <= incoming_frame[1:0] == frame_index;
        hdr_top_eq_q   <= incoming_top_down == frame_top_down;
        hdr_res_valid_q<= resolution_valid;
        hdr_res_same_q <= resolution_same;
    end
end

assign pixel_valid = (state == ST_SEND);
assign pixel_rgb = {packet_rg_out, packet_b_out[B_WIDTH-1 -: 8]};
assign pixel_tag = UI_TAG ? packet_b_out[7:0] : 8'd0;

// Keep the RAM ports in a reset-free synchronous process so TD maps them to
// BRAM9K instead of thousands of resettable flip-flops.
always @(posedge clk) begin
    if ((state == ST_RX) && rx_valid &&
        (byte_index >= HEADER_BYTES) && (byte_index < CRC_OFFSET) &&
        (byte_phase == LAST_PHASE)) begin
        packet_rg[write_pixel_index] <= {red_byte,green_byte};
        packet_b[write_pixel_index] <= UI_TAG ? {blue_byte,rx_data} : rx_data;
    end
    if (state == ST_FETCH) begin
        packet_rg_out <= packet_rg[read_pixel_index];
        packet_b_out <= packet_b[read_pixel_index];
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= ST_IDLE;
        rx_valid_d <= 1'b0;
        byte_index <= 10'd0;
        write_pixel_index <= 8'd0;
        byte_phase <= 2'd0;
        red_byte <= 8'd0;
        green_byte <= 8'd0;
        blue_byte <= 8'd0;
        incoming_frame <= 8'd0;
        incoming_sequence <= 16'd0;
        incoming_top_down <= 1'b0;
        header_ok <= 1'b0;
        crc_running <= 16'hffff;
        crc_received <= 16'd0;
        active_frame <= 1'b0;
        expected_sequence <= 16'd0;
        read_pixel_index <= 8'd0;
        draining_last_packet <= 1'b0;
        frame_index <= 2'd0;
        frame_top_down <= 1'b0;
        frame_resolution <= 32'h028001e0;
        incoming_resolution <= 32'h028001e0;
        frame_start <= 1'b0;
        frame_complete <= 1'b0;
        frame_abort <= 1'b0;
        good_packets <= 16'd0;
        bad_packets <= 16'd0;
        incoming_token <= 32'd0;
        active_token <= 32'd0;
        have_previous <= 1'b0;
        packet_done <= 1'b0;
        packet_duplicate <= 1'b0;
        packet_token <= 32'd0;
        packet_sequence <= 16'd0;
    end else begin
        rx_valid_d <= rx_valid;
        frame_start <= 1'b0;
        frame_complete <= 1'b0;
        frame_abort <= 1'b0;
        packet_done <= 1'b0;
        packet_duplicate <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (rx_valid && !rx_valid_d) begin
                    state <= ST_RX;
                    byte_index <= 10'd1;
                    write_pixel_index <= 8'd0;
                    byte_phase <= 2'd0;
                    header_ok <= (rx_length == PACKET_BYTES) &&
                                 (rx_data == "I");
                    crc_running <= crc16_byte(16'hffff, rx_data);
                end
            end

            ST_RX: begin
                if (rx_valid) begin
                    if (byte_index < PACKET_BYTES)
                        byte_index <= byte_index + 10'd1;
                    else
                        header_ok <= 1'b0;

                    if (byte_index < CRC_OFFSET)
                        crc_running <= crc16_byte(crc_running, rx_data);

                    case (byte_index)
                        10'd1: header_ok <= header_ok && (rx_data == "M");
                        10'd2: header_ok <= header_ok && (rx_data == "G");
                        10'd3: header_ok <= header_ok && (rx_data == (RESOLUTION ? "4" : (UI_TAG ? "3" : (RELIABLE ? "2" : "F"))));
                        10'd4: begin
                            incoming_frame <= rx_data;
                            header_ok <= header_ok && (rx_data < 8'd4);
                        end
                        10'd5: incoming_sequence[7:0] <= rx_data;
                        10'd6: incoming_sequence[15:8] <= rx_data;
                        10'd7: begin
                            incoming_top_down <= rx_data[0];
                            header_ok <= header_ok && (rx_data[7:1] == 7'd0);
                        end
                        CRC_OFFSET: crc_received[15:8] <= rx_data;
                        CRC_OFFSET+1: crc_received[7:0] <= rx_data;
                        default: begin
                            if (RELIABLE && byte_index == 8) incoming_token[7:0] <= rx_data;
                            else if (RELIABLE && byte_index == 9) incoming_token[15:8] <= rx_data;
                            else if (RELIABLE && byte_index == 10) incoming_token[23:16] <= rx_data;
                            else if (RELIABLE && byte_index == 11) incoming_token[31:24] <= rx_data;
                            else if (RESOLUTION && byte_index == 12) incoming_resolution[23:16] <= rx_data;
                            else if (RESOLUTION && byte_index == 13) incoming_resolution[31:24] <= rx_data;
                            else if (RESOLUTION && byte_index == 14) incoming_resolution[7:0] <= rx_data;
                            else if (RESOLUTION && byte_index == 15) incoming_resolution[15:8] <= rx_data;
                            else if ((byte_index >= HEADER_BYTES) &&
                                (byte_index < CRC_OFFSET)) begin
                                case (byte_phase)
                                    2'd0: begin
                                        red_byte <= rx_data;
                                        byte_phase <= 2'd1;
                                    end
                                    2'd1: begin
                                        green_byte <= rx_data;
                                        byte_phase <= 2'd2;
                                    end
                                    2'd2: begin
                                        if(UI_TAG) begin blue_byte<=rx_data;byte_phase<=2'd3;end
                                        else begin write_pixel_index<=write_pixel_index+8'd1;byte_phase<=2'd0;end
                                    end
                                    default: begin
                                        write_pixel_index <= write_pixel_index + 8'd1;
                                        byte_phase <= 2'd0;
                                    end
                                endcase
                            end
                        end
                    endcase
                end else if (rx_valid_d) begin
                    if (RELIABLE && have_previous &&
                        byte_index == PACKET_BYTES && header_ok && hdr_gen_ok_q &&
                        crc_running == crc_received && hdr_tok_eq_q &&
                        hdr_seq_prev_q && hdr_frame_eq_q &&
                        hdr_res_valid_q && hdr_res_same_q && hdr_top_eq_q) begin
                        // A lost ACK may replay a packet. Re-ACK it without
                        // sending its pixels to SDRAM twice.
                        packet_done <= 1'b1;
                        packet_duplicate <= 1'b1;
                        packet_token <= active_token;
                        packet_sequence <= incoming_sequence;
                        state <= ST_IDLE;
                    end else if ((byte_index == PACKET_BYTES) && header_ok && hdr_gen_ok_q &&
                        hdr_res_valid_q &&
                        (crc_running == crc_received) &&
                        ((hdr_seq0_q &&
                          (!RELIABLE || !have_previous || !hdr_tok_eq_q)) ||
                         (active_frame &&
                          (!RELIABLE || hdr_tok_eq_q) &&
                          hdr_seq_exp_q && hdr_frame_eq_q &&
                          hdr_res_same_q && hdr_top_eq_q))) begin
                        if (hdr_seq0_q) begin
                            // A new SOF replaces any unfinished old frame.
                            if (active_frame)
                                frame_abort <= 1'b1;
                            active_frame <= 1'b1;
                            frame_index <= incoming_frame[1:0];
                            frame_top_down <= incoming_top_down;
                            frame_resolution <= RESOLUTION ? incoming_resolution : 32'h028001e0;
                            frame_start <= 1'b1;
                            active_token <= incoming_token;
                            have_previous <= 1'b0;
                        end
                        packet_token <= incoming_token;
                        packet_sequence <= incoming_sequence;
                        expected_sequence <= incoming_sequence + 16'd1;
                        draining_last_packet <=
                            (incoming_sequence == LAST_PACKET);
                        read_pixel_index <= 8'd0;
                        good_packets <= good_packets + 16'd1;
                        state <= ST_FETCH;
                    end else begin
                        bad_packets <= bad_packets + 16'd1;
                        if (!RELIABLE) begin
                            active_frame <= 1'b0;
                            frame_abort <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end
                end
            end

            ST_FETCH: begin
                if (rx_valid && !RELIABLE) begin
                    // The sender must leave time to drain one verified packet.
                    // Abort rather than overwrite BRAM backing a visible frame.
                    state <= ST_DROP;
                    active_frame <= 1'b0;
                    frame_abort <= 1'b1;
                    bad_packets <= bad_packets + 16'd1;
                end else begin
                    state <= ST_SEND;
                end
            end

            ST_SEND: begin
                if (rx_valid && !RELIABLE) begin
                    state <= ST_DROP;
                    active_frame <= 1'b0;
                    frame_abort <= 1'b1;
                    bad_packets <= bad_packets + 16'd1;
                end else if (pixel_ready) begin
                    if (read_pixel_index == 8'd255) begin
                        state <= ST_IDLE;
                        packet_done <= 1'b1;
                        have_previous <= 1'b1;
                        if (draining_last_packet) begin
                            frame_complete <= 1'b1;
                            active_frame <= 1'b0;
                        end
                    end else begin
                        read_pixel_index <= read_pixel_index + 8'd1;
                        state <= ST_FETCH;
                    end
                end
            end

            ST_DROP: begin
                if (!rx_valid)
                    state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
