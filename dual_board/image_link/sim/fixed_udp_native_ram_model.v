`timescale 1ns/1ps
// Test-only replacement for the RAMB16_S9_S9 primitive wrapper. The actual
// tx_client_fifo/rx_client_fifo RTL is compiled unchanged. This abstraction
// matches its 2048 x 9, clock-enabled, synchronous-read, write-through dual-port
// contract; it does not model primitive collision checks or physical timing.
module RAMB16_S9_S9 #(
    parameter DEVICE="EG4"
) (
    output reg [8:0] doa,dob,
    input wire [8:0] dia,dib,
    input wire [10:0] addra,addrb,
    input wire cea,ceb,clka,clkb,wea,web
);
reg [8:0] memory[0:2047];
always @(posedge clka)if(cea)begin
    if(wea)begin memory[addra]<=dia;doa<=dia;end
    else doa<=memory[addra];
end
always @(posedge clkb)if(ceb)begin
    if(web)begin memory[addrb]<=dib;dob<=dib;end
    else dob<=memory[addrb];
end
endmodule
