`timescale 1ns/1ps

module tb_image_packet_rx;
    reg clk = 1'b0;
    always #4 clk = ~clk;
    reg rst = 1'b1;
    reg rx_valid = 1'b0;
    reg [7:0] rx_data = 8'd0;
    reg [15:0] rx_length = 16'd0;
    reg pixel_ready = 1'b1;
    wire pixel_valid;
    wire [23:0] pixel_rgb;
    wire [1:0] frame_index;
    wire frame_top_down, frame_start, frame_complete, frame_abort;
    wire [15:0] good_packets, bad_packets;

    image_packet_rx #(.FRAME_PACKETS(4)) dut (
        .clk(clk), .rst(rst), .rx_valid(rx_valid), .rx_data(rx_data),
        .rx_length(rx_length), .pixel_ready(pixel_ready),
        .pixel_valid(pixel_valid), .pixel_rgb(pixel_rgb),
        .frame_index(frame_index), .frame_top_down(frame_top_down),
        .frame_start(frame_start), .frame_complete(frame_complete),
        .frame_abort(frame_abort), .good_packets(good_packets),
        .bad_packets(bad_packets), .packet_done(), .packet_duplicate(),
        .packet_token(), .packet_sequence()
    );

    function [15:0] crc16_byte;
        input [15:0] old_crc;
        input [7:0] value;
        reg [15:0] c;
        integer j;
        begin
            c = old_crc ^ {value,8'h00};
            for (j=0;j<8;j=j+1)
                c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
            crc16_byte = c;
        end
    endfunction

    integer cycle_count = 0;
    integer expected_pixel = 0;
    integer starts = 0;
    integer completions = 0;
    integer aborts = 0;
    reg [23:0] expected_rgb;
    always @(posedge clk) begin
        if (!rst) begin
            cycle_count = cycle_count + 1;
            pixel_ready <= (cycle_count[2:0] != 3'b111);
            if (frame_start) begin
                starts = starts + 1;
                expected_pixel = 0;
            end
            if (pixel_valid && pixel_ready) begin
                expected_rgb = {6'd0, frame_index,
                                expected_pixel[15:8],
                                expected_pixel[7:0]};
                if (pixel_rgb !== expected_rgb) begin
                    $display("FAIL pixel frame=%0d pos=%0d got=%h want=%h",
                             frame_index, expected_pixel, pixel_rgb,
                             expected_rgb);
                    $fatal(1);
                end
                expected_pixel = expected_pixel + 1;
            end
            if (frame_complete) begin
                completions = completions + 1;
                if (expected_pixel != 1024) begin
                    $display("FAIL premature completion at %0d pixels",
                             expected_pixel);
                    $fatal(1);
                end
            end
            if (frame_abort) aborts = aborts + 1;
        end
    end

    task send_packet;
        input [7:0] frame_id;
        input [15:0] seq_number;
        input integer bad_crc;
        input integer bad_length;
        reg [15:0] c;
        reg [7:0] b;
        integer k, p, ch;
        begin
            c = 16'hffff;
            for (k=0;k<778;k=k+1) begin
                case (k)
                    0: b = "I";
                    1: b = "M";
                    2: b = "G";
                    3: b = "F";
                    4: b = frame_id;
                    5: b = seq_number[7:0];
                    6: b = seq_number[15:8];
                    7: b = 8'd0;
                    776: b = c[15:8] ^ (bad_crc ? 8'h01 : 8'h00);
                    777: b = c[7:0];
                    default: begin
                        p = (k-8)/3;
                        ch = (k-8)%3;
                        case (ch)
                            0: b = frame_id;
                            1: b = seq_number[7:0];
                            default: b = p[7:0];
                        endcase
                    end
                endcase
                @(negedge clk);
                rx_valid = 1'b1;
                rx_data = b;
                rx_length = bad_length ? 16'd777 : 16'd778;
                if (k<776) c = crc16_byte(c,b);
            end
            @(negedge clk);
            rx_valid = 1'b0;
            rx_data = 8'd0;
            repeat (700) @(negedge clk);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst = 1'b0;
        // Two good packets, then a corrupt third one: no frame commit.
        send_packet(8'd0,16'd0,0,0);
        send_packet(8'd0,16'd1,0,0);
        send_packet(8'd0,16'd2,1,0);
        // A missing sequence must also abort the incomplete replacement.
        send_packet(8'd1,16'd0,0,0);
        send_packet(8'd1,16'd2,0,0);
        // A complete replacement frame reaches frame_complete exactly once.
        send_packet(8'd2,16'd0,0,0);
        send_packet(8'd2,16'd1,0,0);
        send_packet(8'd2,16'd2,0,0);
        send_packet(8'd2,16'd3,0,0);
        send_packet(8'd3,16'd0,0,1);
        if (good_packets !== 16'd7 || bad_packets !== 16'd3 ||
            starts != 3 || completions != 1 || aborts != 3) begin
            $display("FAIL good=%0d bad=%0d starts=%0d complete=%0d abort=%0d",
                     good_packets,bad_packets,starts,completions,aborts);
            $fatal(1);
        end
        $display("PASS image_packet_rx: valid, CRC, missing, length, frame commit");
        $finish;
    end
endmodule
