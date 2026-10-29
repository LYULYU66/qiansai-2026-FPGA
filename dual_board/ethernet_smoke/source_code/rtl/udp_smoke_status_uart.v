`timescale 1ns / 1ps

// One ASCII line per second at 115200 8N1:
// A TX=0000 RX=0000 LOST=0000 BAD=0000
module udp_smoke_status_uart #(
    parameter integer CLK_HZ = 125_000_000,
    parameter [7:0] ROLE_CHAR = "A"
)(
    input wire clk,
    input wire rst,
    input wire [31:0] tx_packets,
    input wire [31:0] rx_packets,
    input wire [31:0] rx_missing,
    input wire [31:0] rx_bad,
    output wire uart_tx_pin
);

reg [31:0] second_count;
reg [15:0] tx_snapshot, rx_snapshot, missing_snapshot, bad_snapshot;
reg [5:0] char_index;
reg [1:0] state;
reg start;
reg [7:0] char_data;
wire busy, done, baud_tick;

localparam [1:0] WAIT_SECOND = 2'd0, LAUNCH = 2'd1, WAIT_DONE = 2'd2;

uart_baud_tick #(.CLK_FREQ_HZ(CLK_HZ), .BAUD_RATE(115_200))
baud (.clk(clk), .rst_n(!rst), .tick(baud_tick));
uart_tx tx (.clk(clk), .rst_n(!rst), .tick(baud_tick),
            .start(start), .data(char_data), .tx(uart_tx_pin),
            .busy(busy), .done(done));

function [7:0] hex_ascii;
    input [3:0] nibble;
    begin
        hex_ascii = (nibble < 4'd10) ? (8'h30 + {4'd0,nibble}) :
                                    (8'h41 + {4'd0,nibble} - 8'd10);
    end
endfunction

always @* begin
    char_data = 8'h20;
    case (char_index)
         0: char_data = ROLE_CHAR;
         2: char_data = "T";
         3: char_data = "X";
         4: char_data = "=";
         5: char_data = hex_ascii(tx_snapshot[15:12]);
         6: char_data = hex_ascii(tx_snapshot[11:8]);
         7: char_data = hex_ascii(tx_snapshot[7:4]);
         8: char_data = hex_ascii(tx_snapshot[3:0]);
        10: char_data = "R";
        11: char_data = "X";
        12: char_data = "=";
        13: char_data = hex_ascii(rx_snapshot[15:12]);
        14: char_data = hex_ascii(rx_snapshot[11:8]);
        15: char_data = hex_ascii(rx_snapshot[7:4]);
        16: char_data = hex_ascii(rx_snapshot[3:0]);
        18: char_data = "L";
        19: char_data = "O";
        20: char_data = "S";
        21: char_data = "T";
        22: char_data = "=";
        23: char_data = hex_ascii(missing_snapshot[15:12]);
        24: char_data = hex_ascii(missing_snapshot[11:8]);
        25: char_data = hex_ascii(missing_snapshot[7:4]);
        26: char_data = hex_ascii(missing_snapshot[3:0]);
        28: char_data = "B";
        29: char_data = "A";
        30: char_data = "D";
        31: char_data = "=";
        32: char_data = hex_ascii(bad_snapshot[15:12]);
        33: char_data = hex_ascii(bad_snapshot[11:8]);
        34: char_data = hex_ascii(bad_snapshot[7:4]);
        35: char_data = hex_ascii(bad_snapshot[3:0]);
        36: char_data = 8'h0d;
        37: char_data = 8'h0a;
        default: ;
    endcase
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        second_count <= 32'd0;
        tx_snapshot <= 16'd0;
        rx_snapshot <= 16'd0;
        missing_snapshot <= 16'd0;
        bad_snapshot <= 16'd0;
        char_index <= 6'd0;
        state <= WAIT_SECOND;
        start <= 1'b0;
    end else begin
        start <= 1'b0;
        if (second_count == CLK_HZ - 1)
            second_count <= 32'd0;
        else
            second_count <= second_count + 32'd1;

        case (state)
            WAIT_SECOND: if (second_count == CLK_HZ - 1) begin
                tx_snapshot <= tx_packets[15:0];
                rx_snapshot <= rx_packets[15:0];
                missing_snapshot <= rx_missing[15:0];
                bad_snapshot <= rx_bad[15:0];
                char_index <= 6'd0;
                state <= LAUNCH;
            end
            LAUNCH: if (!busy) begin
                start <= 1'b1;
                state <= WAIT_DONE;
            end
            WAIT_DONE: if (done) begin
                if (char_index == 6'd37)
                    state <= WAIT_SECOND;
                else begin
                    char_index <= char_index + 6'd1;
                    state <= LAUNCH;
                end
            end
            default: state <= WAIT_SECOND;
        endcase
    end
end

endmodule
