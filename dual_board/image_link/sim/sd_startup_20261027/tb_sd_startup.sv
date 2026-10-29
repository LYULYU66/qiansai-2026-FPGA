`timescale 1ns/1ps
// Exercises the real SD top/command/sector/SPI RTL through card pins.
// The card's power/idle state survives a controller reset, as on the board.
module tb_sd_startup;
reg clk=0, rst=1, abort_io=0, read_req=0;
always #10 clk=~clk;
wire cs,sclk,mosi,init_done,data_valid,read_end;
wire [7:0] read_data;
reg miso=1;
integer scenario=0, cycles=0, ready_cycle=0;
sd_card_top #(.SPI_LOW_SPEED_DIV(2),.SPI_HIGH_SPEED_DIV(0)
`ifndef LEGACY
    ,.POWERUP_WAIT_CYCLES(80),.INIT_TIMEOUT_CYCLES(20000)
`endif
) dut(.clk(clk),.rst(rst),.io_abort(abort_io),.SD_nCS(cs),.SD_DCLK(sclk),
    .SD_MOSI(mosi),.SD_MISO(miso),.sd_init_done(init_done),
    .sd_sec_read(read_req),.sd_sec_read_addr(32'd17),.sd_sec_read_data(read_data),
    .sd_sec_read_data_valid(data_valid),.sd_sec_read_end(read_end),
    .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
    .sd_sec_write_data_req(),.sd_sec_write_end());

reg [7:0] reply[0:2047];
integer qr=0,qw=0,bits=0,cmd_bytes=0,cmd_no=0;
integer cmd0_count=0,cmd16_count=0,acmd_count=0,read_count=0;
integer i, received=0, checked=0, saved_cmd0;
reg [7:0] in_byte=0,out_byte=8'hff;
reg [31:0] argument=0;
reg card_ready=0,app_prefix=0,injected=0,block_length_ok=0;
reg check_read=0;

task push(input [7:0] b); begin reply[qw]=b; qw=qw+1; end endtask
task execute_command;
begin
    if (scenario==4 && cycles<65000) begin
        // Card power is late: all commands initially receive FF forever.
    end else begin
        push(8'hff); push(8'hff);
        case(cmd_no)
        0: begin
            cmd0_count=cmd0_count+1; card_ready=0; app_prefix=0;
            acmd_count=0; block_length_ok=0; push(8'h01);
        end
        8: begin
            if(argument!==32'h1aa) $fatal(1,"CMD8 argument corrupted: %h",argument);
            push(8'h01);push(0);push(0);push(1);push(8'haa);
        end
        55: begin app_prefix=1; push(card_ready ? 8'h00 : 8'h01); end
        41: begin
            if(!app_prefix) $fatal(1,"ACMD41 missing CMD55");
            app_prefix=0;acmd_count=acmd_count+1;
            if(acmd_count>=3) card_ready=1;
            if(scenario==2 && card_ready && !injected) begin
                // Card accepted ACMD41, but host sees a stale/corrupt idle R1.
                push(8'h01);injected=1;
            end else push(card_ready ? 8'h00 : 8'h01);
        end
        16: begin
            if(!card_ready || argument!==512) $fatal(1,"bad CMD16");
            cmd16_count=cmd16_count+1;
            // Delay response: upstream must not issue the first read yet.
            repeat(40) push(8'hff);
            if(scenario==3 && !injected) begin push(8'h04);injected=1; end
            else begin push(8'h00);block_length_ok=1; end
        end
        17: begin
            if(!card_ready || !block_length_ok || argument!==17)
                $fatal(1,"read before card init/incorrect sector");
            read_count=read_count+1;push(0);push(8'hff);push(8'hfe);
            for(i=0;i<512;i=i+1) push((i ^ (i>>8) ^ 8'ha5) & 255);
            push(8'h12);push(8'h34);
        end
        default: $fatal(1,"unexpected/truncated SPI command %0d",cmd_no);
        endcase
    end
end
endtask

// Mode 3 card: drive on falling edge, sample MOSI on rising edge.
always @(posedge cs) begin
    bits=0;cmd_bytes=0;qr=0;qw=0;in_byte=0;out_byte=8'hff;miso=1;
end
always @(negedge sclk) if(!cs) begin
    miso=(scenario==1 && cmd_bytes!=0) ? 1'b0 : out_byte[7];
    out_byte={out_byte[6:0],1'b1};
end
always @(posedge sclk) if(!cs) begin
    in_byte={in_byte[6:0],mosi};bits=bits+1;
    if(bits==8) begin
        bits=0;
        if(cmd_bytes==0 && in_byte[7:6]==2'b01) begin
            cmd_no=in_byte[5:0];cmd_bytes=1;argument=0;
        end else if(cmd_bytes!=0) begin
            if(cmd_bytes<=4) argument={argument[23:0],in_byte};
            if(cmd_bytes==5) begin cmd_bytes=0;execute_command(); end
            else cmd_bytes=cmd_bytes+1;
        end
        if(qr<qw) begin out_byte=reply[qr];qr=qr+1;end
        else out_byte=8'hff;
    end
end

always @(posedge clk) begin
    cycles=cycles+1;
    if(!rst && init_done && dut.sd_card_sec_read_write_m0.state==18)
        $fatal(1,"sd_init_done asserted before CMD16 completed (first read can be lost)");
    if(check_read && data_valid) begin
        if(received>=512 || read_data!==((received ^ (received>>8) ^ 8'ha5) & 8'hff))
            $fatal(1,"sector byte %0d mismatch %h",received,read_data);
        received=received+1;
    end
    if(cycles>170000) $fatal(1,"startup stuck case=%0d CMD0=%0d CMD16=%0d state=%0d",
        scenario,cmd0_count,cmd16_count,dut.sd_card_sec_read_write_m0.state);
end
task read_sector;
begin
    @(negedge clk);received=0;check_read=1;read_req=1;
    @(negedge clk);read_req=0;
    wait(read_end);@(negedge clk);
    if(received!=512) $fatal(1,"first sector request lost/count=%0d",received);
    check_read=0;checked=checked+1;
end
endtask

initial begin
    if(!$value$plusargs("CASE=%d",scenario)) scenario=0;
    repeat(5) @(negedge clk);rst=0;
    wait(init_done);ready_cycle=cycles;
    read_sector();
    if(scenario==2 && (!injected || cmd0_count<2)) $fatal(1,"watchdog did not reinitialize card");
    if(scenario==3 && (!injected || cmd0_count<2)) $fatal(1,"CMD16 failure did not restart at CMD0");
    if(scenario==4 && ready_cycle<65000) $fatal(1,"initialized unpowered card");
    saved_cmd0=cmd0_count;
    // Normal idle/backpressure lasts longer than the init watchdog period.
    repeat(22000) @(negedge clk);
    if(!init_done || cmd0_count!=saved_cmd0) $fatal(1,"watchdog disturbed initialized card");
    // Abort a real in-flight sector, then read it again without CMD0/re-init.
    read_req=1;@(negedge clk);read_req=0;
    wait(data_valid);repeat(8)@(negedge clk);abort_io=1;
    repeat(8)@(negedge clk);abort_io=0;
    repeat(1200)@(negedge clk);
    if(!init_done || cmd0_count!=saved_cmd0) $fatal(1,"io_abort restarted card");
    read_sector();
    if(scenario==5) begin
        // Restart the FPGA reader mid-sector while the card remains powered.
        read_req=1;@(negedge clk);read_req=0;wait(data_valid);
        @(negedge clk);rst=1;repeat(7)@(negedge clk);rst=0;
        wait(init_done);read_sector();
        if(cmd0_count<=saved_cmd0) $fatal(1,"warm restart skipped CMD0");
    end
    $display("PASS SD pins case=%0d ready_cycle=%0d CMD0=%0d sectors_checked=%0d",scenario,ready_cycle,cmd0_count,checked);
    $finish;
end
endmodule
