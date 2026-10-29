`timescale 1ns/1ps
module tb_ctl4_receipt_20261021;
reg clk=0, rst=1; always #4 clk=~clk;
// ---------- CTL4 with hazard ----------
reg [75:0] bundle; reg hazard=0;
wire req, valid; wire [7:0] data; wire [15:0] len; reg ack=0;
media_control_star_tx #(.UPDATE_CYCLES(60)) tx (.clk(clk),.rst(rst),.star_bundle(bundle),.hazard(hazard),
    .udp_ready(1'b1),.udp_ack(ack),.udp_request(req),.udp_valid(valid),.udp_data(data),.udp_length(len));
reg corrupt=0;
wire [75:0] rx_bundle; wire rx_toggle, rx_hazard;
media_control_star_rx rx (.clk(clk),.rst(rst),.rx_valid(valid),.rx_data(data ^ {7'd0,corrupt}),.rx_length(len),
    .star_bundle(rx_bundle),.bundle_toggle(rx_toggle),.hazard(rx_hazard));
always @(posedge clk) ack<=req && !ack;
// ---------- IAK2 receipt ----------
reg ev=0; reg [31:0] tok; reg [15:0] sq; wire rreq, rvalid; wire [7:0] rdata; wire [15:0] rlen; reg rack=0;
image_receipt_tx itx (.clk(clk),.rst(rst),.event_valid(ev),.event_token(tok),.event_sequence(sq),
    .udp_ready(1'b1),.udp_ack(rack),.udp_request(rreq),.udp_valid(rvalid),.udp_data(rdata),.udp_length(rlen));
always @(posedge clk) rack<=rreq && !rack;
reg rcorrupt=0;
wire got; wire [31:0] got_tok; wire [15:0] got_sq;
image_receipt_rx irx (.clk(clk),.rst(rst),.rx_valid(rvalid),.rx_data(rdata ^ {rcorrupt,7'd0}),.rx_length(rlen),
    .receipt_valid(got),.receipt_token(got_tok),.receipt_sequence(got_sq));
integer errors=0, accepted=0, receipts=0, i;
reg last_toggle=0;
always @(posedge clk) if(!rst && rx_toggle!=last_toggle) begin
    last_toggle<=rx_toggle; accepted=accepted+1;
end
always @(posedge clk) if(got) begin
    receipts=receipts+1;
    if(got_tok!==tok || got_sq!==sq) begin errors=errors+1; $display("ERR receipt %h %h", got_tok, got_sq); end
end
task one_receipt(input [31:0] t, input [15:0] s, input bad, input expect_ok);
    integer count_before;
    begin
        count_before=receipts; tok=t; sq=s; rcorrupt=0;
        @(posedge clk) ev<=1; @(posedge clk) ev<=0;
        if(bad) begin wait(rvalid); repeat(5) @(posedge clk); rcorrupt<=1; @(posedge clk); rcorrupt<=0; end
        repeat(60) @(posedge clk);
        if((receipts-count_before)!=(expect_ok?1:0)) begin errors=errors+1; $display("ERR receipt count t=%h bad=%0d", t, bad); end
    end
endtask
initial begin
    bundle=76'h0; #50 rst=0;
    for(i=0;i<6;i=i+1) begin
        bundle={$random,$random,$random}; hazard=i[0];
        repeat(120) @(posedge clk);
        if(rx_bundle!==bundle || rx_hazard!==hazard) begin
            errors=errors+1; $display("ERR ctl4 i=%0d bundle %h/%h hazard %b/%b", i, rx_bundle, bundle, rx_hazard, hazard);
        end
    end
    // A corrupted packet must not change the accepted hazard or toggle.
    hazard=0; repeat(120) @(posedge clk);
    begin : corrupt_test
        integer n0; n0=accepted;
        hazard=1; wait(valid); repeat(3) @(posedge clk); corrupt<=1; @(posedge clk); corrupt<=0;
        wait(!valid); repeat(3) @(posedge clk);
        if(rx_hazard!==1'b0 || accepted!=n0) begin errors=errors+1; $display("ERR corrupted CTL4 accepted"); end
    end
    one_receipt(32'h12345678, 16'h0001, 0, 1);
    one_receipt(32'hCAFEF00D, 16'h04AF, 1, 0);
    one_receipt(32'hCAFEF00D, 16'h04AF, 0, 1);
    one_receipt(32'h00000000, 16'hFFFF, 0, 1);
    $display("ctl4 accepted=%0d receipts=%0d errors=%0d", accepted, receipts, errors);
    if(errors==0) $display("PASS"); else $display("FAIL");
    $finish;
end
endmodule
