`timescale 1ns/1ps

module tb_uart_audio_control;

localparam integer CLK_FREQ_HZ  = 1_000_000;
localparam integer BAUD_RATE    = 100_000;
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
localparam integer BIT_TIME_NS  = 1_000_000_000 / BAUD_RATE;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg uart_rx = 1'b1;
wire uart_tx;
wire [3:0] volume_level;
wire [1:0] brightness_level;
wire [1:0] contrast_level;
wire rx_error;
reg test_passed=0;
integer errors = 0;

always #500 clk = ~clk;

uart_audio_control #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
) dut (
    .I_clk         (clk),
    .I_rst_n       (rst_n),
    .I_uart_rx     (uart_rx),
    .O_uart_tx     (uart_tx),
    .O_volume_level(volume_level),
    .O_brightness_level(brightness_level),
    .O_contrast_level  (contrast_level),
    .O_rx_error    (rx_error)
);

task send_byte;
    input [7:0] value;
    integer bit_no;
    begin
        uart_rx = 1'b0;
        repeat (CLKS_PER_BIT) @(posedge clk);
        for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
            uart_rx = value[bit_no];
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
        uart_rx = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
    end
endtask

task expect_byte;
    input [7:0] expected;
    reg [7:0] captured;
    integer bit_no;
    begin
        @(negedge uart_tx);
        #(BIT_TIME_NS + BIT_TIME_NS/2);
        for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
            captured[bit_no] = uart_tx;
            #(BIT_TIME_NS);
        end
        if (uart_tx !== 1'b1) begin
            $display("FAIL TX stop bit for expected %02x", expected);
            errors = errors + 1;
        end
        if (captured !== expected) begin
            $display("FAIL TX byte got=%02x expected=%02x", captured, expected);
            errors = errors + 1;
        end
    end
endtask

task expect_ok_volume;
    input [7:0] digit;
    begin
        expect_byte("O");
        expect_byte("K");
        expect_byte(" ");
        expect_byte("V");
        expect_byte("O");
        expect_byte("L");
        expect_byte("=");
        expect_byte(digit);
        expect_byte(8'h0D);
        expect_byte(8'h0A);
    end
endtask

task expect_setting_value;
    input [1:0] level;
    begin
        case (level)
            2'd0: begin
                expect_byte("0"); expect_byte("2"); expect_byte("5");
            end
            2'd1: begin
                expect_byte("0"); expect_byte("5"); expect_byte("0");
            end
            2'd2: begin
                expect_byte("0"); expect_byte("7"); expect_byte("5");
            end
            default: begin
                expect_byte("1"); expect_byte("0"); expect_byte("0");
            end
        endcase
    end
endtask

task expect_ok_setting;
    input [7:0] kind;
    input [1:0] level;
    begin
        expect_byte("O");
        expect_byte("K");
        expect_byte(" ");
        if (kind == "B") begin
            expect_byte("B"); expect_byte("R"); expect_byte("I");
        end else begin
            expect_byte("C"); expect_byte("O"); expect_byte("N");
        end
        expect_byte("=");
        expect_setting_value(level);
        expect_byte(8'h0D);
        expect_byte(8'h0A);
    end
endtask

task expect_text;
    input [8*64-1:0] value;
    input integer length;
    integer k;
    begin
        for(k=length-1;k>=0;k=k-1) expect_byte(value[k*8 +: 8]);
    end
endtask

task expect_err;
    begin
        expect_byte("E"); expect_byte("R"); expect_byte("R");
        expect_byte(8'h0D); expect_byte(8'h0A);
    end
endtask

task expect_status;
    input [7:0] digit;
    input [1:0] brightness;
    input [1:0] contrast;
    begin
        expect_byte("V");
        expect_byte("O");
        expect_byte("L");
        expect_byte("=");
        expect_byte(digit);
        expect_byte(" ");
        expect_byte("B"); expect_byte("R"); expect_byte("I");
        expect_byte("=");
        expect_setting_value(brightness);
        expect_byte(" ");
        expect_byte("C"); expect_byte("O"); expect_byte("N");
        expect_byte("=");
        expect_setting_value(contrast);
        expect_byte(8'h0D);
        expect_byte(8'h0A);
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);
    if (volume_level !== 4'd8)
        $fatal(1, "default volume is not full scale: %0d", volume_level);
    if (brightness_level !== 2'd3)
        $fatal(1, "default brightness is not 100 percent: level=%0d", brightness_level);
    if (contrast_level !== 2'd0)
        $fatal(1, "default contrast is not natural 25 level: level=%0d", contrast_level);

    // Lower-case input and CRLF termination are both accepted.
    fork
        begin
            send_byte("v"); send_byte("o"); send_byte("l");
            send_byte(" "); send_byte("3");
            send_byte(8'h0D); send_byte(8'h0A);
        end
        begin
            expect_ok_volume("3");
        end
    join
    if (volume_level !== 4'd3)
        $fatal(1, "VOL 3 command failed: %0d", volume_level);

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("V"); send_byte("O"); send_byte("L");
            send_byte("+"); send_byte(8'h0A);
        end
        begin
            expect_ok_volume("4");
        end
    join
    if (volume_level !== 4'd4)
        $fatal(1, "VOL+ command failed: %0d", volume_level);

    // Zero is no longer a legal brightness setting: it must return ERR and
    // preserve the power-on BRI100 value.
    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("B"); send_byte("R"); send_byte("I");
            send_byte(" "); send_byte("0"); send_byte(8'h0A);
        end
        begin
            expect_err;
        end
    join
    if (brightness_level !== 2'd3)
        $fatal(1, "invalid BRI 0 changed brightness: level=%0d", brightness_level);

    // Exercise all four legal brightness settings. Both separators, mixed
    // case and all accepted line endings are covered across the command set.

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("b"); send_byte("r"); send_byte("i");
            send_byte("="); send_byte("2"); send_byte("5"); send_byte(8'h0D);
        end
        begin
            expect_ok_setting("B", 2'd0);
        end
    join
    if (brightness_level !== 2'd0)
        $fatal(1, "BRI 25 command failed: level=%0d", brightness_level);

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("B"); send_byte("R"); send_byte("I");
            send_byte(" "); send_byte("5"); send_byte("0"); send_byte(8'h0D);
            send_byte(8'h0A);
        end
        begin
            expect_ok_setting("B", 2'd1);
        end
    join
    if (brightness_level !== 2'd1)
        $fatal(1, "BRI 50 command failed: level=%0d", brightness_level);

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("B"); send_byte("R"); send_byte("I");
            send_byte("="); send_byte("7"); send_byte("5");
            send_byte(8'h0A);
        end
        begin
            expect_ok_setting("B", 2'd2);
        end
    join
    if (brightness_level !== 2'd2)
        $fatal(1, "BRI 75 command failed: level=%0d", brightness_level);

    // Full brightness is the fourth legal setting.
    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("B"); send_byte("R"); send_byte("I");
            send_byte(" "); send_byte("1"); send_byte("0"); send_byte("0");
            send_byte(8'h0A);
        end
        begin
            expect_ok_setting("B", 2'd3);
        end
    join
    if (brightness_level !== 2'd3)
        $fatal(1, "BRI 100 command failed: level=%0d", brightness_level);

    // Zero is also illegal for contrast and must preserve default CON25.
    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("C"); send_byte("O"); send_byte("N");
            send_byte("="); send_byte("0"); send_byte(8'h0D);
        end
        begin
            expect_err;
        end
    join
    if (contrast_level !== 2'd0)
        $fatal(1, "invalid CON 0 changed contrast: level=%0d", contrast_level);

    // Exercise all four legal contrast-enhancement settings.

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("c"); send_byte("o"); send_byte("n");
            send_byte(" "); send_byte("2"); send_byte("5"); send_byte(8'h0A);
        end
        begin
            expect_ok_setting("C", 2'd0);
        end
    join
    if (contrast_level !== 2'd0)
        $fatal(1, "CON 25 command failed: level=%0d", contrast_level);

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("C"); send_byte("O"); send_byte("N");
            send_byte("="); send_byte("5"); send_byte("0"); send_byte(8'h0D);
            send_byte(8'h0A);
        end
        begin
            expect_ok_setting("C", 2'd1);
        end
    join
    if (contrast_level !== 2'd1)
        $fatal(1, "CON 50 command failed: level=%0d", contrast_level);

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("C"); send_byte("O"); send_byte("N");
            send_byte(" "); send_byte("7"); send_byte("5");
            send_byte(8'h0A);
        end
        begin
            expect_ok_setting("C", 2'd2);
        end
    join
    if (contrast_level !== 2'd2)
        $fatal(1, "CON 75 command failed: level=%0d", contrast_level);

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("C"); send_byte("O"); send_byte("N");
            send_byte("="); send_byte("1"); send_byte("0"); send_byte("0");
            send_byte(8'h0D);
        end
        begin
            expect_ok_setting("C", 2'd3);
        end
    join
    if (contrast_level !== 2'd3)
        $fatal(1, "CON 100 command failed: level=%0d", contrast_level);

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("S"); send_byte("T"); send_byte("A");
            send_byte("T"); send_byte("U"); send_byte("S");
            send_byte(8'h0D);
        end
        begin
            expect_status("4", 2'd3, 2'd3);
        end
    join

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("M"); send_byte("U"); send_byte("T");
            send_byte("E"); send_byte(8'h0D);
        end
        begin
            expect_ok_volume("0");
        end
    join
    if (volume_level !== 4'd0)
        $fatal(1, "MUTE command failed: %0d", volume_level);

    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("V"); send_byte("O"); send_byte("L");
            send_byte(" "); send_byte("9"); send_byte(8'h0A);
        end
        begin
            expect_err;
        end
    join
    if (volume_level !== 4'd0)
        $fatal(1, "invalid command changed volume: %0d", volume_level);

    // The TEST/DIAG/DCLEAR debug commands were removed from the playback
    // build.  They must now be rejected like any other unknown command and
    // must not disturb the current settings.
    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("T"); send_byte("E"); send_byte("S"); send_byte("T");
            send_byte(" "); send_byte("1"); send_byte(8'h0A);
        end
        expect_err;
    join
    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("D"); send_byte("I"); send_byte("A"); send_byte("G"); send_byte(8'h0A);
        end
        expect_err;
    join
    repeat (20) @(posedge clk);
    fork
        begin
            send_byte("D"); send_byte("C"); send_byte("L"); send_byte("E");
            send_byte("A"); send_byte("R"); send_byte(8'h0A);
        end
        expect_err;
    join
    if (volume_level !== 4'd0)
        $fatal(1, "removed debug command changed volume: %0d", volume_level);
    if (errors != 0)
        $fatal(1, "UART audio control errors=%0d", errors);
    $display("PASS UART removed TEST/DIAG/DCLEAR commands answer ERR");
    if (rx_error !== 1'b0)
        $fatal(1, "unexpected UART receive error latch");
    $display("PASS UART parser/tx volume regression + BRI/CON 25/50/75/100 + STATUS");
    test_passed=1;
    $finish;
end

initial begin
    #70_000_000;
    $fatal(1, "timeout");
end

endmodule
