// Bidirectional UART command interface for the multimedia design.
// 115200 baud, 8 data bits, no parity, one stop bit.
//
// Commands are case-insensitive and may end in CR, LF, or CRLF:
//   VOL 0 ... VOL 8   set gain in eighths
//   VOL+ / VOL-       increase / decrease one step
//   MUTE / FULL       set zero / unity gain
//   BRI 25/50/75/100  set image brightness percentage
//   CON 25/50/75/100  set image contrast-enhancement level
//   STATUS            return volume, brightness and contrast
//   PING              link test
module uart_audio_control #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire       I_uart_rx,
    output wire       O_uart_tx,
    output reg  [3:0] O_volume_level,
    output reg  [1:0] O_brightness_level,
    output reg  [1:0] O_contrast_level,
    output wire       O_rx_error
);

localparam [2:0] RESP_OK_VOL = 3'd0;
localparam [2:0] RESP_STATUS = 3'd1;
localparam [2:0] RESP_PONG   = 3'd2;
localparam [2:0] RESP_ERR    = 3'd3;
localparam [2:0] RESP_OK_BRI = 3'd4;
localparam [2:0] RESP_OK_CON = 3'd5;

wire       baud_tick;
wire [7:0] rx_data;
wire       rx_valid;
wire       rx_framing_error;
reg        tx_start;
reg  [7:0] tx_data;
wire       tx_busy;
wire       tx_done;

reg [7:0] command_buffer [0:15];
reg [4:0] command_length;
reg       command_overlong;
reg       ignore_lf;
reg       rx_error_latched;

reg       response_active;
reg [2:0] response_kind;
reg [3:0] response_volume;
reg [1:0] response_brightness;
reg [1:0] response_contrast;
reg [4:0] response_index;
reg [4:0] response_count;
reg       response_waiting_done;

wire command_terminator = rx_valid &&
                          ((rx_data == 8'h0D) ||
                           ((rx_data == 8'h0A) && !ignore_lf));
assign O_rx_error = rx_error_latched;

uart_baud_tick #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
) u_uart_baud_tick (
    .clk  (I_clk),
    .rst_n(I_rst_n),
    .tick (baud_tick)
);

uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
) u_uart_rx (
    .clk          (I_clk),
    .rst_n        (I_rst_n),
    .rx           (I_uart_rx),
    .data         (rx_data),
    .valid        (rx_valid),
    .framing_error(rx_framing_error)
);

uart_tx u_uart_tx (
    .clk  (I_clk),
    .rst_n(I_rst_n),
    .tick (baud_tick),
    .start(tx_start),
    .data (tx_data),
    .tx   (O_uart_tx),
    .busy (tx_busy),
    .done (tx_done)
);

function [7:0] upper_ascii;
    input [7:0] value;
    begin
        if ((value >= "a") && (value <= "z"))
            upper_ascii = value - 8'd32;
        else
            upper_ascii = value;
    end
endfunction

// Fixed-width decimal representation used by replies: 025, 050, 075, 100.
function [7:0] setting_digit;
    input [1:0] level;
    input [1:0] position;
    begin
        case (level)
            2'd0: begin
                case (position)
                    2'd0: setting_digit = "0";
                    2'd1: setting_digit = "2";
                    default: setting_digit = "5";
                endcase
            end
            2'd1: begin
                case (position)
                    2'd0: setting_digit = "0";
                    2'd1: setting_digit = "5";
                    default: setting_digit = "0";
                endcase
            end
            2'd2: begin
                case (position)
                    2'd0: setting_digit = "0";
                    2'd1: setting_digit = "7";
                    default: setting_digit = "5";
                endcase
            end
            default: begin
                case (position)
                    2'd0: setting_digit = "1";
                    2'd1: setting_digit = "0";
                    default: setting_digit = "0";
                endcase
            end
        endcase
    end
endfunction

function [7:0] response_byte;
    input [2:0] kind;
    input [4:0] index;
    input [3:0] volume;
    input [1:0] brightness;
    input [1:0] contrast;
    reg [1:0] selected_setting;
    begin
        selected_setting = (kind == RESP_OK_BRI) ? brightness : contrast;
        case (kind)
            RESP_OK_VOL: begin
                case (index)
                    5'd0: response_byte = "O";
                    5'd1: response_byte = "K";
                    5'd2: response_byte = " ";
                    5'd3: response_byte = "V";
                    5'd4: response_byte = "O";
                    5'd5: response_byte = "L";
                    5'd6: response_byte = "=";
                    5'd7: response_byte = "0" + volume;
                    5'd8: response_byte = 8'h0D;
                    default: response_byte = 8'h0A;
                endcase
            end
            RESP_STATUS: begin
                case (index)
                    5'd0:  response_byte = "V";
                    5'd1:  response_byte = "O";
                    5'd2:  response_byte = "L";
                    5'd3:  response_byte = "=";
                    5'd4:  response_byte = "0" + volume;
                    5'd5:  response_byte = " ";
                    5'd6:  response_byte = "B";
                    5'd7:  response_byte = "R";
                    5'd8:  response_byte = "I";
                    5'd9:  response_byte = "=";
                    5'd10: response_byte = setting_digit(brightness, 2'd0);
                    5'd11: response_byte = setting_digit(brightness, 2'd1);
                    5'd12: response_byte = setting_digit(brightness, 2'd2);
                    5'd13: response_byte = " ";
                    5'd14: response_byte = "C";
                    5'd15: response_byte = "O";
                    5'd16: response_byte = "N";
                    5'd17: response_byte = "=";
                    5'd18: response_byte = setting_digit(contrast, 2'd0);
                    5'd19: response_byte = setting_digit(contrast, 2'd1);
                    5'd20: response_byte = setting_digit(contrast, 2'd2);
                    5'd21: response_byte = 8'h0D;
                    default: response_byte = 8'h0A;
                endcase
            end
            RESP_OK_BRI, RESP_OK_CON: begin
                case (index)
                    5'd0: response_byte = "O";
                    5'd1: response_byte = "K";
                    5'd2: response_byte = " ";
                    5'd3: response_byte = (kind == RESP_OK_BRI) ? "B" : "C";
                    5'd4: response_byte = (kind == RESP_OK_BRI) ? "R" : "O";
                    5'd5: response_byte = (kind == RESP_OK_BRI) ? "I" : "N";
                    5'd6: response_byte = "=";
                    5'd7: response_byte = setting_digit(selected_setting, 2'd0);
                    5'd8: response_byte = setting_digit(selected_setting, 2'd1);
                    5'd9: response_byte = setting_digit(selected_setting, 2'd2);
                    5'd10: response_byte = 8'h0D;
                    default: response_byte = 8'h0A;
                endcase
            end
            RESP_PONG: begin
                case (index)
                    5'd0: response_byte = "P";
                    5'd1: response_byte = "O";
                    5'd2: response_byte = "N";
                    5'd3: response_byte = "G";
                    5'd4: response_byte = 8'h0D;
                    default: response_byte = 8'h0A;
                endcase
            end
            default: begin
                case (index)
                    5'd0: response_byte = "E";
                    5'd1: response_byte = "R";
                    5'd2: response_byte = "R";
                    5'd3: response_byte = 8'h0D;
                    default: response_byte = 8'h0A;
                endcase
            end
        endcase
    end
endfunction

wire command_setting_value_valid =
    ((command_length == 5'd6) &&
     (((command_buffer[4] == "2") && (command_buffer[5] == "5")) ||
      ((command_buffer[4] == "5") && (command_buffer[5] == "0")) ||
      ((command_buffer[4] == "7") && (command_buffer[5] == "5")))) ||
    ((command_length == 5'd7) &&
     (command_buffer[4] == "1") && (command_buffer[5] == "0") &&
     (command_buffer[6] == "0"));

wire [1:0] command_setting_level =
    (command_buffer[4] == "2") ? 2'd0 :
    (command_buffer[4] == "5") ? 2'd1 :
    (command_buffer[4] == "7") ? 2'd2 : 2'd3;

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        O_volume_level       <= 4'd8;
        O_brightness_level   <= 2'd3;
        O_contrast_level     <= 2'd0;
        command_length       <= 5'd0;
        command_overlong     <= 1'b0;
        ignore_lf            <= 1'b0;
        rx_error_latched     <= 1'b0;
        response_active      <= 1'b0;
        response_kind        <= RESP_ERR;
        response_volume      <= 4'd8;
        response_brightness  <= 2'd3;
        response_contrast    <= 2'd0;
        response_index       <= 5'd0;
        response_count       <= 5'd0;
        response_waiting_done<= 1'b0;
        tx_start             <= 1'b0;
        tx_data              <= 8'd0;
    end else begin
        tx_start <= 1'b0;

        // Response sequencer follows the lesson10 busy/done handshake and
        // never changes a byte while the transmitter is busy.
        if (response_active && !response_waiting_done && !tx_busy) begin
            tx_data               <= response_byte(response_kind,
                                                   response_index,
                                                   response_volume,
                                                   response_brightness,
                                                   response_contrast);
            tx_start              <= 1'b1;
            response_waiting_done <= 1'b1;
        end else if (response_active && response_waiting_done && tx_done) begin
            response_waiting_done <= 1'b0;
            if (response_index == response_count - 5'd1) begin
                response_active <= 1'b0;
                response_index  <= 5'd0;
            end else begin
                response_index <= response_index + 5'd1;
            end
        end

        if (rx_framing_error) begin
            command_length   <= 5'd0;
            command_overlong <= 1'b0;
            ignore_lf        <= 1'b0;
            rx_error_latched <= 1'b1;
            if (!response_active) begin
                response_active       <= 1'b1;
                response_kind         <= RESP_ERR;
                response_volume       <= O_volume_level;
                response_brightness   <= O_brightness_level;
                response_contrast     <= O_contrast_level;
                response_index        <= 5'd0;
                response_count        <= 5'd5;
                response_waiting_done <= 1'b0;
            end
        end else if (rx_valid) begin
            if (rx_data == 8'h0D)
                ignore_lf <= 1'b1;
            else if (rx_data == 8'h0A)
                ignore_lf <= 1'b0;
            else
                ignore_lf <= 1'b0;

            if (command_terminator) begin
                command_length   <= 5'd0;
                command_overlong <= 1'b0;
                if (response_active) begin
                    rx_error_latched <= 1'b1;
                end else begin
                    response_active       <= 1'b1;
                    response_index        <= 5'd0;
                    response_waiting_done <= 1'b0;
                    response_volume       <= O_volume_level;
                    response_brightness   <= O_brightness_level;
                    response_contrast     <= O_contrast_level;

                    if (!command_overlong && (command_length == 5) &&
                        (command_buffer[0] == "V") &&
                        (command_buffer[1] == "O") &&
                        (command_buffer[2] == "L") &&
                        ((command_buffer[3] == " ") ||
                         (command_buffer[3] == "=")) &&
                        (command_buffer[4] >= "0") &&
                        (command_buffer[4] <= "8")) begin
                        O_volume_level  <= command_buffer[4] - "0";
                        response_volume <= command_buffer[4] - "0";
                        response_kind   <= RESP_OK_VOL;
                        response_count  <= 5'd10;
                    end else if (!command_overlong && (command_length == 4) &&
                                 (command_buffer[0] == "V") &&
                                 (command_buffer[1] == "O") &&
                                 (command_buffer[2] == "L") &&
                                 (command_buffer[3] == "+")) begin
                        if (O_volume_level < 4'd8) begin
                            O_volume_level  <= O_volume_level + 4'd1;
                            response_volume <= O_volume_level + 4'd1;
                        end
                        response_kind  <= RESP_OK_VOL;
                        response_count <= 5'd10;
                    end else if (!command_overlong && (command_length == 4) &&
                                 (command_buffer[0] == "V") &&
                                 (command_buffer[1] == "O") &&
                                 (command_buffer[2] == "L") &&
                                 (command_buffer[3] == "-")) begin
                        if (O_volume_level != 4'd0) begin
                            O_volume_level  <= O_volume_level - 4'd1;
                            response_volume <= O_volume_level - 4'd1;
                        end
                        response_kind  <= RESP_OK_VOL;
                        response_count <= 5'd10;
                    end else if (!command_overlong && (command_length == 4) &&
                                 (command_buffer[0] == "M") &&
                                 (command_buffer[1] == "U") &&
                                 (command_buffer[2] == "T") &&
                                 (command_buffer[3] == "E")) begin
                        O_volume_level  <= 4'd0;
                        response_volume <= 4'd0;
                        response_kind   <= RESP_OK_VOL;
                        response_count  <= 5'd10;
                    end else if (!command_overlong && (command_length == 4) &&
                                 (command_buffer[0] == "F") &&
                                 (command_buffer[1] == "U") &&
                                 (command_buffer[2] == "L") &&
                                 (command_buffer[3] == "L")) begin
                        O_volume_level  <= 4'd8;
                        response_volume <= 4'd8;
                        response_kind   <= RESP_OK_VOL;
                        response_count  <= 5'd10;
                    end else if (!command_overlong &&
                                 command_setting_value_valid &&
                                 (command_buffer[0] == "B") &&
                                 (command_buffer[1] == "R") &&
                                 (command_buffer[2] == "I") &&
                                 ((command_buffer[3] == " ") ||
                                  (command_buffer[3] == "="))) begin
                        O_brightness_level <= command_setting_level;
                        response_brightness <= command_setting_level;
                        response_kind  <= RESP_OK_BRI;
                        response_count <= 5'd12;
                    end else if (!command_overlong &&
                                 command_setting_value_valid &&
                                 (command_buffer[0] == "C") &&
                                 (command_buffer[1] == "O") &&
                                 (command_buffer[2] == "N") &&
                                 ((command_buffer[3] == " ") ||
                                  (command_buffer[3] == "="))) begin
                        O_contrast_level <= command_setting_level;
                        response_contrast <= command_setting_level;
                        response_kind  <= RESP_OK_CON;
                        response_count <= 5'd12;
                    end else if (!command_overlong && (command_length == 6) &&
                                 (command_buffer[0] == "S") &&
                                 (command_buffer[1] == "T") &&
                                 (command_buffer[2] == "A") &&
                                 (command_buffer[3] == "T") &&
                                 (command_buffer[4] == "U") &&
                                 (command_buffer[5] == "S")) begin
                        response_kind  <= RESP_STATUS;
                        response_count <= 5'd23;
                    end else if (!command_overlong && (command_length == 4) &&
                                 (command_buffer[0] == "P") &&
                                 (command_buffer[1] == "I") &&
                                 (command_buffer[2] == "N") &&
                                 (command_buffer[3] == "G")) begin
                        response_kind  <= RESP_PONG;
                        response_count <= 5'd6;
                    end else begin
                        response_kind  <= RESP_ERR;
                        response_count <= 5'd5;
                    end
                end
            end else if ((rx_data != 8'h0D) && (rx_data != 8'h0A)) begin
                if (command_length < 5'd16) begin
                    command_buffer[command_length] <= upper_ascii(rx_data);
                    command_length <= command_length + 5'd1;
                end else begin
                    command_overlong <= 1'b1;
                end
            end
        end
    end
end

endmodule
