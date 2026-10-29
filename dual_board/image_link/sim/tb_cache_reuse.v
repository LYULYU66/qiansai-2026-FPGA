`timescale 1ns/1ps
// Actual reliable IMG4 sender/receiver/ACK path. SDRAM completion is a writer
// model; protected replays must work even with that writer permanently paused.
module tb_cache_reuse;
parameter integer PACKETS=4;
parameter integer FULL=0;
localparam integer PIXELS=PACKETS*256;
reg clk=0;always #4 clk=~clk;
reg rst=1,source_reset=1,restart=0,tx_ack=0,ack_ack=0;
reg writer_enabled=1,writer_ack=0,writer_finish=0,finish_issued=0;
reg [3:0] protect=0;
reg [15:0] generation=1;
reg [31:0] token=32'h00010001,size=32'h050003c0;
reg top_down=1;
integer source_count=0,revision=0,phase=0,cycles=0;
integer total_writes=0,frame_writes=0,finish_wait=0,final_receipts=0;
wire source_ready,tx_req,tx_valid,frame_sent,ack_req,ack_valid,receipt_valid;
wire [7:0] tx_data,ack_data;
wire [15:0] tx_length,ack_length,receipt_sequence,tx_sequence;
wire [31:0] receipt_token;
wire write_req,write_abort,write_en,commit,fault;
wire [31:0] write_data;
wire [3:0] cache;
wire [127:0] sizes;
wire writer_ready=writer_enabled && cycles%9!=0;
function [23:0] rgb(input integer p);
begin rgb=p[23:0]^((revision==1 && p==PIXELS-1)?24'h000001:24'd0);end
endfunction
function [7:0] tag(input integer p);
begin tag=p[7:0]^8'ha5^((revision==2 && p==PIXELS-1)?8'h01:8'd0);end
endfunction
image_packet_tx #(.FRAME_PACKETS(PACKETS),.RELIABLE(1),.EXTERNAL_TOKEN(1),.UI_TAG(1),.RESOLUTION(1),.RETRY_CYCLES(1500)) tx (
    .clk(clk),.rst(rst || source_reset),.source_valid(source_count<PIXELS),.source_ready(source_ready),
    .source_rgb(rgb(source_count)),.source_tag(tag(source_count)),.source_frame_start(source_count==0),
    .source_frame_index(2'd0),.source_top_down(top_down),.source_resolution(size),.frame_token(token),
    .udp_ready(1'b1),.udp_ack(tx_ack),.udp_request(tx_req),.udp_valid(tx_valid),.udp_data(tx_data),.udp_length(tx_length),
    .frame_sent(frame_sent),.packets_sent(),.receipt_valid(receipt_valid),.receipt_token(receipt_token),
    .receipt_sequence(receipt_sequence),.transfer_token(),.packet_sequence(tx_sequence));
reg corrupted=0,dropped_first=0,dropped_final=0;
wire corrupt_now=phase==0 && tx_valid && tx_sequence==1 && tx.byte_index==50 && !corrupted;
wire drop_ack=phase==1 && ((main.u_receipt.sequence_no==0 && !dropped_first) ||
                          (main.u_receipt.sequence_no==PACKETS-1 && !dropped_final));
image_main_ingress #(.FRAME_PACKETS(PACKETS),.TIMEOUT_CYCLES(10000),.UI_TAG(1),.RESOLUTION(1),.SESSION_GUARD(1),.REUSE_CACHE(1)) main (
    .clk(clk),.rst(rst),.generation(generation),.restart_receive(restart),
    .rx_valid(tx_valid),.rx_data(tx_data^(corrupt_now?8'h01:8'h00)),.rx_length(tx_length),
    .writer_ready(writer_ready),.writer_ack(writer_ack),.writer_finish_toggle(writer_finish),.protected_buffers(protect),
    .write_req(write_req),.write_abort(write_abort),.write_en(write_en),.write_data(write_data),.write_index(),.write_top_down(),
    .cache_valid(cache),.source_resolutions(sizes),.commit_toggle(commit),.fault(fault),
    .udp_ready(1'b1),.udp_ack(ack_ack),.udp_request(ack_req),.udp_valid(ack_valid),.udp_data(ack_data),.udp_length(ack_length));
image_receipt_rx receipt (
    .clk(clk),.rst(rst || source_reset),.rx_valid(ack_valid && !drop_ack),.rx_data(ack_data),.rx_length(ack_length),
    .receipt_valid(receipt_valid),.receipt_token(receipt_token),.receipt_sequence(receipt_sequence));
always @(posedge clk)if(!rst)begin
    cycles=cycles+1;tx_ack<=tx_req;ack_ack<=ack_req;
    writer_ack<=write_req && !write_abort;
    if(source_reset)source_count<=0;
    else if(source_ready && source_count<PIXELS)source_count<=source_count+1;
    if(corrupt_now)corrupted<=1;
    if(write_en)begin
        if(protect[0])$fatal(1,"protected replay wrote SDRAM");
        if(write_data!=={rgb(frame_writes),tag(frame_writes)})$fatal(1,"wrong/duplicate pixel %0d",frame_writes);
        total_writes=total_writes+1;frame_writes=frame_writes+1;
    end
    if(frame_writes==PIXELS && !finish_issued)begin
        finish_wait=finish_wait+1;
        if(finish_wait==80)begin writer_finish<=~writer_finish;finish_issued<=1;end
    end
    if(receipt_valid && receipt_token==token && receipt_sequence==PACKETS-1)final_receipts=final_receipts+1;
    if(ack_valid && main.u_receipt.index==11 && phase==1)begin
        if(main.u_receipt.sequence_no==0)dropped_first<=1;
        if(main.u_receipt.sequence_no==PACKETS-1)dropped_final<=1;
    end
end
task begin_frame(input [31:0] next_token,input integer next_revision);
begin
    @(negedge clk);source_reset=1;
    repeat(6)@(negedge clk);token=next_token;revision=next_revision;
    frame_writes=0;finish_wait=0;finish_issued=0;final_receipts=0;source_reset=0;
end
endtask
task sent;
integer n;
begin
    n=0;while(!frame_sent && n<PACKETS*6000+15000)begin @(negedge clk);n=n+1;end
    if(!frame_sent)$fatal(1,"sender stuck phase=%0d seq=%0d state=%0d",phase,tx_sequence,main.u_sink.state);
    repeat(12)@(negedge clk);
end
endtask
task rejected_replay;
begin
    wait(main.u_sink.state==4);wait(main.u_sink.protocol_done);
    repeat(4500)@(negedge clk);
    if(frame_sent || final_receipts || !fault || main.u_sink.final_ack_valid)
        $fatal(1,"mismatch/final retry got false completion phase=%0d",phase);
end
endtask
function [31:0] crc_byte(input [31:0] old_crc,input [7:0] value);
reg [31:0] c;integer i;
begin c=old_crc^{24'd0,value};for(i=0;i<8;i=i+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
endfunction
integer before_writes,i;
reg old_commit;
reg [31:0] reference;
reg [23:0] value;
initial begin
    repeat(8)@(negedge clk);rst=0;
    begin_frame(32'h00010001,0);sent;
    if(cache!=1 || total_writes!=PIXELS || !corrupted || sizes[31:0]!=size)$fatal(1,"initial cache/CRC retry failed");
    reference=32'hffffffff;
    for(i=0;i<PIXELS;i=i+1)begin
        value=rgb(i);reference=crc_byte(reference,value[23:16]);reference=crc_byte(reference,value[15:8]);
        reference=crc_byte(reference,value[7:0]);reference=crc_byte(reference,tag(i));
    end
    if(main.u_sink.cached_crc[31:0]!==reference)$fatal(1,"half-word CRC differs from byte reference");
    before_writes=total_writes;old_commit=commit;protect=1;writer_enabled=0;
    phase=1;source_reset=1;restart=1;generation=2;repeat(20)@(negedge clk);restart=0;
    begin_frame(32'h00020001,0);sent;
    if(total_writes!=before_writes || frame_writes!=0 || cache!=1 || commit!=old_commit ||
       !dropped_first || !dropped_final || fault || !main.u_sink.final_ack_valid)
        $fatal(1,"protected identical replay failed or rewrote cache");
    if(FULL)begin
        $display("PASS cache reuse full: 1200-packet CRC32, 307200 RGB+tag words, B session reset, blocked writer, lost first/final ACK, zero replay writes");$finish;
    end
    phase=2;begin_frame(32'h00020002,1);rejected_replay;
    if(total_writes!=before_writes || cache!=1 || commit!=old_commit || sizes[31:0]!=size)$fatal(1,"RGB mismatch damaged cached frame");
    // Same RGB, but an altered UI tag also changes the complete fingerprint.
    phase=3;begin_frame(32'h00020003,2);rejected_replay;
    if(total_writes!=before_writes || cache!=1)$fatal(1,"tag mismatch damaged cache");
    phase=4;begin_frame(32'h00020004,0);sent;
    if(total_writes!=before_writes || cache!=1)$fatal(1,"correct retry could not recover");
    // Metadata mismatch must be rejected before entering read-only verification.
    phase=5;size=32'h07800438;begin_frame(32'h00020005,0);
    repeat(10000)@(negedge clk);
    if(frame_sent || final_receipts || main.u_sink.state==4 || total_writes!=before_writes || sizes[31:0]!=32'h050003c0)
        $fatal(1,"protected metadata changed");
    source_reset=1;size=32'h050003c0;top_down=0;begin_frame(32'h00020006,0);
    repeat(10000)@(negedge clk);
    if(frame_sent || final_receipts || total_writes!=before_writes)$fatal(1,"orientation mismatch accepted");
    // Interrupt verification while the CRC second half is pending.
    phase=6;top_down=1;begin_frame(32'h00020007,0);wait(main.u_sink.crc_pending);
    @(negedge clk);restart=1;source_reset=1;generation=3;repeat(20)@(negedge clk);
    if(cache!=1 || total_writes!=before_writes || main.u_sink.crc_pending)$fatal(1,"partial verification survived restart");
    restart=0;begin_frame(32'h00030001,0);sent;
    if(total_writes!=before_writes || commit!=old_commit)$fatal(1,"restart changed cached display");
    // Different content is writable after it is no longer protected; its new
    // fingerprint must replace the old one only after SDRAM completion.
    phase=7;protect=0;writer_enabled=1;begin_frame(32'h00030002,1);sent;
    if(total_writes!=before_writes+PIXELS || commit==old_commit)$fatal(1,"unprotected content update failed");
    before_writes=total_writes;protect=1;writer_enabled=0;
    begin_frame(32'h00030003,1);sent;
    if(total_writes!=before_writes || cache!=1)$fatal(1,"new cached fingerprint not reusable");
    $display("PASS cache reuse guard: reference CRC32, RGB/tag mismatch, no false final ACK on retry, metadata/orientation, interrupted CRC, safe unprotected update");$finish;
end
initial begin #(PACKETS*100000+4000000);$fatal(1,"cache reuse test timeout phase=%0d",phase);end
endmodule
module tb_cache_reuse_full;
tb_cache_reuse #(.PACKETS(1200),.FULL(1)) full_frame();
endmodule
