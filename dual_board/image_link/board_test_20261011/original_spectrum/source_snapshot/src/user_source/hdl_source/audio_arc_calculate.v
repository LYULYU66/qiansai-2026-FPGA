module audio_arc_calculate #(
    parameter ACR_N = 6144
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_audio_valid,
    output reg         O_acr_valid,
    output reg  [19:0] O_acr_cts,
    output reg  [19:0] O_acr_n
);

localparam AUDIO_DIV = ACR_N >> 7;
reg [7:0] S_audio_div_cnt;
reg [19:0] S_acr_cts_cnt;
wire S_audio_valid_div = I_audio_valid && (S_audio_div_cnt == AUDIO_DIV - 1);

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst)
        S_audio_div_cnt <= 8'd0;
    else if (I_audio_valid)
        S_audio_div_cnt <= S_audio_valid_div ? 8'd0 : S_audio_div_cnt + 8'd1;
end

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst)
        S_acr_cts_cnt <= 20'd0;
    else if (S_audio_valid_div)
        S_acr_cts_cnt <= 20'd0;
    else
        S_acr_cts_cnt <= S_acr_cts_cnt + 20'd1;
end

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        O_acr_valid <= 1'b0;
        O_acr_cts   <= 20'd0;
        O_acr_n     <= 20'd0;
    end else if (S_audio_valid_div) begin
        O_acr_valid <= 1'b1;
        O_acr_cts   <= S_acr_cts_cnt + 20'd1;
        O_acr_n     <= ACR_N;
    end else begin
        O_acr_valid <= 1'b0;
        O_acr_cts   <= 20'd0;
        O_acr_n     <= 20'd0;
    end
end

endmodule
