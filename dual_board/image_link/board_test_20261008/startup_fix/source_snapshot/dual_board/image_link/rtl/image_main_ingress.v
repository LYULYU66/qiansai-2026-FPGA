`timescale 1ns/1ps
// A application component: validated network pixels -> existing SDRAM writer.
// write_clk must be udp_clk, not mem_clk. writer_ack is synchronized here;
// writer_finish_toggle must be generated from write_finish in mem_clk.
module image_main_ingress #(
    parameter integer FRAME_PACKETS=1200,
    parameter integer TIMEOUT_CYCLES=250_000_000,
    parameter integer UI_TAG=0,
    parameter integer RESOLUTION=0,
    parameter integer SESSION_GUARD=0,
    parameter integer REUSE_CACHE=0
) (
    input wire clk, rst, rx_valid,
    input wire [15:0] generation,
    input wire restart_receive,
    input wire [7:0] rx_data,
    input wire [15:0] rx_length,
    input wire writer_ready, writer_ack, writer_finish_toggle,
    input wire [3:0] protected_buffers,
    output wire write_req, write_abort, write_en,
    output wire [31:0] write_data,
    output wire [1:0] write_index,
    output wire write_top_down,
    output wire [3:0] cache_valid,
    output wire [127:0] source_resolutions,
    output wire commit_toggle, fault,
    input wire udp_ready, udp_ack,
    output wire udp_request, udp_valid,
    output wire [7:0] udp_data,
    output wire [15:0] udp_length
);
wire pixel_valid, pixel_ready, frame_start, frame_complete, frame_abort, top_down;
wire [23:0] pixel_rgb;
wire [7:0] pixel_tag;
wire [1:0] frame_index;
wire [31:0] frame_resolution;
wire packet_done, receive_reset, receipt_event;
wire recovery_reset=SESSION_GUARD && restart_receive;
wire [31:0] packet_token, receipt_token;
wire [15:0] packet_sequence, receipt_sequence;
image_packet_rx #(.RELIABLE(1),.FRAME_PACKETS(FRAME_PACKETS),.UI_TAG(UI_TAG),.RESOLUTION(RESOLUTION),.SESSION_GUARD(SESSION_GUARD)) u_rx (
    .clk(clk),.rst(rst || receive_reset || recovery_reset),.rx_valid(rx_valid),.generation(generation),
    .rx_data(rx_data),.rx_length(rx_length),.pixel_ready(pixel_ready),
    .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_tag(pixel_tag),.frame_index(frame_index),
    .frame_top_down(top_down),.frame_start(frame_start),
    .frame_resolution(frame_resolution),
    .frame_complete(frame_complete),.frame_abort(frame_abort),
    .good_packets(),.bad_packets(),.packet_done(packet_done),.packet_duplicate(),
    .packet_token(packet_token),.packet_sequence(packet_sequence)
);
image_sdram_sink #(.FRAME_PACKETS(FRAME_PACKETS),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.UI_TAG(UI_TAG),.RESOLUTION(RESOLUTION),.RECOVERY(SESSION_GUARD),.REUSE_CACHE(REUSE_CACHE)) u_sink (
    .clk(clk),.rst(rst),.restart_transfer(recovery_reset),.frame_start(frame_start),.frame_complete(frame_complete),
    .frame_abort(frame_abort),.frame_index(frame_index),.frame_top_down(top_down),
    .frame_resolution(frame_resolution),
    .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_tag(pixel_tag),.pixel_ready(pixel_ready),
    .packet_done(packet_done),.packet_token(packet_token),.packet_sequence(packet_sequence),
    .writer_ready(writer_ready),.writer_ack(writer_ack),
    .writer_finish_toggle(writer_finish_toggle),.protected_buffers(protected_buffers),
    .write_req(write_req),.write_abort(write_abort),.write_en(write_en),
    .write_data(write_data),.write_index(write_index),.write_top_down(write_top_down),
    .receipt_event(receipt_event),.receipt_token(receipt_token),
    .receipt_sequence(receipt_sequence),.cache_valid(cache_valid),
    .source_resolutions(source_resolutions),
    .commit_toggle(commit_toggle),.receive_reset(receive_reset),.fault(fault)
);
image_receipt_tx u_receipt (
    .clk(clk),.rst(rst || recovery_reset),.event_valid(receipt_event),
    .event_token(receipt_token),.event_sequence(receipt_sequence),
    .udp_ready(udp_ready),.udp_ack(udp_ack),.udp_request(udp_request),
    .udp_valid(udp_valid),.udp_data(udp_data),.udp_length(udp_length)
);
endmodule
