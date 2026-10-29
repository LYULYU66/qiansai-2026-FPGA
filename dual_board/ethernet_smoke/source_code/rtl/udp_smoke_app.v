`timescale 1ns / 1ps

// Fixed-size, self-checking UDP heartbeat used only for the two-board link test.
// Payload: 'D' 'B' 'L' 'K', board ID, sequence LSB, sequence MSB, XOR.
module udp_smoke_app #(
    parameter [7:0] BOARD_ID = 8'hA1,
    parameter [7:0] PEER_ID = 8'hB2,
    parameter integer PERIOD_CYCLES = 1_250_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        send_enable,
    input  wire        rx_valid,
    input  wire [7:0]  rx_data,
    input  wire [15:0] rx_length,
    input  wire        tx_ready,
    input  wire        tx_ack,
    output wire        tx_request,
    output wire        tx_valid,
    output reg  [7:0]  tx_data,
    output wire [15:0] tx_length,
    output reg  [31:0] tx_packets,
    output reg  [31:0] rx_packets,
    output reg  [31:0] rx_missing,
    output reg  [31:0] rx_bad
);

localparam [1:0] TX_IDLE = 2'd0, TX_REQ = 2'd1, TX_BYTES = 2'd2;
reg [1:0] tx_state;
reg [2:0] tx_index;
reg [15:0] tx_sequence;
reg [31:0] period_count;
reg pending;

assign tx_request = (tx_state == TX_REQ);
assign tx_valid = (tx_state == TX_BYTES);
assign tx_length = 16'd8;

always @* begin
    case (tx_index)
        3'd0: tx_data = 8'h44;
        3'd1: tx_data = 8'h42;
        3'd2: tx_data = 8'h4c;
        3'd3: tx_data = 8'h4b;
        3'd4: tx_data = BOARD_ID;
        3'd5: tx_data = tx_sequence[7:0];
        3'd6: tx_data = tx_sequence[15:8];
        default: tx_data = 8'h01 ^ BOARD_ID ^
                           tx_sequence[7:0] ^ tx_sequence[15:8];
    endcase
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        tx_state <= TX_IDLE;
        tx_index <= 3'd0;
        tx_sequence <= 16'd0;
        period_count <= 32'd0;
        pending <= 1'b0;
        tx_packets <= 32'd0;
    end else begin
        if (!send_enable)
            pending <= 1'b0;
        if (period_count == PERIOD_CYCLES - 1) begin
            period_count <= 32'd0;
            if (send_enable)
                pending <= 1'b1;
        end else begin
            period_count <= period_count + 32'd1;
        end

        case (tx_state)
            TX_IDLE: if (pending && send_enable && tx_ready) begin
                pending <= 1'b0;
                tx_state <= TX_REQ;
            end
            TX_REQ: if (tx_ack) begin
                tx_index <= 3'd0;
                tx_state <= TX_BYTES;
            end
            TX_BYTES: if (tx_index == 3'd7) begin
                tx_state <= TX_IDLE;
                tx_sequence <= tx_sequence + 16'd1;
                tx_packets <= tx_packets + 32'd1;
            end else begin
                tx_index <= tx_index + 3'd1;
            end
            default: tx_state <= TX_IDLE;
        endcase
    end
end

reg rx_valid_d;
reg [3:0] rx_index;
reg [15:0] rx_length_latched;
reg [7:0] rx_xor;
reg rx_header_ok;
reg [15:0] rx_sequence;
reg [15:0] last_sequence;
reg have_sequence;
wire [15:0] rx_delta = rx_sequence - last_sequence;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_valid_d <= 1'b0;
        rx_index <= 4'd0;
        rx_length_latched <= 16'd0;
        rx_xor <= 8'd0;
        rx_header_ok <= 1'b0;
        rx_sequence <= 16'd0;
        last_sequence <= 16'd0;
        have_sequence <= 1'b0;
        rx_packets <= 32'd0;
        rx_missing <= 32'd0;
        rx_bad <= 32'd0;
    end else begin
        rx_valid_d <= rx_valid;
        if (rx_valid) begin
            if (!rx_valid_d) begin
                rx_index <= 4'd1;
                rx_length_latched <= rx_length;
                rx_header_ok <= (rx_data == 8'h44);
                rx_xor <= rx_data;
            end else begin
                if (rx_index != 4'hf)
                    rx_index <= rx_index + 4'd1;
                if (rx_index != 4'd7)
                    rx_xor <= rx_xor ^ rx_data;
                case (rx_index)
                    4'd1: rx_header_ok <= rx_header_ok && (rx_data == 8'h42);
                    4'd2: rx_header_ok <= rx_header_ok && (rx_data == 8'h4c);
                    4'd3: rx_header_ok <= rx_header_ok && (rx_data == 8'h4b);
                    4'd4: rx_header_ok <= rx_header_ok && (rx_data == PEER_ID);
                    4'd5: rx_sequence[7:0] <= rx_data;
                    4'd6: rx_sequence[15:8] <= rx_data;
                    4'd7: rx_header_ok <= rx_header_ok && (rx_data == rx_xor);
                    default: ;
                endcase
            end
        end else if (rx_valid_d) begin
            if ((rx_index == 4'd8) &&
                (rx_length_latched == 16'd8) && rx_header_ok) begin
                if (!have_sequence ||
                    ((rx_delta != 16'd0) && !rx_delta[15])) begin
                    rx_packets <= rx_packets + 32'd1;
                    if (have_sequence)
                        rx_missing <= rx_missing + {16'd0, rx_delta - 16'd1};
                    last_sequence <= rx_sequence;
                    have_sequence <= 1'b1;
                end else begin
                    // Duplicate or stale/out-of-order packet, not a huge loss.
                    rx_bad <= rx_bad + 32'd1;
                end
            end else begin
                rx_bad <= rx_bad + 32'd1;
            end
            rx_index <= 4'd0;
        end
    end
end

endmodule
