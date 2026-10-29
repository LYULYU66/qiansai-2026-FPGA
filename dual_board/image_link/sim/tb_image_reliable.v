`timescale 1ns/1ps
module tb_image_reliable;
    parameter integer PACKETS=4;
    parameter integer UI_TAG=0;
    parameter integer RESOLUTION=0;
    localparam integer PIXELS=PACKETS*256;
    reg clk=0; always #4 clk=~clk;
    reg rst=1, tx_ack=0, receipt_ack=0;
    wire tx_req, tx_valid, source_ready, frame_sent;
    wire [7:0] tx_data;
    wire [15:0] tx_len, transmissions, tx_sequence;
    reg [18:0] source_count=0;
    wire receipt_valid;
    wire [31:0] receipt_token;
    wire [15:0] receipt_sequence;
    image_packet_tx #(.FRAME_PACKETS(PACKETS),.RELIABLE(1),.RETRY_CYCLES(2500),.UI_TAG(UI_TAG),.RESOLUTION(RESOLUTION)) tx (
        .clk(clk),.rst(rst),.source_valid(source_count<PIXELS),
        .source_ready(source_ready),.source_rgb({5'd0,source_count}),
        .source_tag(source_count[7:0]^8'ha5),
        .source_frame_start(source_count==0),.source_frame_index(2'd2),
        .source_top_down(1'b1),.udp_ready(1'b1),.udp_ack(tx_ack),
        .source_resolution(32'h050003c0),
        .udp_request(tx_req),.udp_valid(tx_valid),.udp_data(tx_data),.udp_length(tx_len),
        .frame_sent(frame_sent),.packets_sent(transmissions),
        .receipt_valid(receipt_valid),.receipt_token(receipt_token),
        .receipt_sequence(receipt_sequence),.transfer_token(),.packet_sequence(tx_sequence),
        .frame_token(32'd0)
    );
    reg corrupted=0;
    wire corrupt_now=tx_valid && tx_sequence==1 && tx.byte_index==(UI_TAG ? 1035 : 50) && !corrupted;
    wire write_req, write_abort, write_en, top_down;
    wire [31:0] write_data;
    wire [1:0] write_index;
    wire [3:0] cache_valid;
    wire [127:0] resolutions;
    wire commit_toggle, fault, ack_req, ack_valid;
    wire [7:0] ack_data;
    wire [15:0] ack_len;
    reg writer_ack=0, writer_finish=0;
    integer cycles=0, received=0, finish_wait=0;
    reg finish_issued=0, done=0;
    wire writer_ready=(cycles>=7000) && (cycles%9!=0);
    image_main_ingress #(.FRAME_PACKETS(PACKETS),.TIMEOUT_CYCLES(20000),.UI_TAG(UI_TAG),.RESOLUTION(RESOLUTION)) main (
        .clk(clk),.rst(rst),.rx_valid(tx_valid),.rx_data(tx_data ^ (corrupt_now ? 8'h01 : 8'h00)),
        .rx_length(tx_len),.writer_ready(writer_ready),.writer_ack(writer_ack),
        .writer_finish_toggle(writer_finish),.protected_buffers(4'd0),
        .write_req(write_req),.write_abort(write_abort),.write_en(write_en),
        .write_data(write_data),.write_index(write_index),.write_top_down(top_down),
        .cache_valid(cache_valid),.commit_toggle(commit_toggle),.fault(fault),
        .source_resolutions(resolutions),
        .udp_ready(1'b1),.udp_ack(receipt_ack),.udp_request(ack_req),
        .udp_valid(ack_valid),.udp_data(ack_data),.udp_length(ack_len)
    );
    reg dropped_first=0, dropped_final=0;
    wire drop_receipt=(main.u_receipt.sequence_no==0 && !dropped_first) ||
                      (main.u_receipt.sequence_no==PACKETS-1 && !dropped_final);
    image_receipt_rx ack_parser (
        .clk(clk),.rst(rst),.rx_valid(ack_valid && !drop_receipt),.rx_data(ack_data),
        .rx_length(ack_len),.receipt_valid(receipt_valid),
        .receipt_token(receipt_token),.receipt_sequence(receipt_sequence)
    );
    always @(posedge clk) if(!rst) begin
        cycles=cycles+1;
        tx_ack<=tx_req; receipt_ack<=ack_req;
        writer_ack<=write_req && !write_abort;
        if(source_count<PIXELS && source_ready) source_count<=source_count+1'b1;
        if(corrupt_now) corrupted<=1;
        if(write_en) begin
            if(write_data !== {received[23:0],(UI_TAG ? (received[7:0]^8'ha5) : 8'd0)})
                $fatal(1,"duplicate, missing or damaged pixel %0d got %h",received,write_data);
            if(write_index!=2 || !top_down) $fatal(1,"wrong writer metadata");
            received=received+1;
        end
        if(received==PIXELS && !finish_issued) begin
            finish_wait=finish_wait+1;
            if(finish_wait==6000) begin writer_finish<=~writer_finish; finish_issued<=1; end
        end
        if(cache_valid[2] && !finish_issued) $fatal(1,"committed before SDRAM completed");
        if(RESOLUTION && ((!cache_valid[2] && resolutions!=0) ||
                         (cache_valid[2] && resolutions[95:64]!=32'h050003c0)))
            $fatal(1,"resolution not committed with image");
        if(ack_valid && main.u_receipt.sequence_no==PACKETS-1 && !finish_issued)
            $fatal(1,"final ACK before SDRAM completion");
        if(ack_valid && main.u_receipt.index==11) begin
            if(main.u_receipt.sequence_no==0) dropped_first<=1;
            if(main.u_receipt.sequence_no==PACKETS-1) dropped_final<=1;
        end
        if(fault) $fatal(1,"unexpected sink abort");
        if(frame_sent) begin
            if(received!=PIXELS || !cache_valid[2] || !dropped_first ||
               !dropped_final || !corrupted || transmissions<=PACKETS)
                $fatal(1,"missing reliable recovery coverage");
            done<=1;
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst=0;
        repeat(PACKETS*3500+50000) @(negedge clk);
        if(!done || received!=PIXELS) $fatal(1,"reliable transfer timed out");
        if(RESOLUTION) $display("PASS resolution image: %0d packets, metadata atomic commit, CRC retry, lost ACK, SDRAM stall",PACKETS);
        else if(UI_TAG) $display("PASS tagged image: %0d packets, 307200 RGB+UI words, last-tag CRC retry, lost ACK, writer stall, atomic commit",PACKETS);
        else $display("PASS reliable image: %0d packets, CRC retry, lost ACK, stalled writer, final commit, no duplicated pixels",PACKETS);
        $finish;
    end
endmodule

module tb_image_reliable_full;
    tb_image_reliable #(.PACKETS(1200)) u_full();
endmodule

module tb_image_tagged_full;
    tb_image_reliable #(.PACKETS(1200),.UI_TAG(1)) u_full();
endmodule

module tb_image_resolution;
    tb_image_reliable #(.PACKETS(4),.UI_TAG(1),.RESOLUTION(1)) u_full();
endmodule
