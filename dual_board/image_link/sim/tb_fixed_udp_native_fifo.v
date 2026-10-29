`timescale 1ns/1ps
// Actual project TX/RX client FIFO RTL + real fixed UDP endpoints. Between the
// FIFOs a behavioral MAC relay consumes the TX client interface and provides a
// complete, FCS-free good/bad RX client frame on a distinct clock. It can either
// preserve Ethernet padding or strip it. The FIFOs themselves neither inspect
// IP length nor remove padding/FCS. The encrypted TEMAC core, preamble/FCS/PHY,
// collision/retransmission, RGMII timing and electrical link are NOT simulated.
module tb_fixed_udp_native_fifo #(parameter integer STRIP_PADDING=0);
reg source_clk=0,tx_mac_clk=0,rx_mac_clk=0,dest_clk=0;
always #4 source_clk=~source_clk;
always #4.25 tx_mac_clk=~tx_mac_clk;
always #3.75 rx_mac_clk=~rx_mac_clk;
always #4.1 dest_clk=~dest_clk;
reg rst=1,tx_request=0,tx_valid=0,forced_rx_stall=0,make_bad_frame=0;
reg [7:0] tx_data=0;
reg [15:0] tx_length=0;
wire tx_ready,tx_ack;
wire [7:0] tx_local_data,tx_mac_data,rx_local_data,rx_data;
wire tx_local_valid_n,tx_local_ready_n,tx_local_sof_n,tx_local_eof_n;
wire tx_mac_valid,tx_overflow,rx_overflow;
wire rx_local_valid_n,rx_local_sof_n,rx_local_eof_n,rx_endpoint_ready_n;
wire rx_valid;
wire [15:0] rx_length;
wire tx_rd_enable;
reg mac_tx_ack=0,mac_rx_valid=0,mac_rx_good=0,mac_rx_bad=0;
reg [7:0] mac_rx_data=0;

fixed_peer_udp #(
    .LOCAL_IP(32'hc0a80a0c),.PEER_IP(32'hc0a80a0b),
    .LOCAL_MAC(48'h02000000000c),.PEER_MAC(48'h02000000000b)
) source (
    .clk(source_clk),.rst(rst),.app_tx_request(tx_request),.app_tx_valid(tx_valid),
    .app_tx_data(tx_data),.app_tx_length(tx_length),.app_tx_ready(tx_ready),.app_tx_ack(tx_ack),
    .app_rx_valid(),.app_rx_data(),.app_rx_length(),.app_rx_port(),
    .mac_rx_valid(1'b0),.mac_rx_data(8'd0),.mac_rx_sof_n(1'b1),.mac_rx_eof_n(1'b1),.mac_rx_ready_n(),
    .mac_tx_ready_n(tx_local_ready_n),.mac_tx_valid_n(tx_local_valid_n),.mac_tx_data(tx_local_data),
    .mac_tx_sof_n(tx_local_sof_n),.mac_tx_eof_n(tx_local_eof_n));
tx_client_fifo #(.DEVICE("EG4")) tx_fifo (
    .rd_clk(tx_mac_clk),.rd_sreset(rst),.rd_enable(tx_rd_enable),.tx_data(tx_mac_data),
    .tx_data_valid(tx_mac_valid),.tx_ack(mac_tx_ack),.tx_collision(1'b0),.tx_retransmit(1'b0),.overflow(tx_overflow),
    .wr_clk(source_clk),.wr_sreset(rst),.wr_data(tx_local_data),.wr_sof_n(tx_local_sof_n),
    .wr_eof_n(tx_local_eof_n),.wr_src_rdy_n(tx_local_valid_n),.wr_dst_rdy_n(tx_local_ready_n),.wr_fifo_status());
rx_client_fifo #(.DEVICE("EG4")) rx_fifo (
    .wr_clk(rx_mac_clk),.wr_sreset(rst),.wr_enable(1'b1),.rx_data(mac_rx_data),.rx_data_valid(mac_rx_valid),
    .rx_good_frame(mac_rx_good),.rx_bad_frame(mac_rx_bad),.overflow(rx_overflow),
    .rd_clk(dest_clk),.rd_sreset(rst),.rd_data_out(rx_local_data),.rd_sof_n(rx_local_sof_n),
    .rd_eof_n(rx_local_eof_n),.rd_src_rdy_n(rx_local_valid_n),
    .rd_dst_rdy_n(rx_endpoint_ready_n || forced_rx_stall),.rx_fifo_status());
fixed_peer_udp #(
    .LOCAL_IP(32'hc0a80a0b),.PEER_IP(32'hc0a80a0c),
    .LOCAL_MAC(48'h02000000000b),.PEER_MAC(48'h02000000000c)
) receiver (
    .clk(dest_clk),.rst(rst),.app_tx_request(1'b0),.app_tx_valid(1'b0),.app_tx_data(8'd0),.app_tx_length(16'd0),
    .app_tx_ready(),.app_tx_ack(),.app_rx_valid(rx_valid),.app_rx_data(rx_data),.app_rx_length(rx_length),.app_rx_port(),
    .mac_rx_valid(!rx_local_valid_n && !forced_rx_stall),.mac_rx_data(rx_local_data),
    .mac_rx_sof_n(rx_local_sof_n),.mac_rx_eof_n(rx_local_eof_n),.mac_rx_ready_n(rx_endpoint_ready_n),
    .mac_tx_ready_n(1'b0),.mac_tx_valid_n(),.mac_tx_data(),.mac_tx_sof_n(),.mac_tx_eof_n());

function [7:0] sample_byte;
    input integer index,seed;
    begin sample_byte=(index*29)^(index>>3)^seed;end
endfunction
reg [7:0] frame_memory[0:1151];
integer tx_cycles=0,tx_wait=0,capture_count=0,captured_length=0;
integer tx_frames=0,rx_frames=0,relay_index=0,relay_length=0;
reg capturing=0,frame_toggle=0,seen_frame_toggle=0,relaying=0,captured_bad=0,relay_bad=0;
reg [7:0] waiting_data;
reg waiting_valid=0;
// MAC ACK grants a complete frame, not one byte per ACK. Stall the first byte
// for a varying delay, then consume only on enabled MAC clocks.
assign tx_rd_enable=tx_cycles%9!=0;
always @(negedge tx_mac_clk)begin
    mac_tx_ack<=!rst && !capturing && tx_mac_valid && tx_wait>=(3+tx_frames%4*5) && tx_rd_enable;
end
always @(posedge tx_mac_clk)begin
    if(rst)begin
        tx_cycles<=0;tx_wait=0;capture_count=0;captured_length=0;tx_frames=0;
        capturing=0;frame_toggle=0;waiting_valid=0;captured_bad=0;
    end else begin
        tx_cycles<=tx_cycles+1;
        if(tx_overflow)$fatal(1,"native TX FIFO overflow");
        if(tx_rd_enable)begin
            if(!capturing)begin
                if(tx_mac_valid)begin
                    if(waiting_valid && tx_mac_data!==waiting_data)$fatal(1,"TX first byte changes before MAC ACK");
                    waiting_data=tx_mac_data;waiting_valid=1;tx_wait=tx_wait+1;
                    if(mac_tx_ack)begin
                        frame_memory[0]=tx_mac_data;capture_count=1;capturing=1;
                        waiting_valid=0;tx_wait=0;
                    end
                end else waiting_valid=0;
            end else if(tx_mac_valid)begin
                if(capture_count>=1152)$fatal(1,"native TX frame too large");
                frame_memory[capture_count]=tx_mac_data;capture_count=capture_count+1;
            end else begin
                captured_length=capture_count;captured_bad=make_bad_frame;
                if(captured_length!=(tx_length<18 ? 60 : tx_length+42))
                    $fatal(1,"TX FIFO truncates/pads frame bytes=%0d payload=%0d",captured_length,tx_length);
                frame_toggle=~frame_toggle;capturing=0;tx_frames=tx_frames+1;
            end
        end
    end
end
// No FCS bytes enter the RX client interface. STRIP_PADDING toggles only
// whether the 0..8 Ethernet pad bytes reach the RX FIFO for short UDP payloads.
always @(posedge rx_mac_clk)begin
    if(rst)begin
        seen_frame_toggle=0;relaying=0;relay_index=0;relay_length=0;rx_frames=0;
        mac_rx_valid<=0;mac_rx_good<=0;mac_rx_bad<=0;mac_rx_data<=0;
    end else begin
        mac_rx_good<=0;mac_rx_bad<=0;
        if(rx_overflow)$fatal(1,"native RX FIFO overflow");
        if(!relaying && frame_toggle!=seen_frame_toggle)begin
            seen_frame_toggle=frame_toggle;relaying=1;relay_index=1;relay_bad=captured_bad;
            relay_length=STRIP_PADDING && captured_length==60 ? {frame_memory[38],frame_memory[39]}+34 : captured_length;
            mac_rx_data<=frame_memory[0];mac_rx_valid<=1;
        end else if(relaying)begin
            if(relay_index<relay_length)begin
                mac_rx_data<=frame_memory[relay_index];mac_rx_valid<=1;relay_index=relay_index+1;
            end else begin
                mac_rx_valid<=0;mac_rx_good<=!relay_bad;mac_rx_bad<=relay_bad;
                relaying=0;rx_frames=rx_frames+1;
            end
        end else mac_rx_valid<=0;
    end
end

integer expected_length=0,expected_seed=0,published=0,receive_index=0;
integer fifo_frame_count=0,fifo_byte_count=0,stall_cycles=0;
reg previous_rx_valid=0;
always @(posedge dest_clk)begin
    if(rst)begin previous_rx_valid=0;receive_index=0;fifo_byte_count=0;end
    else begin
        if(forced_rx_stall && !rx_local_valid_n)stall_cycles=stall_cycles+1;
        if(!rx_local_valid_n && !rx_endpoint_ready_n && !forced_rx_stall)begin
            if(!rx_local_sof_n && fifo_byte_count!=0)$fatal(1,"native RX duplicate SOF");
            if(rx_local_sof_n && fifo_byte_count==0)$fatal(1,"native RX missing SOF");
            fifo_byte_count=fifo_byte_count+1;
            if(!rx_local_eof_n)begin
                if(fifo_byte_count!=(STRIP_PADDING && expected_length<18 ? expected_length+42 : expected_length<18 ? 60 : expected_length+42))
                    $fatal(1,"native RX EOF/padding boundary wrong count=%0d expected_payload=%0d",fifo_byte_count,expected_length);
                fifo_frame_count=fifo_frame_count+1;fifo_byte_count=0;
            end
        end
        if(rx_valid)begin
            if(!previous_rx_valid)receive_index=0;
            if(rx_length!=expected_length || rx_data!==sample_byte(receive_index,expected_seed))
                $fatal(1,"native UDP publication wrong index=%0d data=%h len=%0d expected=%0d",receive_index,rx_data,rx_length,expected_length);
            receive_index=receive_index+1;
            if(receive_index>expected_length)$fatal(1,"native UDP publishes padding or duplicate payload");
        end else if(previous_rx_valid)begin
            if(receive_index!=expected_length)$fatal(1,"native UDP publication not contiguous/complete");
            published=published+1;
        end
        previous_rx_valid=rx_valid;
    end
end
task send_application;
    input integer length,seed;
    integer index;
    begin
        expected_length=length;expected_seed=seed;
        wait(tx_ready);@(negedge source_clk);tx_length=length;tx_request=1;
        while(!tx_ack)@(negedge source_clk);
        tx_request=0;
        for(index=0;index<length;index=index+1)begin
            tx_valid=1;tx_data=sample_byte(index,seed);@(negedge source_clk);
            if(index%31==17)begin tx_valid=0;repeat(2)@(negedge source_clk);end
        end
        tx_valid=0;
    end
endtask
task good_case;
    input integer length,seed,stall;
    integer initial_published;
    begin
        initial_published=published;
        if(stall)forced_rx_stall=1;
        send_application(length,seed);
        if(stall)begin
            wait(!rx_local_valid_n);repeat(83)@(negedge dest_clk);forced_rx_stall=0;
        end
        wait(published==initial_published+1);repeat(50)@(negedge dest_clk);
    end
endtask
integer before_bad,before_reset;
initial begin
    repeat(32)@(negedge source_clk);rst=0;
    good_case(10,8'h31,0);good_case(12,8'h45,1);good_case(18,8'h69,0);
    good_case(530,8'h82,1);good_case(1042,8'hb3,1);
    // A bad-frame flag from the MAC causes the actual RX FIFO to roll back;
    // not one byte of the otherwise valid UDP payload may be published.
    before_bad=published;make_bad_frame=1;send_application(12,8'hce);
    wait(rx_frames==6);repeat(200)@(negedge dest_clk);make_bad_frame=0;
    if(published!=before_bad || fifo_frame_count!=5)$fatal(1,"native RX FIFO leaks a bad MAC frame");
    good_case(10,8'hf2,0);
    // Reset while TX FIFO is feeding a frame to the MAC relay, before EOF.
    before_reset=published;send_application(1042,8'h19);
    wait(capturing && capture_count>20);@(negedge source_clk);rst=1;
    repeat(40)@(negedge source_clk);rst=0;repeat(100)@(negedge dest_clk);
    if(published!=before_reset)$fatal(1,"native FIFO reset leaks a partial old frame");
    good_case(18,8'h7e,1);good_case(1042,8'ha4,0);
    if(published!=8 || stall_cycles<83)$fatal(1,"native FIFO coverage incomplete published=%0d stall=%0d",published,stall_cycles);
    if(STRIP_PADDING)$display("PASS fixed UDP native FIFO stripped: real TX/RX FIFOs, four clocks, MAC ACK/enable, unpadded small packets, contiguous publication, bad-frame drop and reset recovery");
    else $display("PASS fixed UDP native FIFO padded: real TX/RX FIFOs, four clocks, MAC ACK/enable, padded small packets, contiguous publication, bad-frame drop and reset recovery");
    $finish;
end
initial begin #2000000;$fatal(1,"native FIFO timeout published=%0d TX=%0d RX=%0d capturing=%0d cnt=%0d",published,tx_frames,rx_frames,capturing,capture_count);end
endmodule
module tb_fixed_udp_native_fifo_stripped;
tb_fixed_udp_native_fifo #(.STRIP_PADDING(1)) test();
endmodule
