`timescale 1ns/1ps

// Byte-for-byte TX/RX integration test. The UDP stack itself is not modeled;
// its request/ack and contiguous receive payload are represented directly.
module tb_image_link_loop;
    parameter integer FRAME_PACKETS = 4;
    localparam integer FRAME_PIXELS = FRAME_PACKETS * 256;
    reg clk = 1'b0;
    always #4 clk = ~clk;
    reg rst = 1'b1;
    reg udp_ack = 1'b0;
    wire udp_request, udp_valid;
    wire [7:0] udp_data;
    wire [15:0] udp_length;
    wire source_ready;
    reg [18:0] source_count = 19'd0;
    wire source_valid = (source_count < FRAME_PIXELS);
    wire [23:0] source_rgb = {5'd0,source_count[18:16],
                              source_count[15:8],source_count[7:0]};
    wire frame_sent;
    wire [15:0] packets_sent;
    reg pixel_ready = 1'b1;
    wire pixel_valid;
    wire [23:0] pixel_rgb;
    wire [1:0] frame_index;
    wire frame_top_down, frame_start, frame_complete, frame_abort;
    wire [15:0] good_packets, bad_packets;

    image_packet_tx #(.FRAME_PACKETS(FRAME_PACKETS), .INTER_PACKET_CYCLES(700)) tx (
        .clk(clk), .rst(rst), .source_valid(source_valid),
        .source_ready(source_ready), .source_rgb(source_rgb),
        .source_frame_start(source_count == 19'd0),
        .source_frame_index(2'd2), .source_top_down(1'b1),
        .udp_ready(1'b1), .udp_ack(udp_ack),
        .udp_request(udp_request), .udp_valid(udp_valid),
        .udp_data(udp_data), .udp_length(udp_length),
        .frame_sent(frame_sent), .packets_sent(packets_sent),
        .receipt_valid(1'b0), .receipt_token(32'd0), .receipt_sequence(16'd0),
        .transfer_token(), .packet_sequence(), .frame_token(32'd0)
    );
    image_packet_rx #(.FRAME_PACKETS(FRAME_PACKETS)) rx (
        .clk(clk), .rst(rst), .rx_valid(udp_valid),
        .rx_data(udp_data), .rx_length(udp_length),
        .pixel_ready(pixel_ready), .pixel_valid(pixel_valid),
        .pixel_rgb(pixel_rgb), .frame_index(frame_index),
        .frame_top_down(frame_top_down), .frame_start(frame_start),
        .frame_complete(frame_complete), .frame_abort(frame_abort),
        .good_packets(good_packets), .bad_packets(bad_packets),
        .packet_done(), .packet_duplicate(), .packet_token(), .packet_sequence()
    );

    integer cycle_count = 0;
    integer received_count = 0;
    integer completed = 0;
    integer started = 0;
    always @(posedge clk) begin
        if (!rst) begin
            udp_ack <= udp_request;
            cycle_count = cycle_count + 1;
            pixel_ready <= (cycle_count[2:0] != 3'b111);
            if (source_valid && source_ready)
                source_count <= source_count + 19'd1;
            if (frame_start) begin
                started = started + 1;
                if (frame_index != 2'd2 || !frame_top_down)
                    $fatal(1,"wrong frame metadata");
            end
            if (pixel_valid && pixel_ready) begin
                if (pixel_rgb !== {5'd0,received_count[18:16],
                                    received_count[15:8],received_count[7:0]}) begin
                    $display("FAIL loop pixel %0d got=%h",received_count,pixel_rgb);
                    $fatal(1);
                end
                received_count = received_count + 1;
            end
            if (frame_abort) $fatal(1,"unexpected frame abort");
            if (frame_complete) begin
                completed = completed + 1;
                if (received_count != FRAME_PIXELS) $fatal(1,"early frame complete");
            end
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (FRAME_PACKETS * 2000 + 4000) @(negedge clk);
        if (started != 1 || completed != 1 || received_count != FRAME_PIXELS ||
            good_packets !== FRAME_PACKETS || bad_packets !== 16'd0 ||
            packets_sent !== FRAME_PACKETS) begin
            $display("FAIL starts=%0d done=%0d pixels=%0d good=%0d bad=%0d tx=%0d",
                     started,completed,received_count,good_packets,bad_packets,packets_sent);
            $fatal(1);
        end
        $display("PASS image link TX/RX: %0d packets, %0d RGB pixels, metadata, CRC",
                 FRAME_PACKETS,FRAME_PIXELS);
        $finish;
    end
endmodule
