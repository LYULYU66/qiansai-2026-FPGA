`timescale 1ns/1ps
module tb_link_session;
reg clk=0; always #4 clk=~clk;
reg ar=1,br=1,drop_ab=0,drop_ba=0,renew=0;
wire aq,av,bq,bv,ardy,brdy,aat,bat;
wire [7:0] ad,bd;
wire [15:0] al,bl,ag,bg;
wire areq,aval,breq,bval;
wire [7:0] adata,bdata;
wire [15:0] alen,blen;
reg aa=0,ba=0,inject=0;
reg [7:0] injected_data=0;
media_link_session #(.ROLE(0),.HEARTBEAT_CYCLES(80),.TIMEOUT_CYCLES(800)) a (
    .clk(clk),.rst(ar),.renew(1'b0),.rx_valid(bval && !drop_ba),.rx_data(bdata),.rx_length(blen),
    .udp_ready(ardy),.udp_ack(aat),.udp_request(aq),.udp_valid(av),.udp_data(ad),.udp_length(al),
    .ready(),.generation(ag),.restart());
media_link_session #(.ROLE(1),.HEARTBEAT_CYCLES(80),.TIMEOUT_CYCLES(800)) b (
    .clk(clk),.rst(br),.renew(renew),.rx_valid(inject || (aval && !drop_ab)),
    .rx_data(inject ? injected_data : adata),.rx_length(inject ? 16'd10 : alen),
    .udp_ready(brdy),.udp_ack(bat),.udp_request(bq),.udp_valid(bv),.udp_data(bd),.udp_length(bl),
    .ready(),.generation(bg),.restart());
media_udp_arbiter amux (
    .clk(clk),.rst(ar),.net_ready(1'b1),.net_ack(aa),.net_request(areq),.net_valid(aval),.net_data(adata),.net_length(alen),
    .c0_request(1'b0),.c0_valid(1'b0),.c0_data(8'd0),.c0_length(16'd0),.c0_ready(),.c0_ack(),
    .c1_request(aq),.c1_valid(av),.c1_data(ad),.c1_length(al),.c1_ready(ardy),.c1_ack(aat));
media_udp_arbiter bmux (
    .clk(clk),.rst(br),.net_ready(1'b1),.net_ack(ba),.net_request(breq),.net_valid(bval),.net_data(bdata),.net_length(blen),
    .c0_request(1'b0),.c0_valid(1'b0),.c0_data(8'd0),.c0_length(16'd0),.c0_ready(),.c0_ack(),
    .c1_request(bq),.c1_valid(bv),.c1_data(bd),.c1_length(bl),.c1_ready(brdy),.c1_ack(bat));
always @(posedge clk) begin aa<=areq && !aa; ba<=breq && !ba; end
always @(posedge clk) begin
    if(a.ready && b.ready && !ar && !br && ag!==bg) $fatal(1,"active generations differ");
    if(b.state==3 && b.ready) $fatal(1,"B released SD/compute before reset guard finished");
    if(a.ready && a.state!=2) $fatal(1,"A ready before peer ALIVE");
end
task connected;
integer n;
begin
    n=0;
    while(!(a.ready && b.ready && ag==bg) && n<4000) begin @(negedge clk); n=n+1; end
    if(n==4000) $fatal(1,"link negotiation failed A=%0d B=%0d ageA=%0d ageB=%0d",a.state,b.state,a.age,b.age);
    repeat(200) @(negedge clk);
end
endtask
function [15:0] crc_byte(input [15:0] old_crc,input [7:0] value);
reg [15:0] c;integer i;
begin c=old_crc^{value,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
endfunction
task stale_ack(input [15:0] g,input integer corrupt);
reg [7:0] bytes[0:9];reg [15:0] c;integer i;
begin
    bytes[0]="L";bytes[1]="N";bytes[2]="K";bytes[3]="1";
    bytes[4]=3;bytes[5]=0;bytes[6]=g[7:0];bytes[7]=g[15:8];c=16'hffff;
    for(i=0;i<8;i=i+1)c=crc_byte(c,bytes[i]);bytes[8]=c[15:8];bytes[9]=c[7:0]^corrupt;
    for(i=0;i<10;i=i+1)begin @(negedge clk);inject=1;injected_data=bytes[i];end
    @(negedge clk);inject=0;repeat(4)@(negedge clk);
end
endtask
reg [15:0] old_generation;
initial begin
    repeat(8)@(negedge clk);ar=0;br=0;connected;
    if(ag!=1)$fatal(1,"cold negotiation");old_generation=ag;
    drop_ab=1;drop_ba=1;repeat(180)@(negedge clk);drop_ab=0;drop_ba=0;connected;
    if(ag!=old_generation)$fatal(1,"short outage restarted media");
    drop_ab=1;br=1;repeat(8)@(negedge clk);br=0;
    repeat(180)@(negedge clk);stale_ack(old_generation,0);stale_ack(old_generation,1);
    if(b.ready)$fatal(1,"stale ACK started reset B");
    drop_ab=0;connected;
    if(ag==old_generation)$fatal(1,"B restart reused generation");old_generation=ag;
    ar=1;repeat(8)@(negedge clk);ar=0;connected;
    if(ag==old_generation)$fatal(1,"A restart reused generation");old_generation=ag;
    drop_ab=1;drop_ba=1;repeat(1100)@(negedge clk);
    if(a.ready || b.ready)$fatal(1,"lost peer not timed out");
    drop_ab=0;drop_ba=0;connected;
    if(ag==old_generation)$fatal(1,"long outage reused generation");old_generation=ag;
    // Each one-way failure also has to converge, not just cable removal.
    drop_ab=1;repeat(2000)@(negedge clk);
    if(a.ready || b.ready)$fatal(1,"A-to-B failure not detected");
    drop_ab=0;connected;
    if(ag==old_generation)$fatal(1,"one-way outage reused generation");old_generation=ag;
    drop_ba=1;repeat(1200)@(negedge clk);
    if(a.ready || b.ready)$fatal(1,"B-to-A failure not detected");
    drop_ba=0;connected;
    if(ag==old_generation)$fatal(1,"reverse outage reused generation");old_generation=ag;
    renew=1;repeat(3)@(negedge clk);renew=0;connected;
    if(ag==old_generation)$fatal(1,"renewal reused generation");
    // Accelerate rare wrap without generating 65k sessions.
    ar=1;br=1;repeat(8)@(negedge clk);ar=0;br=0;
    b.generation=16'hffff;b.have_generation=1;connected;
    if(ag!=0 || bg!=0)$fatal(1,"generation wrap failed");
    $display("PASS link session: cold/short loss, A/B reset, stale ACK/CRC, two/one-way loss, renewal, u16 wrap, real arbiters");$finish;
end
initial begin #1000000;$fatal(1,"link session timeout");end
endmodule
