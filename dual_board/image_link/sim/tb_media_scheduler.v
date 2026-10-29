`timescale 1ns/1ps
module tb_media_scheduler #(parameter integer CHANNELS=5,MAX_LENGTH=1042);
reg clk=0,rst=1;
always #4 clk=~clk;
reg [CHANNELS-1:0] requests=0,valids=0;
wire [CHANNELS-1:0] ready,acks;
reg [CHANNELS*8-1:0] data=0;
reg [CHANNELS*16-1:0] lengths=0;
wire request,valid;
wire [7:0] out_data;
wire [15:0] out_length;
integer cycles=0,ack_ticks=0,ack_delay=4;
reg request_seen=0;
wire net_ready=(cycles%19)!=0 && (cycles%19)!=1;
wire ack=request && net_ready && !request_seen && ack_ticks>=ack_delay;
media_udp_scheduler #(.CHANNELS(CHANNELS),.MAX_LENGTH(MAX_LENGTH)) dut (
    .clk(clk),.rst(rst),.net_ready(net_ready),.net_ack(ack),
    .net_request(request),.net_valid(valid),.net_data(out_data),.net_length(out_length),
    .c_request(requests),.c_valid(valids),.c_data(data),.c_length(lengths),.c_ready(ready),.c_ack(acks));
integer state[0:CHANNELS-1],index[0:CHANNELS-1],gap_left[0:CHANNELS-1];
integer packet_length[0:CHANNELS-1],abort_at[0:CHANNELS-1],start_gap[0:CHANNELS-1];
reg [7:0] bytes[0:CHANNELS*MAX_LENGTH-1];
integer i,j,c;
function [15:0] crc_byte;
    input [15:0] old_crc;input [7:0] value;
    reg [15:0] crc;integer bitno;
    begin
        crc=old_crc;
        for(bitno=7;bitno>=0;bitno=bitno-1)
            if(crc[15]^value[bitno])crc=(crc<<1)^16'h1021;
            else crc=crc<<1;
        crc_byte=crc;
    end
endfunction
always @(posedge clk)begin
    cycles<=cycles+1;
    if(rst)begin ack_ticks<=0;request_seen<=0;end
    else begin
        if(!request)begin ack_ticks<=0;request_seen<=0;end
        else if(ack)request_seen<=1;
        else if(net_ready)ack_ticks<=ack_ticks+1;
    end
    if(!rst)for(c=0;c<CHANNELS;c=c+1)begin
        if(acks[c])begin
            if(state[c]!=1)$fatal(1,"ACK to non-requesting channel %0d",c);
            requests[c]<=0;state[c]<=2;gap_left[c]<=start_gap[c];
        end else if(state[c]==2)begin
            if(gap_left[c]!=0)gap_left[c]<=gap_left[c]-1;
            else begin
                index[c]<=0;data[c*8+:8]<=bytes[c*MAX_LENGTH];
                valids[c]<=abort_at[c]!=0;state[c]<=3;
            end
        end else if(state[c]==3)begin
            if(index[c]==packet_length[c]-1)begin valids[c]<=0;state[c]<=4;end
            else begin
                index[c]<=index[c]+1;
                data[c*8+:8]<=bytes[c*MAX_LENGTH+index[c]+1];
                valids[c]<=abort_at[c]<0 || index[c]+1<abort_at[c];
            end
        end
    end
end
integer active=-1,received=0,finished=0,selected,highest,locked_expected=-1;
integer priority_left=0,expected_priority=0;
reg bad=0;
reg [15:0] reference_crc;
always @(posedge clk)begin
    if(rst)begin active=-1;received=0;locked_expected=-1;end
    else begin
        // Selection is locked when requesting UDP, NOT at its later ACK.
        // A new high-priority producer while waiting for ACK must not steal it.
        if(!dut.busy && request)begin
            locked_expected=-1;
            for(j=0;j<CHANNELS;j=j+1)
                if(requests[j] && lengths[j*16+:16]>=2 && lengths[j*16+:16]<=MAX_LENGTH)locked_expected=j;
        end
        if(ack)begin
            if(active!=-1)$fatal(1,"packet owner changed while active");
            selected=-1;highest=-1;
            for(j=0;j<CHANNELS;j=j+1)begin
                if(requests[j] && lengths[j*16+:16]>=2 && lengths[j*16+:16]<=MAX_LENGTH)highest=j;
                if(acks[j])begin
                    if(selected!=-1)$fatal(1,"ACK is not one-hot");selected=j;
                end
            end
            if(selected!=locked_expected || selected<0)$fatal(1,"wrong locked boundary priority got=%0d expected=%0d pending=%0d",selected,locked_expected,highest);
            if(priority_left!=0)begin
                if(selected!=expected_priority)$fatal(1,"priority order changed");
                expected_priority=expected_priority-1;priority_left=priority_left-1;
            end
            active=selected;received=0;reference_crc=16'hffff;
            bad=abort_at[active]>=0 || start_gap[active]>=7;
            if(out_length!=packet_length[active])$fatal(1,"declared length damaged");
        end
        if(valid)begin
            if(active<0 || received>=packet_length[active])$fatal(1,"spliced/overrun payload");
            if(out_length!=packet_length[active])$fatal(1,"length changed mid-packet");
            if(!bad)begin
                if(out_data!==bytes[active*MAX_LENGTH+received])$fatal(1,"payload/CRC mismatch c=%0d i=%0d",active,received);
            end else if(received>=packet_length[active]-2)begin
                if(received==packet_length[active]-2 && out_data!==reference_crc[15:8])$fatal(1,"poison high CRC wrong");
                if(received==packet_length[active]-1 && out_data!==(reference_crc[7:0]^8'h01))$fatal(1,"aborted packet could pass CRC");
            end else if(start_gap[active]<7)begin
                if(out_data!==(received<abort_at[active] ? bytes[active*MAX_LENGTH+received] : 8'd0))
                    $fatal(1,"abort padding/source restoration wrong");
            end
            if(received<packet_length[active]-2)reference_crc=crc_byte(reference_crc,out_data);
            received=received+1;
            if(received==packet_length[active])begin finished=finished+1;active=-1;end
        end
    end
end
task prepare;
    input integer channel,len,cut,prime;
    reg [15:0] crc;integer n;
    begin
        packet_length[channel]=len;abort_at[channel]=cut;start_gap[channel]=prime;
        state[channel]=1;index[channel]=0;
        lengths[channel*16+:16]=len;valids[channel]=0;
        crc=16'hffff;
        for(n=0;n<len-2;n=n+1)begin
            bytes[channel*MAX_LENGTH+n]=(channel*29+n*3+len)&255;
            crc=crc_byte(crc,bytes[channel*MAX_LENGTH+n]);
        end
        bytes[channel*MAX_LENGTH+len-2]=crc[15:8];bytes[channel*MAX_LENGTH+len-1]=crc[7:0];
        requests[channel]=1;
    end
endtask
task settle;
    input integer target;
    begin wait(finished==target);repeat(30)@(negedge clk);end
endtask
integer target=0,round;
initial begin
    for(i=0;i<CHANNELS;i=i+1)begin state[i]=0;packet_length[i]=0;abort_at[i]=-1;start_gap[i]=0;end
    repeat(5)@(negedge clk);rst=0;
    // All pending: true packet-boundary priority, variable ready/ACK latency.
    for(round=0;round<4;round=round+1)begin
        ack_delay=round*3;priority_left=CHANNELS;expected_priority=CHANNELS-1;
        for(i=0;i<CHANNELS;i=i+1)prepare(i,round==0 ? MAX_LENGTH : 10+(i%3),-1,1);
        target=target+CHANNELS;settle(target);
    end
    // A late high-priority request must not interrupt a locked long packet.
    prepare(0,MAX_LENGTH,-1,1);wait(acks[0]);@(negedge clk);
    lengths[0+:16]=2;prepare(CHANNELS-1,10,-1,1);
    target=target+2;settle(target);
    // Aborts before the first byte, in the payload, and at either CRC byte.
    for(round=0;round<5;round=round+1)begin
        prepare(0,MAX_LENGTH,round==0 ? 0 : round==1 ? 1 : round==2 ? MAX_LENGTH/2 : MAX_LENGTH-5+round,1);
        target=target+1;settle(target);
    end
    // Prime timeout then producer resumes: poison latch must remain active.
    prepare(0,MAX_LENGTH,-1,12);target=target+1;settle(target);
    // The smallest supported packet still terminates; invalid length is never ACKed.
    prepare(0,2,-1,1);target=target+1;settle(target);
    requests[CHANNELS-1]=1;lengths[(CHANNELS-1)*16+:16]=MAX_LENGTH+1;
    prepare(0,10,-1,1);target=target+1;settle(target);
    if(acks[CHANNELS-1] || request)$fatal(1,"oversized producer accepted/truncated");
    requests=0;
    // Base reset can abandon a packet only along with the UDP core reset.
    prepare(0,MAX_LENGTH,-1,1);wait(valid);@(negedge clk);rst=1;requests=0;valids=0;
    for(i=0;i<CHANNELS;i=i+1)state[i]=0;
    repeat(5)@(negedge clk);rst=0;prepare(0,10,-1,1);target=target+1;settle(target);
    if(CHANNELS==3)$display("PASS flat scheduler A: priority, lengths, ACK latency, poisoning, reset (%0d packets)",finished);
    else $display("PASS flat scheduler B: priority, lengths, ACK latency, poisoning, reset (%0d packets)",finished);
    $finish;
end
initial begin #4000000;$fatal(1,"scheduler timeout finished=%0d active=%0d",finished,active);end
endmodule

module tb_media_scheduler_a;
tb_media_scheduler #(.CHANNELS(3),.MAX_LENGTH(18)) test();
endmodule
