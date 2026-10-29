`timescale 1ns/1ps
// Native CTL4 TX/RX + native bundled-mailbox CDC + A display controller.
// The SD/video memory cores are not needed for this protocol-level regression.
module tb_page_sync;
reg clk=0,vclk=0;
always #4 clk=~clk;
always #20 vclk=~vclk;
reg rst=1,vs=0;
integer vcycles=0;
always @(negedge vclk) begin
    if(rst)begin vcycles=0;vs=0;end
    else begin vcycles=vcycles+1;vs=(vcycles%30)==0;end
end
reg manual_valid=0;
reg [7:0] manual_data=0;
reg [15:0] manual_length=14;
reg use_tx=0,tx_rst=1,tx_ready=1,tx_ack=0,drop_tx=0;
reg [7:0] tx_settings=8'hc5,tx_page=8'h81;
reg [15:0] tx_phase=16'd314;
wire tx_request,tx_valid;
wire [7:0] tx_data;
wire [15:0] tx_length;
media_control_tx #(.STAR_SYNC(1),.PAGE_SYNC(1),.UPDATE_CYCLES(80)) tx (
    .clk(clk),.rst(tx_rst),.settings(tx_settings),.star_phase(tx_phase),.page_token(tx_page),
    .udp_ready(tx_ready),.udp_ack(tx_ack),.udp_request(tx_request),
    .udp_valid(tx_valid),.udp_data(tx_data),.udp_length(tx_length)
);
always @(posedge clk)tx_ack<=!tx_rst && tx_request && !tx_ack;
wire rx_valid=use_tx ? (tx_valid && !drop_tx) : manual_valid;
wire [7:0] rx_data=use_tx ? tx_data : manual_data;
wire [15:0] rx_length=use_tx ? tx_length : manual_length;
wire update;
wire [7:0] received_settings,received_page;
wire [15:0] received_phase;
media_control_rx #(.STAR_SYNC(1),.PAGE_SYNC(1),.REBASE_CYCLES(1000)) rx (
    .clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_data(rx_data),.rx_length(rx_length),
    .update_valid(update),.settings(received_settings),.star_phase(received_phase),.page_token(received_page)
);
wire [31:0] video_snapshot;
wire video_capture;
audio_visual_cdc #(.WIDTH(32),.RESET_STATE(32'h00000038)) cdc (
    .udp_clk(clk),.video_clk(vclk),.rst(rst),.frame_vs(vs),
    .update_valid(1'b0),.publish_enable(1'b1),
    .visual_state({received_page,received_phase,received_settings}),
    .frame_state(video_snapshot),.capture_valid(video_capture)
);
reg key_next=1,key_auto=1,hazard=0;
reg [3:0] cache=15;
wire display_valid,warning_ready;
wire [1:0] image_index;
image_remote_display_control #(.CLK_FREQ(1000),.PAGE_SYNC(1)) display (
    .clk(vclk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.warning_hold(hazard),
    .cache_valid_async(cache),.remote_page_token(video_snapshot[31:24]),
    .remote_page_valid(video_capture),.display_valid(display_valid),
    .warning_ready(warning_ready),.requested_index(image_index)
);
integer accepted=0;
always @(posedge clk)if(!rst && update)accepted=accepted+1;
reg [31:0] previous_snapshot=32'h00000038;
always @(posedge vclk) begin
    #1;
    if(!rst && video_snapshot!=previous_snapshot && !vs)
        $fatal(1,"CTL4 mailbox changed outside VS");
    previous_snapshot=video_snapshot;
end
function [15:0] crc_byte(input [15:0] old,input [7:0] b);
    reg [15:0] c;integer i;
    begin
        c=old^{b,8'd0};
        for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;
        crc_byte=c;
    end
endfunction
task settle;
    begin repeat(300)@(negedge clk);end
endtask
task packet(input [31:0] seq,input [7:0] s,input [15:0] ph,input [7:0] page,input integer mode);
    reg [7:0] p[0:14];reg [15:0] crc;integer i;
    begin
        p[0]="C";p[1]="T";p[2]="L";p[3]=mode==2 ? "3" : "4";
        p[4]=seq[7:0];p[5]=seq[15:8];p[6]=seq[23:16];p[7]=seq[31:24];
        p[8]=s;p[9]=ph[7:0];p[10]=ph[15:8];p[11]=page;
        crc=16'hffff;for(i=0;i<12;i=i+1)crc=crc_byte(crc,p[i]);
        p[12]=crc[15:8];p[13]=crc[7:0]^(mode==1);p[14]=0;
        manual_length=mode==3 ? 13 : 14;
        for(i=0;i<(mode==4 ? 11 : (mode==5 ? 15 : 14));i=i+1)begin
            @(negedge clk);manual_valid=1;manual_data=p[i];
        end
        @(negedge clk);manual_valid=0;repeat(4)@(negedge clk);
        settle;
    end
endtask
task press_next;
    begin
        @(negedge vclk);key_next=0;repeat(30)@(negedge vclk);
        key_next=1;repeat(30)@(negedge vclk);
    end
endtask
task press_auto;
    begin
        @(negedge vclk);key_auto=0;repeat(30)@(negedge vclk);
        key_auto=1;repeat(30)@(negedge vclk);
    end
endtask
task reset_all;
    begin
        @(negedge clk);rst=1;key_next=1;key_auto=1;hazard=0;cache=15;
        manual_valid=0;accepted=0;
        repeat(8)@(negedge vclk);rst=0;settle;
    end
endtask
integer saved_accept;
initial begin
    reset_all;
    packet(100,8'hb4,100,8'h00,0);
    if(accepted!=1 || image_index!=0 || video_snapshot!=={8'h00,16'd100,8'hb4})
        $fatal(1,"first TF5 baseline or CTL4 atomic CDC");
    press_auto;
    if(!display.auto_play)$fatal(1,"original A autoplay control lost");
    press_next;
    if(image_index!=1)$fatal(1,"original A manual next lost");
    saved_accept=accepted;
    packet(101,8'h38,200,8'h81,1); // CRC corruption
    packet(101,8'h38,200,8'h81,2); // CTL3 sent to CTL4 receiver
    packet(101,8'h38,200,8'h81,3); // bad length
    packet(101,8'h38,200,8'h81,4); // truncated
    packet(101,8'h38,200,8'h81,5); // trailing byte
    packet(101,8'h39,200,8'h81,0); // invalid volume
    packet(101,8'h38,16'h5000,8'h81,0); // invalid phase
    if(accepted!=saved_accept || image_index!=1 || received_page!=0)
        $fatal(1,"bad CTL4 packet changed page or controls");
    packet(101,8'h38,200,8'h81,0);
    if(image_index!=2 || display.auto_play || display.remote_pending)
        $fatal(1,"first TF6 entry failed or autoplay not paused");
    press_next;
    if(image_index!=3)$fatal(1,"A cannot manually leave paired relaxation");
    packet(102,8'h38,201,8'h81,0);
    packet(102,8'h38,201,8'h81,0); // exact duplicate allowed by old RX ordering
    if(image_index!=3)$fatal(1,"repeated TF6 state dragged A back");
    saved_accept=accepted;
    packet(101,8'h38,202,8'h82,0);
    if(accepted!=saved_accept || image_index!=3)$fatal(1,"stale entry accepted");
    packet(103,8'h38,203,8'h01,0);
    if(image_index!=3)$fatal(1,"B TF5 forced A page");
    // A dropped initial entry packet is harmless: the periodic repeat carries
    // the latest epoch instead of a one-clock network event.
    packet(105,8'h38,205,8'h82,0);
    if(image_index!=2)$fatal(1,"later/repeated TF6 entry not delivered");
    repeat(1100)@(negedge vclk);
    if(image_index!=2 || display.auto_play)$fatal(1,"paired relaxation auto-advanced");

    press_next;cache=4'b1011;repeat(5)@(negedge vclk);
    packet(106,8'h38,206,8'h02,0);
    packet(107,8'h38,207,8'h83,0);
    if(image_index!=3 || !display.remote_pending)$fatal(1,"missing cache lost entry");
    hazard=1;cache=15;repeat(15)@(negedge vclk);
    if(image_index!=3 || !display.remote_pending)$fatal(1,"remote entry bypassed local hazard");
    packet(108,8'h38,208,8'h83,0);
    hazard=0;repeat(15)@(negedge vclk);
    if(image_index!=2 || display.remote_pending)$fatal(1,"queued entry not applied after hazard");
    press_next;settle;
    if(image_index!=3)$fatal(1,"queued repeat generated a second switch");
    press_auto;
    if(!display.auto_play)$fatal(1,"local explicit KEY4 cannot restore autoplay");

    reset_all;
    packet(1,8'h38,10,8'h80,0);
    if(image_index!=2)$fatal(1,"A reset while B already TF6 failed");
    press_next;
    packet(2,8'h38,11,8'h7f,0);
    if(image_index!=3)$fatal(1,"TF5 at wrap forced page");
    packet(3,8'h38,12,8'h80,0);
    if(image_index!=2)$fatal(1,"7-bit entry epoch wrap failed");
    press_next;
    saved_accept=accepted;
    packet(0,8'h38,13,8'h00,0);
    if(accepted!=saved_accept)$fatal(1,"early B reset bypassed ordering");
    repeat(1000)@(negedge clk);
    packet(0,8'h38,14,8'h00,0);
    if(image_index!=3 || received_page!=0)$fatal(1,"B reset rebase forced page");
    packet(1,8'h38,15,8'h81,0);
    if(image_index!=2)$fatal(1,"B reset subsequent TF6 entry failed");

    // TX holds one coherent CTL4 snapshot even if all input fields change
    // mid-packet; its reserved byte is included in the native CRC calculation.
    reset_all;use_tx=1;tx_ready=1;tx_rst=0;
    wait(tx_valid && tx.index==0);
    @(negedge clk);tx_ready=0;tx_settings=8'h14;tx_phase=400;tx_page=8'h82;
    wait(accepted==1);settle;
    if(tx_length!=14 || received_settings!==8'hc5 || received_phase!==16'd314 || received_page!==8'h81)
        $fatal(1,"CTL4 TX packet snapshot/CRC not atomic");
    if(video_snapshot!=={8'h81,16'd314,8'hc5} || image_index!=2)
        $fatal(1,"TX loopback snapshot not applied atomically");
    tx_ready=1;wait(accepted>=2);settle;
    if(received_settings!==8'h14 || received_phase!==16'd400 || received_page!==8'h82)
        $fatal(1,"CTL4 TX latest state not repeated");
    $display("PASS page sync: CTL4 TX/RX atomic snapshot and CRC, legacy rejection, malformed/stale/repeated packets, manual override, TF5 baseline, later TF6/recovery, cache wait, hazard priority, A autoplay pause/restore, A/B reset and epoch wrap, VS atomic CDC");
    $finish;
end
initial begin #1000000;$fatal(1,"page sync timeout");end
endmodule
