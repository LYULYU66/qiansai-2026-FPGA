`timescale 1ns/1ps

// Independent packet oracle. No hierarchical access to the implementation is
// used: checksum, frame shape and all payload bytes are checked at the ports.
module tb_fixed_peer_udp;
localparam [31:0] LOCAL_IP=32'hc0a80132, PEER_IP=32'hc0a80133;
localparam [47:0] LOCAL_MAC=48'h020000000032, PEER_MAC=48'h020000000033;
localparam [15:0] PORT=16'h5002;
reg clk=0; always #4 clk=~clk;
reg rst=1;
wire app_ready, app_ack, rx_valid, mr_ready_n, mt_valid_n, mt_sof_n, mt_eof_n;
wire [7:0] rx_data, mt_data;
wire [15:0] rx_length, rx_port;
reg request=0, valid=0, mr_valid=0, mr_sof_n=1, mr_eof_n=1, mt_ready_n=0;
reg [7:0] data=0, mr_data=0;
reg [15:0] length=0;
integer tx_packets=0, tx_size=0, tx_last_size=0, acks=0;
integer rx_packets=0, rx_index=0, rx_expected_length=0;
integer rx_armed=0, rx_in_progress=0;
integer seed=32'h17ab9012;
integer random_stalls=0, force_stall=0;
reg ack_last=0, tx_stalled=0;
reg [10:0] tx_hold=0;
reg [7:0] payload[0:1041];
reg [7:0] expected_rx[0:1041];
reg [7:0] frame[0:1199];
reg [7:0] captured[0:1199];
integer frame_length=0;

fixed_peer_udp #(.LOCAL_IP(LOCAL_IP),.PEER_IP(PEER_IP),.LOCAL_MAC(LOCAL_MAC),
    .PEER_MAC(PEER_MAC),.UDP_PORT(PORT),.MAX_TX_PAYLOAD(1042),
    .MAX_RX_PAYLOAD(1042),.FILL_TIMEOUT_CYCLES(64)) dut (
    .clk(clk),.rst(rst),.app_tx_ready(app_ready),.app_tx_ack(app_ack),
    .app_tx_request(request),.app_tx_valid(valid),.app_tx_data(data),.app_tx_length(length),
    .app_rx_valid(rx_valid),.app_rx_data(rx_data),.app_rx_length(rx_length),.app_rx_port(rx_port),
    .mac_rx_valid(mr_valid),.mac_rx_data(mr_data),.mac_rx_sof_n(mr_sof_n),
    .mac_rx_eof_n(mr_eof_n),.mac_rx_ready_n(mr_ready_n),
    .mac_tx_ready_n(mt_ready_n),.mac_tx_valid_n(mt_valid_n),.mac_tx_data(mt_data),
    .mac_tx_sof_n(mt_sof_n),.mac_tx_eof_n(mt_eof_n));

function [15:0] crc16_byte(input [15:0] old_crc,input [7:0] value);
reg [15:0] c; integer j;
begin
    c=old_crc^{value,8'd0};
    for(j=0;j<8;j=j+1) c=c[15]?(c<<1)^16'h1021:c<<1;
    crc16_byte=c;
end
endfunction

// Deliberately use addition/folding rather than DUT checksum logic.
function [15:0] header_checksum(input integer from_capture);
integer j; reg [31:0] sum; reg [15:0] word_value;
begin
    sum=0;
    for(j=14;j<34;j=j+2) begin
        if(from_capture) word_value={captured[j],captured[j+1]};
        else word_value={frame[j],frame[j+1]};
        sum=sum+word_value;
    end
    while(sum[31:16]!=0) sum={16'd0,sum[15:0]}+sum[31:16];
    header_checksum=~sum[15:0];
end
endfunction

always @(negedge clk) begin
    if(rst) mt_ready_n=0;
    else if(force_stall) mt_ready_n=1;
    else if(random_stalls) mt_ready_n=(($random(seed)&7)<3);
    else mt_ready_n=0;
end

always @(posedge clk) begin
    if(rst) begin
        tx_size=0; tx_stalled=0; ack_last=0;
        rx_index=0; rx_in_progress=0;
    end else begin
        if(app_ack && ack_last) $fatal(1,"TX ACK lasted more than one clock");
        if(app_ack) acks=acks+1;
        ack_last=app_ack;
        if(tx_stalled && {mt_valid_n,mt_sof_n,mt_eof_n,mt_data}!==tx_hold)
            $fatal(1,"MAC TX changed while waiting for ready_n");
        tx_stalled=(!mt_valid_n && mt_ready_n);
        tx_hold={mt_valid_n,mt_sof_n,mt_eof_n,mt_data};
        if(!mt_valid_n && !mt_ready_n) begin
            if(tx_size>=1200) $fatal(1,"oversized TX frame");
            if((tx_size==0) != (!mt_sof_n)) $fatal(1,"incorrect TX SOF position");
            captured[tx_size]=mt_data; tx_size=tx_size+1;
            if(!mt_eof_n) begin
                tx_last_size=tx_size; tx_size=0; tx_packets=tx_packets+1;
            end
        end
        if(rx_valid) begin
            if(!rx_armed) $fatal(1,"malformed/reset/stale packet leaked to application");
            if(rx_length!=rx_expected_length || rx_port!=PORT)
                $fatal(1,"application RX metadata changed len=%0d port=%h",rx_length,rx_port);
            if(rx_data!==expected_rx[rx_index])
                $fatal(1,"RX payload mismatch at %0d expected=%h got=%h",rx_index,expected_rx[rx_index],rx_data);
            if(!mr_ready_n) $fatal(1,"MAC input not backpressured during application delivery");
            rx_in_progress=1; rx_index=rx_index+1;
            if(rx_index==rx_expected_length) begin
                rx_packets=rx_packets+1; rx_armed=0; rx_index=0; rx_in_progress=0;
            end
        end else if(rx_in_progress) $fatal(1,"application RX payload had a bubble");
    end
end

task make_payload(input integer n,input integer salt);
integer j; reg [15:0] crc;
begin
    for(j=0;j<n;j=j+1) payload[j]=(j*37+salt*11)^(j>>2);
    if(n>=2) begin
        crc=16'hffff;
        for(j=0;j<n-2;j=j+1) crc=crc16_byte(crc,payload[j]);
        payload[n-2]=crc[15:8]; payload[n-1]=crc[7:0];
    end
end
endtask

task set_ip_checksum;
reg [15:0] check;
begin
    frame[24]=0; frame[25]=0; check=header_checksum(0);
    frame[24]=check[15:8]; frame[25]=check[7:0];
end
endtask

task make_frame(input integer n);
integer j; reg [15:0] ip_size, udp_size;
begin
    frame_length=(42+n<60)?60:42+n;
    for(j=0;j<1200;j=j+1) frame[j]=0;
    for(j=0;j<6;j=j+1) begin
        frame[j]=LOCAL_MAC>>(40-8*j); frame[6+j]=PEER_MAC>>(40-8*j);
    end
    frame[12]=8'h08; frame[13]=0;
    frame[14]=8'h45; frame[15]=0;
    ip_size=28+n; frame[16]=ip_size[15:8]; frame[17]=ip_size[7:0];
    frame[18]=8'h12; frame[19]=8'h34;
    frame[20]=0; frame[21]=0; frame[22]=64; frame[23]=17;
    for(j=0;j<4;j=j+1) begin
        frame[26+j]=PEER_IP>>(24-8*j); frame[30+j]=LOCAL_IP>>(24-8*j);
    end
    frame[34]=PORT[15:8]; frame[35]=PORT[7:0];
    frame[36]=PORT[15:8]; frame[37]=PORT[7:0];
    udp_size=8+n; frame[38]=udp_size[15:8]; frame[39]=udp_size[7:0];
    frame[40]=0; frame[41]=0;
    for(j=0;j<n;j=j+1) frame[42+j]=(j<1042)?payload[j]:8'hdd;
    set_ip_checksum;
end
endtask

task arm_receive(input integer n);
integer j;
begin
    if(rx_armed || rx_in_progress) $fatal(1,"test RX scoreboard overlap");
    rx_expected_length=n; rx_index=0;
    for(j=0;j<n;j=j+1) expected_rx[j]=payload[j];
    rx_armed=1;
end
endtask

task send_frame_bytes(input integer bytes,input integer bubbles,input integer has_sof,input integer has_eof);
integer j,guard,gaps;
begin
    for(j=0;j<bytes;j=j+1) begin
        if(bubbles) begin
            gaps=($random(seed)&3);
            repeat(gaps) begin @(negedge clk); mr_valid=0; mr_sof_n=1; mr_eof_n=1; end
        end
        @(negedge clk);
        mr_valid=1; mr_data=frame[j];
        mr_sof_n=!(has_sof && j==0); mr_eof_n=!(has_eof && j==bytes-1);
        guard=0;
        @(posedge clk);
        while(mr_ready_n) begin
            guard=guard+1; if(guard>3000) $fatal(1,"RX MAC stalled indefinitely");
            @(posedge clk);
        end
        @(negedge clk); mr_valid=0; mr_sof_n=1; mr_eof_n=1;
    end
end
endtask

task giant_frame;
integer j;
begin
    // Beyond the receiver counter's representable range, then EOF. A wrapped
    // index must not reparse this as another short packet or expose a prefix.
    for(j=0;j<4096;j=j+1) begin
        @(negedge clk); mr_valid=1;
        mr_data=(j<42)?frame[j]:8'had;
        mr_sof_n=(j!=0); mr_eof_n=(j!=4095);
        @(posedge clk);
        if(mr_ready_n) $fatal(1,"giant malformed packet started application delivery");
    end
    @(negedge clk); mr_valid=0; mr_sof_n=1; mr_eof_n=1;
    repeat(1100) @(negedge clk);
end
endtask

task wait_receive(input integer before_count);
integer guard;
begin
    guard=0;
    while(rx_packets==before_count) begin
        @(negedge clk); guard=guard+1;
        if(guard>3000) $fatal(1,"valid RX packet was not delivered");
    end
    repeat(5) @(negedge clk);
end
endtask

task rejected_frame(input integer bytes,input integer bubbles);
integer before_count;
begin
    before_count=rx_packets;
    if(rx_armed) $fatal(1,"test forgot to disarm RX scoreboard");
    send_frame_bytes(bytes,bubbles,1,1);
    repeat(1100) @(negedge clk);
    if(rx_packets!=before_count) $fatal(1,"invalid frame accepted");
end
endtask

task tx_begin(input integer n);
integer guard;
begin
    guard=0;
    while(!app_ready) begin
        @(negedge clk); guard=guard+1;
        if(guard>3000) $fatal(1,"TX ready did not return");
    end
    @(negedge clk); length=n; request=1;
    guard=0;
    while(!app_ack) begin
        @(negedge clk); guard=guard+1;
        if(guard>100) $fatal(1,"TX request was not acknowledged");
    end
    request=0;
end
endtask

task tx_fill(input integer n,input integer bubbles);
integer j,gaps;
begin
    for(j=0;j<n;j=j+1) begin
        if(bubbles) begin
            gaps=$random(seed)&3;
            repeat(gaps) begin @(negedge clk); valid=0; end
        end
        @(negedge clk); valid=1; data=payload[j];
        if(j<n-1 && !mt_valid_n) $fatal(1,"TX published an incompletely filled payload");
    end
    @(negedge clk); valid=0;
end
endtask

task invalid_tx_request(input integer n);
integer old_acks;
begin
    while(!app_ready) @(negedge clk);
    old_acks=acks;
    @(negedge clk); request=1; length=n;
    repeat(5) @(negedge clk);
    request=0;
    if(acks!=old_acks || !app_ready || !mt_valid_n)
        $fatal(1,"illegal application TX length acknowledged n=%0d",n);
end
endtask

task check_tx_frame(input integer n);
integer j, expected_size; reg [15:0] ip_size, udp_size;
begin
    expected_size=(42+n<60)?60:42+n;
    if(tx_last_size!=expected_size) $fatal(1,"TX frame size expected=%0d got=%0d",expected_size,tx_last_size);
    for(j=0;j<6;j=j+1) begin
        if(captured[j]!==((PEER_MAC>>(40-j*8))&8'hff)) $fatal(1,"TX destination MAC");
        if(captured[6+j]!==((LOCAL_MAC>>(40-j*8))&8'hff)) $fatal(1,"TX source MAC");
    end
    if({captured[12],captured[13]}!=16'h0800 || captured[14]!=8'h45)
        $fatal(1,"TX EtherType/IPv4 version/IHL");
    ip_size=28+n; udp_size=8+n;
    if({captured[16],captured[17]}!=ip_size || captured[22]==0 || captured[23]!=17)
        $fatal(1,"TX IP length/TTL/protocol");
    if(captured[20]&8'hbf || captured[21]!=0) $fatal(1,"TX fragmented IPv4 packet");
    if(header_checksum(1)!=0) $fatal(1,"TX independent IPv4 checksum failed");
    for(j=0;j<4;j=j+1) begin
        if(captured[26+j]!==((LOCAL_IP>>(24-j*8))&8'hff)) $fatal(1,"TX source IP");
        if(captured[30+j]!==((PEER_IP>>(24-j*8))&8'hff)) $fatal(1,"TX destination IP");
    end
    if({captured[34],captured[35]}!=PORT || {captured[36],captured[37]}!=PORT ||
        {captured[38],captured[39]}!=udp_size || {captured[40],captured[41]}!=0)
        $fatal(1,"TX UDP header");
    for(j=0;j<n;j=j+1)
        if(captured[42+j]!==payload[j]) $fatal(1,"TX payload mismatch at %0d",j);
    for(j=42+n;j<expected_size;j=j+1)
        if(captured[j]!=0) $fatal(1,"TX minimum frame padding is not zero");
end
endtask

task roundtrip_unit(input integer n,input integer salt);
integer before_tx,before_rx,guard;
begin
    make_payload(n,salt);
    before_tx=tx_packets; force_stall=1;
    tx_begin(n); tx_fill(n,1);
    repeat(12) @(negedge clk);
    if(tx_packets!=before_tx || tx_size!=0) $fatal(1,"TX ignored MAC backpressure");
    force_stall=0; random_stalls=1; guard=0;
    while(tx_packets==before_tx) begin
        @(negedge clk); guard=guard+1;
        if(guard>10000) $fatal(1,"TX frame timeout");
    end
    random_stalls=0; @(negedge clk); check_tx_frame(n);
    make_frame(n); before_rx=rx_packets; arm_receive(n);
    send_frame_bytes(frame_length,1,1,1); wait_receive(before_rx);
end
endtask

integer k,before_tx,before_rx,guard;
initial begin
    repeat(6) @(negedge clk); rst=0;
    invalid_tx_request(0); invalid_tx_request(1043); invalid_tx_request(65535);
    roundtrip_unit(1,1); roundtrip_unit(10,2); roundtrip_unit(12,3);
    roundtrip_unit(18,4); roundtrip_unit(47,5); roundtrip_unit(530,6); roundtrip_unit(1042,7);
    roundtrip_unit(17,14); roundtrip_unit(19,15); roundtrip_unit(255,16);
    roundtrip_unit(256,17); roundtrip_unit(1023,18); roundtrip_unit(1024,19);
    // Arbitrary pad bytes are legal Ethernet padding, never application data.
    make_payload(10,8); make_frame(10);
    for(k=52;k<60;k=k+1) frame[k]=8'hb0+k;
    before_rx=rx_packets; arm_receive(10);
    send_frame_bytes(60,1,1,1); wait_receive(before_rx);
    // A MAC that strips padding exposes the exact Ethernet+IP+UDP+payload
    // length instead. Both complete forms are accepted, not intermediate tails.
    make_payload(10,20); make_frame(10); before_rx=rx_packets; arm_receive(10);
    send_frame_bytes(52,1,1,1); wait_receive(before_rx);
    make_payload(12,21); make_frame(12); before_rx=rx_packets; arm_receive(12);
    send_frame_bytes(54,1,1,1); wait_receive(before_rx);
    // Fields not constrained by the fixed-peer contract must remain legal.
    make_frame(10); frame[15]=8'hdb; frame[18]=8'hbe; frame[19]=8'hef;
    frame[22]=1; set_ip_checksum;
    before_rx=rx_packets; arm_receive(10);
    send_frame_bytes(60,1,1,1); wait_receive(before_rx);
    // DF is not fragmentation. Reject MF, reserved flags and any offset below.
    make_frame(10); frame[20]=8'h40; set_ip_checksum;
    before_rx=rx_packets; arm_receive(10);
    send_frame_bytes(60,1,1,1); wait_receive(before_rx);

    make_frame(47); frame[14]=8'h65; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[14]=8'h46; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[20]=8'h20; set_ip_checksum; rejected_frame(frame_length,0);
    make_frame(47); frame[21]=1; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[20]=8'h80; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[22]=0; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[23]=6; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[24]=frame[24]^1; rejected_frame(frame_length,1);
    make_frame(47); frame[0]=frame[0]^1; rejected_frame(frame_length,1);
    make_frame(47); frame[6]=frame[6]^1; rejected_frame(frame_length,1);
    make_frame(47); frame[29]=frame[29]^1; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[33]=frame[33]^1; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[35]=frame[35]^1; rejected_frame(frame_length,1);
    make_frame(47); frame[37]=frame[37]^1; rejected_frame(frame_length,1);
    make_frame(47); frame[12]=8'h81; frame[13]=0; rejected_frame(frame_length,1);
    make_frame(47); frame[17]=frame[17]-1; set_ip_checksum; rejected_frame(frame_length,1);
    make_frame(47); frame[39]=frame[39]-1; rejected_frame(frame_length,1);
    make_frame(47); frame[38]=0; frame[39]=7; rejected_frame(frame_length,1);
    make_frame(47); frame[41]=1; rejected_frame(frame_length,1);
    make_frame(47); rejected_frame(frame_length-1,1);
    make_frame(47); rejected_frame(frame_length+1,1);
    make_frame(10); rejected_frame(59,1);
    make_frame(10); rejected_frame(61,1);
    make_frame(0); rejected_frame(60,1);
    make_frame(1043); rejected_frame(frame_length,1);
    make_frame(47); send_frame_bytes(frame_length,1,0,1); repeat(1100) @(negedge clk);
    make_frame(47); rejected_frame(14,1);
    make_frame(47); rejected_frame(34,1);
    make_frame(47); rejected_frame(41,1);
    make_frame(10); giant_frame;
    // Missing EOF and a subsequent fresh SOF must resynchronize cleanly.
    make_frame(47); send_frame_bytes(frame_length,1,1,0);
    // A malformed frame must not poison the next well-formed one.
    roundtrip_unit(47,9);

    // Partial application fill must time out without emitting any MAC bytes.
    before_tx=tx_packets; make_payload(18,10); tx_begin(18); tx_fill(4,0);
    repeat(100) @(negedge clk);
    if(!app_ready || tx_packets!=before_tx || tx_size!=0) $fatal(1,"TX fill timeout leaked/stalled");
    // Late payload bytes after timeout have no active request and must be ignored.
    tx_fill(14,0); repeat(12) @(negedge clk);
    if(tx_packets!=before_tx) $fatal(1,"late TX bytes formed an old frame");
    roundtrip_unit(18,11);

    // Reset while TX waits for the external MAC: no stale buffered frame after reset.
    make_payload(47,12); before_tx=tx_packets; force_stall=1;
    tx_begin(47); tx_fill(47,0); repeat(4) @(negedge clk);
    rst=1; repeat(3) @(negedge clk); rst=0; force_stall=0;
    repeat(80) @(negedge clk);
    if(tx_packets!=before_tx || tx_size!=0) $fatal(1,"reset TX buffer leaked");
    // Reset half way through an incoming header. No incomplete bytes escape.
    make_frame(47); send_frame_bytes(23,1,1,0);
    @(negedge clk); rst=1; repeat(3) @(negedge clk); rst=0;
    send_frame_bytes(47,1,0,1); repeat(1100) @(negedge clk);
    // Reset immediately after EOF while payload is buffered, before delivery.
    make_frame(47); send_frame_bytes(frame_length,1,1,1);
    rst=1; repeat(3) @(negedge clk); rst=0;
    repeat(80) @(negedge clk);
    roundtrip_unit(1042,13);
    $display("PASS fixed UDP unit: independent Ethernet/IP checksum oracle, all media lengths, MAC stalls, invalid headers/lengths, padding, timeout, reset isolation");
    $finish;
end
initial begin #8000000; $fatal(1,"fixed UDP unit global timeout"); end
endmodule

// Actual MAC streams from two independent instances are crossed directly.
// The asymmetric capacities match the formal A/B media topology.
module tb_fixed_peer_udp_pair;
reg clk=0; always #4 clk=~clk;
reg rst=1, aq=0, av=0, bq=0, bv=0;
reg [7:0] ad=0, bd=0;
reg [15:0] al=0, bl=0;
wire ar,aa,br,ba, arv,brv;
wire [7:0] ard,brd, amtd,bmtd;
wire [15:0] arl,brl,arp,brp;
wire amtvn,bmtvn,amtsofn,bmtsofn,amteofn,bmteofn,amrrn,bmrrn;
integer a_received=0,b_received=0,ai=0,bi=0,alen=0,blen=0;
integer a_started=0,b_started=0,salt=0;
integer pair_seed=32'h47d90013;
function [7:0] a_value(input integer i,input integer s); begin a_value=(i*17+s*31)^8'hb2; end endfunction
function [7:0] b_value(input integer i,input integer s); begin b_value=(i*41+s*23)^8'h5e; end endfunction
fixed_peer_udp #(.LOCAL_IP(32'hc0a80132),.PEER_IP(32'hc0a80133),
    .LOCAL_MAC(48'h020000000032),.PEER_MAC(48'h020000000033),
    .MAX_TX_PAYLOAD(18),.MAX_RX_PAYLOAD(1042),.FILL_TIMEOUT_CYCLES(4096)) a (
    .clk(clk),.rst(rst),.app_tx_ready(ar),.app_tx_ack(aa),.app_tx_request(aq),
    .app_tx_valid(av),.app_tx_data(ad),.app_tx_length(al),
    .app_rx_valid(arv),.app_rx_data(ard),.app_rx_length(arl),.app_rx_port(arp),
    .mac_rx_valid(!bmtvn),.mac_rx_data(bmtd),.mac_rx_sof_n(bmtsofn),.mac_rx_eof_n(bmteofn),
    .mac_rx_ready_n(amrrn),.mac_tx_ready_n(bmrrn),.mac_tx_valid_n(amtvn),
    .mac_tx_data(amtd),.mac_tx_sof_n(amtsofn),.mac_tx_eof_n(amteofn));
fixed_peer_udp #(.LOCAL_IP(32'hc0a80133),.PEER_IP(32'hc0a80132),
    .LOCAL_MAC(48'h020000000033),.PEER_MAC(48'h020000000032),
    .MAX_TX_PAYLOAD(1042),.MAX_RX_PAYLOAD(18),.FILL_TIMEOUT_CYCLES(4096)) b (
    .clk(clk),.rst(rst),.app_tx_ready(br),.app_tx_ack(ba),.app_tx_request(bq),
    .app_tx_valid(bv),.app_tx_data(bd),.app_tx_length(bl),
    .app_rx_valid(brv),.app_rx_data(brd),.app_rx_length(brl),.app_rx_port(brp),
    .mac_rx_valid(!amtvn),.mac_rx_data(amtd),.mac_rx_sof_n(amtsofn),.mac_rx_eof_n(amteofn),
    .mac_rx_ready_n(bmrrn),.mac_tx_ready_n(amrrn),.mac_tx_valid_n(bmtvn),
    .mac_tx_data(bmtd),.mac_tx_sof_n(bmtsofn),.mac_tx_eof_n(bmteofn));
always @(posedge clk) if(!rst) begin
    if(arv) begin
        if(arl!=blen || arp!=16'h5002 || ard!==b_value(ai,salt))
            $fatal(1,"pair B->A data/metadata i=%0d",ai);
        a_started=1; ai=ai+1;
        if(ai==blen) begin a_received=a_received+1; ai=0; a_started=0; end
    end else if(a_started) $fatal(1,"pair A application output bubble");
    if(brv) begin
        if(brl!=alen || brp!=16'h5002 || brd!==a_value(bi,salt))
            $fatal(1,"pair A->B data/metadata i=%0d",bi);
        b_started=1; bi=bi+1;
        if(bi==alen) begin b_received=b_received+1; bi=0; b_started=0; end
    end else if(b_started) $fatal(1,"pair B application output bubble");
end
task send_a(input integer n);
integer j,gaps,guard;
begin
    guard=0;
    while(!ar) begin @(negedge clk); guard=guard+1; if(guard>4000) $fatal(1,"pair A ready timeout"); end
    @(negedge clk); al=n; aq=1; guard=0;
    while(!aa) begin @(negedge clk); guard=guard+1; if(guard>100) $fatal(1,"pair A ACK timeout"); end
    aq=0;
    for(j=0;j<n;j=j+1) begin
        gaps=$random(pair_seed)&3; repeat(gaps) begin @(negedge clk); av=0; end
        @(negedge clk); av=1; ad=a_value(j,salt);
    end
    @(negedge clk); av=0;
end
endtask
task send_b(input integer n);
integer j,gaps,guard;
begin
    guard=0;
    while(!br) begin @(negedge clk); guard=guard+1; if(guard>4000) $fatal(1,"pair B ready timeout"); end
    @(negedge clk); bl=n; bq=1; guard=0;
    while(!ba) begin @(negedge clk); guard=guard+1; if(guard>100) $fatal(1,"pair B ACK timeout"); end
    bq=0;
    for(j=0;j<n;j=j+1) begin
        gaps=$random(pair_seed)&3; repeat(gaps) begin @(negedge clk); bv=0; end
        @(negedge clk); bv=1; bd=b_value(j,salt);
    end
    @(negedge clk); bv=0;
end
endtask
task exchange(input integer na,input integer nb,input integer s);
integer old_a,old_b,guard;
begin
    alen=na; blen=nb; salt=s; old_a=a_received; old_b=b_received;
    fork send_a(na); send_b(nb); join
    guard=0;
    while(a_received==old_a || b_received==old_b) begin
        @(negedge clk); guard=guard+1;
        if(guard>6000) $fatal(1,"pair simultaneous UDP exchange timeout");
    end
    repeat(5) @(negedge clk);
end
endtask
integer i;
initial begin
    repeat(6) @(negedge clk); rst=0;
    exchange(10,47,1); exchange(12,530,2); exchange(18,1042,3);
    exchange(1,1,4);
    for(i=0;i<6;i=i+1) exchange(18,1042,5+i);
    rst=1; repeat(3) @(negedge clk); rst=0;
    exchange(18,1042,11);
    if(a_received!=11 || b_received!=11) $fatal(1,"pair packet count mismatch");
    $display("PASS fixed UDP pair: asymmetric A18/RX1042 B1042/RX18, simultaneous full media payloads, repeat traffic, reset");
    $finish;
end
initial begin #3000000; $fatal(1,"fixed UDP pair global timeout"); end
endmodule
