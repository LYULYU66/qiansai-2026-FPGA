`timescale 1ns / 1ps

module tb_udp_smoke_app;
reg clk = 1'b0;
reg rst = 1'b1;
reg a_send = 1'b0;
reg b_send = 1'b0;
always #4 clk = ~clk;

wire a_req, a_valid;
wire [7:0] a_data;
wire [15:0] a_len;
wire [31:0] a_tx, a_rx, a_missing, a_bad;
wire b_req, b_valid;
wire [7:0] b_data;
wire [15:0] b_len;
wire [31:0] b_tx, b_rx, b_missing, b_bad;

// Suppress one complete A->B datagram after two good datagrams.
wire drop_a_packet = (a_tx == 32'd2);

udp_smoke_app #(.BOARD_ID(8'hA1), .PEER_ID(8'hB2),
                .PERIOD_CYCLES(24)) board_a (
    .clk(clk), .rst(rst), .rx_valid(b_valid), .rx_data(b_data),
    .send_enable(a_send),
    .rx_length(b_len), .tx_ready(1'b1), .tx_ack(a_req),
    .tx_request(a_req), .tx_valid(a_valid), .tx_data(a_data),
    .tx_length(a_len), .tx_packets(a_tx), .rx_packets(a_rx),
    .rx_missing(a_missing), .rx_bad(a_bad)
);

udp_smoke_app #(.BOARD_ID(8'hB2), .PEER_ID(8'hA1),
                .PERIOD_CYCLES(24)) board_b (
    .clk(clk), .rst(rst), .rx_valid(a_valid && !drop_a_packet),
    .send_enable(b_send),
    .rx_data(a_data), .rx_length(a_len), .tx_ready(1'b1),
    .tx_ack(b_req), .tx_request(b_req), .tx_valid(b_valid),
    .tx_data(b_data), .tx_length(b_len), .tx_packets(b_tx),
    .rx_packets(b_rx), .rx_missing(b_missing), .rx_bad(b_bad)
);

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (40) @(posedge clk);
    if (a_tx != 0 || b_tx != 0) begin
        $display("FAIL: sent packets before button A=%0d B=%0d", a_tx, b_tx);
        $stop;
    end
    a_send = 1'b1;
    b_send = 1'b1;
    repeat (400) @(posedge clk);
    if (a_tx < 8 || b_tx < 8) begin
        $display("FAIL: send count A=%0d B=%0d", a_tx, b_tx);
        $stop;
    end
    if (a_rx < 8 || b_rx < 7 || b_missing != 1 ||
        a_missing != 0 || a_bad != 0 || b_bad != 0) begin
        $display("FAIL: A rx=%0d miss=%0d bad=%0d; B rx=%0d miss=%0d bad=%0d",
                 a_rx, a_missing, a_bad, b_rx, b_missing, b_bad);
        $stop;
    end
    $display("PASS: A tx=%0d rx=%0d; B tx=%0d rx=%0d missing=%0d",
             a_tx, a_rx, b_tx, b_rx, b_missing);
    $finish;
end
endmodule
